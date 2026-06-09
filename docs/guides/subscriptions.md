# Subscription billing

You want to charge customers on a recurring basis: a monthly or yearly
plan. This guide walks the whole flow, from nothing to an active
subscription you can manage.

The pieces: a **customer**, a **product** with a recurring **price**, and a
**subscription** that ties a customer to a price. You can create the
subscription two ways: send the customer to a hosted Checkout page (Stripe
collects the card), or create it directly if you already have a payment
method on file. We cover both.

If you have not configured a client yet, start with
[Getting started](getting-started.md). The examples below use an explicit
`Client`.

## 1. Create the customer

```erlang
{ok, Cust} = livery_stripe_customer:create(Client, #{
    email    => <<"a@b.c">>,
    name     => <<"A B">>,
    metadata => #{<<"user_id">> => <<"u1">>}
}),
CustomerId = maps:get(<<"id">>, Cust).
```

Stashing your own `user_id` in `metadata` makes it easy to match Stripe
objects back to your database later.

## 2. Define a product and a recurring price

A product is the thing you sell; a price is how much and how often. You set
these up once, not per customer:

```erlang
{ok, Product} = livery_stripe_product:create(Client, #{name => <<"Pro plan">>}),
ProductId = maps:get(<<"id">>, Product),

{ok, Price} = livery_stripe_price:create(Client, #{
    product     => ProductId,
    unit_amount => 1500,                       %% $15.00, in cents
    currency    => <<"usd">>,
    recurring   => #{interval => <<"month">>}
}),
PriceId = maps:get(<<"id">>, Price).
```

In real apps you create prices ahead of time and keep their ids in config.
The facade's `price_id/2` then resolves a plan to a price id (see
[Getting started](getting-started.md)).

## 3a. Start the subscription with hosted Checkout

The easiest path. Stripe hosts the payment page and collects the card; you
just send the customer to the returned URL:

```erlang
{ok, Session} = livery_stripe_checkout:subscription_session(Client, #{
    customer    => CustomerId,
    price       => PriceId,
    success_url => <<"https://app/billing?success=1">>,
    cancel_url  => <<"https://app/billing?canceled=1">>,
    metadata    => #{<<"user_id">> => <<"u1">>}
}),
CheckoutUrl = maps:get(<<"url">>, Session).
%% Redirect the customer to CheckoutUrl.
```

The subscription becomes active once they pay. You find out by listening for
the `checkout.session.completed` webhook, see [Webhooks](webhooks.md).

## 3b. Or create the subscription directly

If the customer already has a payment method (see
[Saving cards](saving-cards.md)), skip Checkout and create the subscription
yourself:

```erlang
{ok, Sub} = livery_stripe_subscription:create(Client, #{
    customer => CustomerId,
    items    => [#{price => PriceId}]
}),
SubId = maps:get(<<"id">>, Sub).
```

A subscription that bills immediately needs a default payment method on the
customer, or it errors. With a saved card you can also pass
`default_payment_method` in the create call.

## 4. Manage the subscription

Once it exists, the everyday operations:

```erlang
%% Change plan, quantity, or metadata:
{ok, _} = livery_stripe_subscription:update(Client, SubId, #{
    metadata => #{<<"tier">> => <<"pro">>}
}),

%% Pause collection (voids invoices while paused) and resume later:
{ok, _} = livery_stripe_subscription:pause(Client, SubId),
{ok, _} = livery_stripe_subscription:resume(Client, SubId),

%% Cancel now, or at period end:
{ok, _} = livery_stripe_subscription:cancel(Client, SubId),
{ok, _} = livery_stripe_subscription:update(Client, SubId, #{cancel_at_period_end => true}).
```

`cancel/2` ends it immediately; setting `cancel_at_period_end` lets the
customer keep access until the period they paid for runs out. To read the
current state at any time:

```erlang
{ok, Current} = livery_stripe_subscription:retrieve(Client, SubId),
Status = maps:get(<<"status">>, Current).   %% active, past_due, canceled, ...
```

## 5. Let customers manage themselves

Rather than building plan-change and card-update screens, hand customers a
Stripe-hosted Billing Portal:

```erlang
{ok, Portal} = livery_stripe_portal:create_session(Client, #{
    customer   => CustomerId,
    return_url => <<"https://app/billing">>
}),
PortalUrl = maps:get(<<"url">>, Portal).
%% Redirect the customer to PortalUrl.
```

From there they can update their card, switch plans, view invoices, and
cancel, all without you writing those flows.

## Related

- [Saving cards](saving-cards.md) to put a payment method on file first.
- [Discounts and promotions](discounts.md) to apply a coupon to a plan.
- [Webhooks](webhooks.md) to react when a checkout completes or a payment
  fails.
