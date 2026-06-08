-module(livery_stripe_setup_intent).
-moduledoc "Stripe SetupIntents API (save a payment method for future use).".

-export([create/2, create/3, retrieve/2, confirm/2, confirm/3, cancel/2, list/1, list/2]).

-define(BASE, <<"/setup_intents">>).

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

-spec confirm(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
confirm(Client, Id) ->
    confirm(Client, Id, []).

-spec confirm(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
confirm(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"confirm">>), Params).

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
