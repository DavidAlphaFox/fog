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
-export([connect/3,channel/1,recv_data/2,close/1]).
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

start_link(Args) ->
	IP = proplists:get_value(ip,Args),
	Port = proplists:get_value(port,Args),
	HeartBeat = proplists:get_value(heart_beat,Args),
	gen_server:start_link({local, ?SERVER}, ?MODULE, {IP,Port,HeartBeat}, []).

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

handle_call({fetch,Pid,ID,Address,Port},_From,#state{heart_beat = HeartBeat,socket = Socket} = State)->
	{AType,Address2} = Address,
	Addr = <<Address2/binary>>,
	AddrLen = erlang:byte_size(Addr), 
	Data = <<AType:8,AddrLen:32/big,Addr/binary,Port:16/big>>,
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

terminate(_Reason, _State) ->
	lager:log(info,?MODULE,"stop"),
	ok.
	
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.
