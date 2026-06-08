-module(livery_stripe_util).
-moduledoc "Small shared helpers.".

-export([lower_hex/1, to_bin/1]).

-doc "Lowercase hex encoding of a binary.".
-spec lower_hex(binary()) -> binary().
lower_hex(Bin) when is_binary(Bin) ->
    <<<<(hex(N bsr 4)), (hex(N band 16#0F))>> || <<N>> <= Bin>>.

hex(D) when D < 10 -> $0 + D;
hex(D) -> $a + (D - 10).

-doc "Coerce a binary | iolist | atom | integer to a binary.".
-spec to_bin(binary() | iolist() | atom() | integer()) -> binary().
to_bin(B) when is_binary(B) -> B;
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_bin(L) when is_list(L) -> iolist_to_binary(L).
