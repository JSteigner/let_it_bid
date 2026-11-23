defmodule LetItBid.AuctionsFixtures do
  @moduledoc """
  Test helpers for creating auctions and bids.

  `auction_fixture/1` and `bid_fixture/2` insert rows directly, without
  starting an auction server, so they work in async tests and can build
  states the API wouldn't allow (an auction that already ended).
  `live_auction_fixture/2` goes through `LetItBid.Auctions.create_auction/2`
  and starts a real server.
  """

  alias LetItBid.Accounts.Scope
  alias LetItBid.AccountsFixtures
  alias LetItBid.Auctions
  alias LetItBid.Auctions.{Auction, Bid, Server, ServerSupervisor}
  alias LetItBid.Repo

  @spec valid_auction_attributes(map() | keyword()) :: map()
  def valid_auction_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      title: "#{Faker.Commerce.product_name()} #{System.unique_integer([:positive])}",
      description: Faker.Lorem.sentence(),
      starting_price_cents: 1_000,
      min_increment_cents: 100,
      ends_at: DateTime.add(DateTime.utc_now(), 1, :hour)
    })
  end

  @spec auction_fixture(map() | keyword()) :: Auction.t()
  def auction_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    seller = Map.get_lazy(attrs, :seller, fn -> AccountsFixtures.user_fixture() end)

    attrs
    |> Map.drop([:seller])
    |> valid_auction_attributes()
    |> Map.put(:seller_id, seller.id)
    |> then(&struct!(Auction, &1))
    |> Repo.insert!()
  end

  @spec bid_fixture(Auction.t(), map() | keyword()) :: Bid.t()
  def bid_fixture(%Auction{} = auction, attrs \\ %{}) do
    attrs = Map.new(attrs)
    bidder = Map.get_lazy(attrs, :bidder, fn -> AccountsFixtures.user_fixture() end)

    Repo.insert!(%Bid{
      auction_id: auction.id,
      bidder_id: bidder.id,
      amount_cents: Map.get(attrs, :amount_cents, auction.starting_price_cents)
    })
  end

  @spec live_auction_fixture(Scope.t(), map() | keyword()) :: Auction.t()
  def live_auction_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, auction} = Auctions.create_auction(scope, valid_auction_attributes(attrs))
    auction
  end

  @doc "Whether a server is running for the auction."
  @spec server_running?(integer()) :: boolean()
  def server_running?(auction_id) do
    auction_id
    |> Server.whereis()
    |> is_pid()
  end

  @doc """
  Stops every running auction server. Call it in `on_exit` before the
  sandbox shuts down.

  Waits for each server to finish its current work first (`:sys.get_state/1`
  runs after `handle_continue`), so none is killed mid-query.
  """
  @spec stop_auction_servers() :: :ok
  def stop_auction_servers do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(ServerSupervisor), is_pid(pid) do
      stop_server(pid)
    end

    :ok
  end

  defp stop_server(pid) do
    _ = :sys.get_state(pid)
    _ = DynamicSupervisor.terminate_child(ServerSupervisor, pid)
    :ok
  catch
    :exit, _already_stopped -> :ok
  end
end
