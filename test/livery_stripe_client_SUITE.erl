-module(livery_stripe_client_SUITE).
-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").

all() ->
    [
        retry_replays_same_idempotency_key,
        retry_on_429_honors_retry_after,
        no_retry_on_card_error,
        transport_error_passthrough,
        success_decodes_json,
        empty_body_decodes_to_empty_map,
        invalid_json_on_2xx_is_decode_error,
        non_json_error_body_is_wrapped,
        get_encodes_query_string,
        get_has_no_idempotency_key,
        custom_idempotency_key_is_used,
        concurrency_gate_rejects_when_full,
        circuit_breaker_opens_after_failures,
        build_requires_secret_key,
        stripe_account_header_is_set,
        timeout_opt_is_passed_through
    ].

init_per_suite(Config) ->
    %% livery brings up livery_client_circuit_store (an ETS owner) needed by
    %% the circuit_breaker layer, plus crypto for idempotency keys.
    {ok, _} = application:ensure_all_started(livery),
    Config.

end_per_suite(_Config) ->
    livery_stripe_ct_adapter:reset(),
    ok.

%%====================================================================
%% Helpers
%%====================================================================

%% A client over the mock adapter with a caller-supplied layer stack.
client(Stack) ->
    livery_client:new(#{
        base_url => <<"http://mock">>,
        adapter => livery_stripe_ct_adapter,
        headers => [{<<"content-type">>, <<"application/x-www-form-urlencoded">>}],
        stack => Stack
    }).

retry_client() ->
    client([
        livery_client:retry(#{
            max => 3,
            backoff => {1, 1.0},
            statuses => [429, 500],
            retry_non_idempotent => true,
            retry_after_max => 50
        })
    ]).

bare_client() ->
    client([]).

ok_json(Body) ->
    {ok, #{status => 200, headers => [], body => {full, Body}}}.

status(Status, Headers, Body) ->
    {ok, #{status => Status, headers => Headers, body => {full, Body}}}.

%%====================================================================
%% Retry / idempotency
%%====================================================================

retry_replays_same_idempotency_key(_Config) ->
    ok = livery_stripe_ct_adapter:setup([
        status(500, [], <<"{\"error\":{\"message\":\"boom\"}}">>),
        ok_json(<<"{\"id\":\"cus_1\"}">>)
    ]),
    {ok, #{<<"id">> := <<"cus_1">>}} =
        livery_stripe_customer:create(retry_client(), #{email => <<"a@b.c">>}),
    Reqs = livery_stripe_ct_adapter:requests(),
    2 = length(Reqs),
    [K1, K2] = [livery_client:header(<<"idempotency-key">>, R) || R <- Reqs],
    true = is_binary(K1),
    K1 = K2,
    ok.

retry_on_429_honors_retry_after(_Config) ->
    ok = livery_stripe_ct_adapter:setup([
        status(429, [{<<"retry-after">>, <<"0">>}], <<"{\"error\":{\"message\":\"slow down\"}}">>),
        ok_json(<<"{\"ok\":true}">>)
    ]),
    {ok, #{<<"ok">> := true}} =
        livery_stripe_customer:create(retry_client(), #{email => <<"a@b.c">>}),
    2 = length(livery_stripe_ct_adapter:requests()),
    ok.

no_retry_on_card_error(_Config) ->
    ok = livery_stripe_ct_adapter:setup([
        status(402, [], <<"{\"error\":{\"type\":\"card_error\",\"message\":\"declined\"}}">>)
    ]),
    {error, {stripe_error, 402, Err}} =
        livery_stripe_customer:create(retry_client(), #{email => <<"a@b.c">>}),
    <<"card_error">> = maps:get(<<"type">>, Err),
    1 = length(livery_stripe_ct_adapter:requests()),
    ok.

transport_error_passthrough(_Config) ->
    ok = livery_stripe_ct_adapter:setup([{error, econnrefused}]),
    {error, econnrefused} =
        livery_stripe_customer:retrieve(bare_client(), <<"cus_1">>),
    1 = length(livery_stripe_ct_adapter:requests()),
    ok.

%%====================================================================
%% Response decoding
%%====================================================================

success_decodes_json(_Config) ->
    ok = livery_stripe_ct_adapter:setup([ok_json(<<"{\"id\":\"sub_1\",\"status\":\"active\"}">>)]),
    {ok, #{<<"status">> := <<"active">>}} =
        livery_stripe_subscription:retrieve(bare_client(), <<"sub_1">>),
    ok.

empty_body_decodes_to_empty_map(_Config) ->
    ok = livery_stripe_ct_adapter:setup([ok_json(<<>>)]),
    {ok, Map} = livery_stripe_subscription:retrieve(bare_client(), <<"sub_1">>),
    0 = map_size(Map),
    ok.

invalid_json_on_2xx_is_decode_error(_Config) ->
    ok = livery_stripe_ct_adapter:setup([ok_json(<<"not json">>)]),
    {error, {decode, <<"not json">>}} =
        livery_stripe_subscription:retrieve(bare_client(), <<"sub_1">>),
    ok.

non_json_error_body_is_wrapped(_Config) ->
    ok = livery_stripe_ct_adapter:setup([status(400, [], <<"<html>oops</html>">>)]),
    {error, {stripe_error, 400, Err}} =
        livery_stripe_subscription:retrieve(bare_client(), <<"sub_1">>),
    <<"non-json stripe error">> = maps:get(<<"message">>, Err),
    <<"<html>oops</html>">> = maps:get(<<"raw">>, Err),
    ok.

%%====================================================================
%% Request shaping
%%====================================================================

get_encodes_query_string(_Config) ->
    ok = livery_stripe_ct_adapter:setup([ok_json(<<"{\"object\":\"list\"}">>)]),
    {ok, _} = livery_stripe_subscription:list(bare_client(), #{status => <<"active">>, limit => 10}),
    [Req] = livery_stripe_ct_adapter:requests(),
    Url = livery_client:url(Req),
    assert_contains(Url, <<"/subscriptions?">>),
    assert_contains(Url, <<"status=active">>),
    assert_contains(Url, <<"limit=10">>),
    ok.

get_has_no_idempotency_key(_Config) ->
    ok = livery_stripe_ct_adapter:setup([ok_json(<<"{\"id\":\"sub_1\"}">>)]),
    {ok, _} = livery_stripe_subscription:retrieve(bare_client(), <<"sub_1">>),
    [Req] = livery_stripe_ct_adapter:requests(),
    undefined = livery_client:header(<<"idempotency-key">>, Req),
    ok.

custom_idempotency_key_is_used(_Config) ->
    ok = livery_stripe_ct_adapter:setup([ok_json(<<"{\"id\":\"cus_1\"}">>)]),
    {ok, _} = livery_stripe_customer:create(
        bare_client(), #{email => <<"a@b.c">>}, #{idempotency_key => <<"my-key-123">>}
    ),
    [Req] = livery_stripe_ct_adapter:requests(),
    <<"my-key-123">> = livery_client:header(<<"idempotency-key">>, Req),
    ok.

%%====================================================================
%% Flow control layers
%%====================================================================

concurrency_gate_rejects_when_full(_Config) ->
    ok = livery_stripe_ct_adapter:setup([ok_json(<<"{}">>)]),
    Client = client([livery_client:concurrency(0)]),
    {error, overloaded} = livery_stripe_customer:retrieve(Client, <<"cus_1">>),
    0 = length(livery_stripe_ct_adapter:requests()),
    ok.

circuit_breaker_opens_after_failures(_Config) ->
    ok = livery_stripe_ct_adapter:setup([
        {error, econnrefused},
        {error, econnrefused}
    ]),
    Name = {?MODULE, erlang:unique_integer([positive])},
    Client = client([
        livery_client:circuit_breaker(#{name => Name, window => 1, trip => 1.0, cooldown => 60000})
    ]),
    {error, econnrefused} = livery_stripe_customer:retrieve(Client, <<"cus_1">>),
    {error, circuit_open} = livery_stripe_customer:retrieve(Client, <<"cus_1">>),
    %% Only the first call reached the adapter; the breaker shorted the second.
    1 = length(livery_stripe_ct_adapter:requests()),
    ok.

%%====================================================================
%% Build / per-request options
%%====================================================================

build_requires_secret_key(_Config) ->
    try
        _ = livery_stripe_client:build(#{}),
        ct:fail(expected_missing_config)
    catch
        error:{missing_config, secret_key} -> ok
    end.

stripe_account_header_is_set(_Config) ->
    ok = livery_stripe_ct_adapter:setup([ok_json(<<"{\"id\":\"cus_1\"}">>)]),
    {ok, _} = livery_stripe_customer:create(
        bare_client(), #{email => <<"a@b.c">>}, #{stripe_account => <<"acct_42">>}
    ),
    [Req] = livery_stripe_ct_adapter:requests(),
    <<"acct_42">> = livery_client:header(<<"stripe-account">>, Req),
    ok.

timeout_opt_is_passed_through(_Config) ->
    ok = livery_stripe_ct_adapter:setup([ok_json(<<"{\"id\":\"cus_1\"}">>)]),
    {ok, _} = livery_stripe_customer:create(
        bare_client(), #{email => <<"a@b.c">>}, #{timeout => 1234}
    ),
    [Req] = livery_stripe_ct_adapter:requests(),
    1234 = maps:get(timeout, Req),
    ok.

%%====================================================================
%% Internals
%%====================================================================

assert_contains(Haystack, Needle) ->
    {_, _} = binary:match(Haystack, Needle).
