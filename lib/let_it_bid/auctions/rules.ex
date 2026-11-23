defmodule LetItBid.Auctions.Rules do
  @moduledoc """
  The bidding rules, as pure functions.

  No processes, no database: the auction server passes in its current state
  and the time, and acts on the answer. That keeps every rule testable on
  its own.
  """

  @type state :: %{
          required(:status) => :open | :closed,
          required(:seller_id) => integer(),
          required(:starting_price_cents) => pos_integer(),
          required(:min_increment_cents) => pos_integer(),
          required(:ends_at) => DateTime.t(),
          required(:top_bid_cents) => pos_integer() | nil,
          optional(atom()) => any()
        }

  @type rejection :: :closed | :own_auction | :too_low

  @doc """
  The lowest amount the next bid can be: the starting price when there are
  no bids, otherwise the top bid plus the minimum increment.
  """
  @spec minimum_next_bid(state()) :: pos_integer()
  def minimum_next_bid(%{top_bid_cents: nil, starting_price_cents: starting_price}),
    do: starting_price

  def minimum_next_bid(%{top_bid_cents: top_bid, min_increment_cents: increment}),
    do: top_bid + increment

  @doc """
  Checks whether `bidder_id` may bid `amount_cents` at time `now`.

  Problems are reported in this order: the auction is closed (or past
  `ends_at`), the bidder is the seller, the amount is too low.
  """
  @spec validate_bid(state(), integer(), integer(), DateTime.t()) :: :ok | {:error, rejection()}
  def validate_bid(state, bidder_id, amount_cents, now) do
    cond do
      closed?(state, now) -> {:error, :closed}
      bidder_id == state.seller_id -> {:error, :own_auction}
      amount_cents < minimum_next_bid(state) -> {:error, :too_low}
      true -> :ok
    end
  end

  @doc """
  Anti-sniping: a bid placed less than `window_ms` before `ends_at` pushes
  the end back to `now + extension_ms`. The end never moves earlier.
  """
  @spec maybe_extend(DateTime.t(), DateTime.t(), non_neg_integer(), non_neg_integer()) ::
          {:extended, DateTime.t()} | :unchanged
  def maybe_extend(ends_at, now, window_ms, extension_ms) do
    extended = DateTime.add(now, extension_ms, :millisecond)

    if DateTime.diff(ends_at, now, :millisecond) < window_ms and
         DateTime.after?(extended, ends_at) do
      {:extended, extended}
    else
      :unchanged
    end
  end

  defp closed?(%{status: :closed}, _now), do: true
  defp closed?(%{ends_at: ends_at}, now), do: not DateTime.before?(now, ends_at)
end
