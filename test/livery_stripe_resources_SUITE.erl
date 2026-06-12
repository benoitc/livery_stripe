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
            <<"/invoices/in_1/pay">>},

        %% subscription create
        {sub_create, fun() -> livery_stripe_subscription:create(C, P) end, post,
            <<"/subscriptions">>},

        %% payment methods
        {pm_attach,
            fun() ->
                livery_stripe_payment_method:attach(C, <<"pm_1">>, #{customer => <<"cus_1">>})
            end,
            post, <<"/payment_methods/pm_1/attach">>},
        {pm_detach, fun() -> livery_stripe_payment_method:detach(C, <<"pm_1">>) end, post,
            <<"/payment_methods/pm_1/detach">>},
        {pm_retrieve, fun() -> livery_stripe_payment_method:retrieve(C, <<"pm_1">>) end, get,
            <<"/payment_methods/pm_1">>},
        {pm_update, fun() -> livery_stripe_payment_method:update(C, <<"pm_1">>, P) end, post,
            <<"/payment_methods/pm_1">>},
        {pm_list,
            fun() ->
                livery_stripe_payment_method:list(C, #{
                    customer => <<"cus_1">>, type => <<"card">>
                })
            end,
            get, <<"/payment_methods">>},

        %% setup intents
        {si_create, fun() -> livery_stripe_setup_intent:create(C, P) end, post,
            <<"/setup_intents">>},
        {si_retrieve, fun() -> livery_stripe_setup_intent:retrieve(C, <<"seti_1">>) end, get,
            <<"/setup_intents/seti_1">>},
        {si_confirm, fun() -> livery_stripe_setup_intent:confirm(C, <<"seti_1">>) end, post,
            <<"/setup_intents/seti_1/confirm">>},
        {si_cancel, fun() -> livery_stripe_setup_intent:cancel(C, <<"seti_1">>) end, post,
            <<"/setup_intents/seti_1/cancel">>},
        {si_list, fun() -> livery_stripe_setup_intent:list(C) end, get, <<"/setup_intents">>},

        %% refunds
        {refund_create, fun() -> livery_stripe_refund:create(C, P) end, post, <<"/refunds">>},
        {refund_retrieve, fun() -> livery_stripe_refund:retrieve(C, <<"re_1">>) end, get,
            <<"/refunds/re_1">>},
        {refund_update, fun() -> livery_stripe_refund:update(C, <<"re_1">>, P) end, post,
            <<"/refunds/re_1">>},
        {refund_cancel, fun() -> livery_stripe_refund:cancel(C, <<"re_1">>) end, post,
            <<"/refunds/re_1/cancel">>},
        {refund_list, fun() -> livery_stripe_refund:list(C) end, get, <<"/refunds">>},

        %% invoice lifecycle
        {invoice_create, fun() -> livery_stripe_invoice:create(C, P) end, post, <<"/invoices">>},
        {invoice_finalize, fun() -> livery_stripe_invoice:finalize(C, <<"in_1">>) end, post,
            <<"/invoices/in_1/finalize">>},
        {invoice_void, fun() -> livery_stripe_invoice:void(C, <<"in_1">>) end, post,
            <<"/invoices/in_1/void">>},
        {invoice_send, fun() -> livery_stripe_invoice:send(C, <<"in_1">>) end, post,
            <<"/invoices/in_1/send">>},
        {invoice_mark_uncollectible,
            fun() -> livery_stripe_invoice:mark_uncollectible(C, <<"in_1">>) end, post,
            <<"/invoices/in_1/mark_uncollectible">>},
        {invoice_delete, fun() -> livery_stripe_invoice:delete(C, <<"in_1">>) end, delete,
            <<"/invoices/in_1">>},
        {invoice_upcoming,
            fun() -> livery_stripe_invoice:upcoming(C, #{customer => <<"cus_1">>}) end, get,
            <<"/invoices/upcoming">>},

        %% events
        {event_retrieve, fun() -> livery_stripe_event:retrieve(C, <<"evt_1">>) end, get,
            <<"/events/evt_1">>},
        {event_list, fun() -> livery_stripe_event:list(C) end, get, <<"/events">>},

        %% customer payment methods
        {customer_pms, fun() -> livery_stripe_customer:list_payment_methods(C, <<"cus_1">>) end,
            get, <<"/customers/cus_1/payment_methods">>},

        %% payment intent update / list
        {pi_update, fun() -> livery_stripe_payment_intent:update(C, <<"pi_1">>, P) end, post,
            <<"/payment_intents/pi_1">>},
        {pi_list, fun() -> livery_stripe_payment_intent:list(C) end, get, <<"/payment_intents">>},

        %% coupons
        {coupon_create, fun() -> livery_stripe_coupon:create(C, P) end, post, <<"/coupons">>},
        {coupon_retrieve, fun() -> livery_stripe_coupon:retrieve(C, <<"co_1">>) end, get,
            <<"/coupons/co_1">>},
        {coupon_update, fun() -> livery_stripe_coupon:update(C, <<"co_1">>, P) end, post,
            <<"/coupons/co_1">>},
        {coupon_delete, fun() -> livery_stripe_coupon:delete(C, <<"co_1">>) end, delete,
            <<"/coupons/co_1">>},
        {coupon_list, fun() -> livery_stripe_coupon:list(C) end, get, <<"/coupons">>},

        %% promotion codes
        {promo_create, fun() -> livery_stripe_promotion_code:create(C, P) end, post,
            <<"/promotion_codes">>},
        {promo_retrieve, fun() -> livery_stripe_promotion_code:retrieve(C, <<"promo_1">>) end, get,
            <<"/promotion_codes/promo_1">>},
        {promo_update, fun() -> livery_stripe_promotion_code:update(C, <<"promo_1">>, P) end, post,
            <<"/promotion_codes/promo_1">>},
        {promo_list, fun() -> livery_stripe_promotion_code:list(C) end, get,
            <<"/promotion_codes">>},

        %% discount removal
        {customer_delete_discount,
            fun() -> livery_stripe_customer:delete_discount(C, <<"cus_1">>) end, delete,
            <<"/customers/cus_1/discount">>},
        {sub_delete_discount,
            fun() -> livery_stripe_subscription:delete_discount(C, <<"sub_1">>) end, delete,
            <<"/subscriptions/sub_1/discount">>},

        %% mandates (SEPA / debit authorizations)
        {mandate_retrieve, fun() -> livery_stripe_mandate:retrieve(C, <<"mandate_1">>) end, get,
            <<"/mandates/mandate_1">>}
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
