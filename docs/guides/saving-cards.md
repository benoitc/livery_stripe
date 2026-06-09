# Saving cards

Sometimes you want to collect a card now and charge it later: to start a
subscription after a trial, to bill on usage, or to give returning
customers one-click checkout. The modern, PCI-friendly way to do that is a
SetupIntent (to collect and save the card) plus PaymentMethods (to attach,
list, and remove saved cards).

The examples use an explicit `Client`; see
[Getting started](getting-started.md).

## Collect a card without charging

A SetupIntent is like a PaymentIntent with no charge: it sets up a card for
future use. Create one for the customer and hand its `client_secret` to your
frontend, where Stripe.js collects the card and confirms:

```erlang
{ok, SI} = livery_stripe_setup_intent:create(Client, #{
    customer             => CustomerId,
    payment_method_types => [<<"card">>]
}),
ClientSecret = maps:get(<<"client_secret">>, SI).
%% Send ClientSecret to the browser; confirm there with Stripe.js.
```

Once confirmed, the card is saved to the customer and you have a
`PaymentMethod` id (`pm_...`) you can charge later. You can read or cancel
an in-progress SetupIntent too:

```erlang
{ok, _} = livery_stripe_setup_intent:retrieve(Client, maps:get(<<"id">>, SI)),
{ok, _} = livery_stripe_setup_intent:cancel(Client, maps:get(<<"id">>, SI)).
```

## Attach a card directly

If you already have a PaymentMethod id (from the frontend, or Stripe's test
methods like `pm_card_visa`), attach it to a customer yourself:

```erlang
{ok, Pm} = livery_stripe_payment_method:attach(Client, <<"pm_card_visa">>, #{
    customer => CustomerId
}),
PmId = maps:get(<<"id">>, Pm).
```

## Make it the default

So new invoices and subscriptions use this card, set it as the customer's
default:

```erlang
{ok, _} = livery_stripe_customer:update(Client, CustomerId, #{
    invoice_settings => #{default_payment_method => PmId}
}).
```

Now you can create a subscription that bills immediately, see
[Subscription billing](subscriptions.md).

## List and remove

Show a customer what they have on file, or take one off:

```erlang
{ok, Cards} = livery_stripe_payment_method:list(Client, #{
    customer => CustomerId,
    type     => <<"card">>
}),
%% The same list is also reachable from the customer:
{ok, _Same} = livery_stripe_customer:list_payment_methods(Client, CustomerId, #{
    type => <<"card">>
}),

{ok, _} = livery_stripe_payment_method:detach(Client, PmId).
```

Detaching leaves the customer but removes the card; any subscription using
it as default will need a new one.

## Related

- [Subscription billing](subscriptions.md) to charge the saved card on a
  recurring basis.
- [One-time payments](payments.md) to charge it once.
