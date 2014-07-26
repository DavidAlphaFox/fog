-module(fog_config).
-export([get/1]).

get(Key) ->
   case application:get_env(fog,Key) of
        undefined ->
            undefined;
        {ok,Val} ->
            Val
    end.
