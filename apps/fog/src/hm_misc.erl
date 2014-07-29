-module(hm_misc).
-export([monitor/2,demonitor/2]).

monitor(Pid,Tab) ->
	case ets:match_object(Tab, {Pid,'_'}) of
  	[] ->
    	M = erlang:monitor(process, Pid),
      ets:insert(Tab, {Pid, M});
    _ ->
    	ok
  end.

demonitor(Pid,Tab) ->
  case ets:match_object(Tab,{Pid,'_'}) of
  	[{Pid,Ref}] ->
	  	erlang:demonitor(Ref),
      ets:delete(Tab,Pid),
			ok;
    [] ->
	    ok
  end.