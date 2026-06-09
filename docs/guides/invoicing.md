# Invoicing

Subscriptions invoice themselves. But sometimes you want to bill a customer
out of band: a one-off charge on terms, a manual invoice you email, or a
preview of what the next bill will look like before you change a plan. This
guide covers the invoice lifecycle and the upcoming-invoice preview.

The examples use an explicit `Client`; see
[Getting started](getting-started.md).

## Create and send an invoice

Create a draft invoice for a customer. With `collection_method =>
<<"send_invoice">>` Stripe emails it and the customer pays a hosted page;
`days_until_due` sets the terms:

```erlang
{ok, Inv} = livery_stripe_invoice:create(Client, #{
    customer          => CustomerId,
    collection_method => <<"send_invoice">>,
    days_until_due    => 7
}),
Id = maps:get(<<"id">>, Inv).
```

A fresh invoice is a draft. Add line items (via `do_request` on
`/invoiceitems`, or let a subscription add them), then finalize it to lock it
and make it payable, and send it:

```erlang
{ok, _} = livery_stripe_invoice:finalize(Client, Id),
{ok, _} = livery_stripe_invoice:send(Client, Id).
```

## Settle an invoice

Depending on how you collect, you either let Stripe charge the customer's
card or record payment yourself:

```erlang
%% Charge the customer's default payment method now:
{ok, _} = livery_stripe_invoice:pay(Client, Id),

%% Or write it off:
{ok, _} = livery_stripe_invoice:void(Client, Id),
{ok, _} = livery_stripe_invoice:mark_uncollectible(Client, Id).
```

`void` cancels an invoice that was issued in error; `mark_uncollectible`
records that you do not expect to be paid (useful for your reporting).

## Read and list

```erlang
{ok, _}    = livery_stripe_invoice:retrieve(Client, Id),
{ok, Page} = livery_stripe_invoice:list(Client, #{customer => CustomerId, limit => 5}).
```

A draft invoice you no longer want can be deleted (only drafts):

```erlang
{ok, _} = livery_stripe_invoice:delete(Client, Id).
```

## Preview the next invoice

Before you change a customer's plan, show them what it will cost. The
upcoming-invoice preview computes proration without creating anything:

```erlang
{ok, Preview} = livery_stripe_invoice:upcoming(Client, #{customer => CustomerId}),
Total = maps:get(<<"total">>, Preview).
```

Pass `subscription` and the proposed `subscription_items` to preview a
specific change rather than the next scheduled bill.

## Related

- [Subscription billing](subscriptions.md), whose renewals generate invoices
  automatically.
- [Discounts and promotions](discounts.md) to see a coupon reflected in the
  preview total.
