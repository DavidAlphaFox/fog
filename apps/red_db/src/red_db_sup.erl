
-module(red_db_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	RestartStrategy = {one_for_one, 5, 10},
	Count = red_config:get(max_db),
  Children =
    [{red_db:db(I), {red_db, start_link, [I]},
      permanent, brutal_kill, worker, [red_db]}
     || I <- lists:seq(0, Count - 1)],
    {ok, { RestartStrategy,Children} }.

