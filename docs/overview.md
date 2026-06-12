# What you can build

`livery_stripe` is a Stripe client for Erlang/OTP. It speaks to Stripe over
the resilient `livery` HTTP client, so the calls you make retry safely,
trip a breaker when Stripe is down, and shed load instead of piling up. You
work in plain maps in and decoded JSON maps out: `{ok, Map}` on success,
`{error, Reason}` when something goes wrong.

Here is what it lets you do. Each section links to a short guide that walks
through the whole job.

## Charge customers on a recurring basis

Sell a monthly or yearly plan. Create a customer, define a product and a
recurring price, then either send the customer to a hosted Stripe Checkout
page or create the subscription directly. From there you can upgrade,
downgrade, pause, resume, or cancel, and hand customers a Billing Portal to
manage their own plan and cards.

See [Subscription billing](guides/subscriptions.md).

## Take one-off payments

Charge for a single purchase with a PaymentIntent: create it, confirm it,
capture it, or cancel it. Need to give money back? Refund all or part of a
charge in one call.

See [One-time payments](guides/payments.md).

## Save a card for later

Collect a card now and charge it later (the modern, PCI-friendly way) with
SetupIntents and PaymentMethods. Attach a card to a customer, make it their
default, list what they have on file, and remove one.

See [Saving cards](guides/saving-cards.md).

## Offer discounts and promo codes

Define a coupon (percent or amount off), wrap it in a customer-facing
promotion code like `LAUNCH25`, and apply it to a subscription or let
people enter it at Checkout. Remove a discount whenever you want.

See [Discounts and promotions](guides/discounts.md).

## Send and manage invoices

Bill a customer out of band: create an invoice, finalize it, send it, mark
it paid or uncollectible, or void it. You can also preview the next invoice
to show proration before a plan change.

See [Invoicing](guides/invoicing.md).

## React to what happens in Stripe

When a checkout completes or a payment fails, Stripe calls your server with
a signed webhook. Verify the signature against the raw body, mount the
ready-made handler, and run your own code on each event.

See [Webhooks](guides/webhooks.md).

## Take SEPA Direct Debit payments

Selling in Europe? Pull euro payments straight from a customer's bank
account with SEPA Direct Debit. It uses the same PaymentIntent, SetupIntent,
and Checkout calls with a `sepa_debit` payment method, plus reading the
customer's mandate.

See [SEPA Direct Debit](guides/sepa-payments.md).

## Start here

New to the client? [Getting started](guides/getting-started.md) covers
configuring it, making your first call, handling errors, and the options
every request accepts.

And if Stripe has an endpoint this client does not wrap yet, you are never
stuck: `livery_stripe_client:do_request/4,5` reaches any endpoint through
the same pipeline. See the end of the getting-started guide.
