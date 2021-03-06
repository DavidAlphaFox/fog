
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
 	IDMFA = {fog_id,start_link,[RemoteConf]},
 	IDWorker = {fog_id,IDMFA,permanent,5000,worker,[]}, 

 	BalanceMFA = {fog_lb,start_link,[[]]},
 	BalanceWorker = {fog_lb,BalanceMFA,permanent,5000,worker,[]}, 

 	MultiplexSupMFA = {fog_multiplex_sup,start_link,[]},
 	MultiplexSupervisor = {fog_multiplex_sup,MultiplexSupMFA,permanent,5000,supervisor,[]},

	Children = [IDWorker,BalanceWorker,MultiplexSupervisor],
  {ok, { RestartStrategy,Children} }.

