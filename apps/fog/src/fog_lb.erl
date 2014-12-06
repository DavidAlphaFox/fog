%%%-------------------------------------------------------------------
%%% @author David Alpha Fox <>
%%% @copyright (C) 2014, David Alpha Fox
%%% @doc
%%%
%%% @end
%%% Created : 29 Jul 2014 by David Alpha Fox <>
%%%-------------------------------------------------------------------
-module(fog_lb).

-behaviour(gen_server).
-define(SERVER, ?MODULE).
-define(TIMEOUT, timer:seconds(30)).
%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
		 terminate/2, code_change/3]).
-export([enqueue/0,lock_one/0]).

-record(state, {
		multiplexes,
		monitor
	}).
enqueue()->
	Pid  = self(),
	gen_server:cast(?SERVER,{enqueue,Pid}).

lock_one()->
	Pid  = self(),
	gen_server:cast(?SERVER,{lock_one,Pid}),
    receive
    	{multiplex, undefined} ->
    		throw({multiplex_undefined});
    	{multiplex, Multiplex} -> 
    		{ok,Multiplex}
        after ?TIMEOUT ->
        	throw({multiplex_timeout})
    end.

start_link(Args) ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
	State = #state{
		multiplexes = queue:new(),
		monitor  = ets:new(multiplex_monitor, [ordered_set, protected])  
	},  
	{ok,State}.

handle_call(_Request, _From, State) ->
	Reply = ok,
	{reply, Reply, State}.
handle_cast({lock_one,Pid},State)->
	One = queue:out(State#state.multiplexes),
	case One of
		{{value, Multiplex},Multiplexes} ->
			NewMultiplexes = queue:in(Multiplex,Multiplexes),
			erlang:send(Pid,{multiplex,Multiplex}),
			{noreply,State#state{multiplexes =  NewMultiplexes}};
		_->
			erlang:send(Pid,{multiplex,undefined}),
			{noreply,State}
	end;
handle_cast({enqueue,Pid},State)->
	Multiplexes =  queue:in(Pid, State#state.multiplexes),
	hm_misc:monitor(Pid,State#state.monitor),
	{noreply,State#state{multiplexes =  Multiplexes}};
handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info({'DOWN', MonitorRef, process, Pid, _Info},State) -> 
	case ets:match_object(State#state.monitor,{Pid,'_'}) of
		[] ->
			{noreply,State};
		[{Pid,MonitorRef}] ->
			ets:delete(State#state.monitor,Pid),
			Multiplexes = queue:filter(
                     fun(Q) -> Q =/= Pid end,
                     State#state.multiplexes),
  			{noreply, State#state{multiplexes =  Multiplexes}}
	end;

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.
