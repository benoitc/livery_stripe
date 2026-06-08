-module(livery_stripe_webhook_handler_SUITE).
-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").

-define(SECRET, <<"whsec_handler_test">>).
-define(PAYLOAD, <<"{\"id\":\"evt_1\",\"type\":\"checkout.session.completed\"}">>).

all() ->
    [
        dispatch_fun1,
        dispatch_fun2,
        dispatch_mfa,
        dispatch_module,
        no_callback_still_200,
        handle1_reads_config,
        bad_signature_returns_400,
        invalid_payload_returns_400,
        empty_body_returns_400
    ].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(crypto),
    application:load(livery_stripe),
    Config.

end_per_suite(_Config) ->
    application:unset_env(livery_stripe, test_target),
    application:unset_env(livery_stripe, webhook_secret),
    application:unset_env(livery_stripe, webhook_callback),
    ok.

init_per_testcase(_Case, Config) ->
    application:set_env(livery_stripe, test_target, self()),
    Config.

%%====================================================================
%% Callbacks under test (notify the test process via app env target)
%%====================================================================

handle_event(Type, _Event) -> notify({module, Type}).
mfa2(Type, _Event) -> notify({mfa, Type}).
cb2(Type, _Event) -> notify({fun2, Type}).
cb1(Event) -> notify({fun1, maps:get(<<"type">>, Event)}).

notify(Msg) ->
    case application:get_env(livery_stripe, test_target) of
        {ok, Pid} -> Pid ! Msg;
        _ -> ok
    end,
    ok.

%%====================================================================
%% Tests
%%====================================================================

dispatch_fun1(_Config) ->
    200 = call(#{secret => ?SECRET, callback => fun ?MODULE:cb1/1}),
    receive
        {fun1, <<"checkout.session.completed">>} -> ok
    after 1000 -> ct:fail(no_dispatch)
    end.

dispatch_fun2(_Config) ->
    200 = call(#{secret => ?SECRET, callback => fun ?MODULE:cb2/2}),
    receive
        {fun2, <<"checkout.session.completed">>} -> ok
    after 1000 -> ct:fail(no_dispatch)
    end.

dispatch_mfa(_Config) ->
    200 = call(#{secret => ?SECRET, callback => {?MODULE, mfa2}}),
    receive
        {mfa, <<"checkout.session.completed">>} -> ok
    after 1000 -> ct:fail(no_dispatch)
    end.

dispatch_module(_Config) ->
    200 = call(#{secret => ?SECRET, callback => ?MODULE}),
    receive
        {module, <<"checkout.session.completed">>} -> ok
    after 1000 -> ct:fail(no_dispatch)
    end.

no_callback_still_200(_Config) ->
    200 = call(#{secret => ?SECRET, callback => undefined}),
    receive
        Msg -> ct:fail({unexpected, Msg})
    after 200 -> ok
    end.

handle1_reads_config(_Config) ->
    application:set_env(livery_stripe, webhook_secret, ?SECRET),
    application:set_env(livery_stripe, webhook_callback, {?MODULE, mfa2}),
    Resp = livery_stripe_webhook_handler:handle(signed_req(?SECRET, ?PAYLOAD)),
    200 = livery_resp:status(Resp),
    receive
        {mfa, <<"checkout.session.completed">>} -> ok
    after 1000 -> ct:fail(no_dispatch)
    end.

bad_signature_returns_400(_Config) ->
    Req = signed_req(<<"whsec_wrong">>, ?PAYLOAD),
    Resp = livery_stripe_webhook_handler:handle(Req, #{secret => ?SECRET, callback => undefined}),
    400 = livery_resp:status(Resp).

invalid_payload_returns_400(_Config) ->
    %% Valid signature over a non-JSON body -> invalid_payload -> 400.
    Req = signed_req(?SECRET, <<"not json">>),
    Resp = livery_stripe_webhook_handler:handle(Req, #{secret => ?SECRET, callback => undefined}),
    400 = livery_resp:status(Resp).

empty_body_returns_400(_Config) ->
    %% Exercises the empty-body branch of read_body; no body -> signature fails.
    Req = livery_req:new(#{
        method => <<"POST">>,
        path => <<"/stripe/webhook">>,
        headers => [{<<"stripe-signature">>, <<"t=1,v1=deadbeef">>}],
        body => empty
    }),
    Resp = livery_stripe_webhook_handler:handle(Req, #{secret => ?SECRET, callback => undefined}),
    400 = livery_resp:status(Resp).

%%====================================================================
%% Helpers
%%====================================================================

call(Opts) ->
    Resp = livery_stripe_webhook_handler:handle(signed_req(?SECRET, ?PAYLOAD), Opts),
    livery_resp:status(Resp).

signed_req(Secret, Payload) ->
    Ts = integer_to_binary(os:system_time(second)),
    Sig = livery_stripe_util:lower_hex(
        crypto:mac(hmac, sha256, Secret, <<Ts/binary, ".", Payload/binary>>)
    ),
    livery_req:new(#{
        method => <<"POST">>,
        path => <<"/stripe/webhook">>,
        headers => [{<<"stripe-signature">>, <<"t=", Ts/binary, ",v1=", Sig/binary>>}],
        body => {buffered, Payload}
    }).
