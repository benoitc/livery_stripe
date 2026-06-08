-module(livery_stripe_sup).
-moduledoc """
Top supervisor.

The Stripe client is a plain value cached in `persistent_term`, so there
are no long-lived children to supervise yet. The supervisor exists to
give the application a root process and a place to hang future workers
(e.g. a background event reconciler).
""".
-behaviour(supervisor).

-export([start_link/0, init/1]).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
    {ok, {SupFlags, []}}.
