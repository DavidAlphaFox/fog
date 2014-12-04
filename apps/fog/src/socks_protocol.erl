-module(socks_protocol).

-behavior(ranch_protocol).

-export([start_link/4, 
         init/4]).

-export([pretty_address/1]).
-export([loop/1]).

-include("socks.hrl").

start_link(Ref, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
    {ok, Pid}.

init(Ref, Socket, Transport, _Opts) ->
    ok = ranch:accept_ack(Ref),
    link(whereis(fog_multiplex)),
    {ok, {Addr, Port}} = inet:peername(Socket),
    State = #state{
                   auth_methods = [?AUTH_NOAUTH], 
                   transport = Transport, 
                   client_ip = Addr,
                   client_port = Port,
                   incoming_socket = Socket,
                   id = undefined,
                   buffer = <<>>,
                   connected = false
                },
    R = Transport:recv(Socket, 1, ?TIMEOUT),
    case R of
        {ok,<<Version>>}->
            case Version of
                ?VERSION5 -> 
                    loop(socks5:process(State));
            _ -> 
                Transport:close(Socket),
                lager:log(error,?MODULE,"Unsupported SOCKS version ~p", [Version])
            end;
        {error,Reason}->
            lager:log(error,?MODULE,"SOCKS Closed")
    end.
loop(ok)->
	ok;
loop(#state{transport = Transport, incoming_socket = ISocket,id = ID} = State) ->
    inet:setopts(ISocket, [{active, once}]),
    {OK, Closed, Error} = Transport:messages(),
    receive
        {OK, ISocket, Data} ->
            NewState = case State#state.connected of
                true ->
                    fog_multiplex:recv_data(ID, Data),
                    State;
                false ->
                    Buffer = State#state.buffer,
                    State#state{buffer = <<Buffer/bits,Data/bits>>}
                end,
            ?MODULE:loop(NewState);
        {connect} ->
            Buffer = State#state.buffer,
            fog_multiplex:recv_data(ID,Buffer),
            NewState = State#state{buffer = <<>>,connected = true},
            ?MODULE:loop(NewState);
        {recv_data,Data} ->
            Transport:send(ISocket, Data),
            ?MODULE:loop(State);
        {Closed, ISocket} ->
            lager:log(info,?MODULE,"incoming ~p:~p closed!", [pretty_address(State#state.client_ip), State#state.client_port]);
        {close} ->
            Transport:close(ISocket);
        {Error, ISocket, Reason} ->
            lager:log(error,?MODULE,"incoming socket: ~p", [Reason]),
            lager:log(info,?MODULE,"~p:~p closed!", [pretty_address(State#state.client_ip), State#state.client_port])
    end.

pretty_address(Addr) when is_tuple(Addr) ->
    inet_parse:ntoa(Addr);
pretty_address(Addr) ->
    Addr.

%%%===================================================================
%%% Internal functions
%%%===================================================================
