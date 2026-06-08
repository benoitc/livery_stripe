-module(livery_stripe_webhook_e2e_SUITE).
-moduledoc """
End-to-end webhook test: a real livery HTTP service mounting
`livery_stripe_webhook_handler:routes/1`, driven by real signed HTTP
POSTs over the loopback. Exercises the full wire path (routing, streamed
body read, signature verification, dispatch, JSON response) that the
in-memory handler tests do not.
""".
-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").

-define(SECRET, <<"whsec_e2e_test">>).
-define(PAYLOAD,
    <<"{\"id\":\"evt_1\",\"type\":\"checkout.session.completed\",\"data\":{\"object\":{}}}">>
).

all() ->
    [
        valid_event_dispatches,
        bad_signature_returns_400,
        missing_signature_returns_400
    ].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(livery_stripe),
    %% The mounted handle/1 reads webhook_secret and webhook_callback from
    %% livery_stripe:config/0; the callback notifies the per-testcase target.
    application:set_env(livery_stripe, webhook_secret, ?SECRET),
    application:set_env(livery_stripe, webhook_callback, {?MODULE, on_event}),

    {ok, Server} = livery:start_service(#{
        http => #{port => 0},
        router => livery_router:compile(
            livery_stripe_webhook_handler:routes(<<"/stripe/webhook">>)
        )
    }),
    %% start_service links to this short-lived init process; unlink so the
    %% service survives for the cases (end_per_suite stops it explicitly).
    true = unlink(Server),
    Port = maps:get(h1, livery:which_listeners(Server)),

    %% Sign with the effective secret so a STRIPE_WEBHOOK_SECRET in the
    %% environment (which config/0 prefers) cannot break the test.
    Secret = maps:get(webhook_secret, livery_stripe:config()),
    [{server, Server}, {port, Port}, {secret, Secret} | Config].

end_per_suite(Config) ->
    _ = livery:stop_service(?config(server, Config)),
    application:unset_env(livery_stripe, webhook_secret),
    application:unset_env(livery_stripe, webhook_callback),
    application:unset_env(livery_stripe, test_target),
    ok.

init_per_testcase(_Case, Config) ->
    application:set_env(livery_stripe, test_target, self()),
    Config.

%%====================================================================
%% Callback under test (notifies the test process via app env target)
%%====================================================================

on_event(Type, _Event) ->
    case application:get_env(livery_stripe, test_target) of
        {ok, Pid} -> Pid ! {webhook, Type};
        _ -> ok
    end,
    ok.

%%====================================================================
%% Tests
%%====================================================================

valid_event_dispatches(Config) ->
    Header = sign(?PAYLOAD, ?config(secret, Config)),
    {ok, 200, _} = post(Config, Header, ?PAYLOAD),
    receive
        {webhook, <<"checkout.session.completed">>} -> ok
    after 2000 ->
        ct:fail(no_dispatch)
    end.

bad_signature_returns_400(Config) ->
    Header = sign(?PAYLOAD, <<"whsec_wrong">>),
    {ok, 400, _} = post(Config, Header, ?PAYLOAD),
    receive
        {webhook, _} -> ct:fail(unexpected_dispatch)
    after 200 ->
        ok
    end.

missing_signature_returns_400(Config) ->
    {ok, 400, _} = post_raw(Config, [{<<"content-type">>, <<"application/json">>}], ?PAYLOAD),
    ok.

%%====================================================================
%% Helpers
%%====================================================================

sign(Payload, Secret) ->
    Ts = integer_to_binary(os:system_time(second)),
    Sig = livery_stripe_util:lower_hex(
        crypto:mac(hmac, sha256, Secret, <<Ts/binary, ".", Payload/binary>>)
    ),
    <<"t=", Ts/binary, ",v1=", Sig/binary>>.

post(Config, SigHeader, Body) ->
    Headers = [
        {<<"stripe-signature">>, SigHeader},
        {<<"content-type">>, <<"application/json">>}
    ],
    post_raw(Config, Headers, Body).

post_raw(Config, Headers, Body) ->
    Port = ?config(port, Config),
    Url = iolist_to_binary(["http://127.0.0.1:", integer_to_binary(Port), "/stripe/webhook"]),
    {ok, Status, RespHeaders, _RespBody} =
        hackney:request(post, Url, Headers, Body, [with_body]),
    {ok, Status, RespHeaders}.
