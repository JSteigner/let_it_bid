defmodule LetItBid.Auctions.RehydratorTest do
  use LetItBid.DataCase, async: false

  alias LetItBid.Auctions
  alias LetItBid.Auctions.{Auction, Rehydrator, Server}

  setup do
    on_exit(&stop_auction_servers/0)
  end

  describe "start_link/1" do
    test "is ignored when start_rehydrator is off (the test default)" do
      assert Rehydrator.start_link([]) == :ignore
    end

    test "runs at startup when start_rehydrator is on" do
      Application.put_env(:let_it_bid, :start_rehydrator, true)
      on_exit(fn -> Application.put_env(:let_it_bid, :start_rehydrator, false) end)
      auction = auction_fixture()

      pid = start_supervised!(Rehydrator)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      assert server_running?(auction.id)
    end
  end

  describe "run/0" do
    test "starts a server for each open auction" do
      first = auction_fixture()
      second = auction_fixture()

      assert Rehydrator.run() == :ok

      assert server_running?(first.id)
      assert server_running?(second.id)
    end

    test "closes open auctions that ended while no server was running" do
      overdue = auction_fixture(ends_at: DateTime.add(DateTime.utc_now(), -1, :minute))
      winning_bid = bid_fixture(overdue)
      :ok = Auctions.subscribe(overdue.id)

      assert Rehydrator.run() == :ok

      assert_receive {:auction_closed, %Auction{status: :closed, winning_bid_id: winner_id}}
      assert winner_id == winning_bid.id
    end

    test "leaves closed auctions alone" do
      closed = auction_fixture(status: :closed)

      assert Rehydrator.run() == :ok

      refute Server.whereis(closed.id)
    end
  end
end
