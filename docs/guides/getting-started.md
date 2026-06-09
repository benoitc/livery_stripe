# Getting started

This guide gets you from zero to your first Stripe call, then covers the
things every other guide assumes: how errors come back, what options a
request takes, and how the client keeps you out of trouble under load.

## Install

`livery_stripe` builds on `livery`. Until livery is on hex, link it in as a
checkout dependency next to your project:

```sh
ln -s ../livery _checkouts/livery
rebar3 compile
```

You need a Stripe secret key. Use a test key (`sk_test_...`) while you
build; it never touches real money. Grab one from the Stripe Dashboard
under Developers - API keys (with Test mode on).

## Two ways to hold a client

Every Stripe call needs a client. You have two choices.

The first is the cached facade. Configure it once at app start and the
client lives in `persistent_term`, shared by every process. After that you
call the short `livery_stripe:*` functions and never pass a client around:

```erlang
%% Reads app env plus the STRIPE_SECRET_KEY env override, then caches.
_ = livery_stripe:configure(),

{ok, Customer} = livery_stripe:create_customer(#{email => <<"a@b.c">>}).
```

The second is an explicit client. Build it yourself and pass it in. This is
what you want for tests, scripts, or talking to more than one account:

```erlang
Client = livery_stripe_client:build(#{secret_key => <<"sk_test_...">>}),
{ok, Customer} = livery_stripe_customer:create(Client, #{email => <<"a@b.c">>}).
```

The facade wraps a curated subset of the API. For everything else (and most
of these guides), call the domain modules with an explicit client.

## Configuring the client

`livery_stripe_client:build/1` takes a config map. Only `secret_key` is
required:

```erlang
Client = livery_stripe_client:build(#{
    secret_key      => <<"sk_test_...">>,
    api_version     => <<"2024-06-20">>,   %% Stripe-Version header
    base_url        => <<"https://api.stripe.com/v1">>,
    timeout_ms      => 30000,              %% per-call ceiling
    concurrency     => 50,                 %% max in-flight calls
    retry           => #{max => 3, backoff => {500, 2.0}},
    circuit_breaker => #{window => 50, trip => 0.5, cooldown => 5000}
}).
```

With the facade, config comes from the `livery_stripe` application env,
where `secret_key` and `webhook_secret` are overridden by the
`STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` OS variables. That keeps
secrets out of your release. You can also map plans to price ids:

```erlang
%% sys.config: {livery_stripe, [{prices, #{pro_monthly => <<"price_123">>}}]}
{ok, <<"price_123">>} = livery_stripe:price_id(pro, monthly).
```

## Your first call

Create a customer and read it back:

```erlang
{ok, Cust} = livery_stripe_customer:create(Client, #{
    email    => <<"a@b.c">>,
    name     => <<"A B">>,
    metadata => #{<<"user_id">> => <<"u1">>}
}),
Id = maps:get(<<"id">>, Cust),
{ok, _Same} = livery_stripe_customer:retrieve(Client, Id).
```

Params go in as a map (or a proplist if you need ordering). Nested maps and
lists are encoded the way Stripe expects, so `#{recurring => #{interval =>
<<"month">>}}` becomes `recurring[interval]=month` for you.

## Handling errors

Every call returns `{ok, Map}` or `{error, Reason}`. There are three kinds
of `Reason`, and one `case` handles them all:

```erlang
case livery_stripe_customer:retrieve(Client, Id) of
    {ok, Customer} ->
        Customer;
    {error, {stripe_error, 404, _Err}} ->
        not_found;
    {error, {stripe_error, Status, #{<<"message">> := Msg}}} ->
        {api_error, Status, Msg};       %% Stripe said no (4xx/5xx) with details
    {error, {decode, _Body}} ->
        bad_json;                        %% a 2xx body that was not JSON
    {error, timeout} ->
        retry_later;
    {error, circuit_open} ->
        degraded;                        %% breaker tripped on a Stripe outage
    {error, overloaded} ->
        backpressure;                    %% the concurrency gate is full
    {error, _Transport} ->
        transport_error
end.
```

The `stripe_error` map is Stripe's own error object, so you can branch on
`<<"code">>` or `<<"type">>` when you need to.

## Request options

Mutating calls (the `create/3` and `update/4` arities) take an options map:

```erlang
livery_stripe_customer:create(Client, Params, #{
    idempotency_key => <<"order-42">>,   %% safe to retry: Stripe dedupes by key
    stripe_account  => <<"acct_123">>,   %% act as a connected account
    timeout         => 5000,             %% override the timeout for this call
    headers         => [{<<"x-trace">>, <<"abc">>}]
}).
```

You rarely need `idempotency_key`: every POST already gets a generated one,
so the built-in retry never double-charges. Supply your own only when you
want at-least-once safety across processes or restarts.

## Working with lists

List calls take Stripe's pagination params and return a page:

```erlang
{ok, Page} = livery_stripe_customer:list(Client, #{limit => 20}),
Data = maps:get(<<"data">>, Page),
case maps:get(<<"has_more">>, Page) of
    true ->
        After = maps:get(<<"id">>, lists:last(Data)),
        livery_stripe_customer:list(Client, #{limit => 20, starting_after => After});
    false ->
        done
end.
```

## What the client does for you

You do not have to add retries or timeouts yourself. Every call runs
through livery's flow-control stack:

- a hard timeout so no call hangs forever,
- retry with exponential backoff and jitter on transient failures
  (`409/429/5xx` and transport errors), honoring `Retry-After` and replaying
  the same idempotency key,
- a circuit breaker that fails fast when Stripe is having a bad day,
- a concurrency gate that returns `{error, overloaded}` instead of opening
  unbounded connections.

Because the cached client lives in `persistent_term`, the breaker and gate
are shared across your whole node.

## When the client does not wrap an endpoint

This client covers the common billing and payments surface, but Stripe is
huge. Anything without a wrapper is one call away through the same pipeline:

```erlang
%% POST /v1/tax_rates
{ok, _} = livery_stripe_client:do_request(Client, post, <<"/tax_rates">>, #{
    display_name => <<"VAT">>, percentage => 20.0, inclusive => false
}),

%% GET /v1/disputes?limit=3
{ok, _} = livery_stripe_client:do_request(Client, get, <<"/disputes">>, #{limit => 3}).
```

`do_request/4,5` form-encodes your params, adds the idempotency key, maps
the response, and runs through the same resilience stack as every wrapper.

Next, pick the job you are doing: [subscriptions](subscriptions.md),
[one-time payments](payments.md), [saving cards](saving-cards.md),
[discounts](discounts.md), [invoicing](invoicing.md), or
[webhooks](webhooks.md).
