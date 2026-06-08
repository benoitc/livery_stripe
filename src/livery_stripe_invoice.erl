-module(livery_stripe_invoice).
-moduledoc "Stripe Invoices API.".

-export([
    create/2,
    create/3,
    retrieve/2,
    list/1,
    list/2,
    pay/2,
    pay/3,
    finalize/2,
    void/2,
    send/2,
    mark_uncollectible/2,
    delete/2,
    upcoming/2
]).

-define(BASE, <<"/invoices">>).

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
    livery_stripe_client:do_request(Client, post, action(Id, <<"pay">>), Params).

-doc "Finalize a draft invoice so it is ready to pay.".
-spec finalize(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
finalize(Client, Id) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"finalize">>), []).

-spec void(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
void(Client, Id) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"void">>), []).

-doc "Send an invoice to the customer (out-of-band collection).".
-spec send(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
send(Client, Id) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"send">>), []).

-spec mark_uncollectible(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
mark_uncollectible(Client, Id) ->
    livery_stripe_client:do_request(Client, post, action(Id, <<"mark_uncollectible">>), []).

-doc "Delete a draft invoice (only drafts can be deleted).".
-spec delete(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
delete(Client, Id) ->
    livery_stripe_client:do_request(Client, delete, path(Id), none).

-doc "Preview the upcoming invoice for a customer or subscription.".
-spec upcoming(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
upcoming(Client, Params) ->
    livery_stripe_client:do_request(Client, get, <<?BASE/binary, "/upcoming">>, Params).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.

action(Id, Action) ->
    <<?BASE/binary, "/", Id/binary, "/", Action/binary>>.
