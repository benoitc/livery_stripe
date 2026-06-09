# Discounts and promotions

Want to run a launch promo or give a customer 25% off? Stripe splits this
into two pieces. A **coupon** defines the discount itself (percent or amount
off, and how long it lasts). A **promotion code** is the customer-facing
string (like `LAUNCH25`) that maps to a coupon. The applied result is a
**discount**, which you can remove at any time.

The examples use an explicit `Client`; see
[Getting started](getting-started.md).

## Create a coupon

Start with the coupon. This one takes 25% off, once:

```erlang
{ok, Coupon} = livery_stripe_coupon:create(Client, #{
    percent_off => 25,
    duration    => <<"once">>            %% or "repeating" / "forever"
}),
CouponId = maps:get(<<"id">>, Coupon).
```

For a fixed amount instead of a percentage, use `amount_off` (in cents) and
`currency`.

## Wrap it in a promotion code

A coupon on its own is something you apply in code. To give customers a code
they can type, create a promotion code that points at the coupon:

```erlang
{ok, Promo} = livery_stripe_promotion_code:create(Client, #{
    coupon => CouponId,
    code   => <<"LAUNCH25">>             %% optional; Stripe generates one if omitted
}),
PromoId = maps:get(<<"id">>, Promo).
```

## Apply a discount

There are two common ways to apply it.

Apply a coupon straight to a subscription:

```erlang
{ok, _} = livery_stripe_subscription:update(Client, SubId, #{coupon => CouponId}).
```

Or let customers enter the promotion code themselves on the hosted Checkout
page, by turning on the field:

```erlang
{ok, _} = livery_stripe_checkout:create_session(Client, #{
    mode                  => <<"subscription">>,
    line_items            => [#{<<"price">> => PriceId, <<"quantity">> => 1}],
    allow_promotion_codes => true,
    success_url           => <<"https://app/ok">>,
    cancel_url            => <<"https://app/no">>
}).
```

## Remove a discount

To take a discount off a subscription (or a customer), delete it:

```erlang
{ok, _} = livery_stripe_subscription:delete_discount(Client, SubId),
{ok, _} = livery_stripe_customer:delete_discount(Client, CustomerId).
```

## Retire a code or coupon

Promotion codes cannot be deleted, but you can deactivate one so it stops
working:

```erlang
{ok, _} = livery_stripe_promotion_code:update(Client, PromoId, #{active => false}).
```

Coupons can be deleted outright (existing discounts already applied stay):

```erlang
{ok, _} = livery_stripe_coupon:delete(Client, CouponId).
```

## Related

- [Subscription billing](subscriptions.md) for the plans you are discounting.
- [Invoicing](invoicing.md) to see a discount reflected in an upcoming
  invoice preview.
