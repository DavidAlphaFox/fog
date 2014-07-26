%%%-------------------------------------------------------------------                                                          
%%% @author David.Gao <david.alpha.fox@gmail.com>                                                                                                                                     
%%% @copyright (C) 2014                                                                                  
%%% @doc redis protocol parser                                                                                                   
%%% @end                                                                                                                        
%%%------------------------------------------------------------------
-module(redis_parser).
-include("priv/red_db.hrl").
-export([parse_error/2,parse_command/1]).

parse_error(Cmd, unsupported) -> <<Cmd/binary, " unsupported in this version">>;
parse_error(Cmd, nested) -> <<Cmd/binary, " calls can not be nested">>;
parse_error(Cmd, out_of_multi) -> <<Cmd/binary, " without MULTI">>;
parse_error(Cmd, not_in_multi) -> <<Cmd/binary, " inside MULTI is not allowed">>;
parse_error(_Cmd, db_in_multi) -> <<"Transactions may include just one database">>;
parse_error(Cmd, out_of_pubsub) -> <<Cmd/binary, " outside PUBSUB mode is not allowed">>;
parse_error(_Cmd, not_in_pubsub) -> <<"only (P)SUBSCRIBE / (P)UNSUBSCRIBE / QUIT allowed in this context">>;
parse_error(Cmd, unknown_command) -> <<"unknown command '", Cmd/binary, "'">>;
parse_error(_Cmd, no_such_key) -> <<"no such key">>;
parse_error(_Cmd, syntax) -> <<"syntax error">>;
parse_error(_Cmd, not_integer) -> <<"value is not an integer or out of range">>;
parse_error(_Cmd, {not_integer, Field}) -> [Field, " is not an integer or out of range"];
parse_error(_Cmd, {not_float, Field}) -> [Field, " is not a double"];
parse_error(_Cmd, {out_of_range, Field}) -> [Field, " is out of range"];
parse_error(_Cmd, {is_negative, Field}) -> [Field, " is negative"];
parse_error(_Cmd, not_float) -> <<"value is not a double">>;
parse_error(_Cmd, bad_item_type) -> <<"Operation against a key holding the wrong kind of value">>;
parse_error(_Cmd, source_equals_destination) -> <<"source and destinantion objects are the same">>;
parse_error(Cmd, bad_arg_num) -> <<"wrong number of arguments for '", Cmd/binary, "' command">>;
parse_error(_Cmd, {bad_arg_num, SubCmd}) -> ["wrong number of arguments for ", SubCmd];
parse_error(_Cmd, unauthorized) -> <<"operation not permitted">>;
parse_error(_Cmd, nan_result) -> <<"resulting score is not a number (NaN)">>;
parse_error(_Cmd, auth_not_allowed) -> <<"Client sent AUTH, but no password is set">>;
parse_error(_Cmd, {error, Reason}) -> Reason;
parse_error(_Cmd, Error) -> io_lib:format("~p", [Error]).

-spec parse_command(#redis_command{args :: [binary()]}) -> #redis_command{}.
parse_command(C = #redis_command{cmd = <<"QUIT">>, args = []}) ->
 C#redis_command{result_type = ok, group=connection};
parse_command(#redis_command{cmd = <<"QUIT">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"PING">>, args = []}) -> 
  C#redis_command{result_type = string, group=connection};
parse_command(#redis_command{cmd = <<"PING">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"DECR">>, args = [_Key]}) -> 
  C#redis_command{result_type = number, group=strings};
parse_command(#redis_command{cmd = <<"DECR">>}) ->
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"DECRBY">>, args = [Key, Decrement]}) -> 
  C#redis_command{args = [Key, binary_to_integer(Decrement)],result_type = number, group=strings};
parse_command(#redis_command{cmd = <<"DECRBY">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"INCR">>, args = [_Key]}) -> 
  C#redis_command{result_type = number, group=strings};
parse_command(#redis_command{cmd = <<"INCR">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"INCRBY">>, args = [Key, Increment]}) -> 
  C#redis_command{args = [Key, binary_to_integer(Increment)], result_type = number, group=strings};
parse_command(#redis_command{cmd = <<"INCRBY">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"GET">>, args = [_Key]}) -> 
  C#redis_command{result_type = bulk, group=strings};
parse_command(#redis_command{cmd = <<"GET">>}) -> 
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = <<"SELECT">>, args = [Db]}) ->
  C#redis_command{args = [binary_to_integer(Db)],result_type = ok, group = connection};
parse_command(#redis_command{cmd = <<"SELECT">>}) ->
  throw(bad_arg_num);
parse_command(C = #redis_command{cmd = _Any}) -> 
  C#redis_command{ result_type = string, group=strings}.
