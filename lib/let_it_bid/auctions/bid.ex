defmodule LetItBid.Auctions.Bid do
  @moduledoc """
  A bid on an auction. Bids are only created by the auction server, after
  `LetItBid.Auctions.Rules` has accepted them; `auction_id` and `bidder_id`
  are set by the code, not cast.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias LetItBid.Accounts.User
  alias LetItBid.Auctions.Auction

  @required_fields ~w[amount_cents]a

  @type t :: %__MODULE__{
          id: integer() | nil,
          amount_cents: pos_integer() | nil,
          auction_id: integer() | nil,
          auction: Auction.t() | Ecto.Association.NotLoaded.t() | nil,
          bidder_id: integer() | nil,
          bidder: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "bids" do
    field :amount_cents, :integer

    belongs_to :auction, Auction
    belongs_to :bidder, User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Changeset for a new bid."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(bid, attrs) do
    bid
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:amount_cents, greater_than: 0)
    |> check_constraint(:amount_cents, name: :amount_positive)
    |> assoc_constraint(:auction)
    |> assoc_constraint(:bidder)
  end
end
