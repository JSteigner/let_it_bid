defmodule LetItBid.Repo.Migrations.CreateAuctions do
  use Ecto.Migration

  def change do
    create table(:auctions) do
      add :title, :string, null: false
      add :description, :text
      add :starting_price_cents, :integer, null: false
      add :min_increment_cents, :integer, null: false
      add :ends_at, :utc_datetime_usec, null: false
      add :status, :string, null: false, default: "open"
      add :seller_id, references(:users, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:auctions, [:seller_id])
    create index(:auctions, [:status])

    create constraint(:auctions, :starting_price_positive, check: "starting_price_cents > 0")
    create constraint(:auctions, :min_increment_positive, check: "min_increment_cents > 0")
  end
end
