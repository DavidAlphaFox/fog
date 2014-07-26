-module(red_config).
-export([get/1]).

get(Key) ->
   case application:get_env(red_db,Key) of
        undefined ->
            undefined;
        {ok,Val} ->
            Val
    end.