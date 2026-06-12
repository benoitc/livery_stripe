-module(livery_stripe_mandate).
-moduledoc "Stripe Mandates API (the customer authorization behind a SEPA/debit payment).".

-export([retrieve/2]).

-define(BASE, <<"/mandates">>).

%% Stripe exposes no list/create/update for mandates; they are created
%% implicitly when a SetupIntent or PaymentIntent is confirmed.
-spec retrieve(livery_client:client(), binary()) -> {ok, map()} | {error, term()}.
retrieve(Client, Id) ->
    livery_stripe_client:do_request(Client, get, path(Id), none).

path(Id) ->
    <<?BASE/binary, "/", Id/binary>>.
