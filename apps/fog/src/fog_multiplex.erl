%%%-------------------------------------------------------------------
%%% @author David Alpha Fox <>
%%% @copyright (C) 2014, David Alpha Fox
%%% @doc
%%%
%%% @end
%%% Created : 29 Jul 2014 by David Alpha Fox <>
%%%-------------------------------------------------------------------
-module(fog_multiplex).

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
		 terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
	ip,
	port,
	connected,
	heart_beat,
	miss,
	socket,
	buff
	}).

%%%===================================================================
%%% API
%%%===================================================================
to_princess(ID,Bin)->
	gen_server:cast(?SERVER,{to_princess,ID,Bin}).
fetch(Pid,ID,Address,Port)->
	gen_server:call(?SERVER,{fetch,Pid,ID,Address,Port}).
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link(Args) -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
	IP = proplists:get_value(ip,Args),
	Port = proplists:get_value(port,Args),
	HeartBeat = proplists:get_value(heart_beat,Args),
	gen_server:start_link({local, ?SERVER}, ?MODULE, {IP,Port,HeartBeat}, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init({IP,Port,HeartBeat}) ->
	State = #state{
		ip = IP,
		port = Port,
		connected = false,
		heart_beat = HeartBeat,
		miss = 0,
		socket = undefined,
		buff = <<>>
	},
	multiplex_monitor = ets:new(multiplex_monitor, [ordered_set, protected, named_table]),   
	multiplex_mapper = ets:new(multiplex_mapper, [ordered_set, protected, named_table]),   
	{ok,State,0}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({fetch,Pid,ID,Address,Port},_From,#state{heart_beat = HeartBeat,socket = Socket} = State)->
	Addr = <<Address/binary>>,
	AddrLen = erlang:byte_size(Addr), 
	Data = <<AddrLen:32/big,Addr/binary,Port:16/big>>,
	Packet = pack(ID,1,Data),
	Result = ranch_ssl:send(Socket,Packet),
	case Result of
		ok ->
			hm_misc:monitor(Pid,multiplex_monitor),
			ets:insert(multiplex_mapper, {ID,Pid}),
			{reply,ok,State,HeartBeat};
		{error,Error}->
			{reply,{error,Error},State,HeartBeat}
	end;
handle_call(_Request, _From, State) ->
	Reply = ok,
	{reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({to_princess,ID,Bin},#state{heart_beat = HeartBeat,socket = Socket} = State)->
	Packet = pack(ID,2,Bin),
	Result = ranch_ssl:send(Socket,Packet),
	case Result of
		ok ->
			ok;
		{error,_Error}->
			remote_close(ID)
	end,
	{noreply, State,HeartBeat};
handle_cast(_Msg, State) ->
	{noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

handle_info({ssl, Socket, Bin},#state{heart_beat = HeartBeat,socket = Socket,buff = Buff} = State) ->
  % Flow control: enable forwarding of next TCP message
  ok = ranch_ssl:setopts(Socket, [{active, false}]),
  {Packet,NewBuff} = unpack(<<Buff/bits,Bin/bits>>,[]),
  StateBuff = State#state{buff = NewBuff},
  NewState = packet(Packet,StateBuff),
  ok = ranch_ssl:setopts(Socket, [{active, once}]),
  {noreply,NewState,HeartBeat};

handle_info({ssl_closed, Socket}, #state{socket = Socket} = State) ->
  {stop, ssl_closed, State};


handle_info(timeout,#state{ip = IP,port = Port,connected = false,heart_beat = HeartBeat} = State )->
	lager:log(info,?MODULE,"Try to connect to ~s:~p~n",[IP,Port]),
	Result = ranch_ssl:connect(IP,Port,[]),
	NewState = case Result of
		{ok,Socket}->
			ok = ranch_ssl:setopts(Socket, [{active, once}]),
			State#state{connected = true,socket = Socket};
		{error,Error}->
			lager:log(info,?MODULE,"Connect to ~s:~p fail. Reason: ~p~n",[IP,Port,Error]),
			State
		end,
	{noreply,NewState,HeartBeat};

handle_info(timeout,#state{connected = true,heart_beat = HeartBeat,miss = Miss,socket = Socket} = State)->
	lager:log(info,?MODULE,"Heart Beat"),
	NewState = if 
			Miss > 2 ->
				ranch_ssl:close(Socket),
				loop_close(),
				State#state{connected = false,miss = 0,socket = undefined};
			true -> 
				Packet = pack(0,0,<<>>),
				ranch_ssl:send(Socket,Packet),
	 			State#state{miss = Miss + 1}
	 		end,
	{noreply,NewState,HeartBeat};

handle_info({'DOWN', _MonitorRef, process, Pid, _Info},#state{socket = Socket} = State) -> 
	hm_misc:demonitor(Pid,multiplex_monitor),
	case ets:match_object(multiplex_mapper,{'_',Pid}) of
		[] ->
			{noreply,State};
		[{ID,Pid}] ->
			Close = pack(ID,3,<<>>),
			ets:delete(multiplex_mapper,ID),
			ranch_ssl:send(Socket,Close),
  		{noreply, State}
  end;

handle_info(_Info, State) ->
	{noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
	lager:log(info,?MODULE,"stop"),
	ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
loop_close()->
	case ets:match_object(multiplex_mapper,{'_','_'}) of
		[] ->
			ok;
		Any ->
			loop_close(Any)
  end.
loop_close([])->
	ok;
loop_close([H|T])->
	{ID,_Pid} = H,
	remote_close(ID),
	loop_close(T).

remote_close(ID)->
	case ets:match_object(multiplex_mapper,{ID,'_'}) of
		[] ->
			ok;
		[{ID,Pid}] ->
			ets:delete(multiplex_mapper,ID),
			hm_misc:demonitor(Pid,multiplex_monitor),
  		Pid ! {remote_close},
  		ok
  end.
to_client(ID,Bin)->
	case ets:match_object(multiplex_mapper,{ID,'_'}) of
		[] ->
			ok;
		[{ID,Pid}] ->
  		Pid ! {to_client,Bin},
  		ok
  end.

packet([],State)->
	State;
packet([<<0:64/integer,0:32/integer>>|T],State)->
	Miss = State#state.miss,
	NewState = State#state{miss = Miss - 1},
	lager:log(info,?MODULE,"pong~n"),
	packet(T,NewState);

packet([<<ID:64/integer,2:32/integer,Rest/bits>>|T],State)->
	lager:log(info,?MODULE,"free->->client~n"),
	to_client(ID,Rest),
	packet(T,State);
packet([<<ID:64/integer,3:32/integer,_Rest/bits>>|T],State)->
	lager:log(info,?MODULE,"free close~n"),
	remote_close(ID),
	packet(T,State).

pack(ID,OP,Data)->
	R1 = <<ID:64/integer,OP:32/integer,Data/bits>>,
	Len = erlang:byte_size(R1),
	<<Len:32/big,R1/bits>>.

unpack(Data,Acc) when byte_size(Data) < 4 ->
	{lists:reverse(Acc),Data};
unpack(<<Len:32/big,PayLoad/bits>> = Data,Acc) when Len > byte_size(PayLoad) ->
	{lists:reverse(Acc),Data};
unpack(<<Len:32/big, _/bits >> = Data, Acc) ->                                                                                                                                                                                                                                                 
  << _:32/big,Packet:Len/binary, Rest/bits >> = Data,
  unpack(Rest,[Packet|Acc]).