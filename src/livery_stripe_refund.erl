-module(livery_stripe_refund).
-moduledoc "Stripe Refunds API.".

-export([create/2, create/3, retrieve/2, update/3, cancel/2, list/1, list/2]).

-define(BASE, <<"/refunds">>).

-doc "Refund a charge or PaymentIntent (Params carries `payment_intent` or `charge`).".
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

-doc "Cancel a refund still in the `requires_action` state.".
-spec cancel(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
cancel(Client, Id) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"cancel">>), []).

-spec list(livery_client:client()) -> {ok, map()} | {error, term()}.
list(Client) ->
    list(Client, #{}).

-spec list(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
list(Client, Params) ->
    livery_stripe_client:do_request(Client, get, ?BASE, Params).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.

action(Id, Action) ->
    <<?BASE/binary, "/", Id/binary, "/", Action/binary>>.
