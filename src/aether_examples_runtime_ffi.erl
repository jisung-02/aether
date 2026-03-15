%% Runtime environment helpers for example servers.

-module(aether_examples_runtime_ffi).

-export([getenv/1]).

-spec getenv(binary()) -> {ok, binary()} | {error, nil}.
getenv(Name) when is_binary(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.
