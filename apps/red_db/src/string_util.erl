-module(string_util).

-export ([upper/1,lower/1]).
%%% @doc converts all characters in the specified binary to uppercase. 
-spec upper(binary()) -> binary().
upper(Bin) ->
  upper(Bin, <<>>).

%% @private
upper(<<>>, Acc) ->
  Acc;
upper(<<C, Rest/binary>>, Acc) when $a =< C, C =< $z ->
  upper(Rest, <<Acc/binary, (C-32)>>);
upper(<<195, C, Rest/binary>>, Acc) when 160 =< C, C =< 182 -> %% A-0 with tildes plus enye
  upper(Rest, <<Acc/binary, 195, (C-32)>>);
upper(<<195, C, Rest/binary>>, Acc) when 184 =< C, C =< 190 -> %% U and Y with tilde plus greeks
  upper(Rest, <<Acc/binary, 195, (C-32)>>);
upper(<<C, Rest/binary>>, Acc) ->
  upper(Rest, <<Acc/binary, C>>).

%% @doc converts all characters in the specified binary to lowercase
-spec lower(binary()) -> binary().
lower(Bin) ->
  lower(Bin, <<>>).

lower(<<>>, Acc) ->
  Acc;
lower(<<C, Rest/binary>>, Acc) when $A =< C, C =< $Z ->
  lower(Rest, <<Acc/binary, (C+32)>>);
lower(<<195, C, Rest/binary>>, Acc) when 128 =< C, C =< 150 -> %% A-0 with tildes plus enye
  lower(Rest, <<Acc/binary, 195, (C+32)>>);
lower(<<195, C, Rest/binary>>, Acc) when 152 =< C, C =< 158 -> %% U and Y with tilde plus greeks
  lower(Rest, <<Acc/binary, 195, (C+32)>>);
lower(<<C, Rest/binary>>, Acc) ->
  lower(Rest, <<Acc/binary, C>>).