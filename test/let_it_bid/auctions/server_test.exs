defmodule LetItBid.Auctions.ServerTest do
  use LetItBid.DataCase, async: false

  alias LetItBid.Auctions
  alias LetItBid.Auctions.{Auction, Bid, Server, ServerSupervisor}

  setup do
    on_exit(&stop_auction_servers/0)

    %{seller: user_scope_fixture(), bidder: user_scope_fixture()}
  end

  describe "create_auction/2" do
    test "saves the auction and starts its server", %{seller: seller} do
      assert {:ok, %Auction{} = auction} =
               Auctions.create_auction(seller, valid_auction_attributes())

      assert auction.seller_id == seller.user.id
      assert auction.status == :open
      assert server_running?(auction.id)
    end

    test "returns a changeset for invalid attributes and starts nothing", %{seller: seller} do
      assert {:error, changeset} =
               Auctions.create_auction(seller, valid_auction_attributes(title: ""))

      assert "can't be blank" in errors_on(changeset).title
      assert DynamicSupervisor.count_children(ServerSupervisor).active == 0
    end
  end

  describe "subscribe_all/0" do
    test "receives every auction's events, from creation to close",
         %{seller: seller, bidder: bidder} do
      :ok = Auctions.subscribe_all()

      auction = live_auction_fixture(seller, ends_at: in_ms(300))
      auction_id = auction.id
      assert_receive {:auction_created, %Auction{id: ^auction_id}}

      {:ok, bid} = Auctions.place_bid(bidder, auction.id, 1_000)
      assert_receive {:bid_placed, ^bid}
      assert_receive {:auction_extended, ^auction_id, _ends_at}

      assert_receive {:auction_closed, %Auction{id: ^auction_id}}, extension_ms() + 1_000
    end
  end

  describe "place_bid/3" do
    test "saves an accepted bid and broadcasts it", %{seller: seller, bidder: bidder} do
      auction = live_auction_fixture(seller)
      :ok = Auctions.subscribe(auction.id)

      assert {:ok, %Bid{} = bid} = Auctions.place_bid(bidder, auction.id, 1_000)

      assert bid.bidder_id == bidder.user.id
      assert_receive {:bid_placed, ^bid}
      assert [%Bid{id: id}] = Auctions.bid_history(auction.id)
      assert id == bid.id
    end

    test "rejects a bid below the minimum without saving or broadcasting it",
         %{seller: seller, bidder: bidder} do
      auction = live_auction_fixture(seller)
      :ok = Auctions.subscribe(auction.id)

      assert {:ok, _} = Auctions.place_bid(bidder, auction.id, 1_000)
      assert_receive {:bid_placed, _}

      assert Auctions.place_bid(user_scope_fixture(), auction.id, 1_050) == {:error, :too_low}
      refute_receive {:bid_placed, _}, 50
      assert [_] = Auctions.bid_history(auction.id)
    end

    test "rejects the seller bidding on their own auction", %{seller: seller} do
      auction = live_auction_fixture(seller)

      assert Auctions.place_bid(seller, auction.id, 5_000) == {:error, :own_auction}
    end

    test "starts a server for an open auction that doesn't have one", %{bidder: bidder} do
      auction = auction_fixture()
      refute Server.whereis(auction.id)

      assert {:ok, _bid} = Auctions.place_bid(bidder, auction.id, 1_000)
      assert server_running?(auction.id)
    end

    test "returns :closed for a closed auction without starting a server", %{bidder: bidder} do
      auction = auction_fixture(status: :closed)

      assert Auctions.place_bid(bidder, auction.id, 5_000) == {:error, :closed}
      refute Server.whereis(auction.id)
    end

    test "returns :not_found for an unknown auction", %{bidder: bidder} do
      assert Auctions.place_bid(bidder, -1, 5_000) == {:error, :not_found}
    end
  end

  describe "ensure_server_started/1" do
    test "returns the running server", %{seller: seller} do
      auction = live_auction_fixture(seller)
      pid = Server.whereis(auction.id)

      assert Auctions.ensure_server_started(auction.id) == {:ok, pid}
    end

    test "starts a server for an open auction" do
      auction = auction_fixture()

      assert {:ok, pid} = Auctions.ensure_server_started(auction.id)
      assert Server.whereis(auction.id) == pid
    end

    test "doesn't start servers for closed or unknown auctions" do
      closed = auction_fixture(status: :closed)

      assert Auctions.ensure_server_started(closed.id) == {:error, :closed}
      assert Auctions.ensure_server_started(-1) == {:error, :not_found}
    end
  end

  describe "ServerSupervisor.start_server/1" do
    test "returns the same server when called twice" do
      auction = auction_fixture()

      assert {:ok, pid} = ServerSupervisor.start_server(auction.id)
      assert ServerSupervisor.start_server(auction.id) == {:ok, pid}
      assert DynamicSupervisor.count_children(ServerSupervisor).active == 1
    end

    test "a server started for a closed or deleted auction stops itself" do
      for auction_id <- [auction_fixture(status: :closed).id, -1] do
        {:ok, pid} = ServerSupervisor.start_server(auction_id)
        ref = Process.monitor(pid)

        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      end

      assert DynamicSupervisor.count_children(ServerSupervisor).active == 0
    end
  end

  describe "closing" do
    test "closes with no winner when nobody bid, and the server stops normally",
         %{seller: seller} do
      auction = live_auction_fixture(seller, ends_at: in_ms(300))
      :ok = Auctions.subscribe(auction.id)

      ref =
        auction.id
        |> Server.whereis()
        |> Process.monitor()

      assert_receive {:auction_closed, %Auction{status: :closed, winning_bid_id: nil}}, 2_000
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
      assert Auctions.get_auction!(auction.id).status == :closed
    end

    test "closes with the top bid as the winner", %{seller: seller, bidder: bidder} do
      auction = live_auction_fixture(seller, ends_at: in_ms(window_ms() + 300))
      :ok = Auctions.subscribe(auction.id)
      {:ok, bid} = Auctions.place_bid(bidder, auction.id, 1_000)

      assert_receive {:auction_closed, %Auction{winning_bid_id: winner_id}}, 3_000
      assert winner_id == bid.id
    end
  end

  describe "anti-sniping" do
    test "a bid inside the window extends the auction and delays the close",
         %{seller: seller, bidder: bidder} do
      original_ends_at = in_ms(300)
      auction = live_auction_fixture(seller, ends_at: original_ends_at)
      :ok = Auctions.subscribe(auction.id)
      auction_id = auction.id

      assert {:ok, _} = Auctions.place_bid(bidder, auction.id, 1_000)

      assert_receive {:auction_extended, ^auction_id, new_ends_at}
      assert DateTime.after?(new_ends_at, original_ends_at)
      assert Auctions.get_auction!(auction.id).ends_at == new_ends_at

      refute_receive {:auction_closed, _}, 400
      assert_receive {:auction_closed, %Auction{}}, extension_ms() + 1_000
    end

    test "a bid outside the window doesn't extend", %{seller: seller, bidder: bidder} do
      auction = live_auction_fixture(seller, ends_at: in_ms(window_ms() + 300))
      assert extension_ms() > window_ms() + 300
      :ok = Auctions.subscribe(auction.id)

      assert {:ok, _} = Auctions.place_bid(bidder, auction.id, 1_000)
      refute_receive {:auction_extended, _, _}, 50
    end
  end

  describe "race_conditions" do
    test "ignores a close message from a timer that has been replaced",
         %{seller: seller, bidder: bidder} do
      auction = live_auction_fixture(seller)
      :ok = Auctions.subscribe(auction.id)
      pid = Server.whereis(auction.id)

      send(pid, {:close, make_ref()})

      assert {:ok, _bid} = Auctions.place_bid(bidder, auction.id, 1_000)
      refute_received {:auction_closed, _}
      assert Server.whereis(auction.id) == pid
    end

    test "a bid that arrives as the server closes gets :closed, never a crash",
         %{bidder: bidder} do
      for _ <- 1..50 do
        auction = auction_fixture(ends_at: DateTime.add(DateTime.utc_now(), -1, :second))
        :ok = Auctions.subscribe(auction.id)

        {:ok, _pid} = ServerSupervisor.start_server(auction.id)
        assert_receive {:auction_closed, %Auction{}}

        assert Auctions.place_bid(bidder, auction.id, 5_000) == {:error, :closed}
      end
    end

    test "a bid sent right after the server crashed goes to the restarted server",
         %{seller: seller, bidder: bidder} do
      supervisor = Process.whereis(ServerSupervisor)

      for _ <- 1..20 do
        auction = live_auction_fixture(seller)

        auction.id
        |> Server.whereis()
        |> wait_until_idle()
        |> Process.exit(:kill)

        assert {:ok, _bid} = Auctions.place_bid(bidder, auction.id, 1_000)
      end

      assert Process.whereis(ServerSupervisor) == supervisor
    end
  end

  describe "concurrency" do
    test "200 simultaneous bids are applied one at a time", %{seller: seller} do
      auction = live_auction_fixture(seller)
      bidders = for _ <- 1..10, do: user_scope_fixture()
      amounts = for i <- 1..200, do: 1_000 + i * 100

      results =
        bidders
        |> Stream.cycle()
        |> Enum.zip(amounts)
        |> Task.async_stream(
          fn {bidder, amount} -> Auctions.place_bid(bidder, auction.id, amount) end,
          max_concurrency: 50,
          ordered: false,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      {accepted, rejected} = Enum.split_with(results, &match?({:ok, _bid}, &1))

      assert Enum.all?(rejected, &(&1 == {:error, :too_low}))

      amounts_in_accepted_order =
        accepted
        |> Enum.map(fn {:ok, bid} -> bid end)
        |> Enum.sort_by(& &1.id)
        |> Enum.map(& &1.amount_cents)

      assert amounts_in_accepted_order == Enum.sort(amounts_in_accepted_order)
      assert amounts_in_accepted_order == Enum.uniq(amounts_in_accepted_order)

      saved_count =
        auction.id
        |> Auctions.bid_history()
        |> length()

      assert saved_count == length(accepted)

      top = List.last(amounts_in_accepted_order)
      assert {:ok, %{top_bid_cents: ^top}} = Auctions.load_state(auction.id)
      [first_bidder | _] = bidders
      assert Auctions.place_bid(first_bidder, auction.id, top) == {:error, :too_low}
    end
  end

  describe "crash recovery" do
    test "a killed server is restarted with the same top bid", %{seller: seller, bidder: bidder} do
      auction = live_auction_fixture(seller)
      {:ok, _} = Auctions.place_bid(bidder, auction.id, 1_500)

      new_pid = kill_and_await_restart(auction.id)

      assert Server.whereis(auction.id) == new_pid
      assert Auctions.place_bid(bidder, auction.id, 1_550) == {:error, :too_low}
      assert {:ok, _} = Auctions.place_bid(bidder, auction.id, 1_600)
    end

    test "a restarted server still closes on time with the right winner",
         %{seller: seller, bidder: bidder} do
      auction = live_auction_fixture(seller, ends_at: in_ms(window_ms() + 500))
      :ok = Auctions.subscribe(auction.id)
      {:ok, bid} = Auctions.place_bid(bidder, auction.id, 1_000)

      kill_and_await_restart(auction.id)

      assert_receive {:auction_closed, %Auction{winning_bid_id: winner_id}}, 3_000
      assert winner_id == bid.id
    end
  end

  defp kill_and_await_restart(auction_id) do
    pid = Server.whereis(auction_id)
    ref = Process.monitor(pid)

    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    assert [{_, new_pid, :worker, [Server]}] = DynamicSupervisor.which_children(ServerSupervisor)
    assert is_pid(new_pid) and new_pid != pid
    new_pid
  end

  defp wait_until_idle(pid) do
    _ = :sys.get_state(pid)
    pid
  end

  defp in_ms(ms), do: DateTime.add(DateTime.utc_now(), ms, :millisecond)

  defp window_ms, do: Application.fetch_env!(:let_it_bid, Auctions)[:anti_snipe_window_ms]

  defp extension_ms, do: Application.fetch_env!(:let_it_bid, Auctions)[:anti_snipe_extension_ms]
end
