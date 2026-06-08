-module(livery_stripe_customer).
-moduledoc "Stripe Customers API.".

-export([
    create/2,
    create/3,
    retrieve/2,
    update/3,
    update/4,
    delete/2,
    list/1,
    list/2,
    list_payment_methods/2,
    list_payment_methods/3
]).

-define(BASE, <<"/customers">>).

-spec create(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
create(Client, Params) ->
    create(Client, Params, #{}).

-doc """
Like `create/2` with request options: `idempotency_key`, `stripe_account`,
`timeout`, and extra `headers`. (Every POST gets an auto-generated
idempotency key when none is supplied.)
""".
-spec create(livery_client:client(), map() | list(), map()) -> {ok, map()} | {error, term()}.
create(Client, Params, Opts) ->
    livery_stripe_client:do_request(Client, post, ?BASE, Params, Opts).

-spec retrieve(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
retrieve(Client, Id) ->
    livery_stripe_client:do_request(Client, get, path(Id), none).

-spec update(livery_client:client(), binary(), map() | list()) -> {ok, map()} | {error, term()}.
update(Client, Id, Params) ->
    update(Client, Id, Params, #{}).

-spec update(livery_client:client(), binary(), map() | list(), map()) ->
    {ok, map()} | {error, term()}.
update(Client, Id, Params, Opts) ->
    livery_stripe_client:do_request(Client, post, path(Id), Params, Opts).

-spec delete(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
delete(Client, Id) ->
    livery_stripe_client:do_request(Client, delete, path(Id), none).

-spec list(livery_client:client()) -> {ok, map()} | {error, term()}.
list(Client) ->
    list(Client, #{}).

-spec list(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
list(Client, Params) ->
    livery_stripe_client:do_request(Client, get, ?BASE, Params).

-spec list_payment_methods(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
list_payment_methods(Client, Id) ->
    list_payment_methods(Client, Id, #{}).

-doc "List a customer's payment methods; Params may carry `type`.".
-spec list_payment_methods(livery_client:client(), binary(), map() | list()) ->
    {ok, map()} | {error, term()}.
list_payment_methods(Client, Id, Params) ->
    livery_stripe_client:do_request(Client, get, payment_methods_path(Id), Params).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.

payment_methods_path(Id) ->
    <<?BASE/binary, "/", Id/binary, "/payment_methods">>.
