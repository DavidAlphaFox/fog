-module(fog_app).

-behaviour(application).
%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
	Port = fog_config:get(port),
	MaxWorker = fog_config:get(max_worker),
	AcceptorWorker = fog_config:get(acceptor_worker),
	{ok, _} = ranch:start_listener(fog,AcceptorWorker,
                ranch_tcp, [{port, Port}], socks_protocol, []),
	ranch:set_max_connections(fog,MaxWorker),
	fog_sup:start_link().

stop(_State) ->
  ok.

