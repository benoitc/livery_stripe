-module(livery_stripe_invoice).
-moduledoc "Stripe Invoices API.".

-export([retrieve/2, list/1, list/2, pay/2, pay/3]).

-define(BASE, <<"/invoices">>).

-spec retrieve(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
retrieve(Client, Id) ->
    livery_stripe_client:do_request(Client, get, path(Id), none).

-spec list(livery_client:client()) -> {ok, map()} | {error, term()}.
list(Client) ->
    list(Client, #{}).

-spec list(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
list(Client, Params) ->
    livery_stripe_client:do_request(Client, get, ?BASE, Params).

-spec pay(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
pay(Client, Id) ->
    pay(Client, Id, []).

-spec pay(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
pay(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, post, <<(path(Id))/binary, "/pay">>, Params).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.
