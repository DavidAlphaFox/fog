
-module(fog_sup).

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
	GeneratorMFA = {generator_worker, start_link, [[{partition,0},{node_id,0}]]},                                                                
 	GeneratorWorker = {generator_worker,GeneratorMFA,permanent,5000,worker,[]}, 
	Children = [GeneratorWorker],
  {ok, { RestartStrategy,Children} }.

