-module(livery_stripe_webhook_handler).
-moduledoc """
A mountable livery handler for the Stripe webhook endpoint.

Add it to a router with `routes/0,1`:

```erlang
livery_router:compile(livery_stripe_webhook_handler:routes()).
```

`handle/1` reads the raw body and `Stripe-Signature` header, verifies the
event with `livery_stripe_webhook`, and dispatches it to the configured
callback (the `webhook_callback` config key). It always answers JSON: 200
when accepted, 400 on a bad payload or signature.

The callback may be a `fun/1` (`Event`), a `fun/2` (`Type, Event`), a
module implementing `handle_event/2`, or a `{Module, Function}` pair.
Persistence (updating a user's subscription, etc.) belongs in the
callback; this module stays storage-agnostic.
""".

-export([handle/1, handle/2, routes/0, routes/1]).

-callback handle_event(Type :: binary(), Event :: map()) -> ok | {error, term()}.

-doc "livery route handler. Reads secret and callback from app config.".
-spec handle(livery_req:req()) -> livery_resp:resp().
handle(Req) ->
    handle(Req, handler_opts()).

-doc "Like `handle/1` but with explicit `#{secret, callback}` opts.".
-spec handle(livery_req:req(), map()) -> livery_resp:resp().
handle(Req, Opts) ->
    Secret = maps:get(secret, Opts, undefined),
    Callback = maps:get(callback, Opts, undefined),
    Raw = read_body(Req),
    Sig = livery_req:header(<<"stripe-signature">>, Req),
    case livery_stripe_webhook:construct_event(Raw, Sig, Secret) of
        {ok, Event} ->
            _ = dispatch(Callback, Event),
            livery_resp:json(200, <<"{\"received\":true}">>);
        {error, invalid_payload} ->
            livery_resp:json(400, <<"{\"error\":\"invalid payload\"}">>);
        {error, _} ->
            livery_resp:json(400, <<"{\"error\":\"invalid signature\"}">>)
    end.

-doc "Routes for the default path `/stripe/webhook`.".
-spec routes() -> [tuple()].
routes() ->
    routes(<<"/stripe/webhook">>).

-spec routes(binary()) -> [tuple()].
routes(Path) ->
    [{<<"POST">>, Path, {?MODULE, handle}}].

%%====================================================================
%% Internals
%%====================================================================

dispatch(undefined, _Event) ->
    ok;
dispatch(Fun, Event) when is_function(Fun, 1) ->
    Fun(Event);
dispatch(Fun, Event) when is_function(Fun, 2) ->
    Fun(event_type(Event), Event);
dispatch({Mod, Fun}, Event) ->
    Mod:Fun(event_type(Event), Event);
dispatch(Mod, Event) when is_atom(Mod) ->
    Mod:handle_event(event_type(Event), Event).

event_type(Event) ->
    maps:get(<<"type">>, Event, <<>>).

handler_opts() ->
    Cfg = livery_stripe:config(),
    #{
        secret => maps:get(webhook_secret, Cfg, undefined),
        callback => maps:get(webhook_callback, Cfg, undefined)
    }.

read_body(Req) ->
    case livery_req:body(Req) of
        empty ->
            <<>>;
        {buffered, IoData} ->
            iolist_to_binary(IoData);
        {stream, Reader} ->
            case livery_body:read_all(Reader) of
                {ok, Bin, _Reader} -> Bin;
                {error, _Reason, _Reader} -> <<>>
            end
    end.
