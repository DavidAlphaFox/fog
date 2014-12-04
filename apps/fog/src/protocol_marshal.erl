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
		?RSP_PONG ->
			[{Cmd,Channel,<<>>}| Acc];
		?RSP_CHANNEL ->
			{{3,Payload},_Rest2} = binary_marshal:decode(Rest1,sint64),
			[{Cmd,Channel,Payload}| Acc];
		?RSP_CONNECT ->	
			[{Cmd,Channel,<<>>}| Acc];
		?RSP_DATA ->
			{{3,Payload},Rest2} = binary_marshal:decode(Rest1,bytes),
			[{Cmd,Channel,Payload}| Acc];
		?RSP_CLOSE ->
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

write(?REQ_PING,_,_)->
	ID = binary_marshal:encode(1,?CMD_CHANNEL,sint64),
	Cmd = binary_marshal:encode(2,?REQ_PING,sint32),
	pack(ID,Cmd,<<>>);
write(?REQ_CHANNEL,_,_)->
	ID = binary_marshal:encode(1,?CMD_CHANNEL,sint64),
	Cmd = binary_marshal:encode(2,?REQ_CHANNEL,sint32),
	pack(ID,Cmd,<<>>);
write(?REQ_CONNECT,Channel,Data)->
	ID = binary_marshal:encode(1,Channel,sint64),
	Cmd = binary_marshal:encode(2,?REQ_CONNECT,sint32),
	Payload = binary_marshal:encode(3,Data,bytes),
	pack(ID,Cmd,Payload);
write(?REQ_DATA,Channel,Data)->
	ID = binary_marshal:encode(1,Channel,sint64),
	Cmd = binary_marshal:encode(2,?REQ_DATA,sint32),
	Payload = binary_marshal:encode(3,Data,bytes),
	pack(ID,Cmd,Payload);
write(?REQ_CLOSE,Channel,_)->
	ID = binary_marshal:encode(1,Channel,sint64),
	Cmd = binary_marshal:encode(2,?REQ_CLOSE,sint32),
	pack(ID,Cmd,<<>>).

pack(ID,Cmd,Payload)->
	R1 = <<ID/bits,Cmd/bits,Payload/bits>>,
	Len = erlang:byte_size(R1),
	<<Len:32/big,R1/bits>>.