-module(livery_stripe_live_SUITE).
-moduledoc """
Opt-in integration suite that hits the real Stripe API in test mode.

Skipped unless `STRIPE_SECRET_KEY` is set to a test-mode secret
(`sk_test_...`). It only performs non-charging operations and cleans up
what it creates (deletes customers, archives products/prices).

    STRIPE_SECRET_KEY=sk_test_xxx rebar3 ct --suite test/livery_stripe_live_SUITE
""".
-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").

all() ->
    [
        customer_lifecycle,
        idempotency_replay_returns_same_object,
        product_price_and_subscription_checkout,
        payment_intent_lifecycle,
        subscription_lifecycle,
        invoice_list,
        facade_cached_client
    ].

init_per_suite(Config) ->
    case os:getenv("STRIPE_SECRET_KEY") of
        false ->
            {skip, "set STRIPE_SECRET_KEY=sk_test_... to run live Stripe tests"};
        "" ->
            {skip, "STRIPE_SECRET_KEY is empty"};
        Key ->
            {ok, _} = application:ensure_all_started(livery_stripe),
            Client = livery_stripe_client:build(#{secret_key => list_to_binary(Key)}),
            [{client, Client} | Config]
    end.

end_per_suite(_Config) ->
    ok.

%%====================================================================
%% Tests
%%====================================================================

customer_lifecycle(Config) ->
    Client = ?config(client, Config),
    {ok, Created} = livery_stripe_customer:create(Client, #{
        email => email(<<"lifecycle">>),
        name => <<"Livery Stripe Test">>,
        metadata => #{<<"suite">> => <<"live">>}
    }),
    Id = maps:get(<<"id">>, Created),
    <<"cus_", _/binary>> = Id,

    {ok, Fetched} = livery_stripe_customer:retrieve(Client, Id),
    Id = maps:get(<<"id">>, Fetched),

    {ok, Updated} = livery_stripe_customer:update(Client, Id, #{
        metadata => #{<<"suite">> => <<"live">>, <<"step">> => <<"updated">>}
    }),
    Id = maps:get(<<"id">>, Updated),

    {ok, Deleted} = livery_stripe_customer:delete(Client, Id),
    true = maps:get(<<"deleted">>, Deleted),
    ok.

idempotency_replay_returns_same_object(Config) ->
    Client = ?config(client, Config),
    Key = <<"live-idem-", (unique())/binary>>,
    Params = #{email => email(<<"idem">>), metadata => #{<<"suite">> => <<"live">>}},
    {ok, A} = livery_stripe_customer:create(Client, Params, #{idempotency_key => Key}),
    {ok, B} = livery_stripe_customer:create(Client, Params, #{idempotency_key => Key}),
    Id = maps:get(<<"id">>, A),
    Id = maps:get(<<"id">>, B),
    {ok, _} = livery_stripe_customer:delete(Client, Id),
    ok.

product_price_and_subscription_checkout(Config) ->
    Client = ?config(client, Config),
    {ok, Product} = livery_stripe_product:create(Client, #{
        name => <<"livery_stripe test ", (unique())/binary>>
    }),
    ProductId = maps:get(<<"id">>, Product),

    {ok, Price} = livery_stripe_price:list(Client, #{limit => 1}),
    <<"list">> = maps:get(<<"object">>, Price),

    {ok, RecurringPrice} = create_price(Client, ProductId),
    PriceId = maps:get(<<"id">>, RecurringPrice),

    {ok, Customer} = livery_stripe_customer:create(Client, #{email => email(<<"checkout">>)}),
    CustomerId = maps:get(<<"id">>, Customer),

    {ok, Session} = livery_stripe_checkout:subscription_session(Client, #{
        customer => CustomerId,
        price => PriceId,
        success_url => <<"https://example.test/ok">>,
        cancel_url => <<"https://example.test/no">>,
        metadata => #{<<"suite">> => <<"live">>}
    }),
    <<"cs_", _/binary>> = maps:get(<<"id">>, Session),
    true = is_binary(maps:get(<<"url">>, Session)),

    %% Cleanup: archive the price and product, delete the customer.
    _ = livery_stripe_price:retrieve(Client, PriceId),
    _ = safe(fun() -> archive_price(Client, PriceId) end),
    _ = safe(fun() -> archive_product(Client, ProductId) end),
    {ok, _} = livery_stripe_customer:delete(Client, CustomerId),
    ok.

payment_intent_lifecycle(Config) ->
    Client = ?config(client, Config),
    {ok, Intent} = livery_stripe_payment_intent:create(Client, #{
        amount => 1000,
        currency => <<"usd">>,
        payment_method_types => [<<"card">>],
        metadata => #{<<"suite">> => <<"live">>}
    }),
    Id = maps:get(<<"id">>, Intent),
    <<"pi_", _/binary>> = Id,

    {ok, Fetched} = livery_stripe_payment_intent:retrieve(Client, Id),
    Id = maps:get(<<"id">>, Fetched),

    {ok, Canceled} = livery_stripe_payment_intent:cancel(Client, Id),
    <<"canceled">> = maps:get(<<"status">>, Canceled),
    ok.

subscription_lifecycle(Config) ->
    Client = ?config(client, Config),
    {ok, Product} = livery_stripe_product:create(Client, #{
        name => <<"livery_stripe sub ", (unique())/binary>>
    }),
    ProductId = maps:get(<<"id">>, Product),
    {ok, Price} = create_price(Client, ProductId),
    PriceId = maps:get(<<"id">>, Price),

    {ok, Customer} = livery_stripe_customer:create(Client, #{email => email(<<"sub">>)}),
    CustomerId = maps:get(<<"id">>, Customer),

    %% Attach Stripe's shared test payment method so the first invoice can
    %% be paid; no domain wrapper exists, so go through do_request directly.
    {ok, Pm} = livery_stripe_client:do_request(
        Client,
        post,
        <<"/payment_methods/pm_card_visa/attach">>,
        #{customer => CustomerId}
    ),
    PmId = maps:get(<<"id">>, Pm),

    {ok, Sub} = livery_stripe_client:do_request(Client, post, <<"/subscriptions">>, #{
        customer => CustomerId,
        items => [#{price => PriceId}],
        default_payment_method => PmId,
        metadata => #{<<"suite">> => <<"live">>}
    }),
    SubId = maps:get(<<"id">>, Sub),
    <<"sub_", _/binary>> = SubId,

    {ok, FetchedSub} = livery_stripe_subscription:retrieve(Client, SubId),
    SubId = maps:get(<<"id">>, FetchedSub),

    %% The subscription's first invoice is a real id we can round-trip.
    case maps:get(<<"latest_invoice">>, Sub, null) of
        InvId when is_binary(InvId) ->
            {ok, Invoice} = livery_stripe_invoice:retrieve(Client, InvId),
            InvId = maps:get(<<"id">>, Invoice);
        _ ->
            ok
    end,

    {ok, Updated} = livery_stripe_subscription:update(Client, SubId, #{
        metadata => #{<<"suite">> => <<"live">>, <<"step">> => <<"updated">>}
    }),
    SubId = maps:get(<<"id">>, Updated),

    {ok, CanceledSub} = livery_stripe_subscription:cancel(Client, SubId),
    <<"canceled">> = maps:get(<<"status">>, CanceledSub),

    %% Cleanup: archive the price and product, delete the customer.
    _ = safe(fun() -> archive_price(Client, PriceId) end),
    _ = safe(fun() -> archive_product(Client, ProductId) end),
    {ok, _} = livery_stripe_customer:delete(Client, CustomerId),
    ok.

invoice_list(Config) ->
    Client = ?config(client, Config),
    {ok, List} = livery_stripe_invoice:list(Client, #{limit => 1}),
    <<"list">> = maps:get(<<"object">>, List),
    true = is_list(maps:get(<<"data">>, List)),
    ok.

%% Drives the cached app-client path: configure/0 reads the
%% STRIPE_SECRET_KEY override, then the facade uses the cached client.
facade_cached_client(_Config) ->
    _ = livery_stripe:configure(),
    {ok, Customer} = livery_stripe:create_customer(#{
        email => email(<<"facade">>),
        metadata => #{<<"suite">> => <<"live">>}
    }),
    Id = maps:get(<<"id">>, Customer),
    <<"cus_", _/binary>> = Id,

    {ok, Fetched} = livery_stripe:get_customer(Id),
    Id = maps:get(<<"id">>, Fetched),

    {ok, _} = livery_stripe:update_customer(Id, #{
        metadata => #{<<"suite">> => <<"live">>, <<"step">> => <<"facade">>}
    }),

    %% The facade exposes no delete; clean up via the domain module.
    {ok, _} = livery_stripe_customer:delete(livery_stripe:client(), Id),
    ok.

%% Portal sessions (livery_stripe_portal:create_session/2) are not tested
%% live: they require a billing-portal configuration in the dashboard and
%% error on a fresh test account, which would be a false failure.

%%====================================================================
%% Helpers
%%====================================================================

create_price(Client, ProductId) ->
    livery_stripe_price:create(Client, #{
        product => ProductId,
        unit_amount => 500,
        currency => <<"usd">>,
        recurring => #{interval => <<"month">>}
    }).

archive_price(Client, PriceId) ->
    livery_stripe_price:update(Client, PriceId, #{active => false}).

archive_product(Client, ProductId) ->
    livery_stripe_product:update(Client, ProductId, #{active => false}).

email(Tag) ->
    <<"livery-stripe+", Tag/binary, "-", (unique())/binary, "@example.test">>.

unique() ->
    integer_to_binary(erlang:unique_integer([positive, monotonic])).

safe(Fun) ->
    try
        Fun()
    catch
        _:_ -> error
    end.
