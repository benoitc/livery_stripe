-module(livery_stripe_promotion_code).
-moduledoc "Stripe Promotion Codes API (customer-facing codes mapping to a coupon).".

-export([create/2, create/3, retrieve/2, update/3, list/1, list/2]).

-define(BASE, <<"/promotion_codes">>).

-doc "Create a promotion code (Params requires `coupon`; optional `code`).".
-spec create(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
create(Client, Params) ->
    create(Client, Params, #{}).

-doc "Like `create/2` with request options (`idempotency_key`, etc.).".
-spec create(livery_client:client(), map() | list(), map()) -> {ok, map()} | {error, term()}.
create(Client, Params, Opts) ->
    livery_stripe_client:do_request(Client, post, ?BASE, Params, Opts).

-spec retrieve(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
retrieve(Client, Id) ->
    livery_stripe_client:do_request(Client, get, path(Id), none).

-doc "Update a promotion code (e.g. `active => false` to deactivate).".
-spec update(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
update(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, post, path(Id), Params).

-spec list(livery_client:client()) -> {ok, map()} | {error, term()}.
list(Client) ->
    list(Client, #{}).

-spec list(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
list(Client, Params) ->
    livery_stripe_client:do_request(Client, get, ?BASE, Params).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.
