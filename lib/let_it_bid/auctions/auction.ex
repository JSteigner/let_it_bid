defmodule LetItBid.Auctions.Auction do
  @moduledoc """
  An item up for auction.

  `status` and `winning_bid_id` are set by the auction server, `seller_id`
  by the context; none of them are cast from user input.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Changeset

  alias LetItBid.Accounts.User
  alias LetItBid.Auctions.Bid

  @required_fields ~w[title starting_price_cents min_increment_cents ends_at]a
  @optional_fields ~w[description]a
  @fields @required_fields ++ @optional_fields

  @statuses ~w[open closed]a

  @type status :: :open | :closed

  @type t :: %__MODULE__{
          id: integer() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          starting_price_cents: pos_integer() | nil,
          min_increment_cents: pos_integer() | nil,
          ends_at: DateTime.t() | nil,
          status: status(),
          seller_id: integer() | nil,
          seller: User.t() | Ecto.Association.NotLoaded.t() | nil,
          winning_bid_id: integer() | nil,
          winning_bid: Bid.t() | Ecto.Association.NotLoaded.t() | nil,
          bids: [Bid.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "auctions" do
    field :title, :string
    field :description, :string
    field :starting_price_cents, :integer
    field :min_increment_cents, :integer
    field :ends_at, :utc_datetime_usec
    field :status, Ecto.Enum, values: @statuses, default: :open

    belongs_to :seller, User
    belongs_to :winning_bid, Bid
    has_many :bids, Bid

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for a new auction. `now` is the current time, used to check
  that `ends_at` is in the future.
  """
  @spec create_changeset(t(), map(), DateTime.t()) :: Changeset.t()
  def create_changeset(auction, attrs, now) do
    auction
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 3, max: 80)
    |> validate_number(:starting_price_cents, greater_than: 0)
    |> validate_number(:min_increment_cents, greater_than: 0)
    |> validate_in_future(:ends_at, now)
    |> check_constraint(:starting_price_cents, name: :starting_price_positive)
    |> check_constraint(:min_increment_cents, name: :min_increment_positive)
    |> assoc_constraint(:seller)
  end

  defp validate_in_future(changeset, field, now) do
    validate_change(changeset, field, fn ^field, value ->
      if DateTime.after?(value, now), do: [], else: [{field, "must be in the future"}]
    end)
  end
end
