-record(state, {
    incoming_socket :: gen_tcp:socket(),
    client_ip :: inet:ip_address(),
    client_port :: inet:port_number(),
    auth_methods :: list(),
    transport :: module(),
    id :: integer(),
    buffer,
    connected,
    multiplex
}).

-define(TIMEOUT, timer:seconds(5)).
-define(AUTH_NOAUTH, 16#00).
-define(AUTH_UNDEF, 16#FF).

-define(VERSION4, 16#04).
-define(VERSION5, 16#05).
