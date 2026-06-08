-module(livery_stripe_payment_intent).
-moduledoc "Stripe PaymentIntents API.".

-export([
    create/2,
    retrieve/2,
    update/3,
    confirm/2, confirm/3,
    capture/2, capture/3,
    cancel/2,
    list/1,
    list/2
]).

-define(BASE, <<"/payment_intents">>).

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

-spec confirm(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
confirm(Client, Id) ->
    confirm(Client, Id, []).

-spec confirm(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
confirm(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"confirm">>), Params).

-spec capture(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
capture(Client, Id) ->
    capture(Client, Id, []).

-spec capture(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
capture(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"capture">>), Params).

-spec cancel(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
cancel(Client, Id) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"cancel">>), []).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.

action(Id, Action) ->
    <<?BASE/binary, "/", Id/binary, "/", Action/binary>>.
