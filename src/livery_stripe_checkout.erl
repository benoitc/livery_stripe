-module(livery_stripe_checkout).
-moduledoc """
Stripe Checkout Sessions API.

`subscription_session/2` is the friendpaste flow: a hosted subscription
checkout for a single price, with success/cancel URLs and metadata.
""".

-export([create_session/2, retrieve_session/2, expire_session/2, subscription_session/2]).

-define(BASE, <<"/checkout/sessions">>).

-spec create_session(livery_client:client(), map() | list()) -> {ok, map()} | {error, term()}.
create_session(Client, Params) ->
    livery_stripe_client:do_request(Client, post, ?BASE, Params).

-spec retrieve_session(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
retrieve_session(Client, Id) ->
    livery_stripe_client:do_request(Client, get, sid(Id), none).

-spec expire_session(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
expire_session(Client, Id) ->
    livery_stripe_client:do_request(Client, post, <<(sid(Id))/binary, "/expire">>, []).

-doc """
Create a subscription-mode checkout session for a single price, mirroring
friendpaste's billing flow.

`Params` requires `customer`, `price`, `success_url`, `cancel_url`, and
accepts optional `quantity` (default 1) and `metadata`.
""".
-spec subscription_session(livery_client:client(), map()) -> {ok, map()} | {error, term()}.
subscription_session(Client, Params) ->
    #{
        customer := Customer,
        price := Price,
        success_url := SuccessUrl,
        cancel_url := CancelUrl
    } = Params,
    LineItem = #{<<"price">> => Price, <<"quantity">> => maps:get(quantity, Params, 1)},
    Body =
        [
            {<<"mode">>, <<"subscription">>},
            {<<"customer">>, Customer},
            {<<"line_items">>, [LineItem]},
            {<<"success_url">>, SuccessUrl},
            {<<"cancel_url">>, CancelUrl}
        ] ++ metadata(maps:get(metadata, Params, #{})),
    create_session(Client, Body).

metadata(M) when is_map(M), map_size(M) =:= 0 -> [];
metadata(M) -> [{<<"metadata">>, M}].

sid(Id) ->
    <<?BASE/binary, "/", Id/binary>>.
