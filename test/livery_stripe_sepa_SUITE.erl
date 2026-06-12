-module(livery_stripe_sepa_SUITE).
-moduledoc """
SEPA Direct Debit. SEPA is a payment method type, so the existing wrappers
support it by passing `payment_method_types => [<<"sepa_debit">>]`; these
tests assert the requests are built that way and that the mandate wrapper
decodes its response. Hermetic (over the mock adapter): a live test is
avoided because SEPA must be activated on the Stripe account.
""".
-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").

all() ->
    [
        payment_intent_encodes_sepa,
        setup_intent_encodes_sepa,
        checkout_encodes_sepa,
        mandate_retrieve_decodes
    ].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(crypto),
    Config.

end_per_suite(_Config) ->
    livery_stripe_ct_adapter:reset(),
    ok.

client() ->
    livery_client:new(#{
        base_url => <<"https://api.stripe.com/v1">>,
        adapter => livery_stripe_ct_adapter,
        headers => [{<<"content-type">>, <<"application/x-www-form-urlencoded">>}],
        stack => []
    }).

%%====================================================================
%% Tests
%%====================================================================

payment_intent_encodes_sepa(_Config) ->
    Body = post_body(fun(C) ->
        livery_stripe_payment_intent:create(C, #{
            amount => 1999,
            currency => <<"eur">>,
            payment_method_types => [<<"sepa_debit">>]
        })
    end),
    true = contains(Body, <<"currency=eur">>),
    true = contains(Body, <<"sepa_debit">>).

setup_intent_encodes_sepa(_Config) ->
    Body = post_body(fun(C) ->
        livery_stripe_setup_intent:create(C, #{
            customer => <<"cus_1">>,
            payment_method_types => [<<"sepa_debit">>]
        })
    end),
    true = contains(Body, <<"sepa_debit">>).

checkout_encodes_sepa(_Config) ->
    Body = post_body(fun(C) ->
        livery_stripe_checkout:create_session(C, #{
            mode => <<"subscription">>,
            payment_method_types => [<<"sepa_debit">>],
            customer => <<"cus_1">>,
            line_items => [#{<<"price">> => <<"price_1">>, <<"quantity">> => 1}],
            success_url => <<"https://x/ok">>,
            cancel_url => <<"https://x/no">>
        })
    end),
    true = contains(Body, <<"sepa_debit">>).

mandate_retrieve_decodes(_Config) ->
    C = client(),
    ok = livery_stripe_ct_adapter:setup([
        {ok, #{
            status => 200,
            headers => [],
            body =>
                {full, <<"{\"id\":\"mandate_1\",\"object\":\"mandate\",\"status\":\"active\"}">>}
        }}
    ]),
    {ok, Mandate} = livery_stripe_mandate:retrieve(C, <<"mandate_1">>),
    <<"mandate_1">> = maps:get(<<"id">>, Mandate),
    <<"active">> = maps:get(<<"status">>, Mandate),
    [Req] = livery_stripe_ct_adapter:requests(),
    get = livery_client:method(Req),
    true = contains(livery_client:url(Req), <<"/mandates/mandate_1">>).

%%====================================================================
%% Helpers
%%====================================================================

%% Run a POST-producing call through the mock adapter and return the
%% form-encoded request body.
post_body(Fun) ->
    C = client(),
    ok = livery_stripe_ct_adapter:setup([
        {ok, #{status => 200, headers => [], body => {full, <<"{}">>}}}
    ]),
    {ok, _} = Fun(C),
    [Req] = livery_stripe_ct_adapter:requests(),
    {full, Bin} = livery_client:body(Req),
    Bin.

contains(Haystack, Needle) ->
    binary:match(Haystack, Needle) =/= nomatch.
