-module(socks_protocol).

-behavior(ranch_protocol).

-export([start_link/4, 
         init/4]).

-export([connect/3, 
         pretty_address/1]).
-export([loop/1]).

-include("socks.hrl").

start_link(Ref, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
    {ok, Pid}.

init(Ref, Socket, Transport, Opts) ->
    ok = ranch:accept_ack(Ref),
    {ok, {Addr, Port}} = inet:peername(Socket),
    ID = generator_worker:gen_id(),
    State = #state{
                   auth_methods = [?AUTH_NOAUTH], 
                   transport = Transport, 
                   client_ip = Addr,
                   client_port = Port,
                   incoming_socket = Socket,
                   id = ID
                },
    {ok, <<Version>>} = Transport:recv(Socket, 1, ?TIMEOUT),
    case Version of
        ?VERSION5 -> 
            loop(socks5:process(State));
        _ -> 
            Transport:close(Socket),
            lager:error("Unsupported SOCKS version ~p", [Version])
    end.

loop(#state{transport = Transport, incoming_socket = ISocket,id = ID} = State) ->
    inet:setopts(ISocket, [{active, once}]),
    {OK, Closed, Error} = Transport:messages(),
    receive
        {OK, ISocket, Data} ->
            fog_multiplex:to_princess(ID, Data),
            ?MODULE:loop(State);
        {to_client,Data} ->
            Transport:send(ISocket, Data),
            ?MODULE:loop(State);
        {Closed, ISocket} ->
            lager:info("~p:~p closed!", [pretty_address(State#state.client_ip), State#state.client_port]);
        {remote_close} ->
            Transport:close(ISocket);
        {Error, ISocket, Reason} ->
            lager:error("incoming socket: ~p", [Reason]),
            lager:info("~p:~p closed!", [pretty_address(State#state.client_ip), State#state.client_port])
    end.

connect(Transport, Addr, Port) ->
    connect(Transport, Addr, Port, 2).

connect(Transport, Addr, Port, 0) ->
    Transport:connect(Addr, Port, []);
connect(Transport, Addr, Port, Ret) ->
    case Transport:connect(Addr, Port, []) of
        {ok, OSocket} -> {ok, OSocket};
        {error, _} -> connect(Transport, Addr, Port, Ret-1)
    end.

pretty_address(Addr) when is_tuple(Addr) ->
    inet_parse:ntoa(Addr);
pretty_address(Addr) ->
    Addr.

%%%===================================================================
%%% Internal functions
%%%===================================================================
