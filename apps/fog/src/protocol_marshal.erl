-module(protocol_marshal).
-include("priv/protocol.hrl").
-export ([read/1,write/3]).
read(Data)->
	{Packets,Rest} = unpack(Data,[]),
	Cmds = decode(Packets),
	{Cmds,Rest}.

decode([])->
	[];
decode(Packets)->
	decode(Packets,[]).

decode([],Acc)->
	lists:reverse(Acc);
decode([H|T],Acc)->
	{{1,Channel},Rest0} = binary_marshal:decode(H,sint64),
	{{2,Cmd},Rest1} = binary_marshal:decode(Rest0,sint32),
	R = case Cmd of 
		?REQ_PING ->
			[{Cmd,Channel,<<>>}| Acc];
		?REQ_CHANNEL ->
			[{Cmd,Channel,<<>>}| Acc];
		?REQ_CONNECT ->
			{{3,Payload},_Rest2} = binary_marshal:decode(Rest1,string),
			[{Cmd,Channel,Payload}| Acc];
		?REQ_DATA ->
			{{3,Payload},_Rest2} = binary_marshal:decode(Rest1,string),
			[{Cmd,Channel,Payload}| Acc];
		?REQ_CLOSE ->
			[{Cmd,Channel,<<>>}| Acc]
		end,
	decode(T,R).

unpack(Data,Acc) when byte_size(Data) < 4 ->
	{lists:reverse(Acc),Data};
unpack(<<Len:32/big,Payload/bits>> = Data,Acc) when Len > byte_size(Payload) ->
	{lists:reverse(Acc),Data};
unpack(<<Len:32/big, _/bits >> = Data, Acc) ->                                                                                                                                                                                                                                                 
	<< _:32/big,Packet:Len/binary, Rest/bits >> = Data,
  	unpack(Rest,[Packet|Acc]).

write(?RSP_PONG,_,_)->
	ID = binary_marshal:encode(1,?CMD_CHANNEL,sint64),
	Cmd = binary_marshal:encode(2,?RSP_PONG,sint32),
	pack(ID,Cmd,<<>>);
write(?RSP_CHANNEL,_,Data)->
	ID = binary_marshal:encode(1,?CMD_CHANNEL,sint64),
	Cmd = binary_marshal:encode(2,?RSP_CHANNEL,sint32),
	Payload = binary_marshal:encode(3,Data,sint64),
	pack(ID,Cmd,Payload);
write(?RSP_CONNECT,Channel,_)->
	ID = binary_marshal:encode(1,Channel,sint64),
	Cmd = binary_marshal:encode(2,?RSP_CONNECT,sint32),
	pack(ID,Cmd,<<>>);
write(?RSP_DATA,Channel,Data)->
	ID = binary_marshal:encode(1,Channel,sint64),
	Cmd = binary_marshal:encode(2,?RSP_DATA,sint32),
	Payload = binary_marshal:encode(3,Data,string),
	pack(ID,Cmd,Payload);
write(?RSP_CLOSE,Channel,_)->
	ID = binary_marshal:encode(1,Channel,sint64),
	Cmd = binary_marshal:encode(2,?RSP_CLOSE,sint32),
	pack(ID,Cmd,<<>>).

pack(ID,Cmd,Payload)->
	R1 = <<ID/bits,Cmd/bits,Payload/bits>>,
	Len = erlang:byte_size(R1),
	<<Len:32/big,R1/bits>>.