# One-time payments

Not every charge is a subscription. When you just want to take a single
payment, you use a PaymentIntent: you tell Stripe how much, the customer
pays, and you capture the funds. This guide covers creating, confirming,
capturing, and cancelling a payment, plus giving money back with a refund.

The examples use an explicit `Client`; see
[Getting started](getting-started.md) to set one up.

## Create a payment

A PaymentIntent tracks one payment from start to finish. Create it with an
amount (in the smallest currency unit, so cents for USD) and a currency:

```erlang
{ok, PI} = livery_stripe_payment_intent:create(Client, #{
    amount               => 2000,            %% $20.00
    currency             => <<"usd">>,
    payment_method_types => [<<"card">>],
    metadata             => #{<<"order_id">> => <<"42">>}
}),
Id = maps:get(<<"id">>, PI).
```

It comes back in `requires_payment_method` status. The customer supplies a
card next, usually in your frontend with the intent's `client_secret`.

## Confirm and capture

Most of the time the frontend confirms the payment with Stripe.js and you
are done. If you are confirming server-side with a known payment method (for
example in tests with Stripe's `pm_card_visa`):

```erlang
{ok, _} = livery_stripe_payment_intent:confirm(Client, Id, #{
    payment_method => <<"pm_card_visa">>
}).
```

By default a confirmed payment is captured right away. If you created the
intent with `capture_method => <<"manual">>` (to authorize now and charge
later, like a hotel hold), capture it when you are ready:

```erlang
{ok, _} = livery_stripe_payment_intent:capture(Client, Id).
```

You can also amend an intent before it is confirmed:

```erlang
{ok, _} = livery_stripe_payment_intent:update(Client, Id, #{
    metadata => #{<<"note">> => <<"gift">>}
}).
```

## Cancel

Changed your mind before capture? Cancel it:

```erlang
{ok, _} = livery_stripe_payment_intent:cancel(Client, Id).
```

## Look things up

Read one back, or list recent payments:

```erlang
{ok, _}   = livery_stripe_payment_intent:retrieve(Client, Id),
{ok, Page} = livery_stripe_payment_intent:list(Client, #{limit => 5}).
```

## Refunds

To give money back, refund the PaymentIntent. Leave out `amount` for a full
refund, or pass it (in cents) for a partial one:

```erlang
%% Full refund:
{ok, _} = livery_stripe_refund:create(Client, #{payment_intent => Id}),

%% Partial refund of $5.00:
{ok, _} = livery_stripe_refund:create(Client, #{payment_intent => Id, amount => 500}).
```

You can read a refund back, list refunds, or (rarely) cancel one that is
still pending manual action:

```erlang
{ok, _} = livery_stripe_refund:retrieve(Client, <<"re_123">>),
{ok, _} = livery_stripe_refund:list(Client, #{payment_intent => Id}).
```

## Related

- [Saving cards](saving-cards.md) to charge a returning customer without
  re-collecting their card.
- [Webhooks](webhooks.md) to react to `payment_intent.succeeded` and
  `charge.refunded`.
