defmodule LetItBid.Auctions do
  @moduledoc """
  The Auctions context: creating auctions, placing bids, and the reads the
  web layer needs.

  Each open auction has a `LetItBid.Auctions.Server` process that puts its
  bids in order. Postgres stays the source of truth: the server saves every
  change through the persistence functions here before replying, so a
  restarted server picks up exactly where the old one left off.
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Phoenix.PubSub

  alias LetItBid.Accounts.{Scope, User}
  alias LetItBid.Auctions.{Auction, Bid, Rules, Server, ServerSupervisor}
  alias LetItBid.Repo

  @pubsub LetItBid.PubSub
  @all_auctions_topic "auctions"

  @type server_state :: %{
          id: integer(),
          status: Auction.status(),
          seller_id: integer(),
          starting_price_cents: pos_integer(),
          min_increment_cents: pos_integer(),
          ends_at: DateTime.t(),
          top_bid_id: integer() | nil,
          top_bid_cents: pos_integer() | nil
        }

  @doc """
  Creates an auction sold by the scope's user and starts its server.
  """
  @spec create_auction(Scope.t(), map()) :: {:ok, Auction.t()} | {:error, Changeset.t()}
  def create_auction(%Scope{user: %User{} = seller}, attrs) do
    changeset =
      Auction.create_changeset(%Auction{seller_id: seller.id}, attrs, DateTime.utc_now())

    with {:ok, auction} <- Repo.insert(changeset) do
      {:ok, _pid} = ServerSupervisor.start_server(auction.id)
      :ok = broadcast(auction.id, {:auction_created, auction})
      {:ok, auction}
    end
  end

  @doc """
  Places a bid for the scope's user. Returns `{:ok, bid}` once the bid is
  saved and broadcast, or why it was rejected.

  Starts the auction's server if it isn't running (e.g. after a deploy).
  If the server stops or disappears while the bid is on its way, the
  auction is checked in the database: closed returns `{:error, :closed}`,
  still open (the server crashed) sends the bid to the restarted server.
  """
  @spec place_bid(Scope.t(), integer(), integer()) ::
          {:ok, Bid.t()} | {:error, Rules.rejection() | :not_found}
  def place_bid(%Scope{user: %User{} = bidder}, auction_id, amount_cents) do
    with {:ok, pid} <- ensure_server_started(auction_id) do
      Server.place_bid(pid, bidder.id, amount_cents)
    end
  catch
    :exit, {reason, {GenServer, :call, _}} when reason in [:normal, :noproc] ->
      bid_after_lost_server(bidder, auction_id, amount_cents)
  end

  @doc """
  Returns the running server for an open auction, starting it if needed.
  Doesn't start servers for closed or unknown auctions.
  """
  @spec ensure_server_started(integer()) :: {:ok, pid()} | {:error, :closed | :not_found}
  def ensure_server_started(auction_id) do
    case Server.whereis(auction_id) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> start_server_if_open(auction_id)
    end
  end

  @doc """
  Gets an auction. Raises `Ecto.NoResultsError` if it doesn't exist.
  """
  @spec get_auction!(integer()) :: Auction.t()
  def get_auction!(id), do: Repo.get!(Auction, id)

  @doc """
  Gets one auction as the auction list shows it: seller loaded and
  `top_bid_cents` filled in. Raises `Ecto.NoResultsError` if it doesn't exist.
  """
  @spec get_listing!(integer()) :: Auction.t()
  def get_listing!(id) do
    Auction
    |> where(id: ^id)
    |> with_top_bid_and_seller()
    |> Repo.one!()
  end

  @doc """
  Lists open auctions, ending soonest first, with their sellers loaded and
  `top_bid_cents` filled in (`nil` when nobody has bid).
  """
  @spec list_open_auctions() :: [Auction.t()]
  def list_open_auctions do
    Auction
    |> where(status: :open)
    |> order_by(asc: :ends_at)
    |> with_top_bid_and_seller()
    |> Repo.all()
  end

  @doc """
  Lists an auction's bids, highest first, with their bidders loaded.
  """
  @spec bid_history(integer()) :: [Bid.t()]
  def bid_history(auction_id) do
    Bid
    |> where(auction_id: ^auction_id)
    |> order_by(desc: :amount_cents)
    |> preload(:bidder)
    |> Repo.all()
  end

  @doc """
  The PubSub topic for an auction's events: `{:bid_placed, bid}`,
  `{:auction_extended, auction_id, ends_at}` and `{:auction_closed, auction}`.
  """
  @spec topic(integer()) :: String.t()
  def topic(auction_id), do: "auction:#{auction_id}"

  @doc """
  Subscribes the calling process to an auction's events (see `topic/1`).
  """
  @spec subscribe(integer()) :: :ok | {:error, term()}
  def subscribe(auction_id), do: PubSub.subscribe(@pubsub, topic(auction_id))

  @doc """
  Subscribes the calling process to every auction's events, plus
  `{:auction_created, auction}`. Used by pages that list auctions.
  """
  @spec subscribe_all() :: :ok | {:error, term()}
  def subscribe_all, do: PubSub.subscribe(@pubsub, @all_auctions_topic)

  @doc """
  Broadcasts an auction event to the auction's own topic and to the
  all-auctions topic (see `subscribe/1` and `subscribe_all/0`).
  """
  @spec broadcast(integer(), term()) :: :ok
  def broadcast(auction_id, message) do
    :ok = PubSub.broadcast(@pubsub, topic(auction_id), message)
    :ok = PubSub.broadcast(@pubsub, @all_auctions_topic, message)
  end

  @doc """
  Loads what an auction server needs to run: the auction's rules and the
  current top bid. Used by `LetItBid.Auctions.Server` on every (re)start.
  """
  @spec load_state(integer()) :: {:ok, server_state()} | {:error, :not_found}
  def load_state(auction_id) do
    case Repo.get(Auction, auction_id) do
      nil ->
        {:error, :not_found}

      auction ->
        top_bid = top_bid(auction_id)

        state = %{
          id: auction.id,
          status: auction.status,
          seller_id: auction.seller_id,
          starting_price_cents: auction.starting_price_cents,
          min_increment_cents: auction.min_increment_cents,
          ends_at: auction.ends_at,
          top_bid_id: top_bid && top_bid.id,
          top_bid_cents: top_bid && top_bid.amount_cents
        }

        {:ok, state}
    end
  end

  @doc """
  Saves a bid. Used by the auction server after `LetItBid.Auctions.Rules`
  has accepted it.
  """
  @spec insert_bid(integer(), integer(), integer()) :: {:ok, Bid.t()} | {:error, Changeset.t()}
  def insert_bid(auction_id, bidder_id, amount_cents) do
    %Bid{auction_id: auction_id, bidder_id: bidder_id}
    |> Bid.changeset(%{amount_cents: amount_cents})
    |> Repo.insert()
  end

  @doc """
  Saves a new end time after an anti-snipe extension. Used by the auction server.
  """
  @spec extend(integer(), DateTime.t()) :: :ok
  def extend(auction_id, ends_at) do
    {1, _} =
      Auction
      |> where(id: ^auction_id)
      |> Repo.update_all(set: [ends_at: ends_at, updated_at: DateTime.utc_now()])

    :ok
  end

  @doc """
  Marks an auction closed, with its winning bid (or `nil` if nobody bid).
  Used by the auction server when its close timer fires.
  """
  @spec close(integer(), integer() | nil) :: {:ok, Auction.t()} | {:error, Changeset.t()}
  def close(auction_id, winning_bid_id) do
    Auction
    |> Repo.get!(auction_id)
    |> Changeset.change(status: :closed, winning_bid_id: winning_bid_id)
    |> Repo.update()
  end

  # Skips the Registry, which can still point at the dead server, and asks
  # the supervisor, which has already handled the crash.
  defp bid_after_lost_server(bidder, auction_id, amount_cents) do
    with {:ok, pid} <- start_server_if_open(auction_id) do
      Server.place_bid(pid, bidder.id, amount_cents)
    end
  end

  defp start_server_if_open(auction_id) do
    case Repo.get(Auction, auction_id) do
      nil -> {:error, :not_found}
      %Auction{status: :closed} -> {:error, :closed}
      %Auction{status: :open} -> ServerSupervisor.start_server(auction_id)
    end
  end

  defp with_top_bid_and_seller(query) do
    top_bids =
      from b in Bid,
        group_by: b.auction_id,
        select: %{auction_id: b.auction_id, amount_cents: max(b.amount_cents)}

    from a in query,
      left_join: t in subquery(top_bids),
      on: t.auction_id == a.id,
      preload: [:seller],
      select_merge: %{top_bid_cents: t.amount_cents}
  end

  defp top_bid(auction_id) do
    Bid
    |> where(auction_id: ^auction_id)
    |> order_by(desc: :amount_cents)
    |> limit(1)
    |> Repo.one()
  end
end
