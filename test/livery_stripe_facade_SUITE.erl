-module(livery_stripe_facade_SUITE).
-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").

all() ->
    [
        price_id_maps_plan_and_period,
        price_id_unknown_is_error,
        subscription_checkout_resolves_price_and_posts,
        subscription_checkout_unconfigured_plan_errors,
        convenience_functions_hit_endpoints,
        config_env_overrides_app_env
    ].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(crypto),
    application:load(livery_stripe),
    application:set_env(livery_stripe, prices, #{
        pro_monthly => <<"price_pm">>,
        pro_yearly => <<"price_py">>
    }),
    %% Point the cached client at the mock adapter (no network).
    livery_stripe:set_client(mock_client()),
    Config.

end_per_suite(_Config) ->
    livery_stripe_ct_adapter:reset(),
    application:unset_env(livery_stripe, prices),
    ok.

mock_client() ->
    livery_client:new(#{
        base_url => <<"http://mock">>,
        adapter => livery_stripe_ct_adapter,
        headers => [{<<"content-type">>, <<"application/x-www-form-urlencoded">>}],
        stack => []
    }).

price_id_maps_plan_and_period(_Config) ->
    {ok, <<"price_pm">>} = livery_stripe:price_id(pro, monthly),
    {ok, <<"price_py">>} = livery_stripe:price_id(<<"pro">>, <<"yearly">>),
    ok.

price_id_unknown_is_error(_Config) ->
    {error, {price_not_configured, max_monthly}} = livery_stripe:price_id(max, monthly),
    ok.

subscription_checkout_resolves_price_and_posts(_Config) ->
    ok = livery_stripe_ct_adapter:setup([
        {ok, #{
            status => 200,
            headers => [],
            body => {full, <<"{\"id\":\"cs_1\",\"url\":\"https://checkout/x\"}">>}
        }}
    ]),
    {ok, #{<<"url">> := <<"https://checkout/x">>}} =
        livery_stripe:subscription_checkout(#{
            customer => <<"cus_1">>,
            plan => pro,
            billing_period => monthly,
            success_url => <<"https://x/ok">>,
            cancel_url => <<"https://x/no">>,
            metadata => #{<<"user_id">> => <<"u1">>}
        }),
    [Req] = livery_stripe_ct_adapter:requests(),
    assert_contains(livery_client:url(Req), <<"/checkout/sessions">>),
    {full, Body} = maps:get(body, Req),
    assert_contains(Body, <<"mode=subscription">>),
    assert_contains(Body, <<"line_items%5B0%5D%5Bprice%5D=price_pm">>),
    assert_contains(Body, <<"metadata%5Buser_id%5D=u1">>),
    ok.

subscription_checkout_unconfigured_plan_errors(_Config) ->
    ok = livery_stripe_ct_adapter:setup([]),
    {error, {price_not_configured, max_yearly}} =
        livery_stripe:subscription_checkout(#{
            customer => <<"cus_1">>,
            plan => max,
            billing_period => yearly,
            success_url => <<"https://x/ok">>,
            cancel_url => <<"https://x/no">>
        }),
    0 = length(livery_stripe_ct_adapter:requests()),
    ok.

convenience_functions_hit_endpoints(_Config) ->
    %% The cached client is the mock (set in init_per_suite).
    Cases = [
        {
            fun() -> livery_stripe:create_customer(#{email => <<"a@b.c">>}) end,
            post,
            <<"/customers">>
        },
        {fun() -> livery_stripe:get_customer(<<"cus_1">>) end, get, <<"/customers/cus_1">>},
        {
            fun() -> livery_stripe:update_customer(<<"cus_1">>, #{name => <<"X">>}) end,
            post,
            <<"/customers/cus_1">>
        },
        {
            fun() -> livery_stripe:create_checkout_session(#{mode => <<"payment">>}) end,
            post,
            <<"/checkout/sessions">>
        },
        {
            fun() -> livery_stripe:create_portal_session(#{customer => <<"cus_1">>}) end,
            post,
            <<"/billing_portal/sessions">>
        },
        {fun() -> livery_stripe:get_subscription(<<"sub_1">>) end, get, <<"/subscriptions/sub_1">>},
        {
            fun() -> livery_stripe:update_subscription(<<"sub_1">>, #{}) end,
            post,
            <<"/subscriptions/sub_1">>
        },
        {
            fun() -> livery_stripe:cancel_subscription(<<"sub_1">>) end,
            delete,
            <<"/subscriptions/sub_1">>
        }
    ],
    lists:foreach(fun run_case/1, Cases),
    ok.

run_case({Fun, ExpectedMethod, UrlNeedle}) ->
    ok = livery_stripe_ct_adapter:setup([
        {ok, #{status => 200, headers => [], body => {full, <<"{}">>}}}
    ]),
    {ok, _} = Fun(),
    [Req] = livery_stripe_ct_adapter:requests(),
    ExpectedMethod = livery_client:method(Req),
    assert_contains(livery_client:url(Req), UrlNeedle).

config_env_overrides_app_env(_Config) ->
    application:set_env(livery_stripe, secret_key, <<"sk_from_app_env">>),
    try
        true = os:putenv("STRIPE_SECRET_KEY", "sk_from_os_env"),
        #{secret_key := <<"sk_from_os_env">>} = livery_stripe:config()
    after
        os:unsetenv("STRIPE_SECRET_KEY"),
        application:unset_env(livery_stripe, secret_key)
    end,
    %% Without the OS var, the app env value stands.
    application:set_env(livery_stripe, secret_key, <<"sk_only_app">>),
    try
        #{secret_key := <<"sk_only_app">>} = livery_stripe:config()
    after
        application:unset_env(livery_stripe, secret_key)
    end,
    ok.

assert_contains(Haystack, Needle) ->
    {_, _} = binary:match(Haystack, Needle).
