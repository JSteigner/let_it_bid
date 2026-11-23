defmodule LetItBid.Auctions.RulesTest do
  use ExUnit.Case, async: true

  alias LetItBid.Auctions.Rules

  @now ~U[2026-11-17 12:00:00.000000Z]
  @seller_id 1
  @bidder_id 2

  describe "minimum_next_bid/1" do
    test "is the starting price when there are no bids" do
      assert Rules.minimum_next_bid(state()) == 1_000
    end

    test "is the top bid plus the minimum increment once someone has bid" do
      assert Rules.minimum_next_bid(state(top_bid_cents: 1_500)) == 1_600
    end
  end

  describe "validate_bid/4" do
    test "accepts the starting price as the first bid" do
      assert Rules.validate_bid(state(), @bidder_id, 1_000, @now) == :ok
    end

    test "accepts a bid of exactly the top bid plus the increment" do
      assert Rules.validate_bid(state(top_bid_cents: 1_500), @bidder_id, 1_600, @now) == :ok
    end

    test "rejects a first bid below the starting price" do
      assert Rules.validate_bid(state(), @bidder_id, 999, @now) == {:error, :too_low}
    end

    test "rejects a bid below the top bid plus the increment" do
      assert Rules.validate_bid(state(top_bid_cents: 1_500), @bidder_id, 1_599, @now) ==
               {:error, :too_low}
    end

    test "rejects the seller bidding on their own auction" do
      assert Rules.validate_bid(state(), @seller_id, 5_000, @now) == {:error, :own_auction}
    end

    test "rejects bids on a closed auction" do
      assert Rules.validate_bid(state(status: :closed), @bidder_id, 5_000, @now) ==
               {:error, :closed}
    end

    test "rejects bids at or after ends_at, even before the close timer fires" do
      assert Rules.validate_bid(state(ends_at: @now), @bidder_id, 5_000, @now) ==
               {:error, :closed}
    end

    test "reports :closed before other problems" do
      assert Rules.validate_bid(state(status: :closed), @seller_id, 1, @now) == {:error, :closed}
    end
  end

  describe "maybe_extend/4" do
    @window_ms 10_000
    @extension_ms 10_000

    test "leaves ends_at alone when the bid is outside the window" do
      ends_at = DateTime.add(@now, 10_001, :millisecond)
      longer_than_time_left = 60_000

      assert Rules.maybe_extend(ends_at, @now, @window_ms, longer_than_time_left) == :unchanged
    end

    test "moves ends_at to now + extension for a bid inside the window" do
      ends_at = DateTime.add(@now, 3_000, :millisecond)

      assert Rules.maybe_extend(ends_at, @now, @window_ms, @extension_ms) ==
               {:extended, DateTime.add(@now, 10_000, :millisecond)}
    end

    test "never moves ends_at earlier" do
      ends_at = DateTime.add(@now, 5_000, :millisecond)
      assert Rules.maybe_extend(ends_at, @now, @window_ms, 2_000) == :unchanged
    end
  end

  defp state(overrides \\ []) do
    Enum.into(overrides, %{
      status: :open,
      seller_id: @seller_id,
      starting_price_cents: 1_000,
      min_increment_cents: 100,
      ends_at: DateTime.add(@now, 1, :hour),
      top_bid_cents: nil
    })
  end
end
