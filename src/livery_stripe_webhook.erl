-module(livery_stripe_webhook).
-moduledoc """
Verify and decode Stripe webhook events, the equivalent of
`stripe.Webhook.construct_event`.

The signature lives in the `Stripe-Signature` header
(`t=<ts>,v1=<hex>[,v1=...]`). We recompute `HMAC-SHA256(secret,
"<ts>.<raw_body>")` and compare it, in constant time, against each `v1`.
The timestamp must be within `tolerance` seconds (default 300) of now to
defeat replay.

CRITICAL: pass the RAW request body bytes, exactly as received. Any
re-encoding (decoding then re-serializing JSON) changes the bytes and the
signature will not match.
""".

-export([construct_event/3, construct_event/4]).

-define(DEFAULT_TOLERANCE, 300).

-type error() :: invalid_signature | invalid_payload | timestamp_out_of_tolerance.
-export_type([error/0]).

-spec construct_event(iodata(), binary() | undefined, iodata()) ->
    {ok, map()} | {error, error()}.
construct_event(Payload, SigHeader, Secret) ->
    construct_event(Payload, SigHeader, Secret, #{}).

-doc """
Opts: `tolerance` (seconds, default 300; `0` disables the timestamp check)
and `now` (unix seconds, for testing).
""".
-spec construct_event(iodata(), binary() | undefined, iodata(), map()) ->
    {ok, map()} | {error, error()}.
construct_event(Payload, SigHeader, Secret, Opts) ->
    Raw = iolist_to_binary(Payload),
    case verify(Raw, SigHeader, livery_stripe_util:to_bin(Secret), Opts) of
        ok -> decode(Raw);
        {error, _} = Error -> Error
    end.

%%====================================================================
%% Verification
%%====================================================================

verify(_Raw, undefined, _Secret, _Opts) ->
    {error, invalid_signature};
verify(Raw, SigHeader, Secret, Opts) ->
    case parse(livery_stripe_util:to_bin(SigHeader)) of
        {ok, Ts, Sigs} ->
            case timestamp_ok(Ts, Opts) of
                ok -> match(Raw, Ts, Sigs, Secret);
                {error, _} = Error -> Error
            end;
        error ->
            {error, invalid_signature}
    end.

match(Raw, Ts, Sigs, Secret) ->
    Signed = <<(integer_to_binary(Ts))/binary, ".", Raw/binary>>,
    Expected = livery_stripe_util:lower_hex(crypto:mac(hmac, sha256, Secret, Signed)),
    case lists:any(fun(S) -> secure_equal(Expected, S) end, Sigs) of
        true -> ok;
        false -> {error, invalid_signature}
    end.

timestamp_ok(Ts, Opts) ->
    case maps:get(tolerance, Opts, ?DEFAULT_TOLERANCE) of
        Tol when Tol =< 0 ->
            ok;
        Tol ->
            Now = maps:get(now, Opts, os:system_time(second)),
            case abs(Now - Ts) =< Tol of
                true -> ok;
                false -> {error, timestamp_out_of_tolerance}
            end
    end.

decode(Raw) ->
    try json:decode(Raw) of
        Event when is_map(Event) -> {ok, Event};
        _ -> {error, invalid_payload}
    catch
        _:_ -> {error, invalid_payload}
    end.

%% Parse "t=...,v1=...,v1=...,v0=..." into the timestamp and the v1 list.
parse(Header) ->
    Parts = binary:split(Header, <<",">>, [global]),
    KVs = [kv(P) || P <- Parts],
    Sigs = [V || {<<"v1">>, V} <- KVs],
    case [V || {<<"t">>, V} <- KVs] of
        [TsBin | _] ->
            case to_int(TsBin) of
                {ok, Ts} when Sigs =/= [] -> {ok, Ts, Sigs};
                _ -> error
            end;
        _ ->
            error
    end.

kv(Part) ->
    case binary:split(trim(Part), <<"=">>) of
        [K, V] -> {trim(K), trim(V)};
        _ -> {<<>>, <<>>}
    end.

trim(B) -> string:trim(B).

to_int(B) ->
    case string:to_integer(B) of
        {I, <<>>} when is_integer(I) -> {ok, I};
        _ -> error
    end.

%% Constant-time comparison; bails fast only on length mismatch.
secure_equal(A, B) when byte_size(A) =:= byte_size(B) ->
    secure_equal(A, B, 0);
secure_equal(_, _) ->
    false.

secure_equal(<<>>, <<>>, Acc) ->
    Acc =:= 0;
secure_equal(<<X, RestA/binary>>, <<Y, RestB/binary>>, Acc) ->
    secure_equal(RestA, RestB, Acc bor (X bxor Y)).
