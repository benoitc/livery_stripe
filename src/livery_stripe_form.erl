-module(livery_stripe_form).
-moduledoc """
Encode parameters as `application/x-www-form-urlencoded`, the body format
Stripe expects, including its bracketed nesting for maps and lists.

The encoding mirrors Stripe's own client libraries:

- a map `#{K => V}` becomes `parent[K]=...` (one pair per key, keys sorted
  for deterministic output),
- a list of maps becomes `parent[0][k]=...&parent[1][k]=...`,
- a list of scalars becomes `parent[]=a&parent[]=b`,
- scalars are coerced: integers, floats, booleans, and atoms render to
  their textual form; strings must be binaries.

Reserved characters are percent-encoded and spaces become `+`, matching
`quote_plus` semantics, so brackets render as `%5B`/`%5D` (Stripe decodes
both forms).

```erlang
<<"line_items%5B0%5D%5Bprice%5D=price_1&line_items%5B0%5D%5Bquantity%5D=1">> =
    livery_stripe_form:encode([{<<"line_items">>,
        [#{<<"price">> => <<"price_1">>, <<"quantity">> => 1}]}]).
```
""".

-export([encode/1]).

-type key() :: binary() | atom() | integer() | string().
-type value() :: binary() | integer() | float() | boolean() | atom() | map() | list().
-export_type([key/0, value/0]).

-doc "Encode an ordered proplist (or a map) of parameters into a form body.".
-spec encode([{key(), value()}] | map()) -> binary().
encode(Params) ->
    Pairs = collect(Params),
    Encoded = [[urlencode(K), $=, urlencode(V)] || {K, V} <- Pairs],
    iolist_to_binary(lists:join($&, Encoded)).

%%====================================================================
%% Flattening
%%====================================================================

%% Top level: a map is sorted for deterministic output; a proplist keeps
%% its given order.
collect(Params) when is_map(Params) ->
    collect(sorted_pairs(Params));
collect(Params) when is_list(Params) ->
    lists:append([field(to_key(K), V) || {K, V} <- Params]).

%% field(Prefix, Value) -> [{FlatKey :: binary(), Value :: binary()}]
%% `undefined` is dropped (matching Stripe's clients, which omit nil), so
%% callers can pass optional fields without filtering them first.
field(_Prefix, undefined) ->
    [];
field(Prefix, Value) when is_map(Value) ->
    lists:append(
        [
            field(<<Prefix/binary, "[", (to_key(K))/binary, "]">>, V)
         || {K, V} <- sorted_pairs(Value)
        ]
    );
field(Prefix, Value) when is_list(Value) ->
    array(Prefix, Value, 0);
field(Prefix, Value) ->
    [{Prefix, to_val(Value)}].

array(_Prefix, [], _I) ->
    [];
array(Prefix, [undefined | T], I) ->
    array(Prefix, T, I);
array(Prefix, [H | T], I) when is_map(H); is_list(H) ->
    Key = <<Prefix/binary, "[", (integer_to_binary(I))/binary, "]">>,
    field(Key, H) ++ array(Prefix, T, I + 1);
array(Prefix, [H | T], I) ->
    [{<<Prefix/binary, "[]">>, to_val(H)} | array(Prefix, T, I + 1)].

sorted_pairs(Map) ->
    lists:keysort(1, [{to_key(K), V} || {K, V} <- maps:to_list(Map)]).

%%====================================================================
%% Coercion
%%====================================================================

to_key(K) when is_binary(K) -> K;
to_key(K) when is_atom(K) -> atom_to_binary(K, utf8);
to_key(K) when is_integer(K) -> integer_to_binary(K);
to_key(K) when is_list(K) -> list_to_binary(K).

%% Only scalars reach to_val: maps and lists are handled in field/array.
to_val(V) when is_binary(V) -> V;
to_val(V) when is_integer(V) -> integer_to_binary(V);
to_val(true) -> <<"true">>;
to_val(false) -> <<"false">>;
to_val(V) when is_atom(V) -> atom_to_binary(V, utf8);
to_val(V) when is_float(V) -> float_to_binary(V, [short]).

%%====================================================================
%% Percent-encoding (quote_plus)
%%====================================================================

urlencode(Bin) ->
    <<<<(esc(C))/binary>> || <<C>> <= Bin>>.

esc(C) when C >= $A, C =< $Z -> <<C>>;
esc(C) when C >= $a, C =< $z -> <<C>>;
esc(C) when C >= $0, C =< $9 -> <<C>>;
esc($-) -> <<"-">>;
esc($_) -> <<"_">>;
esc($.) -> <<".">>;
esc($~) -> <<"~">>;
esc($\s) -> <<"+">>;
esc(C) -> <<$%, (hex_u(C bsr 4)), (hex_u(C band 16#0F))>>.

hex_u(D) when D < 10 -> $0 + D;
hex_u(D) -> $A + (D - 10).
