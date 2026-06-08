-module(livery_stripe_form_tests).
-include_lib("eunit/include/eunit.hrl").

simple_test() ->
    ?assertEqual(<<"a=b">>, livery_stripe_form:encode([{<<"a">>, <<"b">>}])).

order_preserved_test() ->
    ?assertEqual(
        <<"amount=1000&active=true&plan=pro">>,
        livery_stripe_form:encode([
            {<<"amount">>, 1000},
            {<<"active">>, true},
            {<<"plan">>, pro}
        ])
    ).

escaping_test() ->
    %% space -> '+', '@' -> %40, '.' kept
    ?assertEqual(
        <<"email=a+b%40c.com">>,
        livery_stripe_form:encode([{<<"email">>, <<"a b@c.com">>}])
    ).

url_value_escaping_test() ->
    ?assertEqual(
        <<"success_url=https%3A%2F%2Fx%2Fbilling%3Fsuccess%3D1">>,
        livery_stripe_form:encode([{<<"success_url">>, <<"https://x/billing?success=1">>}])
    ).

nested_map_sorted_keys_test() ->
    ?assertEqual(
        <<"metadata%5Bplan%5D=pro&metadata%5Buser_id%5D=u1">>,
        livery_stripe_form:encode([
            {<<"metadata">>, #{<<"user_id">> => <<"u1">>, <<"plan">> => <<"pro">>}}
        ])
    ).

scalar_array_test() ->
    ?assertEqual(
        <<"expand%5B%5D=customer&expand%5B%5D=subscription">>,
        livery_stripe_form:encode([{<<"expand">>, [<<"customer">>, <<"subscription">>]}])
    ).

line_items_array_of_maps_test() ->
    ?assertEqual(
        <<"line_items%5B0%5D%5Bprice%5D=price_1&line_items%5B0%5D%5Bquantity%5D=1">>,
        livery_stripe_form:encode([
            {<<"line_items">>, [#{<<"price">> => <<"price_1">>, <<"quantity">> => 1}]}
        ])
    ).

empty_collections_test() ->
    ?assertEqual(<<>>, livery_stripe_form:encode([])),
    ?assertEqual(<<"a=1">>, livery_stripe_form:encode([{<<"meta">>, #{}}, {<<"a">>, 1}])),
    ?assertEqual(<<"a=1">>, livery_stripe_form:encode([{<<"tags">>, []}, {<<"a">>, 1}])).

false_boolean_test() ->
    ?assertEqual(<<"flag=false">>, livery_stripe_form:encode([{<<"flag">>, false}])).

float_value_test() ->
    ?assertEqual(<<"rate=1.5">>, livery_stripe_form:encode([{<<"rate">>, 1.5}])).

string_key_test() ->
    ?assertEqual(<<"a=b">>, livery_stripe_form:encode([{"a", <<"b">>}])).

atom_and_integer_keys_test() ->
    ?assertEqual(<<"limit=10">>, livery_stripe_form:encode([{limit, 10}])),
    ?assertEqual(<<"meta%5B0%5D=x">>, livery_stripe_form:encode([{<<"meta">>, #{0 => <<"x">>}}])).

drops_undefined_top_level_test() ->
    ?assertEqual(
        <<"email=a%40b.c">>,
        livery_stripe_form:encode([{<<"email">>, <<"a@b.c">>}, {<<"name">>, undefined}])
    ).

drops_undefined_in_map_test() ->
    ?assertEqual(
        <<"metadata%5Bkept%5D=1">>,
        livery_stripe_form:encode([
            {<<"metadata">>, #{<<"kept">> => 1, <<"gone">> => undefined}}
        ])
    ).

drops_undefined_in_array_test() ->
    ?assertEqual(
        <<"tags%5B%5D=a&tags%5B%5D=b">>,
        livery_stripe_form:encode([{<<"tags">>, [<<"a">>, undefined, <<"b">>]}])
    ).

deep_nesting_test() ->
    %% subscription_data[items][0][price] style nesting (map -> map -> list -> map)
    Params = [
        {<<"subscription_data">>, #{
            <<"items">> => [#{<<"price">> => <<"price_1">>}]
        }}
    ],
    ?assertEqual(
        <<"subscription_data%5Bitems%5D%5B0%5D%5Bprice%5D=price_1">>,
        livery_stripe_form:encode(Params)
    ).

map_at_top_level_test() ->
    %% A top-level map is sorted for determinism.
    ?assertEqual(
        <<"a=1&b=2">>,
        livery_stripe_form:encode(#{<<"b">> => 2, <<"a">> => 1})
    ).

friendpaste_checkout_payload_test() ->
    Params = [
        {<<"mode">>, <<"subscription">>},
        {<<"customer">>, <<"cus_1">>},
        {<<"line_items">>, [#{<<"price">> => <<"price_1">>, <<"quantity">> => 1}]},
        {<<"success_url">>, <<"https://x/billing?success=1">>},
        {<<"cancel_url">>, <<"https://x/billing?canceled=1">>},
        {<<"metadata">>, #{<<"user_id">> => <<"u1">>, <<"plan">> => <<"pro">>}}
    ],
    Body = livery_stripe_form:encode(Params),
    assert_contains(Body, <<"mode=subscription">>),
    assert_contains(Body, <<"customer=cus_1">>),
    assert_contains(Body, <<"line_items%5B0%5D%5Bprice%5D=price_1">>),
    assert_contains(Body, <<"line_items%5B0%5D%5Bquantity%5D=1">>),
    assert_contains(Body, <<"metadata%5Bplan%5D=pro">>),
    assert_contains(Body, <<"metadata%5Buser_id%5D=u1">>).

assert_contains(Haystack, Needle) ->
    ?assertMatch({_, _}, binary:match(Haystack, Needle)).
