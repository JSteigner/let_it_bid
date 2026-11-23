defmodule LetItBid.Repo.Migrations.CreateBids do
  use Ecto.Migration

  def change do
    create table(:bids) do
      add :amount_cents, :integer, null: false
      add :auction_id, references(:auctions, on_delete: :delete_all), null: false
      add :bidder_id, references(:users, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:bids, [:auction_id, "amount_cents DESC"])
    create index(:bids, [:bidder_id])

    create constraint(:bids, :amount_positive, check: "amount_cents > 0")

    alter table(:auctions) do
      add :winning_bid_id, references(:bids, on_delete: :nilify_all)
    end

    create index(:auctions, [:winning_bid_id])
  end
end
