defmodule LetItBid.Auctions.BidTest do
  use LetItBid.DataCase, async: true

  alias LetItBid.Auctions.Bid

  describe "changeset/2" do
    test "is valid with a positive amount" do
      assert Bid.changeset(%Bid{auction_id: 1, bidder_id: 2}, %{amount_cents: 1_000}).valid?
    end

    test "requires a positive amount" do
      assert %{amount_cents: ["can't be blank"]} =
               %Bid{}
               |> Bid.changeset(%{})
               |> errors_on()

      assert %{amount_cents: ["must be greater than 0"]} =
               %Bid{}
               |> Bid.changeset(%{amount_cents: 0})
               |> errors_on()
    end

    test "doesn't cast the auction or bidder" do
      changeset = Bid.changeset(%Bid{}, %{amount_cents: 1_000, auction_id: 1, bidder_id: 2})

      refute Map.has_key?(changeset.changes, :auction_id)
      refute Map.has_key?(changeset.changes, :bidder_id)
    end
  end
end
