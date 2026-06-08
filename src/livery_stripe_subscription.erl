-module(livery_stripe_subscription).
-moduledoc "Stripe Subscriptions API.".

-export([retrieve/2, update/3, cancel/2, cancel/3, list/1, list/2, pause/2, resume/2]).

-define(BASE, <<"/subscriptions">>).

-spec retrieve(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
retrieve(Client, Id) ->
    livery_stripe_client:do_request(Client, get, path(Id), none).

-spec update(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
update(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, post, path(Id), Params).

-doc "Cancel a subscription immediately (Stripe `DELETE`).".
-spec cancel(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
cancel(Client, Id) ->
    livery_stripe_client:do_request(Client, delete, path(Id), none).

-spec cancel(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
cancel(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, delete, path(Id), Params).

-spec list(livery_client:client()) -> {ok, map()} | {error, term()}.
list(Client) ->
    list(Client, #{}).

-spec list(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
list(Client, Params) ->
    livery_stripe_client:do_request(Client, get, ?BASE, Params).

-doc "Pause collection on a subscription (voids invoices while paused).".
-spec pause(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
pause(Client, Id) ->
    update(Client, Id, [{<<"pause_collection">>, #{<<"behavior">> => <<"void">>}}]).

-doc "Resume a paused subscription by clearing `pause_collection`.".
-spec resume(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
resume(Client, Id) ->
    update(Client, Id, [{<<"pause_collection">>, <<"">>}]).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.
