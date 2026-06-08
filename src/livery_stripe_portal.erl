-module(livery_stripe_portal).
-moduledoc "Stripe Billing Portal (Customer Portal) sessions.".

-export([create_session/2]).

-doc """
Create a billing portal session. `Params` requires `customer` and accepts
an optional `return_url`.
""".
-spec create_session(livery_client:client(), map()) -> {ok, map()} | {error, term()}.
create_session(Client, #{customer := Customer} = Params) ->
    Body = [{<<"customer">>, Customer}] ++ return_url(maps:get(return_url, Params, undefined)),
    livery_stripe_client:do_request(Client, post, <<"/billing_portal/sessions">>, Body).

return_url(undefined) -> [];
return_url(Url) -> [{<<"return_url">>, Url}].
