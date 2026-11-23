@AGENTS.md

# Project: LetItBid (Elixir 1.20 / OTP 29 / Phoenix 1.8 / LiveView 1.2 / Postgres 18)

Portfolio app: a live auction house. Each auction is a supervised GenServer; LiveView pushes bids to everyone watching. Postgres is the source of truth, so a crashed or restarted auction picks up where it left off.
Postgres 18 on port 5432 by default: a local install (Postgres.app here) or `docker compose up -d`. Override the connection with `DB_HOST`, `DB_PORT`, `DB_USER` and `DB_PASSWORD`.

## Commands
- Test: `mix test` (single test: `mix test test/path_test.exs:42`; rerun failures: `mix test --failed`)
- Before finishing any task: `mix precommit` (compile with warnings as errors, unlock unused deps, `hex.audit` for retired or vulnerable packages, format, `credo --strict`, `dialyzer`, then tests with a 95% minimum coverage via `mix coveralls`). Check its exit code (`mix precommit; echo $?`), not just the last lines: a failing test doesn't stop the run.
- Coverage report: `mix coveralls.html` (writes `cover/excoveralls.html`)
- Docs: `mix docs` (writes `doc/index.html`)

## How to work
- Test-driven development, always (see below). No implementation code before a failing test for it.
- For changes touching more than 3 files, or adding a process, table or dependency: propose a short plan first and wait for my OK.
- Keep diffs minimal; don't refactor or rename unrelated code.
- If a business rule is ambiguous, ask. Don't guess.
- When there's a real tradeoff (e.g. GenServer vs ETS vs DB), state it in a line or two and pick one.
- Don't say something works until its tests pass and `mix precommit` exits 0.

## Test-driven development
1. **Red:** write the test first. Run it and check it fails *for the right reason*: an assertion against real code. `UndefinedFunctionError`, a compile error, a typo or a broken fixture don't count. For a new module or function, first add a stub with the real name, arity, `@spec` and `@doc` that returns a wrong but well-typed value (e.g. `def minimum_next_bid(_state), do: 0`), so the first failure is the assertion.
2. **Green:** write the least code that makes it pass.
3. **Refactor:** clean up with the tests green, then run `mix precommit`.
- Every public function has a test, in a test file. No doctests, and no `iex>` examples in `@doc`s.
- Every bug fix starts with a failing regression test.
- A test that passes on its first run (e.g. one that pins down existing behavior) hasn't shown it can fail. Break the code it covers on purpose (flip a comparison, drop a call), watch the test fail on its assertion, then restore the code.
- Test behavior through the public API (context functions, LiveView events), not private functions or process internals.

## Docs and types
- Every module has a `@moduledoc` (`@moduledoc false` only for internal modules that aren't part of the API).
- Every public function has a `@doc` and a `@spec`, including `defdelegate`s. Credo's `Specs` check enforces specs (function components in `core_components.ex` and `layouts.ex` are exempt; they're documented with `attr`/`slot`).
- `@impl true` callbacks need no `@doc` or `@spec`; the behaviour documents them.
- Exception: `lib/let_it_bid_web.ex` (the `LetItBidWeb` module) doesn't need `@doc`s on its functions. They still need `@spec`s. It's also excluded from coverage (`coveralls.json`): its `quote` helpers run at compile time, so a test calling them can't fail without the app failing to compile first. Don't add tests for them.
- Every schema defines `@type t`. Enum fields get their own type, e.g. `Auction.status()`.
- Specs are precise: `{:ok, Auction.t()} | {:error, Ecto.Changeset.t()}`, not `any()` or `term()` unless the value really is arbitrary.
- Doc examples with `#{...}` use `@doc ~S"""` so they aren't interpolated.
- Dialyzer runs with `:unmatched_returns`. Don't silence it with `_ =` when a result can be an error: match it (`:ok = ...`, `{:ok, _} = ...`) or handle the error. `_ =` is only for results that really don't matter (e.g. test setup).

## Architecture
- Business logic lives in contexts under `lib/let_it_bid/` (`Accounts`, `Auctions`). LiveViews and controllers in `lib/let_it_bid_web/` stay thin.
- **Never use Ecto in the web layer**: no `Repo`, `Ecto.Query`, `Ecto.Changeset` calls, and no `%Ecto.Changeset{}` pattern matches. If the web layer needs a changeset transformed, add a context function. Passing a changeset the context returned into `to_form/2` is fine.
- Context functions take the caller's `%Scope{}` first when the action belongs to a user (`Auctions.place_bid(scope, auction_id, amount_cents)`).
- Context functions return `{:ok, value} | {:error, reason}`, where `reason` is a changeset or a tagged atom/tuple (`:too_low`, `{:delivery_failed, reason}`). Bang (`!`) variants only when failure is a bug.
- Domain functions take `integer()` IDs. The web layer parses string params before calling the context.
- PubSub topics come from the owning context (`Auctions.topic(auction_id)`, `Auctions.subscribe(auction_id)`), never inline strings.
- Log operational failures (an email that didn't send) with `Logger` where they're handled; don't swallow them.

## Auction domain rules
- **Postgres is the source of truth.** A bid is persisted *before* the auction server replies `{:ok, bid}`.
- Each auction server holds the current state in memory and puts concurrent bids in order. No ETS for auction state.
- Store `ends_at` as a timestamp (`:utc_datetime_usec`). On every (re)start the server recomputes the time left from `ends_at` and schedules its close timer from it; an overdue auction closes right away.
- The countdown runs in the browser from `ends_at`. The server broadcasts only when something changes: bid placed, auction extended (anti-snipe), auction closed. Never a per-second tick.
- Money is integer cents in `*_cents` fields. Never floats.
- Bid and anti-snipe rules live in the pure `LetItBid.Auctions.Rules` module (no processes, no Repo). The GenServer only coordinates: validate with `Rules`, persist, broadcast, reply.
- The Registry is node-local by design. Clustering (Horde, `:syn`) is out of scope; mention it in the README, don't build it.

## OTP
- Use a GenServer for state, serialization or lifecycle, never just to organize code.
- Every process is supervised: no bare `spawn` or `Task.start`. Use `Task.Supervisor` for fire-and-forget work.
- Dynamic processes: `DynamicSupervisor` + `Registry` via-tuples. Never create atoms from runtime data for names.
- Auction servers are `restart: :transient`: a finished auction stops normally and isn't restarted; a crashed one is.
- Keep `handle_call` fast. Put startup work in `handle_continue`, not `init/1`.
- Let it crash: no `try/rescue` to hide errors. Rescue only at system boundaries.
- Timer messages carry a ref; ignore messages whose ref isn't the current one.
- When adding a child to a supervision tree, say where it goes and why the order matters.

## Tests
- Test files mirror `lib/` (e.g. `test/let_it_bid/auctions/rules_test.exs`).
- Data tests use `LetItBid.DataCase`; web tests use `LetItBidWeb.ConnCase`. Default to `async: true`.
- Build data with the fixture modules in `test/support/fixtures/` (`AccountsFixtures`, `AuctionsFixtures`). `DataCase` and `ConnCase` import both (and `ConnCase` imports `Phoenix.LiveViewTest`), so tests don't import them again. Use literal values only when the exact value matters.
- Processes: `start_supervised!/1`. Wait for messages with `assert_receive`, never `Process.sleep`.
- Tests that change global state (application env, a named process the app owns) use `async: false` and restore the state in `on_exit`.
- Auction server tests are `async: false` (the restarted processes need the shared sandbox) and stop their servers in `on_exit` (`stop_auction_servers/0`) before the sandbox shuts down.
- Async tests never start an auction server: build data with `auction_fixture/1` and `bid_fixture/2` (direct inserts), never `live_auction_fixture/2`, `Auctions.create_auction/2` or `Auctions.place_bid/3`. A server started from an async test queries the database outside that test's sandbox and crashes.
- LiveView tests assert with `has_element?/2`/`element/2` and the DOM IDs in the template, not raw HTML matching (see AGENTS.md).

## Conventions
- Pattern-match in function heads; use `with` for ok/error chains.
- All writes go through changesets; use `Ecto.Multi` or `Repo.transact/1` for multi-step writes.
- Preload associations in the context, never in templates. No Repo calls inside `Enum.map` (N+1).
- `Req` for HTTP (already a dep).

## Elixir style

Follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide). `credo --strict` (in `mix precommit`, configured in `.credo.exs`) enforces most of it: pipes one step per line, no single-step pipes, pipes starting with a bare value, a `@moduledoc` on every module, a `@spec` on every public function, directive order (`@moduledoc`, `@behaviour`, `use`, `import`, `require`, `alias`), and aliases for nested modules called more than once. Fix what it reports rather than disabling checks.

Credo can't check these, so follow them by hand:

- No nested `case` (or `case` inside `with`/`if`). Move the inner one into a private function named for what it decides, e.g. `start_server_if_open/1`.
- When a value passes through two or more nested calls, write a pipe chain that starts from the value instead, and keep adding steps to the chain rather than wrapping its result:
  ```elixir
  # not this
  Process.exit(Server.whereis(auction.id), :kill)
  Repo.insert!(struct!(Auction, Map.put(fields, :seller_id, seller.id)))

  # this
  auction.id
  |> Server.whereis()
  |> Process.exit(:kill)

  attrs
  |> valid_auction_attributes()
  |> Map.put(:seller_id, seller.id)
  |> then(&struct!(Auction, &1))
  |> Repo.insert!()
  ```
  The rule covers a value flowing through each call's first argument (`f(g(x))`, `f(g(x), y)`). These stay as they are:
  - An inner call in another argument position: `Phoenix.PubSub.subscribe(@pubsub, topic(auction_id))`.
  - A builder called on literals, typically in tests: `Rules.validate_bid(state(top_bid_cents: 1_500), ...)`.
  - A call wrapped around a call with no value argument, since its pipe would start with a function call: `DateTime.add(DateTime.utc_now(), 1, :hour)`.

  Inside an existing chain, use `then/2` for a step that takes the value in another position (the `struct!/2` step above). If a later step needs the value again, bind it to a variable, or end the chain with a small helper that returns it (e.g. `wait_until_idle/1`).

- Private functions (`defp`) go at the bottom of the module, after every public function, in tests too (after the last `test`/`describe`). Generated auth code predates this rule; don't reorder it unless you're already changing that module.
- After the directives come module attributes, `defstruct`, then `@type`. Put a blank line between each group, including after the `@moduledoc`:
  ```elixir
  defmodule LetItBid.Auctions.Auction do
    @moduledoc """
    An item up for auction.
    """

    use Ecto.Schema

    import Ecto.Changeset

    alias LetItBid.Accounts.User
    alias LetItBid.Auctions.Bid
  ```
- In Ecto schemas, declare changeset fields as module attributes using the `~w[]a` sigil, and put enum values in their own attribute:
  ```elixir
  @required_fields ~w[title starting_price_cents min_increment_cents ends_at]a
  @optional_fields ~w[description]a
  @fields @required_fields ++ @optional_fields

  @statuses ~w[open closed]a

  schema "auctions" do
    field :status, Ecto.Enum, values: @statuses, default: :open
  ```
  Then use `cast(attrs, @fields)` and `validate_required(@required_fields)` in the changeset. Fields set by the code (`seller_id`, `status`) are not cast.
- Credo's alias check only counts function calls. The rule is wider: if a module name is written out in full more than once in a file (calls, structs, typespecs), alias it and use the short name everywhere. A module used only once stays fully qualified.
- Put external aliases (Ecto, Phoenix, ...) first and `LetItBid` aliases second, with a blank line between the two groups:
  ```elixir
  alias Ecto.Multi
  alias Phoenix.PubSub

  alias LetItBid.Auctions.{Auction, Bid}
  alias LetItBid.Repo
  ```
- Group aliases that share a parent module with curly braces: `alias LetItBid.Auctions.{Auction, Bid, Rules}`.

## Don'ts
- Don't modify existing migrations; create new ones with `mix ecto.gen.migration name`.
- Every migration must be reversible. Prefer `change/0` with reversible operations (use `modify ... from:` when altering columns); otherwise write explicit `up/0` and `down/0`. Verify with `mix ecto.migrate && mix ecto.rollback && mix ecto.migrate` before finishing.
- Add an index for every foreign key.
- Ask before adding deps to `mix.exs`.
- Don't edit files in `deps/` or `_build/`, or secrets in `config/runtime.exs`.
