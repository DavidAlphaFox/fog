-module(nx_pool).
-behaviour(gen_server).
-export([
         execute/1,
         start_link/0,
         stop/1]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-record(state, {
    supervisors :: [{pid(),integer()}],
    workers :: [pid()],
    waiting :: [pid()],
    monitors :: ets:tid(),

    }).

execute(Pool,Fun) ->
    case gen_server:call(Pool, check_out) of
        {ok, Pid} ->
            try {ok, Fun(Pid)}
            catch _:E -> {error, E}
            after gen_server:cast(Pool, {check_in, Pid}) end;
        {error, E} -> {error, E}
    end.
start_link(Pool,Mods) -> 
    gen_server:start_link({local, Pool}, ?MODULE, Mods, []).

stop(Pool) -> 
    gen_server:cast(Pool, stop).

%% @hidden
init(Mods) ->
    process_flag(trap_exit, true),
    Waiting = queue:new(),
    Monitors = ets:new(monitors, [private]),
    State = #state{waiting = Waiting, monitors = Monitors},
    {ok,State}.

handle_call(_Request, _From, State) -> {reply, ok, State}.

%% @hidden
handle_cast({check_in, Pid}, State=#state{pids=Pids}) ->
    NewPids = queue:in(Pid, Pids),
    {noreply, State#state{pids=NewPids}};
handle_cast(stop, State) -> {stop, normal, State};
handle_cast(_Msg, State) -> {noreply, State}.

%% @hidden
handle_info(_Info, State) -> {noreply, State}.

%% @hidden
terminate(_Reason, undefined) -> ok;
terminate(_Reason, #state{pids=Pids}) ->
    StopFun =
        fun(Pid) ->
            case is_process_alive(Pid) of
                true -> riakc_pb_socket:stop(Pid);
                false -> ok
            end
        end,
    [StopFun(Pid) || Pid <- queue:to_list(Pids)], ok.

%% @hidden
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% @doc Returns a state with a single pid if a connection could be established,
%% otherwise returns undefined.
-spec new_state(host(), integer()) -> #state{} | undefined.
new_state(Host, Port) ->
    case new_connection(Host, Port) of
        {ok, Pid} ->
            #state{host=Host, port=Port, pids=queue:in(Pid, queue:new())};
        error -> undefined
    end.

%% @doc Returns {ok, Pid} if a new connection was established and added to the
%% supervisor, otherwise returns error.
-spec new_connection(host(), integer()) -> {ok, pid()} | error.
new_connection(Host, Port) ->
    case supervisor:start_child(riakpool_connection_sup, [Host, Port]) of
        {ok, Pid} when is_pid(Pid) -> {ok, Pid};
        {ok, Pid, _} when is_pid(Pid) -> {ok, Pid};
        _ -> error
    end.

%% @doc Recursively dequeues Pids in search of a live connection. Dead
%% connections are removed from the queue as it is searched. If no connection
%% pid could be found, a new one will be established. Returns {ok, Pid, NewPids}
%% where NewPids is the queue after any necessary dequeues. Returns error if no
%% live connection could be found and no new connection could be established.
-spec next_pid(host(), integer(), queue()) -> {ok, pid(), queue()} |
                                              {error, queue()}.
next_pid(Host, Port, Pids) ->
    case queue:out(Pids) of
        {{value, Pid}, NewPids} ->
            case is_process_alive(Pid) of
                true -> {ok, Pid, NewPids};
                false -> next_pid(Host, Port, NewPids)
            end;
        {empty, _} ->
            case new_connection(Host, Port) of
                {ok, Pid} -> {ok, Pid, Pids};
                error -> {error, Pids}
            end
    end.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

execute_test() ->
    riakpool_connection_sup:start_link(),
    riakpool:start_link(),
    riakpool:start_pool(),
    ?assertEqual(1, count()),
    Fun1 = fun(C) -> riakc_pb_socket:ping(C) end,
    Fun2 = fun(_) -> riakc_pb_socket:ping(1) end,
    ?assertEqual({ok, pong}, execute(Fun1)),
    ?assertMatch({error, _}, execute(Fun2)),
    ?assertEqual({ok, pong}, execute(Fun1)),
    riakpool:stop(),
    timer:sleep(10),
    ?assertEqual(0, count()).

execute_error_test() ->
    riakpool:start_link(),
    Fun = fun(C) -> riakc_pb_socket:ping(C) end,
    ?assertEqual({error, pool_not_started}, execute(Fun)),
    riakpool:stop(),
    timer:sleep(10),
    ?assertEqual(0, count()).

start_pool_test() ->
    riakpool_connection_sup:start_link(),
    riakpool:start_link(),
    {H, P} = {"localhost", 8000},
    ?assertEqual({error, connection_error}, riakpool:start_pool(H, P)),
    ?assertEqual(ok, riakpool:start_pool()),
    ?assertEqual({error, pool_already_started}, riakpool:start_pool()),
    riakpool:stop(),
    timer:sleep(10),
    ?assertEqual(0, count()).

next_pid_test() ->
    riakpool_connection_sup:start_link(),
    {H, P} = {"localhost", 8087},
    ?assertEqual(0, count()),
    {ok, P1} = new_connection(H, P),
    {ok, P2} = new_connection(H, P),
    {ok, P3} = new_connection(H, P),
    ?assertEqual(3, count()),
    riakc_pb_socket:stop(P1),
    riakc_pb_socket:stop(P2),
    ?assertEqual(1, count()),
    Q0 = queue:new(),
    Q = queue:from_list([P1, P2, P3]),
    ?assertMatch({ok, P3, Q0}, next_pid(H, P, Q)),
    riakc_pb_socket:stop(P3),
    {ok, P4, Q0} = next_pid(H, P, Q0),
    ?assertEqual(1, count()),
    riakc_pb_socket:stop(P4),
    ?assertEqual(0, count()).

next_pid_error_test() ->
    {H, P} = {"localhost", 8000},
    Q0 = queue:new(),
    ?assertMatch({error, Q0}, next_pid(H, P, Q0)).

-endif.
