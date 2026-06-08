-module(livery_stripe_payment_method).
-moduledoc "Stripe PaymentMethods API.".

-export([attach/3, detach/2, retrieve/2, update/3, list/2]).

-define(BASE, <<"/payment_methods">>).

-doc "Attach a payment method to a customer (Params carries `customer`).".
-spec attach(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
attach(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"attach">>), Params).

-spec detach(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
detach(Client, Id) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"detach">>), []).

-spec retrieve(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
retrieve(Client, Id) ->
    livery_stripe_client:do_request(Client, get, path(Id), none).

-spec update(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
update(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, post, path(Id), Params).

-doc "List payment methods; Params should carry `customer` and `type`.".
-spec list(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
list(Client, Params) ->
    livery_stripe_client:do_request(Client, get, ?BASE, Params).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.

action(Id, Action) ->
    <<?BASE/binary, "/", Id/binary, "/", Action/binary>>.
