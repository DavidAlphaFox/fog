
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

 	RemoteConf = fog_config:get(remote),
 	MultiplexMFA = {fog_multiplex,start_link,[RemoteConf]},
 	MultiplexWorker = {fog_multiplex,MultiplexMFA,permanent,5000,worker,[]}, 

	Children = [MultiplexWorker],
  {ok, { RestartStrategy,Children} }.

