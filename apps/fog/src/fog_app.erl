-module(fog_app).

-behaviour(application).
%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
	lager:start(),
	application:start(crypto),
	application:start(ssl),
	application:start(ranch),
	start_socks(),
	fog_sup:start_link().

stop(_State) ->
  ok.

start_socks()->
	SocksConf = fog_config:get(socks),
	Port = proplists:get_value(port,SocksConf),
	MaxWorker = proplists:get_value(max_worker,SocksConf),
	AcceptorWorker = proplists:get_value(acceptor_worker,SocksConf),
	{ok, _} = ranch:start_listener(fog_socks,AcceptorWorker,
                ranch_tcp, [{port, Port}], socks_protocol, []),
	ranch:set_max_connections(fog_socks,MaxWorker).
