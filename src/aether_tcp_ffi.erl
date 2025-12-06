%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% Aether TCP FFI Module
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%%
%% Helper functions for TCP socket operations.
%%

-module(aether_tcp_ffi).

-export([
    connect/5,
    connect_timeout/6,
    decode_ipv4_tuple/1
]).

%% @doc Connects to a remote TCP host with simplified options.
%% Host should be a binary string (Gleam String).
-spec connect(Host :: binary(), Port :: integer(), Reuseaddr :: boolean(),
              Nodelay :: boolean(), Keepalive :: boolean()) ->
    {ok, gen_tcp:socket()} | {error, atom()}.
connect(Host, Port, Reuseaddr, Nodelay, Keepalive) ->
    HostList = binary_to_list(Host),
    Opts = build_connect_opts(Reuseaddr, Nodelay, Keepalive),
    gen_tcp:connect(HostList, Port, Opts).

%% @doc Connects to a remote TCP host with timeout.
-spec connect_timeout(Host :: binary(), Port :: integer(), Reuseaddr :: boolean(),
                      Nodelay :: boolean(), Keepalive :: boolean(), Timeout :: integer()) ->
    {ok, gen_tcp:socket()} | {error, atom()}.
connect_timeout(Host, Port, Reuseaddr, Nodelay, Keepalive, Timeout) ->
    HostList = binary_to_list(Host),
    Opts = build_connect_opts(Reuseaddr, Nodelay, Keepalive),
    gen_tcp:connect(HostList, Port, Opts, Timeout).

%% @doc Builds the options list for TCP connect.
build_connect_opts(Reuseaddr, Nodelay, Keepalive) ->
    [
        binary,
        {active, false},
        {reuseaddr, Reuseaddr},
        {nodelay, Nodelay},
        {keepalive, Keepalive}
    ].

%% @doc Decodes a 4-element tuple (for IPv4 addresses).
-spec decode_ipv4_tuple(tuple()) -> {ok, {integer(), integer(), integer(), integer()}} | {error, nil}.
decode_ipv4_tuple(Tuple) when is_tuple(Tuple), tuple_size(Tuple) =:= 4 ->
    {A, B, C, D} = Tuple,
    case is_integer(A) andalso is_integer(B) andalso is_integer(C) andalso is_integer(D) of
        true -> {ok, {A, B, C, D}};
        false -> {error, nil}
    end;
decode_ipv4_tuple(_) ->
    {error, nil}.
