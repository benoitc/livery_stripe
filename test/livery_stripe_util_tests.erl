-module(livery_stripe_util_tests).
-include_lib("eunit/include/eunit.hrl").

lower_hex_test() ->
    ?assertEqual(<<"ff0010">>, livery_stripe_util:lower_hex(<<255, 0, 16>>)),
    ?assertEqual(<<>>, livery_stripe_util:lower_hex(<<>>)).

to_bin_test() ->
    ?assertEqual(<<"a">>, livery_stripe_util:to_bin(<<"a">>)),
    ?assertEqual(<<"123">>, livery_stripe_util:to_bin(123)),
    ?assertEqual(<<"abc">>, livery_stripe_util:to_bin(abc)),
    ?assertEqual(<<"ab">>, livery_stripe_util:to_bin([<<"a">>, <<"b">>])).
