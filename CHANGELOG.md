# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-12

### Added

- SEPA Direct Debit support: a `livery_stripe_mandate` module (retrieve)
  and a SEPA guide. The payment flows use the existing PaymentIntent /
  SetupIntent / Checkout wrappers with `payment_method_types =>
  [<<"sepa_debit">>]`.

## [0.1.0] - 2026-06-09

First working version: a Stripe API client for Erlang/OTP built on the
livery HTTP client, covering the common billing and payments surface.

### Added

- Resilient client (`livery_stripe_client`) built on `livery_client` with
  a timeout ceiling, retry with exponential backoff and idempotency-key
  replay (honors `Retry-After`), a circuit breaker, and a concurrency
  gate. The shared client is built once and cached in `persistent_term`.
- Facade `livery_stripe` over the cached app-configured client, with
  config from app env and `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET`
  overrides, plus `price_id/2` plan resolution.
- Resource wrappers:
  - Customers: create, retrieve, update, delete, list,
    `list_payment_methods`, `delete_discount`.
  - Products and prices: full CRUD.
  - Checkout sessions: create, retrieve, expire, subscription session.
  - Billing portal: create session.
  - Subscriptions: create, retrieve, update, cancel, list, pause, resume,
    `delete_discount`.
  - Payment intents: create, retrieve, update, confirm, capture, cancel,
    list.
  - Payment methods: attach, detach, retrieve, update, list.
  - Setup intents: create, retrieve, confirm, cancel, list.
  - Refunds: create, retrieve, update, cancel, list.
  - Invoices: create, retrieve, list, pay, finalize, void, send,
    mark_uncollectible, delete, upcoming.
  - Events: retrieve, list.
  - Coupons: full CRUD. Promotion codes: create, retrieve, update, list.
- Webhook signature verification (`livery_stripe_webhook`) and a mountable
  livery handler (`livery_stripe_webhook_handler`) that verifies and
  dispatches events to a configured callback.
- `application/x-www-form-urlencoded` encoder with Stripe's bracketed
  nesting (`livery_stripe_form`).
- Tests: unit (form, webhook, util), resilience and resource SUITEs, a
  webhook handler SUITE, an end-to-end webhook suite over a real livery
  HTTP service, and an opt-in live suite against a real Stripe test
  account (skipped unless `STRIPE_SECRET_KEY` is set).
- erlfmt and elvis (`rebar3_lint`) tooling, and GitHub Actions CI
  (fmt / lint / xref / dialyzer, then build / eunit / ct) plus a gated,
  secret-driven workflow that runs the live suite weekly and on demand.
- ex_doc (`rebar3_ex_doc`) configuration for HTML / hex API docs, with the
  README, the "what you can build" overview, the task guides, and the
  changelog as extras.
- Use-case documentation: an overview plus task guides (getting started,
  subscriptions, payments, saving cards, discounts, invoicing, webhooks).
