-module(socks5).

-export([process/1]).

-include("socks.hrl").

-define(VERSION, 16#05).
-define(RSV, 16#00).
-define(IPV4, 16#01).
-define(IPV6, 16#04).
-define(DOMAIN, 16#03).

-define(CMD_CONNECT, 16#01).
-define(CMD_BIND, 16#02).
-define(CMD_UDP_ASSOCIATE,  16#03).


-define(REP_SUCCESS, 16#00).
-define(REP_SERVER_ERROR, 16#01).
-define(REP_FORBBIDEN, 16#02).
-define(REP_NET_NOTAVAILABLE, 16#03).
-define(REP_HOST_NOTAVAILABLE, 16#04).
-define(REP_FAILURE, 16#05).
-define(REP_TTL_EXPIRES, 16#06).
-define(REP_CMD_NOTSUPPORTED, 16#07).
-define(REP_ATYP_NOSUPPORTED, 16#08).
-define(REP_UNDEF, 16#FF).


process(State) ->
    try auth(State)
    catch 
        _:Reason ->
            Transport = State#state.transport,
            Transport:close(State#state.incoming_socket),
            lager:log(error,?MODULE,"Auth error ~p", [Reason])
    end.

auth(#state{transport = Transport, incoming_socket = ISocket} = State) ->
    {ok, <<NMethods>>} = Transport:recv(ISocket, 1, ?TIMEOUT),
    {ok, Data} = Transport:recv(ISocket, NMethods, ?TIMEOUT),
    doAuth(Data, State).

doAuth(Data, #state{auth_methods = AuthMethods, transport = Transport, incoming_socket = ISocket} = State) ->
    OfferAuthMethods = binary_to_list(Data),
    Addr = State#state.client_ip,
    Port = State#state.client_port,
    lager:log(info,?MODULE,"~p:~p offers authentication methods: ~p", [socks_protocol:pretty_address(Addr),
                                                           Port, OfferAuthMethods]),
    [Method | _] = lists:filter(fun(E) -> lists:member(E, OfferAuthMethods) end, AuthMethods),
    % only no authentication support now
    case Method of
        ?AUTH_NOAUTH -> 
            Transport:send(ISocket, <<?VERSION, Method>>),
            lager:log(info,?MODULE,"~p:~p Authorized with ~p type", [socks_protocol:pretty_address(Addr), Port, Method]),
            cmd(State);
        _ ->
            Transport:send(ISocket, <<?VERSION, ?AUTH_UNDEF>>),
            lager:log(error,?MODULE,"~p:~p Authorization method (~p) not supported", [socks_protocol:pretty_address(Addr),
                                                                          Port, OfferAuthMethods]),
            throw(auth_not_supported)
    end.

cmd(#state{transport = Transport, incoming_socket = ISocket} = State) ->
    try
    	{ok, <<?VERSION, CMD, ?RSV, ATYP>>} = Transport:recv(ISocket, 4, ?TIMEOUT),
        {ok, NewState} = doCmd(CMD, ATYP, State),
        NewState
    catch 
        _:Reason ->
            ok = Transport:close(ISocket),
            lager:log(error,?MODULE,"~p:~p command error ~p", [socks_protocol:pretty_address(State#state.client_ip), 
                                                   State#state.client_port, Reason])
    end.

doCmd(?CMD_CONNECT, ATYP, #state{transport = Transport, incoming_socket = ISocket,id = ID} = State) ->
    {ok, Data} = get_address_port(ATYP, Transport, ISocket),
    {Addr, Port} = parse_addr_port(ATYP, Data),
    Pid = self(),
    fog_multiplex:fetch(Pid,ID,Addr,Port),
    lager:log(info,?MODULE,"~p:~p connected to ~p:~p", [socks_protocol:pretty_address(State#state.client_ip), 
                                            State#state.client_port,
                                            socks_protocol:pretty_address(Addr), Port]),
    {ok, {BAddr, BPort}} = inet:sockname(ISocket),
    BAddr2 = list_to_binary(tuple_to_list(BAddr)),
    ok = Transport:send(ISocket, <<?VERSION, ?REP_SUCCESS, ?RSV, ?IPV4, BAddr2/binary, BPort:16>>),
    {ok, State};

doCmd(Cmd, _, State) ->
    lager:log(error,?MODULE,"Command ~p not implemented yet", [Cmd]),
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
get_address_port(ATYP, Transport, Socket) ->
    case ATYP of
        ?IPV4 -> 
            Transport:recv(Socket, 6, ?TIMEOUT);
        ?IPV6 -> 
           % Transport:recv(Socket, 18, ?TIMEOUT);
           throw(address_not_supported);
        ?DOMAIN ->
            {ok, <<DLen>>} = Transport:recv(Socket, 1, ?TIMEOUT),
            {ok, AddrPort} = Transport:recv(Socket, DLen+2, ?TIMEOUT),
            {ok, <<DLen, AddrPort/binary>>};
        true -> throw(unknown_atyp)
    end.

parse_addr_port(?IPV4, <<Addr:4/binary, Port:16>>) ->
    {{?IPV4,Addr}, Port};
parse_addr_port(?IPV6, <<Addr:16/binary, Port:16>>) ->
    {{?IPV6,Addr}, Port};
parse_addr_port(?DOMAIN, <<Len, Addr:Len/binary, Port:16>>) ->
    {{?DOMAIN,Addr}, Port}.
