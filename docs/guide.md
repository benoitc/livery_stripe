# livery_stripe usage guide

A feature-by-feature cookbook for the Stripe client. Every domain call
returns `{ok, map()}` (decoded JSON) or `{error, Reason}`. Calls take a
`Client` as the first argument; the `livery_stripe` facade wraps a cached,
app-configured client so you can skip passing one.

## Contents

- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Request options and lists](#request-options-and-lists)
- [Error handling](#error-handling)
- [Customers](#customers)
- [Products and prices](#products-and-prices)
- [Checkout](#checkout)
- [Billing portal](#billing-portal)
- [Subscriptions](#subscriptions)
- [Payment intents](#payment-intents)
- [Payment methods](#payment-methods)
- [Setup intents](#setup-intents)
- [Refunds](#refunds)
- [Invoices](#invoices)
- [Discounts: coupons and promotion codes](#discounts-coupons-and-promotion-codes)
- [Events](#events)
- [Webhooks](#webhooks)
- [Resilience](#resilience)
- [Uncovered endpoints](#uncovered-endpoints)

## Quick start

Two ways to get a client.

Cached facade (configured once at app start, shared via `persistent_term`):

```erlang
%% Reads app env + the STRIPE_SECRET_KEY env override, builds and caches.
_ = livery_stripe:configure(),

{ok, Customer} = livery_stripe:create_customer(#{email => <<"a@b.c">>}),
{ok, Sub}      = livery_stripe:create_subscription(#{
    customer => maps:get(<<"id">>, Customer),
    items    => [#{price => <<"price_123">>}]
}).
```

Explicit client (multiple accounts, tests). Build once and reuse:

```erlang
Client = livery_stripe_client:build(#{secret_key => <<"sk_test_...">>}),
{ok, Customer} = livery_stripe_customer:create(Client, #{email => <<"a@b.c">>}).
```

The facade exposes a curated subset (`create_customer/1`, `get_customer/1`,
`update_customer/2`, `create_checkout_session/1`, `subscription_checkout/1`,
`create_portal_session/1`, `create_subscription/1`, `get_subscription/1`,
`update_subscription/2`, `cancel_subscription/1`). For everything else, call
the domain modules with an explicit client.

## Configuration

`livery_stripe_client:build/1` accepts:

| Key | Default | Meaning |
|---|---|---|
| `secret_key` | (required) | `sk_test_...` / `sk_live_...` |
| `api_version` | `<<"2024-06-20">>` | `Stripe-Version` header |
| `base_url` | `https://api.stripe.com/v1` | API base |
| `timeout_ms` | `30000` | per-call ceiling |
| `retry` | see below | retry layer config |
| `circuit_breaker` | `#{window => 50, trip => 0.5, cooldown => 5000}` | breaker config |
| `concurrency` | `50` | in-flight admission gate |
| `adapter_opts` | `#{hackney => [{pool, livery_stripe}]}` | transport options |

Default retry: `#{max => 3, backoff => {500, 2.0}, statuses => [409, 429,
500, 502, 503, 504], retry_non_idempotent => true, retry_after_max =>
60000}`.

With the facade, config comes from the `livery_stripe` application env,
with `secret_key` / `webhook_secret` overridden by the `STRIPE_SECRET_KEY`
/ `STRIPE_WEBHOOK_SECRET` OS variables. Prices map to a plan + period:

```erlang
%% sys.config: {livery_stripe, [{prices, #{pro_monthly => <<"price_123">>}}]}
{ok, <<"price_123">>} = livery_stripe:price_id(pro, monthly).
```

## Request options and lists

Mutating calls take an options map (on the `create/3`, `update/4` arities):

```erlang
livery_stripe_customer:create(Client, Params, #{
    idempotency_key => <<"order-42">>,   %% reuse for at-least-once flows
    stripe_account  => <<"acct_123">>,   %% act as a connected account
    timeout         => 5000,             %% override the call timeout (ms)
    headers         => [{<<"x-trace">>, <<"abc">>}]
}).
```

Every POST gets an auto-generated `Idempotency-Key` when you do not supply
one, so a retried create is deduplicated by Stripe rather than repeated.

List calls take the usual Stripe pagination params:

```erlang
{ok, Page} = livery_stripe_customer:list(Client, #{limit => 20}),
Data  = maps:get(<<"data">>, Page),
More  = maps:get(<<"has_more">>, Page),
{ok, Next} = livery_stripe_customer:list(Client, #{
    limit => 20, starting_after => maps:get(<<"id">>, lists:last(Data))
}).
```

## Error handling

```erlang
case livery_stripe_customer:retrieve(Client, Id) of
    {ok, Customer} ->
        Customer;
    {error, {stripe_error, 404, _Err}} ->
        not_found;
    {error, {stripe_error, Status, #{<<"message">> := Msg}}} ->
        {api_error, Status, Msg};
    {error, {decode, _Body}} ->
        bad_json;                 %% a 2xx body that was not valid JSON
    {error, timeout} ->
        retry_later;
    {error, circuit_open} ->
        degraded;                 %% breaker tripped on a Stripe outage
    {error, overloaded} ->
        backpressure;             %% concurrency gate is full
    {error, _Transport} ->
        transport_error
end.
```

## Customers

```erlang
{ok, Cust} = livery_stripe_customer:create(Client, #{
    email    => <<"a@b.c">>,
    name     => <<"A B">>,
    metadata => #{<<"user_id">> => <<"u1">>}
}),
Id = maps:get(<<"id">>, Cust),

{ok, _} = livery_stripe_customer:retrieve(Client, Id),
{ok, _} = livery_stripe_customer:update(Client, Id, #{metadata => #{<<"plan">> => <<"pro">>}}),
{ok, _} = livery_stripe_customer:list(Client, #{limit => 10}),

{ok, PMs} = livery_stripe_customer:list_payment_methods(Client, Id, #{type => <<"card">>}),
{ok, _}   = livery_stripe_customer:delete_discount(Client, Id),
{ok, #{<<"deleted">> := true}} = livery_stripe_customer:delete(Client, Id).
```

## Products and prices

```erlang
{ok, Product} = livery_stripe_product:create(Client, #{name => <<"Pro plan">>}),
ProductId = maps:get(<<"id">>, Product),

{ok, Price} = livery_stripe_price:create(Client, #{
    product     => ProductId,
    unit_amount => 1500,
    currency    => <<"usd">>,
    recurring   => #{interval => <<"month">>}
}),
PriceId = maps:get(<<"id">>, Price),

%% Prices and products are archived, not deleted:
{ok, _} = livery_stripe_price:update(Client, PriceId, #{active => false}),
{ok, _} = livery_stripe_product:update(Client, ProductId, #{active => false}).
```

## Checkout

Hosted subscription checkout for a single price (the friendpaste flow):

```erlang
{ok, Session} = livery_stripe_checkout:subscription_session(Client, #{
    customer    => CustomerId,
    price       => PriceId,
    success_url => <<"https://app/billing?success=1">>,
    cancel_url  => <<"https://app/billing?canceled=1">>,
    metadata    => #{<<"user_id">> => <<"u1">>}
}),
CheckoutUrl = maps:get(<<"url">>, Session).
```

A generic session (any mode, multiple line items, promotion codes):

```erlang
{ok, _} = livery_stripe_checkout:create_session(Client, #{
    mode                  => <<"payment">>,
    line_items            => [#{<<"price">> => PriceId, <<"quantity">> => 1}],
    allow_promotion_codes => true,
    success_url           => <<"https://app/ok">>,
    cancel_url            => <<"https://app/no">>
}),
{ok, _} = livery_stripe_checkout:retrieve_session(Client, <<"cs_123">>),
{ok, _} = livery_stripe_checkout:expire_session(Client, <<"cs_123">>).
```

## Billing portal

```erlang
{ok, Portal} = livery_stripe_portal:create_session(Client, #{
    customer   => CustomerId,
    return_url => <<"https://app/billing">>
}),
PortalUrl = maps:get(<<"url">>, Portal).
```

## Subscriptions

```erlang
{ok, Sub} = livery_stripe_subscription:create(Client, #{
    customer => CustomerId,
    items    => [#{price => PriceId}]
}),
SubId = maps:get(<<"id">>, Sub),

{ok, _} = livery_stripe_subscription:update(Client, SubId, #{metadata => #{<<"tier">> => <<"pro">>}}),
{ok, _} = livery_stripe_subscription:pause(Client, SubId),
{ok, _} = livery_stripe_subscription:resume(Client, SubId),

{ok, _} = livery_stripe_subscription:cancel(Client, SubId),                       %% immediate
{ok, _} = livery_stripe_subscription:cancel(Client, SubId, #{invoice_now => true}).
```

Creating a subscription that bills immediately needs a customer with a
default payment method. Attach one first (see Payment methods) or collect it
through Checkout.

## Payment intents

```erlang
{ok, PI} = livery_stripe_payment_intent:create(Client, #{
    amount               => 2000,
    currency             => <<"usd">>,
    payment_method_types => [<<"card">>]
}),
Id = maps:get(<<"id">>, PI),

{ok, _} = livery_stripe_payment_intent:update(Client, Id, #{metadata => #{<<"order">> => <<"42">>}}),
{ok, _} = livery_stripe_payment_intent:confirm(Client, Id, #{payment_method => <<"pm_card_visa">>}),
{ok, _} = livery_stripe_payment_intent:capture(Client, Id),
{ok, _} = livery_stripe_payment_intent:cancel(Client, Id),
{ok, _} = livery_stripe_payment_intent:list(Client, #{limit => 5}).
```

## Payment methods

```erlang
%% Attach a (client-collected, or test) payment method to a customer:
{ok, Pm} = livery_stripe_payment_method:attach(Client, <<"pm_card_visa">>, #{customer => CustomerId}),
PmId = maps:get(<<"id">>, Pm),

%% Make it the default for invoices:
{ok, _} = livery_stripe_customer:update(Client, CustomerId, #{
    invoice_settings => #{default_payment_method => PmId}
}),

{ok, _} = livery_stripe_payment_method:list(Client, #{customer => CustomerId, type => <<"card">>}),
{ok, _} = livery_stripe_payment_method:retrieve(Client, PmId),
{ok, _} = livery_stripe_payment_method:detach(Client, PmId).
```

## Setup intents

Save a card for future billing without charging now:

```erlang
{ok, SI} = livery_stripe_setup_intent:create(Client, #{
    customer             => CustomerId,
    payment_method_types => [<<"card">>]
}),
ClientSecret = maps:get(<<"client_secret">>, SI),  %% confirm client-side, then the PM is saved

{ok, _} = livery_stripe_setup_intent:retrieve(Client, maps:get(<<"id">>, SI)),
{ok, _} = livery_stripe_setup_intent:cancel(Client, maps:get(<<"id">>, SI)).
```

## Refunds

```erlang
%% Full refund of a PaymentIntent:
{ok, _} = livery_stripe_refund:create(Client, #{payment_intent => <<"pi_123">>}),

%% Partial refund:
{ok, _} = livery_stripe_refund:create(Client, #{payment_intent => <<"pi_123">>, amount => 500}),

{ok, _} = livery_stripe_refund:retrieve(Client, <<"re_123">>),
{ok, _} = livery_stripe_refund:list(Client, #{limit => 5}).
```

## Invoices

```erlang
{ok, Inv} = livery_stripe_invoice:create(Client, #{
    customer          => CustomerId,
    collection_method => <<"send_invoice">>,
    days_until_due    => 7
}),
Id = maps:get(<<"id">>, Inv),

{ok, _} = livery_stripe_invoice:finalize(Client, Id),
{ok, _} = livery_stripe_invoice:send(Client, Id),
{ok, _} = livery_stripe_invoice:pay(Client, Id),
{ok, _} = livery_stripe_invoice:void(Client, Id),
{ok, _} = livery_stripe_invoice:mark_uncollectible(Client, Id),

%% Preview the next invoice (proration when changing plans):
{ok, Preview} = livery_stripe_invoice:upcoming(Client, #{customer => CustomerId}),
{ok, _}       = livery_stripe_invoice:list(Client, #{customer => CustomerId, limit => 5}).
```

## Discounts: coupons and promotion codes

A coupon defines the discount; a promotion code is a customer-facing code
that maps to a coupon.

```erlang
{ok, Coupon} = livery_stripe_coupon:create(Client, #{percent_off => 25, duration => <<"once">>}),
CouponId = maps:get(<<"id">>, Coupon),

{ok, Promo} = livery_stripe_promotion_code:create(Client, #{
    coupon => CouponId,
    code   => <<"LAUNCH25">>
}),

%% Apply to a subscription:
{ok, _} = livery_stripe_subscription:update(Client, SubId, #{coupon => CouponId}),

%% Or let customers enter a code at Checkout:
%%   livery_stripe_checkout:create_session(Client, #{..., allow_promotion_codes => true})

%% Remove a subscription's (or customer's) discount:
{ok, _} = livery_stripe_subscription:delete_discount(Client, SubId),

%% Deactivate a promotion code (there is no delete):
{ok, _} = livery_stripe_promotion_code:update(Client, maps:get(<<"id">>, Promo), #{active => false}),
{ok, _} = livery_stripe_coupon:delete(Client, CouponId).
```

## Events

```erlang
{ok, Event} = livery_stripe_event:retrieve(Client, <<"evt_123">>),
{ok, _}     = livery_stripe_event:list(Client, #{
    type  => <<"checkout.session.completed">>,
    limit => 5
}).
```

Re-fetching an event by id is useful for idempotent webhook processing:
verify the signature on receipt, then re-read the authoritative event from
the API before acting on it.

## Webhooks

Verify the signature and decode the event. Pass the RAW request body bytes;
re-encoding the JSON breaks the signature.

```erlang
case livery_stripe_webhook:construct_event(RawBody, SigHeader, Secret) of
    {ok, Event}                          -> handle(Event);
    {error, invalid_signature}           -> reject;
    {error, invalid_payload}             -> reject;
    {error, timestamp_out_of_tolerance}  -> reject
end.
```

Or mount the ready-made handler, which verifies and dispatches to your
callback. Set `webhook_secret` and `webhook_callback` in the `livery_stripe`
app env:

```erlang
Router = livery_router:compile(
    livery_stripe_webhook_handler:routes(<<"/stripe/webhook">>) ++ OtherRoutes
).
```

The callback may be a `fun/1` (`Event`), a `fun/2` (`Type, Event`), a
module exporting `handle_event/2`, or a `{Module, Function}` pair. A
verified event returns `200`; a bad payload or signature returns `400`.
Persistence belongs in the callback, so the client stays storage-agnostic.

## Resilience

Every call goes through livery's flow-control stack: a `timeout` ceiling,
`retry` with exponential backoff and jitter (honoring `Retry-After`, and
replaying the same `Idempotency-Key` so retried POSTs are deduplicated), a
`circuit_breaker` that trips on a failure ratio, and a `concurrency` gate
that returns `{error, overloaded}` instead of piling up connections. The
breaker and gate state is shared across callers because the client is
cached in `persistent_term`. Tune any of it through the config keys above.

## Uncovered endpoints

Any Stripe endpoint without a domain wrapper is reachable through
`livery_stripe_client:do_request/4,5`, the same funnel every wrapper uses
(form-encoding, idempotency keys, error mapping, the resilience stack):

```erlang
%% POST /v1/tax_rates
{ok, _} = livery_stripe_client:do_request(Client, post, <<"/tax_rates">>, #{
    display_name => <<"VAT">>,
    percentage   => 20.0,
    inclusive    => false
}),

%% GET /v1/disputes?limit=3
{ok, _} = livery_stripe_client:do_request(Client, get, <<"/disputes">>, #{limit => 3}),

%% With request options (idempotency key, connected account, ...):
{ok, _} = livery_stripe_client:do_request(Client, post, <<"/payouts">>,
    #{amount => 1000, currency => <<"usd">>},
    #{idempotency_key => <<"payout-1">>}).
```
