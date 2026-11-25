defmodule LetItBid.AuctionsTest do
  use LetItBid.DataCase, async: true

  alias LetItBid.Auctions
  alias LetItBid.Auctions.Auction

  describe "get_auction!/1" do
    test "returns the auction" do
      %{id: id} = auction_fixture()
      assert %Auction{id: ^id} = Auctions.get_auction!(id)
    end

    test "raises for an unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Auctions.get_auction!(-1) end
    end
  end

  describe "list_open_auctions/0" do
    test "returns open auctions, ending soonest first, with the seller loaded" do
      later = auction_fixture(ends_at: DateTime.add(DateTime.utc_now(), 2, :hour))
      sooner = auction_fixture(ends_at: DateTime.add(DateTime.utc_now(), 1, :hour))
      _closed = auction_fixture(status: :closed)

      assert [first, second] = Auctions.list_open_auctions()
      assert [first.id, second.id] == [sooner.id, later.id]
      assert first.seller.email
    end
  end

  describe "bid_history/1" do
    test "returns the auction's bids, highest first, with the bidder loaded" do
      auction = auction_fixture()
      low = bid_fixture(auction, amount_cents: 1_000)
      high = bid_fixture(auction, amount_cents: 1_200)
      _other_auction_bid = bid_fixture(auction_fixture())

      assert [first, second] = Auctions.bid_history(auction.id)
      assert [first.id, second.id] == [high.id, low.id]
      assert first.bidder.email
    end
  end

  describe "subscribe/1" do
    test "receives messages broadcast on the auction's topic" do
      :ok = Auctions.subscribe(42)
      Phoenix.PubSub.broadcast(LetItBid.PubSub, Auctions.topic(42), :hello)

      assert_receive :hello
    end

    test "topics are per auction" do
      refute Auctions.topic(1) == Auctions.topic(2)
    end
  end

  describe "broadcast/2" do
    test "reaches subscribers of that auction" do
      :ok = Auctions.subscribe(42)
      :ok = Auctions.broadcast(42, :hello)

      assert_receive :hello
    end

    test "doesn't reach subscribers of a different auction" do
      :ok = Auctions.subscribe(43)
      :ok = Auctions.broadcast(42, :hello)

      refute_receive :hello, 50
    end
  end

  describe "load_state/1" do
    test "returns the state the auction server needs" do
      auction = auction_fixture(starting_price_cents: 500, min_increment_cents: 50)

      assert {:ok, state} = Auctions.load_state(auction.id)

      assert state == %{
               id: auction.id,
               status: :open,
               seller_id: auction.seller_id,
               starting_price_cents: 500,
               min_increment_cents: 50,
               ends_at: auction.ends_at,
               top_bid_id: nil,
               top_bid_cents: nil
             }
    end

    test "includes the highest bid" do
      auction = auction_fixture()
      bid_fixture(auction, amount_cents: 1_000)
      top = bid_fixture(auction, amount_cents: 1_500)

      assert {:ok, %{top_bid_id: top_id, top_bid_cents: 1_500}} = Auctions.load_state(auction.id)
      assert top_id == top.id
    end

    test "returns :not_found for an unknown auction" do
      assert Auctions.load_state(-1) == {:error, :not_found}
    end
  end

  describe "insert_bid/3" do
    test "saves the bid" do
      auction = auction_fixture()
      bidder = user_fixture()

      assert {:ok, bid} = Auctions.insert_bid(auction.id, bidder.id, 1_000)
      assert bid.amount_cents == 1_000
      assert bid.bidder_id == bidder.id
      assert [_] = Auctions.bid_history(auction.id)
    end

    test "returns a changeset for an invalid amount" do
      auction = auction_fixture()

      assert {:error, changeset} = Auctions.insert_bid(auction.id, user_fixture().id, 0)
      assert "must be greater than 0" in errors_on(changeset).amount_cents
    end
  end

  describe "extend/2" do
    test "saves the new end time" do
      auction = auction_fixture()
      new_ends_at = DateTime.add(auction.ends_at, 30, :second)

      assert :ok = Auctions.extend(auction.id, new_ends_at)
      assert Auctions.get_auction!(auction.id).ends_at == new_ends_at
    end
  end

  describe "close/2" do
    test "marks the auction closed with the winning bid" do
      auction = auction_fixture()
      bid = bid_fixture(auction)

      assert {:ok, closed} = Auctions.close(auction.id, bid.id)
      assert closed.status == :closed
      assert closed.winning_bid_id == bid.id
    end

    test "closes an auction with no bids and no winner" do
      auction = auction_fixture()

      assert {:ok, %Auction{status: :closed, winning_bid_id: nil}} =
               Auctions.close(auction.id, nil)
    end
  end
end
