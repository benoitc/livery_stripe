# livery_stripe

A Stripe API client for Erlang/OTP, built on the [livery](https://github.com/benoitc/livery)
HTTP client. It covers core Stripe resources and subscriptions, and can back the
same billing flow friendpaste uses (Checkout + Billing Portal + webhooks).

## Why livery

The client is built on `livery_client` and wired with livery's flow-control
layers so calls retry safely and degrade gracefully under load:

- `timeout` - a hard ceiling over the whole call.
- `retry` - exponential backoff with jitter, honors `Retry-After`. Retries on
  transport errors and on `409/429/5xx`.
- `circuit_breaker` - trips on a failure ratio so a Stripe outage fails fast
  instead of piling up.
- `concurrency` - an in-flight admission gate (a semaphore) that caps real
  connections; excess calls return `{error, overloaded}`.

The client value is built once at app start and cached in `persistent_term`, so
the breaker and gate state is shared across every caller.

### Safe retries

Every mutating request (POST) carries an `Idempotency-Key`. livery's retry
replays the same request map, so the key is identical on every attempt and
Stripe deduplicates instead of, say, creating two subscriptions. Because of
this the retry layer enables `retry_non_idempotent` safely. Supply your own key
for cross-process at-least-once flows:

```erlang
livery_stripe_customer:create(Client, Params, #{idempotency_key => <<"order-42">>}).
```

## Configuration

Configure via the `livery_stripe` application environment (see
`config/sys.config.example`). Secrets are better supplied through the OS
environment, which overrides app env at runtime:

- `STRIPE_SECRET_KEY` -> `secret_key`
- `STRIPE_WEBHOOK_SECRET` -> `webhook_secret`

Price ids map to a plan + billing period under the `prices` key, e.g.
`livery_stripe:price_id(pro, monthly)` looks up `pro_monthly`.

## Usage

```erlang
%% Uses the cached, app-configured client:
{ok, Customer} = livery_stripe:create_customer(#{
    email => <<"a@b.c">>, name => <<"A B">>,
    metadata => #{<<"user_id">> => <<"u1">>}
}),
CustomerId = maps:get(<<"id">>, Customer),

%% End-to-end subscription checkout (the friendpaste flow):
{ok, Session} = livery_stripe:subscription_checkout(#{
    customer => CustomerId,
    plan => pro, billing_period => monthly,
    success_url => <<"https://app/billing?success=1">>,
    cancel_url  => <<"https://app/billing?canceled=1">>,
    metadata => #{<<"user_id">> => <<"u1">>, <<"plan">> => <<"pro">>}
}),
CheckoutUrl = maps:get(<<"url">>, Session),

{ok, Sub} = livery_stripe:get_subscription(<<"sub_123">>),
{ok, Portal} = livery_stripe:create_portal_session(#{
    customer => CustomerId, return_url => <<"https://app/billing">>
}).
```

For an explicit client (multiple accounts, tests), call the domain modules
directly: `livery_stripe_customer`, `livery_stripe_checkout`,
`livery_stripe_subscription`, `livery_stripe_portal`, `livery_stripe_price`,
`livery_stripe_product`, `livery_stripe_payment_intent`, `livery_stripe_invoice`.

Build an explicit client with `livery_stripe_client:build(Config)`.

Results are `{ok, map()}` (decoded JSON) or `{error, Reason}` where `Reason` is
`{stripe_error, Status, ErrorMap}`, `{decode, Body}`, or a livery client error
(`timeout`, `circuit_open`, `overloaded`, a transport reason).

## Webhooks

Verify and decode events with `livery_stripe_webhook:construct_event/3,4`
(the equivalent of `stripe.Webhook.construct_event`):

```erlang
case livery_stripe_webhook:construct_event(RawBody, SigHeader, Secret) of
    {ok, Event}                  -> handle(Event);
    {error, invalid_signature}   -> reject;
    {error, invalid_payload}     -> reject;
    {error, timestamp_out_of_tolerance} -> reject
end.
```

Pass the RAW request body bytes; any re-encoding breaks the signature.

Or mount the ready-made livery handler, which verifies the signature and
dispatches to your `webhook_callback` (`handle_event(Type, Event)`):

```erlang
Router = livery_router:compile(
    livery_stripe_webhook_handler:routes(<<"/api/billing/webhook">>)
    ++ OtherRoutes
).
```

Persistence (updating a user's subscription, etc.) lives in the callback, so the
client stays storage-agnostic.

## Build and test

`livery` is consumed locally via `_checkouts/livery` (a symlink to a sibling
`livery` checkout) and is declared in `rebar.config`:

```sh
ln -s ../livery _checkouts/livery   # if not already present

rebar3 compile
rebar3 eunit                 # form encoding, webhook verification, util
rebar3 ct                    # see suites below
rebar3 xref
rebar3 dialyzer
rebar3 do eunit, ct, cover   # combined coverage report
```

Test suites:

- `livery_stripe_form_tests`, `livery_stripe_webhook_tests`,
  `livery_stripe_util_tests` (eunit) - encoding and signature edge cases.
- `livery_stripe_client_SUITE` - resilience over a mock adapter: retry +
  same-key replay, `Retry-After` on 429, no-retry on card errors, transport
  errors, decode/error mapping, query encoding, the concurrency gate, and the
  circuit breaker.
- `livery_stripe_resources_SUITE` - every domain call's method + path.
- `livery_stripe_facade_SUITE` - the facade, `price_id/2`, env override.
- `livery_stripe_billing_SUITE` - end-to-end flow against a live livery mock
  Stripe server + webhook dispatch.
- `livery_stripe_live_SUITE` - opt-in, hits the real Stripe API (see below).

Requires Erlang/OTP 27+ (uses the stdlib `json` module).

## Testing against a real Stripe account

Use a TEST-mode key (`sk_test_...`), never a live key. The operations below
do not charge anyone.

### Automated live suite

`test/livery_stripe_live_SUITE` is skipped unless `STRIPE_SECRET_KEY` is set.
It creates a customer (and verifies the lifecycle), checks idempotency-key
replay returns the same object, and creates a product + recurring price + a
subscription Checkout session, cleaning up after itself (deletes customers,
archives products/prices):

```sh
STRIPE_SECRET_KEY=sk_test_xxx rebar3 ct --suite test/livery_stripe_live_SUITE
```

### Interactive exploration

```sh
STRIPE_SECRET_KEY=sk_test_xxx rebar3 shell
```

```erlang
livery_stripe:configure(),
{ok, Cust} = livery_stripe:create_customer(#{email => <<"you@example.test">>}),
{ok, P}    = livery_stripe_product:create(livery_stripe:client(), #{name => <<"Pro">>}),
{ok, Pr}   = livery_stripe_price:create(livery_stripe:client(),
                #{product => maps:get(<<"id">>, P), unit_amount => 1000,
                  currency => <<"usd">>, recurring => #{interval => <<"month">>}}),
{ok, Sess} = livery_stripe:create_checkout_session(#{
    customer => maps:get(<<"id">>, Cust), mode => <<"subscription">>,
    line_items => [#{<<"price">> => maps:get(<<"id">>, Pr), <<"quantity">> => 1}],
    success_url => <<"https://example.test/ok">>,
    cancel_url  => <<"https://example.test/no">>}),
%% Open maps:get(<<"url">>, Sess) in a browser and pay with card 4242 4242 4242 4242.
```

### Webhooks with the Stripe CLI

Webhook signatures can only be exercised with a real signing secret, which the
Stripe CLI provides:

1. Mount the handler in a livery service and start it:

   ```erlang
   livery:start_service(#{http => #{port => 4000},
       router => livery_router:compile(
           livery_stripe_webhook_handler:routes(<<"/stripe/webhook">>))}).
   ```

   Set `webhook_callback` in config to a `handle_event(Type, Event)` callback,
   and `webhook_secret` to the `whsec_...` that `stripe listen` prints.

2. Forward events and trigger one:

   ```sh
   stripe login
   stripe listen --forward-to localhost:4000/stripe/webhook   # prints whsec_...
   stripe trigger checkout.session.completed
   ```

The handler verifies the signature against the raw body and dispatches the
event to your callback; a verified event returns `200`, a bad signature `400`.

To watch retries and idempotency in action, point `base_url` at a proxy (or
inspect the Stripe dashboard's request logs): a retried create reuses the same
`Idempotency-Key`, so Stripe records one object, not two.
