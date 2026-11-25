defmodule LetItBidWeb.AuctionComponents do
  @moduledoc """
  Components for showing auctions: a list row and a live countdown.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered

  alias LetItBid.Auctions.Auction
  alias LetItBidWeb.Format

  @doc """
  One auction in a list: title, seller, current (or starting) price, and a
  countdown to its end. Expects an auction from `Auctions.list_open_auctions/0`
  or `Auctions.get_listing!/1`, with the seller and `top_bid_cents` loaded.
  """
  @spec auction_row(map()) :: Rendered.t()
  attr :id, :string, required: true
  attr :auction, Auction, required: true

  def auction_row(assigns) do
    ~H"""
    <div id={@id} class="flex items-center justify-between gap-4 py-4">
      <div class="min-w-0">
        <p class="truncate font-semibold">{@auction.title}</p>
        <p class="text-sm text-base-content/60">by {seller_name(@auction.seller)}</p>
      </div>
      <div class="shrink-0 text-right">
        <p class="font-semibold tabular-nums">{Format.money(current_price(@auction))}</p>
        <p class="text-xs text-base-content/60">{price_label(@auction)}</p>
        <.countdown id={"#{@id}-countdown"} ends_at={@auction.ends_at} class="text-sm" />
      </div>
    </div>
    """
  end

  @doc """
  Counts down to `ends_at` in the browser through the `Countdown` hook
  (`assets/js/hooks/countdown.js`), with no server ticks. When the server
  sends a new `ends_at` (an anti-snipe extension), the countdown follows it.
  """
  @spec countdown(map()) :: Rendered.t()
  attr :id, :string, required: true
  attr :ends_at, DateTime, required: true
  attr :class, :any, default: nil

  def countdown(assigns) do
    ~H"""
    <p
      id={@id}
      class={["tabular-nums", @class]}
      phx-hook="Countdown"
      phx-update="ignore"
      data-ends-at={DateTime.to_iso8601(@ends_at)}
    >
    </p>
    """
  end

  defp current_price(%{top_bid_cents: nil, starting_price_cents: starting_price}),
    do: starting_price

  defp current_price(%{top_bid_cents: top_bid}), do: top_bid

  defp price_label(%{top_bid_cents: nil}), do: "starting price"
  defp price_label(_auction), do: "current bid"

  defp seller_name(%{demo: true}), do: "Demo user"

  defp seller_name(%{email: email}) do
    email
    |> String.split("@")
    |> hd()
  end
end
