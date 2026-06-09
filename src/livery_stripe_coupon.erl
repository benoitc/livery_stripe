-module(livery_stripe_coupon).
-moduledoc "Stripe Coupons API (define a discount: percent_off or amount_off).".

-export([create/2, create/3, retrieve/2, update/3, delete/2, list/1, list/2]).

-define(BASE, <<"/coupons">>).

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

-spec update(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
update(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, post, path(Id), Params).

-spec delete(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
delete(Client, Id) ->
    livery_stripe_client:do_request(Client, delete, path(Id), none).

-spec list(livery_client:client()) -> {ok, map()} | {error, term()}.
list(Client) ->
    list(Client, #{}).

-spec list(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
list(Client, Params) ->
    livery_stripe_client:do_request(Client, get, ?BASE, Params).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.
