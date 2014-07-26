%%-------------------------------------------------------------------                                                          
%%% @author David.Gao <david.alpha.fox@gmail.com>                                                                                                                                     
%%% @copyright (C) 2014                                                                                  
%%% @doc redis protocol processor                                                                                                   
%%% @end                                                                                                                        
%%%------------------------------------------------------------------
-module(redis_protocol).

-behaviour(gen_fsm).

-export([start_link/4]).

-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

-export([socket/2, command_start/2, arg_size/2, command_name/2, argument/2]).
-export([disconnect/1]).

-define(FSM_TIMEOUT, 60000).

-record(state, 
        { socket :: undefined | port(),
		      transport :: undefined | atom(),
          peerport :: undefined | pos_integer(),
          missing_args = 0 :: non_neg_integer(),
          next_arg_size :: undefined | integer(),
          command_name :: undefined | binary(),
          args = [] :: [binary()],
          buffer = <<>> :: binary(),
          runner :: undefined | pid()
        }).

-type state() :: #state{}.

%% ====================================================================
%% External functions
%% ====================================================================
%% -- General ---------------------------------------------------------
%% @doc Start the client
-spec start_link(pid(),port(),atom(),list()) -> {ok, pid()}.

start_link(ListenerPid, Socket, Transport, _Opts) ->
    {ok,Pid} = gen_fsm:start_link(?MODULE, [], []),
    set_socket(Pid,ListenerPid,Socket,Transport),
    {ok, Pid}.


%% @doc Associates the client with the socket
-spec set_socket(pid(),pid(), port(),atom()) -> ok.
set_socket(Client,ListenerPid,Socket,Transport) ->
  gen_fsm:send_event(Client, {socket_ready,ListenerPid, Socket,Transport}).

%% @doc Stop the client
-spec disconnect(pid()) -> ok.
disconnect(Client) ->
  gen_fsm:send_event(Client, disconnect).

%% ====================================================================
%% Server functions
%% ====================================================================
%% @hidden
-spec init([]) -> {ok, socket, state(), ?FSM_TIMEOUT}.
init([]) ->
  {ok, socket, #state{}, ?FSM_TIMEOUT}.

%% ASYNC EVENTS -------------------------------------------------------
%% @hidden
-spec socket({socket_ready, port(),atom()} | timeout | term(), state()) -> {next_state, command_start, state(), hibernate} | {stop, timeout | {unexpected_event, term()}, state()}.
socket({socket_ready,ListenerPid,Socket,Transport}, State) ->
  % Now we own the socket
  ranch:accept_ack(ListenerPid),
  PeerPort =
    case Transport:peername(Socket) of
      {ok, {_Ip, Port}} -> Port;
      Error -> Error
    end,
  ok = Transport:setopts(Socket, [{active, once}, {packet, line}, binary]),
  _ = erlang:process_flag(trap_exit, true), %% We want to know even if it stops normally
  {ok, Runner} = redis_runner:start_link(Transport,Socket),
  {next_state, command_start, State#state{socket = Socket,transport = Transport,peerport = PeerPort,runner = Runner}, hibernate};
socket(timeout, State) ->
  {stop, timeout, State};

socket(Other, State) ->
  {stop, {unexpected_event, Other}, State}.

%% @hidden
-spec command_start(term(), state()) -> {next_state, command_start, state(), hibernate} | {next_state, arg_size | argument, state()} | {stop, {unexpected_event, term()}, state()}.
command_start({data, <<"\r\n">>}, State) ->
  {next_state, command_start, State};
command_start({data, <<"\n">>}, State) ->
  {next_state, command_start, State};
command_start({data, <<"*", N/binary>>}, State) -> %% Unified Request Protocol
  {NArgs, "\r\n"} = string:to_integer(binary_to_list(N)),
  {next_state, arg_size, State#state{missing_args = NArgs, command_name = undefined, args = []}};
command_start(Event, State) ->
  {stop, {unexpected_event, Event}, State}.

%% @hidden
-spec arg_size(term(), state()) -> {next_state, command_start, state(), hibernate} | {next_state, command_name | argument, state()} | {stop, {unexpected_event, term()}, state()}.
arg_size({data, <<"$", N/binary>>}, State) ->
  case string:to_integer(binary_to_list(N)) of
    {error, no_integer} ->
      {next_state, command_start, State, hibernate};
    {ArgSize, _Rest} ->
      {next_state, case State#state.command_name of
                     undefined -> command_name;
                     _Command -> argument
                   end, State#state{next_arg_size = ArgSize, buffer = <<>>}}
  end;
arg_size(Event, State) ->
    {stop, {unexpected_event, Event}, State}.

%% @hidden
-spec command_name(term(), state()) -> {next_state, command_start, state(), hibernate} | {next_state, arg_size, state()} | {stop, {unexpected_event, term()}, state()}.
command_name({data, Data}, State = #state{next_arg_size = Size,
					  missing_args = 1}) ->
  <<Command:Size/binary, _Rest/binary>> = Data,
  Runner = State#state.runner,
  redis_runner:run(Runner,string_util:upper(Command),[]),
  {next_state, command_start, State, hibernate};
command_name({data, Data}, State = #state{next_arg_size = Size, 
					  missing_args = MissingArgs}) ->
  <<Command:Size/binary, _Rest/binary>> = Data,
  {next_state, arg_size, State#state{command_name = Command,
				     missing_args = MissingArgs - 1}};
command_name(Event, State) ->
  {stop, {unexpected_event, Event}, State}.

%% @hidden
-spec argument(term(), state()) -> {next_state, command_start, state(), hibernate} | {next_state, argument | arg_size, state()} | {stop, {unexpected_event, term()}, state()}.
argument({data, Data}, State = #state{buffer        = Buffer,
                                      next_arg_size = Size}) ->
  case <<Buffer/binary, Data/binary>> of
      <<Argument:Size/binary, _Rest/binary>> ->
	  case State#state.missing_args of
	      1 ->
          Runner = State#state.runner,
          Args = lists:reverse([Argument|State#state.args]),
          Command = State#state.command_name,
          redis_runner:run(Runner,string_util:upper(Command),Args),
		      {next_state, command_start, State, hibernate};
	      MissingArgs ->
		      {next_state, arg_size, State#state{missing_args = MissingArgs - 1,
                                             args = [Argument | State#state.args]}}
	  end;
      NewBuffer -> %% Not the whole argument yet, just an \r\n in the middle of it
	  {next_state, argument, State#state{buffer = NewBuffer}}
  end;
argument(Event, State) ->
    {stop, {unexpected_event, Event}, State}.

%% OTHER EVENTS -------------------------------------------------------
%% @hidden
-spec handle_event(X, atom(), state()) -> {stop, {atom(), unexpected_event, X}, state()}.
handle_event(Event, StateName, StateData) ->
  {stop, {StateName, unexpected_event, Event}, StateData}.

%% @hidden
-spec handle_sync_event(X, reference(), atom(), state()) -> {stop, {atom(), unexpected_event, X}, state()}.
handle_sync_event(Event, _From, StateName, StateData) ->
  {stop, {StateName, unexpected_event, Event}, StateData}.

%% @hidden
-spec handle_info(term(), atom(), state()) -> term().
handle_info({'EXIT', CmdRunner, Reason}, _StateName, State = #state{runner = CmdRunner}) ->
  {stop, Reason, State};
handle_info({tcp, Socket, Bin}, StateName, #state{socket = Socket,
						  transport = Transport} = StateData) ->
  % Flow control: enable forwarding of next TCP message
  ok = Transport:setopts(Socket, [{active, false}]),
  Result = ?MODULE:StateName({data, Bin}, StateData),
  ok = Transport:setopts(Socket, [{active, once}]),
  Result;

handle_info({tcp_closed, Socket}, _StateName, #state{socket = Socket} = StateData) ->
  {stop, normal, StateData};
handle_info(_Info, StateName, StateData) ->
  {next_state, StateName, StateData}.

%% @hidden
-spec terminate(term(), atom(), state()) -> ok.
terminate(normal, _StateName, #state{socket = Socket,
				     transport = Transport})->
  (catch Transport:close(Socket)),
  ok;

terminate(_Reason, _StateName, #state{socket = Socket, 
				     transport = Transport})->
  (catch Transport:close(Socket)),
  ok.

%% @hidden
-spec code_change(term(), atom(), state(), any()) -> {ok, atom(), state()}.
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.
