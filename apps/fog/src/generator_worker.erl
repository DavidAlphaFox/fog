% The id server will generate a 64-bit integer base on utc time.
% The id is k-order shortable
% 
%
% Bits                      Description      
% 1      Signeddness flag,always 0.Because thrift only supports signed 64-bit integer And I don't want a negtive integer.
% 41     Unix timestamp,down to the millisecond      
% 5      Top 5 bits of node number
% 5      then 5 bits of partition number 
% 12     Per-partition static increasing counter
% +------------------+------------------+--------------+
% |0|1     ...     41|42      ...     51|52   ...    63|
% +------------------+------------------+--------------+     
% |0| Unix Timestamp | Partition Number |    Counter   |
%


-module(generator_worker).

-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
                            terminate/2, code_change/3]).
-export ([gen_id/0]).

%-define (EPOCH,1356998400974295).%2013-1-1 0:0:0 {1356,998400,974295} microseconds

-define (EPOCH,1356998400974). %2013-1-1 0:0:0 {1356,998400,974295} milliseconds

-record(state,{ partition,
                node_id = 0,
                worker_id = 0,
                sequence = 0,
                last_timestamp}).


start_link(Args)->
    PartitionInteger = proplists:get_value(partition,Args),
	NodeIntger = proplists:get_value(node_id,Args),
    gen_server:start_link({local,?MODULE},?MODULE,{NodeIntger,PartitionInteger},[]).

%%%
%%% API
%%%

gen_id()->
    gen_server:call(?MODULE,gen_id).

%%%
%%% gen_server callback
%%%

init(Args)->
    timer:sleep(1),
    TS = timestamp(),
	{Node,Partition} = Args,
	case {Node,Partition} of
		{undefined,_}->
			{stop,error_node};
		{_,undefined}->
			{stop,error_partition};
		_->
			RelPartition = <<Node:5/integer-unsigned,Partition:5/integer-unsigned>>,
			lager:log(info,generator_worker,"starting partition:~p~n",[{Node,Partition}]),
			{ok,#state{
                partition = RelPartition,
                node_id = Node,
                worker_id = Partition,
                sequence = 0,
                last_timestamp = TS}}
	end.

handle_call(gen_id,From, #state{last_timestamp = TS, sequence = Seq, partition = Partition} = State) ->
    case get_next_seq(TS, Seq) of
        backwards_clock ->
            {reply, {fail, backwards_clock}, State};
        exhausted ->
            timer:sleep(1),
            handle_call(gen_id, From, State);
        {ok, Time, NewSeq} ->
            {reply, construct_id(Time, Partition, NewSeq), State#state{last_timestamp = Time, sequence = NewSeq}}
    end;

handle_call(_Msg,_From,State)->
    {reply,ok,State}.

handle_cast(_Msg,State)->
    {noreply,State}.

handle_info(_Msg,State)->
    {noreply,State}.

terminate(_Reason, #state{partition = RelPartition}) ->
	<<Node:5/integer-unsigned,Partition:5/integer-unsigned>> = RelPartition,
	lager:log(info,generator_worker,"stoping partition:~p~n",[{Node,Partition}]),
    ok.

code_change(_Old, State, _Extra) ->
    {ok, State}.

%%%
%%% inner functions
%%%

time_milli()->
    {Mega,Sec,Micro} = erlang:now(),
    (Mega * 1000000 + Sec) *1000 + Micro div 1000. 

timestamp()->
	Now = time_milli(),
	DiffMillis = Now - ?EPOCH,
	DiffMillis.

get_next_seq(Time, Seq) ->
    Now = timestamp(),
    if
        % Time is essentially equal at the millisecond
        Now =:= Time ->
            case (Seq + 1) rem 4096 of
                0 ->
					exhausted;
                NewSeq ->
					{ok, Now, NewSeq}
            end;
        % Woops, clock was moved backwards by NTP
        Now < Time ->
            backwards_clock;
        % New millisecond
        true ->
            {ok, Now, 0}
    end.

construct_id(Millis, Partition, Seq) ->
    <<Integer:64/integer>> = <<0:1, Millis:41/integer-unsigned,
                               Partition:10/bits, Seq:12/integer-unsigned>>,
    Integer.
