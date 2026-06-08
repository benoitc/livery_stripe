-module(livery_stripe_price).
-moduledoc "Stripe Prices API.".

-export([create/2, retrieve/2, update/3, list/1, list/2]).

-define(BASE, <<"/prices">>).

-spec create(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
create(Client, Params) ->
    livery_stripe_client:do_request(Client, post, ?BASE, Params).

-spec retrieve(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
retrieve(Client, Id) ->
    livery_stripe_client:do_request(Client, get, path(Id), none).

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
