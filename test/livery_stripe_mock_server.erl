-module(livery_stripe_mock_server).
-moduledoc "A tiny livery service emulating the few Stripe endpoints the billing suite uses.".

-export([start/1, stop/1, port/1, router/0]).
-export([customers/1, checkout/1, subscription/1, portal/1]).

start(Port) ->
    livery:start_service(#{http => #{port => Port}, router => router()}).

stop(Pid) ->
    livery:stop_service(Pid).

%% The actual bound port (useful when started with port 0).
port(Pid) ->
    maps:get(h1, livery:which_listeners(Pid)).

router() ->
    livery_router:compile([
        {<<"POST">>, <<"/v1/customers">>, {?MODULE, customers}},
        {<<"POST">>, <<"/v1/checkout/sessions">>, {?MODULE, checkout}},
        {<<"GET">>, <<"/v1/subscriptions/:id">>, {?MODULE, subscription}},
        {<<"POST">>, <<"/v1/billing_portal/sessions">>, {?MODULE, portal}}
    ]).

customers(_Req) ->
    livery_resp:json(200, <<"{\"id\":\"cus_mock\",\"object\":\"customer\"}">>).

checkout(_Req) ->
    livery_resp:json(
        200,
        <<"{\"id\":\"cs_mock\",\"url\":\"https://checkout.stripe.com/c/pay/cs_mock\"}">>
    ).

subscription(Req) ->
    Id = livery_req:binding(<<"id">>, Req),
    Body = json:encode(#{
        <<"id">> => Id,
        <<"status">> => <<"active">>,
        <<"current_period_end">> => 1700000000,
        <<"items">> => #{
            <<"data">> => [
                #{<<"price">> => #{<<"recurring">> => #{<<"interval">> => <<"month">>}}}
            ]
        }
    }),
    livery_resp:json(200, Body).

portal(_Req) ->
    livery_resp:json(
        200,
        <<"{\"id\":\"bps_mock\",\"url\":\"https://billing.stripe.com/p/session/bps_mock\"}">>
    ).
