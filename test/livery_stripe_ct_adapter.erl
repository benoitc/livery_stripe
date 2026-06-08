-module(livery_stripe_ct_adapter).
-moduledoc "Test transport adapter: replays a queue of canned responses and records requests.".
-behaviour(livery_client_adapter).

-export([request/2]).
-export([setup/1, requests/0, reset/0]).

-define(TAB, ?MODULE).

-spec setup([livery_client:result()]) -> ok.
setup(Responses) ->
    reset(),
    _ = ets:new(?TAB, [named_table, public, ordered_set]),
    true = ets:insert(?TAB, {queue, Responses}),
    true = ets:insert(?TAB, {count, 0}),
    ok.

-spec reset() -> ok.
reset() ->
    case ets:info(?TAB) of
        undefined ->
            ok;
        _ ->
            ets:delete(?TAB),
            ok
    end.

-spec request(livery_client:request(), map()) -> livery_client:result().
request(Req, _Opts) ->
    N = ets:update_counter(?TAB, count, 1),
    true = ets:insert(?TAB, {{req, N}, Req}),
    case ets:lookup(?TAB, queue) of
        [{queue, [Resp | Rest]}] ->
            true = ets:insert(?TAB, {queue, Rest}),
            Resp;
        _ ->
            {ok, #{status => 200, headers => [], body => {full, <<"{}">>}}}
    end.

-spec requests() -> [livery_client:request()].
requests() ->
    [Req || {{req, _}, Req} <- lists:sort(ets:tab2list(?TAB))].
