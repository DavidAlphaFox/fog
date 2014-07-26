-module(red_db).
-behaviour(gen_server).
-include("priv/red_db.hrl").
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([db/1,run/2,run/3]).

-record(state, {
				db :: atom()
        }).
-type state() :: #state{}.
-define(DEFAULT_TIMEOUT, 5000).

%%% =================================================================================================
%%% External functions
%%% =================================================================================================
run(Db, Command) ->
  run(Db, Command, ?DEFAULT_TIMEOUT).

run(Db, Command, Timeout) ->
  try gen_server:call(Db, Command,Timeout) of
    ok -> 
    	ok;
    {ok, Reply} -> 
    	Reply;
    {error, Error} ->
      throw(Error)
  catch
    _:{timeout, _} ->
      throw(timeout)
  end.


-spec start_link(non_neg_integer()) -> {ok, pid()}.
%%% @doc starts a new db client
start_link(Index) ->
  gen_server:start_link({local,db(Index)}, ?MODULE, Index, []).
%%% =================================================================================================
%%% Server functions
%%% =================================================================================================
%%% @hidden

-spec init(non_neg_integer()) -> {ok, state()} | {stop, any()}.
init(Index) ->
	DB = db(Index),
	{ok,#state{db = DB}}.

handle_call(#redis_command{cmd = <<"INCR">>, args = [Key]}, From, State) ->
  handle_call(#redis_command{cmd = <<"INCRBY">>, args = [Key, 1]}, From, State);
handle_call(#redis_command{cmd = <<"INCRBY">>, args = [Key, Increment]}, _From, State) ->
  Reply =
    update(Key,State,
           fun(Item = #red_item{value = OldV}) ->
                   try binary_to_integer(OldV) of
                     OldInt ->
                       Res = OldInt + Increment,
                       {Res, Item#red_item{value = integer_to_binary(Res)}}
                   catch
                     _:badarg ->
                       throw(not_integer)
                   end
           end, <<"0">>),
  {reply, Reply, State};

handle_call(#redis_command{cmd = <<"DECR">>, args = [Key]}, From, State) ->
  handle_call(#redis_command{cmd = <<"DECRBY">>, args = [Key, 1]}, From, State);
handle_call(#redis_command{cmd = <<"DECRBY">>, args = [Key, Decrement]}, _From, State) ->
  Reply =
    update(Key,State,
           fun(Item = #red_item{value = OldV}) ->
                   try binary_to_integer(OldV) of
                     OldInt ->
                       if
                       	OldInt >= Decrement ->
                       		Res = OldInt - Decrement,
                       		{Res, Item#red_item{value = integer_to_binary(Res)}};
                       	true ->
                       		throw(undefined)
                       end
                   catch
                     _:badarg ->
                       throw(not_integer)
                   end
           end, <<"0">>),
  {reply, Reply, State};

handle_call(#redis_command{cmd = <<"GET">>, args = [Key]}, _From, State) ->
  Reply =
    case get_item(Key,State) of
      [Item] -> 
      	{ok, Item#red_item.value};
      [] -> 
      	{error, undefined};
      {error, Reason} -> 
      	{error, Reason}
    end,
  {reply, Reply,State};

handle_call(Any, _From, State) ->
  {reply, {ok,"R"}, State}.

handle_cast(_Any,State)->
	{noreply,State}.
%% @hidden
-spec handle_info(term(), state()) -> {noreply, state(), hibernate}.
handle_info(_, State) -> 
	{noreply, State, hibernate}.

%% @hidden
-spec terminate(term(), state()) -> ok.
terminate(_, _) -> 
	ok.

%% @hidden
-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) -> 
	{ok, State}.

-spec db(non_neg_integer()) -> atom().
db(Index) ->
  list_to_atom("red_db_" ++ integer_to_list(Index)).

execute_mnesia_transaction(TxFun) ->
	case mnesia:sync_transaction(TxFun) of
  	{atomic,  Result} -> 
  		Result;
    {aborted, Reason} ->
    	throw({error, Reason})
  end.

exists_item(Key,State) ->
  [] /= get_item(Key,State).

set_item(Item,State)->
	DB = State#state.db,	
	Fun = fun()->
    NewItem = {DB,Item#red_item.key, Item#red_item.value},
		mnesia:write(DB,NewItem,write)
	end,
	execute_mnesia_transaction(Fun).

set_item(Key,Value,State)->
	DB = State#state.db,
	Fun = fun()->
			Item = {DB, Key,Value},
			mnesia:write(DB,Item,write)
		end,
	execute_mnesia_transaction(Fun).

get_item(Key,State)->
	DB = State#state.db,
  try
	  R = mnesia:dirty_read(DB,Key),
    lists:map(fun({_,K,V})->
      #red_item{key = K,value = V}
      end,R)
  catch
    exit:Reason ->
      throw({error, Reason})
  end.
  
update(Key,State,Fun,Default)->
	try
		{Res,Item} = 
			case get_item(Key,State) of
				[] ->
					Fun(#red_item{key = Key,value = Default});
				{error,Reason}->
					throw(Reason);
				[OldItem]->
					Fun(OldItem)
			end,
			case set_item(Item,State) of
				ok ->
					{ok,Res}
			end
	catch 
			_:Error ->
				{error,Error}
	end.



