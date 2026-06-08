-module(livery_stripe_app).
-moduledoc """
Application callback.

Reads configuration (`livery_stripe:config/0`), and when a secret key is
present builds the shared `livery_client` and caches it in
`persistent_term` so the circuit breaker and concurrency gate are shared
across every call. Without a key the app still starts; configure later
with `livery_stripe:configure/1`.
""".
-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    Cfg = livery_stripe:config(),
    ok = maybe_configure(Cfg),
    livery_stripe_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.

maybe_configure(Cfg) ->
    case maps:get(secret_key, Cfg, undefined) of
        undefined ->
            ok;
        _ ->
            _ = livery_stripe:configure(Cfg),
            ok
    end.
