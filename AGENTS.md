# Agents

Instructions for AI coding agents working on this project.

## Project Overview

`livery_stripe` is a Stripe API client for Erlang/OTP, built on the
`livery` HTTP client (`livery_client`). It covers the core Stripe
resources and subscriptions and can back a full billing flow
(Checkout + Billing Portal + webhooks). One OTP application, flat
`src/` layout:

```
src/    livery_stripe          Public facade (cached app client)
        livery_stripe_client   Builds the resilient livery_client value
        livery_stripe_form     application/x-www-form-urlencoded encoder
        livery_stripe_webhook  Signature verification + event decode
        livery_stripe_webhook_handler  Ready-made livery route
        livery_stripe_customer / _checkout / _subscription / _portal /
        _price / _product / _payment_intent / _invoice  Domain calls
        livery_stripe_util     Shared helpers
        livery_stripe_app / _sup  OTP runtime (+ livery_stripe.app.src)
test/   EUnit (form, webhook, util) + Common Test suites (client
        resilience over a mock adapter, resources, facade, billing
        end-to-end, opt-in live API)
config/ sys.config.example (app env: keys, prices, webhook callback)
```

`livery` is consumed locally via a `_checkouts/livery` symlink to a
sibling checkout (gitignored); it is declared as `{livery, "..."}` in
`rebar.config`. Drop the checkout once livery is published to hex.

Authoritative behaviour is the suites under `test/`, especially
`livery_stripe_client_SUITE` (retry/idempotency, Retry-After, circuit
breaker, concurrency gate) and `livery_stripe_resources_SUITE`
(method + path per call).

## Required Checks

Every change must be formatted and pass all checks before committing:

```bash
rebar3 fmt          # Auto-format (always run first)
rebar3 compile      # Must compile cleanly (warnings_as_errors)
rebar3 lint         # Elvis linter
rebar3 xref         # Cross-reference analysis
rebar3 dialyzer     # Type checking
rebar3 eunit        # Unit tests (form, webhook, util)
rebar3 ct           # Common Test suites
```

CI (`.github/workflows/ci.yml`) runs `format`, `lint`, `xref`, and
`dialyzer` as fast-fail static checks, then gates `build`/`eunit`/
`ct` on them.

## Build & Development Commands

```bash
ln -s ../livery _checkouts/livery               # if not already present
rebar3 compile                                  # Build
rebar3 shell                                    # Boot a dev shell
rebar3 fmt                                       # Auto-format (erlfmt)
rebar3 fmt --check                               # Format check, no writes
rebar3 lint                                      # Elvis linter
rebar3 ct --suite test/livery_stripe_client_SUITE  # One suite
```

The live suite (`test/livery_stripe_live_SUITE`) hits the real Stripe
API in test mode and is skipped unless `STRIPE_SECRET_KEY` is set. It
covers customer/product/price/checkout, payment intents, the full
subscription lifecycle, invoices, and the cached-client facade, cleaning
up after itself. Use a TEST-mode key (`sk_test_...`) only:

```bash
STRIPE_SECRET_KEY=sk_test_xxx rebar3 ct --suite test/livery_stripe_live_SUITE
```

CI runs it via `.github/workflows/live.yml` (weekly + manual dispatch)
from the `STRIPE_SECRET_KEY` repo secret; it auto-skips when unset. See
the README ("Testing against a real Stripe account") for obtaining keys.

## Architecture

### Resilient client

`livery_stripe_client:build/1` produces a `livery_client` value wired
with livery's flow-control layers: `timeout` (call ceiling), `retry`
(exponential backoff + jitter, honors `Retry-After`, retries on
transport errors and `409/429/5xx`), `circuit_breaker` (trips on a
failure ratio), and `concurrency` (an in-flight admission gate). The
app builds this value once at start and caches it in `persistent_term`
so breaker and gate state is shared across callers.

### Idempotency

Every mutating request (POST) carries an `Idempotency-Key`. livery's
retry replays the same request map, so the key is identical on every
attempt and Stripe deduplicates. This lets the retry layer enable
`retry_non_idempotent` safely. Callers may supply their own key for
cross-process at-least-once flows.

### Facade and domain modules

`livery_stripe` is the public facade over the cached client. For an
explicit client (multi-account, tests), call the domain modules
directly; build a client with `livery_stripe_client:build/1`. Results
are `{ok, map()}` or `{error, Reason}` where `Reason` is
`{stripe_error, Status, ErrorMap}`, `{decode, Body}`, or a livery
client error (`timeout`, `circuit_open`, `overloaded`, transport).

### Webhooks

`livery_stripe_webhook:construct_event/3,4` verifies the signature and
decodes the event. Pass the RAW request body bytes; any re-encoding
breaks the signature. `livery_stripe_webhook_handler:routes/1` mounts
a ready-made livery handler that verifies and dispatches to a
`handle_event(Type, Event)` callback; persistence lives in the
callback so the client stays storage-agnostic.

## Conventions

- Run `rebar3 fmt` before committing; elvis must pass. New per-module
  elvis ignores belong in `rebar.config` with a one-line reason.
- Commit messages: one imperative subject line, body only for
  non-obvious "why". No diff restatement, no "generated by" /
  "co-authored-by" trailers.
- Do not use the em-dash character in code, docs, or messages.
- Secrets come from the OS environment (`STRIPE_SECRET_KEY`,
  `STRIPE_WEBHOOK_SECRET`), which overrides app env at runtime. Never
  commit a live key; tests use `sk_test_...` only.
- Requires Erlang/OTP 27+ (uses the stdlib `json` module).
