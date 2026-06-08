-module(livery_stripe_webhook_tests).
-include_lib("eunit/include/eunit.hrl").

-define(SECRET, <<"whsec_test_secret">>).
-define(TS, 1700000000).

sign(Payload, Ts, Secret) ->
    Signed = <<(integer_to_binary(Ts))/binary, ".", Payload/binary>>,
    Sig = livery_stripe_util:lower_hex(crypto:mac(hmac, sha256, Secret, Signed)),
    <<"t=", (integer_to_binary(Ts))/binary, ",v1=", Sig/binary>>.

valid_event_test() ->
    Payload = <<"{\"id\":\"evt_1\",\"type\":\"checkout.session.completed\"}">>,
    Header = sign(Payload, ?TS, ?SECRET),
    ?assertEqual(
        {ok, #{<<"id">> => <<"evt_1">>, <<"type">> => <<"checkout.session.completed">>}},
        livery_stripe_webhook:construct_event(Payload, Header, ?SECRET, #{now => ?TS})
    ).

extra_scheme_in_header_test() ->
    %% Real Stripe headers also carry a v0; we must ignore it and match v1.
    Payload = <<"{\"a\":1}">>,
    Base = sign(Payload, ?TS, ?SECRET),
    Header = <<Base/binary, ",v0=deadbeef">>,
    ?assertMatch(
        {ok, _}, livery_stripe_webhook:construct_event(Payload, Header, ?SECRET, #{now => ?TS})
    ).

tampered_body_test() ->
    Header = sign(<<"{\"a\":1}">>, ?TS, ?SECRET),
    ?assertEqual(
        {error, invalid_signature},
        livery_stripe_webhook:construct_event(<<"{\"a\":2}">>, Header, ?SECRET, #{now => ?TS})
    ).

wrong_secret_test() ->
    Payload = <<"{\"a\":1}">>,
    Header = sign(Payload, ?TS, ?SECRET),
    ?assertEqual(
        {error, invalid_signature},
        livery_stripe_webhook:construct_event(Payload, Header, <<"whsec_other">>, #{now => ?TS})
    ).

timestamp_out_of_tolerance_test() ->
    Payload = <<"{\"a\":1}">>,
    Header = sign(Payload, ?TS, ?SECRET),
    ?assertEqual(
        {error, timestamp_out_of_tolerance},
        livery_stripe_webhook:construct_event(Payload, Header, ?SECRET, #{now => ?TS + 1000})
    ).

tolerance_disabled_test() ->
    Payload = <<"{\"a\":1}">>,
    Header = sign(Payload, ?TS, ?SECRET),
    ?assertMatch(
        {ok, _},
        livery_stripe_webhook:construct_event(Payload, Header, ?SECRET, #{
            now => ?TS + 1000, tolerance => 0
        })
    ).

malformed_header_test() ->
    ?assertEqual(
        {error, invalid_signature},
        livery_stripe_webhook:construct_event(<<"{}">>, <<"garbage">>, ?SECRET, #{})
    ).

missing_header_test() ->
    ?assertEqual(
        {error, invalid_signature},
        livery_stripe_webhook:construct_event(<<"{}">>, undefined, ?SECRET, #{})
    ).

invalid_payload_but_valid_signature_test() ->
    Payload = <<"not json">>,
    Header = sign(Payload, ?TS, ?SECRET),
    ?assertEqual(
        {error, invalid_payload},
        livery_stripe_webhook:construct_event(Payload, Header, ?SECRET, #{now => ?TS})
    ).
