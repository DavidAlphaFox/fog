-module(nx_pool_sup).
-behaviour(supervisor).
-export([start_link/2, init/1]).

start_link(Mod, Args) ->
    supervisor:start_link(?MODULE, {Mod, Args}).

init({Mod, Args}) ->
	RestartStrategy = {simple_one_for_one, 0, 1},
	MFA = {Mod, start_link, [Args]},
	Child = {Mod,MFA,temporary, 5000, worker, [Mod]},
    {ok, {RestartStrategy,[Child]}}.