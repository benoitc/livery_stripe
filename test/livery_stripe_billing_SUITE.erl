-module(livery_stripe_billing_SUITE).
-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").

-define(SECRET, <<"whsec_test">>).

all() ->
    [full_flow, webhook_dispatch].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(livery_stripe),
    %% Port 0 lets the OS assign a free port, avoiding collisions.
    {ok, Server} = livery_stripe_mock_server:start(0),
    %% start_service/1 uses start_link, which links the gen_server to this
    %% (short-lived) init_per_suite process. Unlink so the mock survives for
    %% the test cases; end_per_suite stops it explicitly.
    true = unlink(Server),
    Port = livery_stripe_mock_server:port(Server),
    Base = iolist_to_binary(["http://127.0.0.1:", integer_to_binary(Port), "/v1"]),
    Client = livery_client:new(#{
        base_url => Base,
        headers => [{<<"content-type">>, <<"application/x-www-form-urlencoded">>}],
        stack => [livery_client:retry(#{max => 2, backoff => {10, 1.0}})]
    }),
    [{server, Server}, {client, Client} | Config].

end_per_suite(Config) ->
    _ = livery_stripe_mock_server:stop(?config(server, Config)),
    ok.

full_flow(Config) ->
    Client = ?config(client, Config),

    {ok, #{<<"id">> := <<"cus_mock">>}} =
        livery_stripe_customer:create(Client, #{
            email => <<"a@b.c">>,
            name => <<"A B">>,
            metadata => #{<<"user_id">> => <<"u1">>}
        }),

    {ok, #{<<"url">> := CheckoutUrl}} =
        livery_stripe_checkout:subscription_session(Client, #{
            customer => <<"cus_mock">>,
            price => <<"price_1">>,
            success_url => <<"https://x/billing?success=1">>,
            cancel_url => <<"https://x/billing?canceled=1">>,
            metadata => #{<<"user_id">> => <<"u1">>, <<"plan">> => <<"pro">>}
        }),
    true = is_binary(CheckoutUrl),

    {ok, #{<<"status">> := <<"active">>}} =
        livery_stripe_subscription:retrieve(Client, <<"sub_123">>),

    {ok, #{<<"url">> := PortalUrl}} =
        livery_stripe_portal:create_session(Client, #{
            customer => <<"cus_mock">>,
            return_url => <<"https://x/billing">>
        }),
    true = is_binary(PortalUrl),
    ok.

webhook_dispatch(_Config) ->
    Self = self(),
    Callback = fun(Type, Event) ->
        Self ! {webhook, Type, Event},
        ok
    end,
    Payload =
        <<"{\"id\":\"evt_1\",\"type\":\"checkout.session.completed\",\"data\":{\"object\":{}}}">>,
    Ts = os:system_time(second),
    Signed = <<(integer_to_binary(Ts))/binary, ".", Payload/binary>>,
    Sig = livery_stripe_util:lower_hex(crypto:mac(hmac, sha256, ?SECRET, Signed)),
    Header = <<"t=", (integer_to_binary(Ts))/binary, ",v1=", Sig/binary>>,
    Req = livery_req:new(#{
        method => <<"POST">>,
        path => <<"/stripe/webhook">>,
        headers => [{<<"stripe-signature">>, Header}],
        body => {buffered, Payload}
    }),
    Resp = livery_stripe_webhook_handler:handle(Req, #{secret => ?SECRET, callback => Callback}),
    200 = livery_resp:status(Resp),
    receive
        {webhook, <<"checkout.session.completed">>, _Event} -> ok
    after 1000 ->
        ct:fail(webhook_not_dispatched)
    end.
