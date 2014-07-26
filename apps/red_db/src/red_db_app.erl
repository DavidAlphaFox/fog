-module(red_db_app).

-behaviour(application).
-include("priv/red_db.hrl").
%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
	application:start(hasher),
	Port = red_config:get(port),
	MaxWorker = red_config:get(max_worker),
	AcceptorWorker = red_config:get(acceptor_worker),
	MaxDB = red_config:get(max_db),
  {ok, _} = ranch:start_listener(red_db,AcceptorWorker,
                ranch_tcp, [{port, Port}], redis_protocol, []),
  ranch:set_max_connections(red_db,MaxWorker),
  init_db(),
  init_tables(MaxDB),
  red_db_sup:start_link().

stop(_State) ->
  ok.


%%% @doc get directory of mnesia
-spec mneisa_dir() -> list().
mneisa_dir() ->
 mnesia:system_info(directory).

%%% @doc check directory of mnesia exsists
-spec ensure_mnesia_dir()-> ok | no_return().
ensure_mnesia_dir() ->
    MnesiaDir = mneisa_dir() ++ "/",
    case filelib:ensure_dir(MnesiaDir) of
        {error, Reason} ->
            throw({error, {cannot_create_mnesia_dir, MnesiaDir, Reason}});
        ok ->
            ok
    end.


init_mnesia()->
	case mnesia:system_info(is_running) of
		yes ->
			application:stop(mnesia),
			ok = mnesia:create_schema([node()]),
			application:start(mnesia);
		_->
			ok = mnesia:create_schema([node()]),
			application:start(mnesia)
		end.

persist_schema()->
	StorageType = mnesia:table_info(schema, storage_type),
	if 
		StorageType /= disc_copies ->
      case mnesia:change_table_copy_type(schema, node(), disc_copies) of
      	{atomic, ok}->
      		true;
      	{aborted, _R}->
      		false
     	end;
    true -> 
     	true
  end.

init_db()->
	ensure_mnesia_dir(),
	application:start(mnesia),
	case persist_schema() of
		true ->
			ok;
		false ->
			init_mnesia()
	end.
	

create_tables(Tables)->
	Fun = fun(Table)->
			case mnesia:create_table(Table,[{attributes,record_info(fields,red_item)},{disc_copies,[node()]}]) of
				{atomic, ok}->
					true;
				{aborted, Reason}->
					false
			end
		end,
	true = lists:all(Fun,Tables).

init_tables(Count)->
	Seq = lists:seq(0, Count - 1),
	Tables = lists:map(fun(I) ->
			red_db:db(I)
			end,Seq),
	TimeOut = red_config:get(table_timeout),
	case mnesia:wait_for_tables(Tables, TimeOut) of
  	ok ->
    	ok;
    {timeout, BadTables} ->
    	create_tables(BadTables);
    {error, Reason} ->
      throw({error, {failed_waiting_for_tables, Reason}})
   end.
