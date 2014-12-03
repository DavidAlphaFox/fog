
-define(CMD_CHANNEL,0).

-define(REQ_PING,0).
-define(REQ_CHANNEL,1).
-define(REQ_CONNECT,2).
-define(REQ_DATA,3).
-define(REQ_CLOSE,4).

-define(RSP_PONG,0).
-define(RSP_CHANNEL,1).
-define(RSP_CONNECT,2).
-define(RSP_DATA,3).
-define(RSP_CLOSE,4).

-define(IPV4, 16#01).
-define(IPV6, 16#04).
-define(DOMAIN, 16#03).