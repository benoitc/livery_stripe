-module(livery_stripe).
-moduledoc """
Public facade for the Stripe client.

Configuration is read from the `livery_stripe` application environment,
with secrets overridable from the OS environment (`STRIPE_SECRET_KEY`,
`STRIPE_WEBHOOK_SECRET`). At app start a shared client is built and cached;
the convenience functions here use that cached client. For an explicit
client (multi-account, tests) call the domain modules
(`livery_stripe_customer`, `livery_stripe_subscription`, ...) directly.

```erlang
{ok, Customer} = livery_stripe:create_customer(#{email => <<"a@b.c">>}),
{ok, Session}  = livery_stripe:subscription_checkout(#{
    customer => maps:get(<<"id">>, Customer),
    plan => pro, billing_period => monthly,
    success_url => <<"https://app/billing?success=1">>,
    cancel_url  => <<"https://app/billing?canceled=1">>
}).
```
""".

%% Configuration / client lifecycle
-export([config/0, configure/0, configure/1, client/0, set_client/1, price_id/2]).

%% Customers
-export([create_customer/1, get_customer/1, update_customer/2]).

%% Checkout
-export([create_checkout_session/1, subscription_checkout/1]).

%% Billing portal
-export([create_portal_session/1]).

%% Subscriptions
-export([create_subscription/1, get_subscription/1, update_subscription/2, cancel_subscription/1]).

-type result() :: {ok, map()} | {error, term()}.
-export_type([result/0]).

%%====================================================================
%% Configuration / client lifecycle
%%====================================================================

-doc """
The effective config map: `livery_stripe` app env, with `secret_key` and
`webhook_secret` overridden by `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET`
when those OS variables are set.
""".
-spec config() -> map().
config() ->
    Base = maps:from_list(application:get_all_env(livery_stripe)),
    M1 = override(secret_key, "STRIPE_SECRET_KEY", Base),
    override(webhook_secret, "STRIPE_WEBHOOK_SECRET", M1).

-doc "Build and cache the shared client from `config/0`.".
-spec configure() -> livery_client:client().
configure() ->
    configure(config()).

-doc "Build and cache the shared client from an explicit config map.".
-spec configure(map()) -> livery_client:client().
configure(Cfg) ->
    Client = livery_stripe_client:build(Cfg),
    ok = livery_stripe_client:cache(Client),
    Client.

-doc "The cached shared client (raises if not configured).".
-spec client() -> livery_client:client().
client() ->
    livery_stripe_client:cached().

-doc "Replace the cached shared client.".
-spec set_client(livery_client:client()) -> ok.
set_client(Client) ->
    livery_stripe_client:cache(Client).

-doc """
Resolve a configured price id for a plan and billing period, e.g.
`price_id(pro, monthly)` looks up the `pro_monthly` key under the `prices`
config map (mirrors friendpaste's plan->price mapping).
""".
-spec price_id(atom() | binary(), atom() | binary()) ->
    {ok, binary()} | {error, {price_not_configured, atom()}}.
price_id(Plan, Period) ->
    Prices = maps:get(prices, config(), #{}),
    Key = price_key(Plan, Period),
    case maps:get(Key, Prices, undefined) of
        undefined -> {error, {price_not_configured, Key}};
        Id -> {ok, livery_stripe_util:to_bin(Id)}
    end.

%%====================================================================
%% Customers
%%====================================================================

-spec create_customer(map() | list()) -> result().
create_customer(Params) ->
    livery_stripe_customer:create(client(), Params).

-spec get_customer(binary()) -> result().
get_customer(Id) ->
    livery_stripe_customer:retrieve(client(), Id).

-spec update_customer(binary(), map() | list()) -> result().
update_customer(Id, Params) ->
    livery_stripe_customer:update(client(), Id, Params).

%%====================================================================
%% Checkout
%%====================================================================

-spec create_checkout_session(map() | list()) -> result().
create_checkout_session(Params) ->
    livery_stripe_checkout:create_session(client(), Params).

-doc """
End-to-end subscription checkout, the friendpaste flow: resolve the price
from `plan` + `billing_period`, then create a subscription-mode session.

`Params` requires `customer`, `plan`, `billing_period`, `success_url`,
`cancel_url`; optional `metadata`, `quantity`.
""".
-spec subscription_checkout(map()) -> result().
subscription_checkout(#{plan := Plan, billing_period := Period} = Params) ->
    case price_id(Plan, Period) of
        {ok, Price} ->
            livery_stripe_checkout:subscription_session(client(), Params#{price => Price});
        {error, _} = Error ->
            Error
    end.

%%====================================================================
%% Billing portal
%%====================================================================

-spec create_portal_session(map()) -> result().
create_portal_session(Params) ->
    livery_stripe_portal:create_session(client(), Params).

%%====================================================================
%% Subscriptions
%%====================================================================

-spec create_subscription(map() | list()) -> result().
create_subscription(Params) ->
    livery_stripe_subscription:create(client(), Params).

-spec get_subscription(binary()) -> result().
get_subscription(Id) ->
    livery_stripe_subscription:retrieve(client(), Id).

-spec update_subscription(binary(), map() | list()) -> result().
update_subscription(Id, Params) ->
    livery_stripe_subscription:update(client(), Id, Params).

-spec cancel_subscription(binary()) -> result().
cancel_subscription(Id) ->
    livery_stripe_subscription:cancel(client(), Id).

%%====================================================================
%% Internals
%%====================================================================

override(Key, Var, Map) ->
    case os:getenv(Var) of
        false -> Map;
        "" -> Map;
        Value -> Map#{Key => list_to_binary(Value)}
    end.

price_key(Plan, Period) ->
    binary_to_atom(
        <<
            (livery_stripe_util:to_bin(Plan))/binary,
            "_",
            (livery_stripe_util:to_bin(Period))/binary
        >>,
        utf8
    ).
