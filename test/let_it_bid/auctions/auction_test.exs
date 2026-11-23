defmodule LetItBid.Auctions.AuctionTest do
  use LetItBid.DataCase, async: true

  alias LetItBid.Auctions.Auction

  @now ~U[2026-11-17 12:00:00.000000Z]

  describe "create_changeset/3" do
    test "is valid with a title, prices and a future end" do
      changeset = Auction.create_changeset(%Auction{}, valid_attrs(), @now)

      assert changeset.valid?
    end

    test "requires title, prices and ends_at" do
      changeset = Auction.create_changeset(%Auction{}, %{}, @now)

      assert %{
               title: ["can't be blank"],
               starting_price_cents: ["can't be blank"],
               min_increment_cents: ["can't be blank"],
               ends_at: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires positive prices" do
      changeset =
        Auction.create_changeset(
          %Auction{},
          valid_attrs(starting_price_cents: 0, min_increment_cents: -1),
          @now
        )

      assert "must be greater than 0" in errors_on(changeset).starting_price_cents
      assert "must be greater than 0" in errors_on(changeset).min_increment_cents
    end

    test "limits the title to 3 to 80 characters" do
      short = Auction.create_changeset(%Auction{}, valid_attrs(title: "ab"), @now)

      long =
        Auction.create_changeset(%Auction{}, valid_attrs(title: String.duplicate("a", 81)), @now)

      assert "should be at least 3 character(s)" in errors_on(short).title
      assert "should be at most 80 character(s)" in errors_on(long).title
    end

    test "requires ends_at to be in the future" do
      changeset = Auction.create_changeset(%Auction{}, valid_attrs(ends_at: @now), @now)

      assert "must be in the future" in errors_on(changeset).ends_at
    end

    test "doesn't cast fields set by the code" do
      changeset =
        Auction.create_changeset(
          %Auction{},
          valid_attrs(seller_id: 99, status: :closed, winning_bid_id: 5),
          @now
        )

      refute Map.has_key?(changeset.changes, :seller_id)
      refute Map.has_key?(changeset.changes, :status)
      refute Map.has_key?(changeset.changes, :winning_bid_id)
    end
  end

  defp valid_attrs(overrides \\ []) do
    Enum.into(overrides, %{
      title: "Vintage watch",
      description: "Still ticks.",
      starting_price_cents: 1_000,
      min_increment_cents: 100,
      ends_at: DateTime.add(@now, 1, :hour)
    })
  end
end
