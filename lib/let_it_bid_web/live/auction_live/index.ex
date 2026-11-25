defmodule LetItBidWeb.AuctionLive.Index do
  @moduledoc """
  The home page: open auctions, ending soonest first, kept up to date live.
  The markup is in `index.html.heex` and `LetItBidWeb.AuctionComponents`.
  """

  use LetItBidWeb, :live_view

  alias LetItBid.Auctions

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :ok = Auctions.subscribe_all()

    {:ok, stream(socket, :auctions, Auctions.list_open_auctions())}
  end

  @impl true
  def handle_info({:bid_placed, bid}, socket), do: {:noreply, refresh_row(socket, bid.auction_id)}

  def handle_info({:auction_extended, auction_id, _ends_at}, socket),
    do: {:noreply, refresh_row(socket, auction_id)}

  def handle_info({event, _auction}, socket) when event in [:auction_created, :auction_closed],
    do: {:noreply, stream(socket, :auctions, Auctions.list_open_auctions(), reset: true)}

  defp refresh_row(socket, auction_id),
    do: stream_insert(socket, :auctions, Auctions.get_listing!(auction_id))
end
