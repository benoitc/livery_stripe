# Webhooks

A lot of what matters happens asynchronously: a hosted checkout completes, a
renewal succeeds, a payment fails. Stripe tells you by calling your server
with a signed event. Your job is to verify the signature, then run your own
code. This guide shows both the manual way and the ready-made handler.

## The golden rule: use the raw body

Stripe signs the exact bytes it sent. If you decode the JSON and re-encode
it before verifying, the bytes change and the signature will not match. Pass
the raw request body through untouched.

## Verify an event yourself

If you have your own HTTP layer, verify and decode in one call. It needs the
raw body, the `Stripe-Signature` header, and your webhook signing secret
(`whsec_...`):

```erlang
case livery_stripe_webhook:construct_event(RawBody, SigHeader, Secret) of
    {ok, Event}                          -> handle(Event);
    {error, invalid_signature}           -> reject;
    {error, invalid_payload}             -> reject;
    {error, timestamp_out_of_tolerance}  -> reject
end.
```

The timestamp check (300s by default) defeats replay attacks. You can widen
or disable it, and pin the clock in tests, with an options map as the fourth
argument: `#{tolerance => 0}` or `#{now => 1700000000}`.

## Or mount the ready-made handler

If you serve HTTP with livery, skip the plumbing. Mount the handler's route
and it verifies the signature, decodes the event, and dispatches to your
callback:

```erlang
Router = livery_router:compile(
    livery_stripe_webhook_handler:routes(<<"/stripe/webhook">>) ++ OtherRoutes
).
```

It reads the signing secret and your callback from the `livery_stripe` app
env (`webhook_secret` and `webhook_callback`). A verified event answers
`200`; a bad payload or signature answers `400`, which tells Stripe to back
off and retry.

## Your callback

The callback is where your code runs. It can be any of four shapes, so use
whichever fits:

```erlang
%% A fun of the event:
fun(Event) -> ... end

%% A fun of type + event:
fun(Type, Event) -> ... end

%% A module exporting handle_event/2:
my_billing            %% my_billing:handle_event(Type, Event)

%% A {Module, Function} pair:
{my_billing, on_stripe_event}
```

A typical handler routes on the event type:

```erlang
handle_event(<<"checkout.session.completed">>, Event) ->
    Session = maps:get(<<"object">>, maps:get(<<"data">>, Event)),
    activate_subscription(maps:get(<<"customer">>, Session)),
    ok;
handle_event(<<"invoice.payment_failed">>, _Event) ->
    flag_past_due(),
    ok;
handle_event(_Other, _Event) ->
    ok.
```

Keep persistence (updating a user's plan, sending an email) inside the
callback. The handler itself stays storage-agnostic.

## Re-fetch for extra safety

A verified signature proves the event is genuine. For high-stakes actions
you can also re-read the authoritative event from the API by id before
acting, which sidesteps any spoofing or staleness:

```erlang
{ok, Fresh} = livery_stripe_event:retrieve(Client, maps:get(<<"id">>, Event)),
{ok, _Page} = livery_stripe_event:list(Client, #{
    type  => <<"checkout.session.completed">>,
    limit => 5
}).
```

## Testing locally

Webhook signatures need a real signing secret, which the Stripe CLI gives
you:

```sh
stripe listen --forward-to localhost:4000/stripe/webhook   # prints whsec_...
stripe trigger checkout.session.completed
```

Point `webhook_secret` at the `whsec_...` it prints, and you will see your
callback fire.

## Related

- [Subscription billing](subscriptions.md), the source of most events you
  will handle.
- [Getting started](getting-started.md) for configuring the client the
  re-fetch calls use.
