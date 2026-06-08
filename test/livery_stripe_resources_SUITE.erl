-module(livery_stripe_resources_SUITE).
-moduledoc "Drives every domain wrapper through the mock adapter and asserts method + path.".
-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").

all() ->
    [endpoint_shapes].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(crypto),
    Config.

end_per_suite(_Config) ->
    livery_stripe_ct_adapter:reset(),
    ok.

client() ->
    livery_client:new(#{
        base_url => <<"https://api.stripe.com/v1">>,
        adapter => livery_stripe_ct_adapter,
        headers => [{<<"content-type">>, <<"application/x-www-form-urlencoded">>}],
        stack => []
    }).

%% {Label, fun(Client) -> _, ExpectedMethod, UrlNeedle}
table() ->
    C = client(),
    P = #{name => <<"x">>},
    [
        %% customers
        {customer_create, fun() -> livery_stripe_customer:create(C, P) end, post, <<"/customers">>},
        {customer_retrieve, fun() -> livery_stripe_customer:retrieve(C, <<"cus_1">>) end, get,
            <<"/customers/cus_1">>},
        {customer_update, fun() -> livery_stripe_customer:update(C, <<"cus_1">>, P) end, post,
            <<"/customers/cus_1">>},
        {customer_delete, fun() -> livery_stripe_customer:delete(C, <<"cus_1">>) end, delete,
            <<"/customers/cus_1">>},
        {customer_list, fun() -> livery_stripe_customer:list(C) end, get, <<"/customers">>},

        %% checkout
        {checkout_create, fun() -> livery_stripe_checkout:create_session(C, P) end, post,
            <<"/checkout/sessions">>},
        {checkout_retrieve, fun() -> livery_stripe_checkout:retrieve_session(C, <<"cs_1">>) end,
            get, <<"/checkout/sessions/cs_1">>},
        {checkout_expire, fun() -> livery_stripe_checkout:expire_session(C, <<"cs_1">>) end, post,
            <<"/checkout/sessions/cs_1/expire">>},
        {checkout_subscription,
            fun() ->
                livery_stripe_checkout:subscription_session(C, #{
                    customer => <<"cus_1">>,
                    price => <<"price_1">>,
                    success_url => <<"https://x/ok">>,
                    cancel_url => <<"https://x/no">>
                })
            end,
            post, <<"/checkout/sessions">>},

        %% billing portal
        {portal_create,
            fun() -> livery_stripe_portal:create_session(C, #{customer => <<"cus_1">>}) end, post,
            <<"/billing_portal/sessions">>},

        %% subscriptions
        {sub_retrieve, fun() -> livery_stripe_subscription:retrieve(C, <<"sub_1">>) end, get,
            <<"/subscriptions/sub_1">>},
        {sub_update, fun() -> livery_stripe_subscription:update(C, <<"sub_1">>, P) end, post,
            <<"/subscriptions/sub_1">>},
        {sub_cancel, fun() -> livery_stripe_subscription:cancel(C, <<"sub_1">>) end, delete,
            <<"/subscriptions/sub_1">>},
        {sub_cancel_params,
            fun() -> livery_stripe_subscription:cancel(C, <<"sub_1">>, #{invoice_now => true}) end,
            delete, <<"/subscriptions/sub_1">>},
        {sub_list, fun() -> livery_stripe_subscription:list(C) end, get, <<"/subscriptions">>},
        {sub_pause, fun() -> livery_stripe_subscription:pause(C, <<"sub_1">>) end, post,
            <<"/subscriptions/sub_1">>},
        {sub_resume, fun() -> livery_stripe_subscription:resume(C, <<"sub_1">>) end, post,
            <<"/subscriptions/sub_1">>},

        %% prices
        {price_create, fun() -> livery_stripe_price:create(C, P) end, post, <<"/prices">>},
        {price_retrieve, fun() -> livery_stripe_price:retrieve(C, <<"price_1">>) end, get,
            <<"/prices/price_1">>},
        {price_update, fun() -> livery_stripe_price:update(C, <<"price_1">>, P) end, post,
            <<"/prices/price_1">>},
        {price_list, fun() -> livery_stripe_price:list(C) end, get, <<"/prices">>},

        %% products
        {product_create, fun() -> livery_stripe_product:create(C, P) end, post, <<"/products">>},
        {product_retrieve, fun() -> livery_stripe_product:retrieve(C, <<"prod_1">>) end, get,
            <<"/products/prod_1">>},
        {product_update, fun() -> livery_stripe_product:update(C, <<"prod_1">>, P) end, post,
            <<"/products/prod_1">>},
        {product_list, fun() -> livery_stripe_product:list(C) end, get, <<"/products">>},

        %% payment intents
        {pi_create, fun() -> livery_stripe_payment_intent:create(C, P) end, post,
            <<"/payment_intents">>},
        {pi_retrieve, fun() -> livery_stripe_payment_intent:retrieve(C, <<"pi_1">>) end, get,
            <<"/payment_intents/pi_1">>},
        {pi_confirm, fun() -> livery_stripe_payment_intent:confirm(C, <<"pi_1">>) end, post,
            <<"/payment_intents/pi_1/confirm">>},
        {pi_capture, fun() -> livery_stripe_payment_intent:capture(C, <<"pi_1">>) end, post,
            <<"/payment_intents/pi_1/capture">>},
        {pi_cancel, fun() -> livery_stripe_payment_intent:cancel(C, <<"pi_1">>) end, post,
            <<"/payment_intents/pi_1/cancel">>},

        %% invoices
        {invoice_retrieve, fun() -> livery_stripe_invoice:retrieve(C, <<"in_1">>) end, get,
            <<"/invoices/in_1">>},
        {invoice_list, fun() -> livery_stripe_invoice:list(C) end, get, <<"/invoices">>},
        {invoice_pay, fun() -> livery_stripe_invoice:pay(C, <<"in_1">>) end, post,
            <<"/invoices/in_1/pay">>}
    ].

endpoint_shapes(_Config) ->
    lists:foreach(fun check/1, table()).

check({Label, Fun, ExpectedMethod, UrlNeedle}) ->
    ok = livery_stripe_ct_adapter:setup([
        {ok, #{status => 200, headers => [], body => {full, <<"{}">>}}}
    ]),
    {ok, _} = Fun(),
    [Req] = livery_stripe_ct_adapter:requests(),
    Method = livery_client:method(Req),
    Url = livery_client:url(Req),
    case Method =:= ExpectedMethod andalso binary:match(Url, UrlNeedle) =/= nomatch of
        true ->
            ok;
        false ->
            ct:fail({Label, {expected, ExpectedMethod, UrlNeedle}, {got, Method, Url}})
    end.
