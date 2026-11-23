defmodule LetItBid.Auctions.Server do
  @moduledoc """
  One process per open auction. It puts concurrent bids in order, runs the
  close timer, and broadcasts every change on `LetItBid.Auctions.topic/1`.

  Postgres is the source of truth: each accepted bid is saved before the
  reply, and on every (re)start the server reloads its state and schedules
  the close timer from `ends_at`. So a crashed server comes back exactly
  where it was, and an auction that ended while no server was running
  closes as soon as one starts.
  """

  use GenServer, restart: :transient

  alias LetItBid.Auctions
  alias LetItBid.Auctions.{Bid, Rules}

  @registry LetItBid.Auctions.Registry

  @type state :: %{
          :id => integer(),
          optional(:status) => :open | :closed,
          optional(:seller_id) => integer(),
          optional(:starting_price_cents) => pos_integer(),
          optional(:min_increment_cents) => pos_integer(),
          optional(:ends_at) => DateTime.t(),
          optional(:top_bid_id) => integer() | nil,
          optional(:top_bid_cents) => pos_integer() | nil,
          optional(:close_timer) => reference(),
          optional(:close_ref) => reference()
        }

  @doc "Starts the server for an auction, registered under its ID."
  @spec start_link(integer()) :: GenServer.on_start()
  def start_link(auction_id) do
    GenServer.start_link(__MODULE__, auction_id, name: process_name(auction_id))
  end

  @doc "Returns the pid of an auction's server, or `nil` if none is running."
  @spec whereis(integer()) :: pid() | nil
  def whereis(auction_id) do
    case Registry.lookup(@registry, auction_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @doc """
  Places a bid. Returns `{:ok, bid}` once the bid is saved, or the reason
  `LetItBid.Auctions.Rules` rejected it.
  """
  @spec place_bid(pid(), integer(), integer()) :: {:ok, Bid.t()} | {:error, Rules.rejection()}
  def place_bid(server, bidder_id, amount_cents) do
    GenServer.call(server, {:place_bid, bidder_id, amount_cents})
  end

  @impl true
  def init(auction_id), do: {:ok, %{id: auction_id}, {:continue, :load}}

  @impl true
  def handle_continue(:load, %{id: auction_id} = state) do
    case Auctions.load_state(auction_id) do
      {:ok, %{status: :open} = loaded} -> {:noreply, schedule_close(loaded)}
      {:ok, %{status: :closed}} -> {:stop, :normal, state}
      {:error, :not_found} -> {:stop, :normal, state}
    end
  end

  @impl true
  def handle_call({:place_bid, bidder_id, amount_cents}, _from, state) do
    now = DateTime.utc_now()

    case Rules.validate_bid(state, bidder_id, amount_cents, now) do
      :ok ->
        {:ok, bid} = Auctions.insert_bid(state.id, bidder_id, amount_cents)
        broadcast(state, {:bid_placed, bid})

        state = maybe_extend(%{state | top_bid_id: bid.id, top_bid_cents: bid.amount_cents}, now)

        {:reply, {:ok, bid}, state}

      {:error, _reason} = rejection ->
        {:reply, rejection, state}
    end
  end

  @impl true
  def handle_info({:close, ref}, %{close_ref: ref} = state) do
    {:ok, auction} = Auctions.close(state.id, state.top_bid_id)
    broadcast(state, {:auction_closed, auction})
    {:stop, :normal, %{state | status: :closed}}
  end

  def handle_info({:close, _stale_ref}, state), do: {:noreply, state}

  defp process_name(auction_id), do: {:via, Registry, {@registry, auction_id}}

  defp maybe_extend(state, now) do
    config = Application.fetch_env!(:let_it_bid, Auctions)

    case Rules.maybe_extend(
           state.ends_at,
           now,
           config[:anti_snipe_window_ms],
           config[:anti_snipe_extension_ms]
         ) do
      {:extended, ends_at} ->
        :ok = Auctions.extend(state.id, ends_at)
        broadcast(state, {:auction_extended, state.id, ends_at})
        schedule_close(%{state | ends_at: ends_at})

      :unchanged ->
        state
    end
  end

  defp schedule_close(state) do
    :ok = cancel_close_timer(state)

    ref = make_ref()

    delay =
      state.ends_at
      |> DateTime.diff(DateTime.utc_now(), :millisecond)
      |> max(0)

    timer = Process.send_after(self(), {:close, ref}, delay)

    Map.merge(state, %{close_timer: timer, close_ref: ref})
  end

  defp cancel_close_timer(%{close_timer: timer}),
    do: Process.cancel_timer(timer, async: true, info: false)

  defp cancel_close_timer(_state), do: :ok

  defp broadcast(state, message) do
    :ok = Phoenix.PubSub.broadcast(LetItBid.PubSub, Auctions.topic(state.id), message)
  end
end
