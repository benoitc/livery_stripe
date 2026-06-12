# SEPA Direct Debit

SEPA Direct Debit lets you pull euro payments straight from a customer's
bank account instead of a card. It is popular for subscriptions in Europe
because fees are low. Two things make it different from cards: the customer
signs a **mandate** (their authorization to debit the account), and
payments are **asynchronous** - a charge starts as `processing` and only
turns `succeeded` (or `failed`) days later.

Good news: you do not need new code for the flow. SEPA is a payment method
type, so you use the same PaymentIntent, SetupIntent, Checkout, and
PaymentMethod calls you already know, with `currency => <<"eur">>` and
`payment_method_types => [<<"sepa_debit">>]`. This client adds one
SEPA-specific helper, reading the mandate.

The examples use an explicit `Client`; see
[Getting started](getting-started.md).

## A one-off SEPA charge

Create a PaymentIntent in euros that accepts SEPA debit. The customer
provides their IBAN (collected in your frontend with Stripe.js), which
yields a `sepa_debit` payment method you confirm with:

```erlang
{ok, PI} = livery_stripe_payment_intent:create(Client, #{
    amount               => 1999,                 %% EUR 19.99, in cents
    currency             => <<"eur">>,
    payment_method_types => [<<"sepa_debit">>],
    customer             => CustomerId
}),
Id = maps:get(<<"id">>, PI),

%% After the customer supplies an IBAN-backed payment method (pm_...):
{ok, Confirmed} = livery_stripe_payment_intent:confirm(Client, Id, #{
    payment_method => <<"pm_...">>
}),
<<"processing">> = maps:get(<<"status">>, Confirmed).
```

Note the status: `processing`, not `succeeded`. Do not deliver the goods
yet. Wait for the `payment_intent.succeeded` webhook (and handle
`payment_intent.payment_failed`), see [Webhooks](webhooks.md).

## Save a mandate for recurring billing

For subscriptions you collect the mandate once with a SetupIntent, then
reuse the saved payment method. Create the SetupIntent for SEPA:

```erlang
{ok, SI} = livery_stripe_setup_intent:create(Client, #{
    customer             => CustomerId,
    payment_method_types => [<<"sepa_debit">>]
}),
ClientSecret = maps:get(<<"client_secret">>, SI).
%% Confirm client-side with the customer's IBAN; this records the mandate.
```

Once confirmed you have a saved `sepa_debit` payment method. Make it the
customer's default and create the subscription as usual:

```erlang
{ok, _} = livery_stripe_customer:update(Client, CustomerId, #{
    invoice_settings => #{default_payment_method => <<"pm_...">>}
}),
{ok, _} = livery_stripe_subscription:create(Client, #{
    customer => CustomerId,
    items    => [#{price => PriceId}]
}).
```

See [Saving cards](saving-cards.md) and
[Subscription billing](subscriptions.md) for the rest of those flows; SEPA
only changes the payment method type.

## Hosted Checkout

If you would rather let Stripe host the page, ask for SEPA in the Checkout
session:

```erlang
{ok, Session} = livery_stripe_checkout:create_session(Client, #{
    mode                 => <<"subscription">>,
    payment_method_types => [<<"sepa_debit">>],
    customer             => CustomerId,
    line_items           => [#{<<"price">> => PriceId, <<"quantity">> => 1}],
    success_url          => <<"https://app/ok">>,
    cancel_url           => <<"https://app/no">>
}),
Url = maps:get(<<"url">>, Session).
```

## Read the mandate

A SEPA payment references the mandate that authorized it. The PaymentIntent,
charge, and saved payment method carry a `mandate` id; read it to show the
customer their authorization or to audit it:

```erlang
{ok, Mandate} = livery_stripe_mandate:retrieve(Client, <<"mandate_123">>),
Status = maps:get(<<"status">>, Mandate),          %% active, inactive, pending
Type   = maps:get(<<"type">>, Mandate).            %% single_use or multi_use
```

Mandates are created for you when the SetupIntent or PaymentIntent is
confirmed; there is nothing to create or list, only retrieve.

## Things to keep in mind

- **Asynchronous settlement.** Treat `processing` as "not yet paid". The
  authoritative outcome arrives by webhook days later. Refunds and disputes
  follow the same delayed pattern.
- **Euros only.** SEPA is a euro scheme; set `currency => <<"eur">>`.
- **Refunds** work exactly like cards, see
  [One-time payments](payments.md).

## Related

- [One-time payments](payments.md) for the PaymentIntent lifecycle.
- [Saving cards](saving-cards.md) for SetupIntents and payment methods.
- [Webhooks](webhooks.md) - essential for SEPA, since results are async.
