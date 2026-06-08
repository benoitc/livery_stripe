-module(livery_stripe_client).
-moduledoc """
Low-level Stripe request pipeline over `livery_client`.

`build/1` turns a config map into a `livery_client` value wired with the
full resilience stack (timeout, retry with backoff, circuit breaker, and a
concurrency gate). Build it once and `cache/1` it in `persistent_term` so
the breaker and gate state is shared across all callers.

`do_request/4,5` is the single entry every domain module funnels through:
it form-encodes parameters, attaches an `Idempotency-Key` on mutating
requests (so a retried POST is deduplicated by Stripe rather than charged
twice), runs the call, and maps the response to `{ok, map()}` or an error.

Errors are one of:
- `{stripe_error, Status, ErrorMap}` - Stripe returned a non-2xx with a
  JSON `error` object,
- `{decode, Body}` - a 2xx body that was not valid JSON,
- any `livery_client` stack error as a value: `timeout`, `circuit_open`,
  `overloaded`, or a transport reason from the adapter.
""".

-export([build/1, cache/1, cached/0, has_client/0]).
-export([do_request/4, do_request/5]).
-export([decode/1]).

-define(PT_KEY, {?MODULE, client}).
-define(API_BASE, <<"https://api.stripe.com/v1">>).
-define(DEFAULT_VERSION, <<"2024-06-20">>).

-type config() :: map().
-type method() :: get | post | put | delete.
-type params() :: none | [{term(), term()}] | map().
-type result() :: {ok, map()} | {error, term()}.
-export_type([config/0, method/0, params/0, result/0]).

%%====================================================================
%% Build and cache
%%====================================================================

-doc "Build a Stripe `livery_client` from a config map.".
-spec build(config()) -> livery_client:client().
build(Cfg) ->
    Key = require(secret_key, Cfg),
    Ver = livery_stripe_util:to_bin(maps:get(api_version, Cfg, ?DEFAULT_VERSION)),
    Headers = [
        {<<"authorization">>, <<"Bearer ", Key/binary>>},
        {<<"stripe-version">>, Ver},
        {<<"accept">>, <<"application/json">>},
        {<<"content-type">>, <<"application/x-www-form-urlencoded">>}
    ],
    livery_client:new(#{
        base_url => livery_stripe_util:to_bin(maps:get(base_url, Cfg, ?API_BASE)),
        headers => Headers,
        adapter_opts => maps:get(adapter_opts, Cfg, #{hackney => [{pool, livery_stripe}]}),
        stack => stack(Cfg)
    }).

stack(Cfg) ->
    [
        livery_client:timeout(maps:get(timeout_ms, Cfg, 30000)),
        livery_client:retry(maps:get(retry, Cfg, default_retry())),
        livery_client:circuit_breaker(maps:get(circuit_breaker, Cfg, default_circuit())),
        livery_client:concurrency(maps:get(concurrency, Cfg, 50))
    ].

default_retry() ->
    #{
        max => 3,
        backoff => {500, 2.0},
        statuses => [409, 429, 500, 502, 503, 504],
        retry_non_idempotent => true,
        retry_after_max => 60000
    }.

default_circuit() ->
    #{name => livery_stripe, window => 50, trip => 0.5, cooldown => 5000}.

-doc "Cache a built client for `cached/0` (shared, process-independent).".
-spec cache(livery_client:client()) -> ok.
cache(Client) ->
    persistent_term:put(?PT_KEY, Client).

-doc "Fetch the cached client, or raise if none was configured.".
-spec cached() -> livery_client:client().
cached() ->
    case persistent_term:get(?PT_KEY, undefined) of
        undefined -> error(livery_stripe_client_not_configured);
        Client -> Client
    end.

-doc "Whether a client has been cached.".
-spec has_client() -> boolean().
has_client() ->
    persistent_term:get(?PT_KEY, undefined) =/= undefined.

%%====================================================================
%% Requests
%%====================================================================

-spec do_request(livery_client:client(), method(), binary(), params()) -> result().
do_request(Client, Method, Path, Params) ->
    do_request(Client, Method, Path, Params, #{}).

-spec do_request(livery_client:client(), method(), binary(), params(), map()) -> result().
do_request(Client, get, Path, Params, Opts) ->
    send(Client, get, with_query(Path, Params), empty, Opts);
do_request(Client, delete, Path, Params, Opts) ->
    send(Client, delete, with_query(Path, Params), empty, Opts);
do_request(Client, Method, Path, Params, Opts) ->
    send(Client, Method, Path, body(Params), Opts).

with_query(Path, Params) ->
    case form(Params) of
        <<>> -> Path;
        Q -> <<Path/binary, "?", Q/binary>>
    end.

body(Params) ->
    case form(Params) of
        <<>> -> empty;
        Bin -> {full, Bin}
    end.

form(none) -> <<>>;
form([]) -> <<>>;
form(M) when is_map(M), map_size(M) =:= 0 -> <<>>;
form(Params) -> livery_stripe_form:encode(Params).

send(Client, Method, Path, Body, Opts) ->
    ReqOpts0 = #{body => Body, headers => headers(Method, Opts)},
    ReqOpts = maybe_timeout(ReqOpts0, Opts),
    case livery_client:request(Client, Method, Path, ReqOpts) of
        {ok, Resp} -> decode(Resp);
        {error, Reason} -> {error, Reason}
    end.

headers(Method, Opts) ->
    idempotency(Method, Opts) ++ account(Opts) ++ maps:get(headers, Opts, []).

%% Idempotency keys make retried mutations safe: Stripe dedupes by key, and
%% livery's retry replays the same request map, so every attempt carries the
%% same key.
idempotency(post, Opts) ->
    [{<<"idempotency-key">>, maps:get(idempotency_key, Opts, gen_idem_key())}];
idempotency(_Method, _Opts) ->
    [].

account(Opts) ->
    case maps:get(stripe_account, Opts, undefined) of
        undefined -> [];
        Acct -> [{<<"stripe-account">>, Acct}]
    end.

maybe_timeout(ReqOpts, Opts) ->
    case maps:get(timeout, Opts, undefined) of
        undefined -> ReqOpts;
        T -> ReqOpts#{timeout => T}
    end.

gen_idem_key() ->
    <<"ls_", (livery_stripe_util:lower_hex(crypto:strong_rand_bytes(16)))/binary>>.

%%====================================================================
%% Response decoding
%%====================================================================

-doc "Map a `livery_client` response to `{ok, map()}` or a Stripe error.".
-spec decode(livery_client:response()) -> result().
decode(Resp) ->
    Status = livery_client:status(Resp),
    Body = read_body(livery_client:body(Resp)),
    case Status of
        S when S >= 200, S =< 299 -> decode_ok(Body);
        S -> {error, stripe_error(S, Body)}
    end.

read_body({full, B}) ->
    B;
read_body({stream, Reader}) ->
    case livery_client:read_body(Reader) of
        {ok, B} -> B;
        {error, _} -> <<>>
    end.

decode_ok(<<>>) ->
    {ok, #{}};
decode_ok(Body) ->
    try json:decode(Body) of
        Decoded -> {ok, Decoded}
    catch
        _:_ -> {error, {decode, Body}}
    end.

stripe_error(Status, Body) ->
    {stripe_error, Status, parse_error(Body)}.

parse_error(Body) ->
    try json:decode(Body) of
        #{<<"error">> := E} when is_map(E) -> E;
        Other -> #{<<"message">> => <<"unexpected stripe response">>, <<"raw">> => Other}
    catch
        _:_ -> #{<<"message">> => <<"non-json stripe error">>, <<"raw">> => Body}
    end.

%%====================================================================
%% Internals
%%====================================================================

require(Key, Cfg) ->
    case maps:get(Key, Cfg, undefined) of
        undefined -> error({missing_config, Key});
        V -> livery_stripe_util:to_bin(V)
    end.
