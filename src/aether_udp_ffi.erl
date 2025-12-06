%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% Aether UDP FFI Module
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%%
%% This module provides Erlang FFI functions for UDP socket operations.
%% It wraps gen_udp to provide a consistent interface for Gleam.
%%

-module(aether_udp_ffi).

-export([
    open_simple/2,
    connect/3,
    send/2,
    send_to/4,
    recv/2,
    recv_timeout/3,
    close/1,
    controlling_process/2,
    sockname/1,
    set_active/2,
    decode_ipv4_tuple/1,
    decode_8_tuple/1
]).

%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% Socket Creation
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

%% @doc Opens a UDP socket with simplified options (reuseaddr only).
-spec open_simple(Port :: integer(), Reuseaddr :: boolean()) ->
    {ok, gen_udp:socket()} | {error, atom()}.
open_simple(Port, Reuseaddr) ->
    Opts = [binary, {active, false}, {reuseaddr, Reuseaddr}],
    gen_udp:open(Port, Opts).

%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% Connection (for connected UDP sockets)
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

%% @doc Connects a UDP socket to a remote address.
%% After connecting, send/2 can be used instead of send_to/4.
-spec connect(Socket :: gen_udp:socket(), Host :: binary() | string() | inet:ip_address(), Port :: integer()) ->
    ok | {error, atom()}.
connect(Socket, Host, Port) when is_binary(Host) ->
    connect(Socket, binary_to_list(Host), Port);
connect(Socket, Host, Port) when is_list(Host) ->
    case inet:getaddr(Host, inet) of
        {ok, Addr} -> gen_udp:connect(Socket, Addr, Port);
        Error -> Error
    end;
connect(Socket, Host, Port) ->
    gen_udp:connect(Socket, Host, Port).

%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% Sending Data
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

%% @doc Sends data on a connected UDP socket.
%% Returns {ok, nil} for Gleam Result compatibility.
-spec send(Socket :: gen_udp:socket(), Data :: binary()) ->
    {ok, nil} | {error, atom()}.
send(Socket, Data) ->
    case gen_udp:send(Socket, Data) of
        ok -> {ok, nil};
        Error -> Error
    end.

%% @doc Sends data to a specific address (unconnected UDP).
%% Returns {ok, nil} for Gleam Result compatibility.
-spec send_to(Socket :: gen_udp:socket(), Host :: binary() | string() | inet:ip_address(),
              Port :: integer(), Data :: binary()) ->
    {ok, nil} | {error, atom()}.
send_to(Socket, Host, Port, Data) when is_binary(Host) ->
    send_to(Socket, binary_to_list(Host), Port, Data);
send_to(Socket, Host, Port, Data) when is_list(Host) ->
    case inet:getaddr(Host, inet) of
        {ok, Addr} ->
            case gen_udp:send(Socket, Addr, Port, Data) of
                ok -> {ok, nil};
                Error -> Error
            end;
        Error -> Error
    end;
send_to(Socket, Host, Port, Data) ->
    case gen_udp:send(Socket, Host, Port, Data) of
        ok -> {ok, nil};
        Error -> Error
    end.

%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% Receiving Data
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

%% @doc Receives data from a UDP socket (blocking, infinite timeout).
-spec recv(Socket :: gen_udp:socket(), Length :: integer()) ->
    {ok, {inet:ip_address(), integer(), binary()}} | {error, atom()}.
recv(Socket, Length) ->
    gen_udp:recv(Socket, Length).

%% @doc Receives data from a UDP socket with a timeout.
-spec recv_timeout(Socket :: gen_udp:socket(), Length :: integer(), Timeout :: integer()) ->
    {ok, {inet:ip_address(), integer(), binary()}} | {error, atom()}.
recv_timeout(Socket, Length, Timeout) ->
    gen_udp:recv(Socket, Length, Timeout).

%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% Socket Control
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

%% @doc Closes a UDP socket.
-spec close(Socket :: gen_udp:socket()) -> ok.
close(Socket) ->
    gen_udp:close(Socket).

%% @doc Sets the controlling process for the socket.
-spec controlling_process(Socket :: gen_udp:socket(), Pid :: pid()) ->
    ok | {error, atom()}.
controlling_process(Socket, Pid) ->
    gen_udp:controlling_process(Socket, Pid).

%% @doc Gets the local address and port of the socket.
-spec sockname(Socket :: gen_udp:socket()) ->
    {ok, {inet:ip_address(), integer()}} | {error, atom()}.
sockname(Socket) ->
    inet:sockname(Socket).

%% @doc Sets the active mode for a socket.
%% Mode can be: passive, once, {count, N}, or active (mapped from Gleam types)
-spec set_active(Socket :: gen_udp:socket(), Mode :: atom() | {atom(), integer()}) ->
    ok | {error, atom()}.
set_active(Socket, passive) ->
    inet:setopts(Socket, [{active, false}]);
set_active(Socket, once) ->
    inet:setopts(Socket, [{active, once}]);
set_active(Socket, active) ->
    inet:setopts(Socket, [{active, true}]);
set_active(Socket, {count, N}) ->
    inet:setopts(Socket, [{active, N}]);
set_active(Socket, _) ->
    inet:setopts(Socket, [{active, false}]).

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

%% @doc Decodes an 8-element tuple (for IPv6 addresses).
-spec decode_8_tuple(tuple()) -> {ok, {integer(), integer(), integer(), integer(), integer(), integer(), integer(), integer()}} | {error, nil}.
decode_8_tuple(Tuple) when is_tuple(Tuple), tuple_size(Tuple) =:= 8 ->
    {A, B, C, D, E, F, G, H} = Tuple,
    case is_integer(A) andalso is_integer(B) andalso is_integer(C) andalso is_integer(D) andalso
         is_integer(E) andalso is_integer(F) andalso is_integer(G) andalso is_integer(H) of
        true -> {ok, {A, B, C, D, E, F, G, H}};
        false -> {error, nil}
    end;
decode_8_tuple(_) ->
    {error, nil}.
