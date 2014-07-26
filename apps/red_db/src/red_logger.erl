-module(red_logger).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
				logger :: atom()
        }).
-type state() :: #state{}.
-define(DEFAULT_TIMEOUT, 5000).

-spec logger(non_neg_integer()) -> atom().
logger(Index) ->
  list_to_atom("red_log_" ++ integer_to_list(Index)).

-spec start_link(non_neg_integer()) -> {ok, pid()}.
%%% @doc starts a new logger client
start_link(Index) ->
  gen_server:start_link({local,logger(Index)}, ?MODULE, Index, []).

-spec init(non_neg_integer()) -> {ok, state()} | {stop, any()}.
init(Index) ->
	Logger = logger(Index),
	{ok,#state{logger = Logger}}.



