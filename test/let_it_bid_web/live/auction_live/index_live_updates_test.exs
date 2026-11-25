defmodule LetItBidWeb.AuctionLive.IndexLiveUpdatesTest do
  # Not async: these tests start auction servers, which need the shared sandbox.
  use LetItBidWeb.ConnCase, async: false

  alias LetItBid.Auctions

  setup do
    on_exit(&stop_auction_servers/0)

    %{seller: user_scope_fixture(), bidder: user_scope_fixture()}
  end

  test "a bid updates the auction's price", %{conn: conn, seller: seller, bidder: bidder} do
    auction = live_auction_fixture(seller, starting_price_cents: 1_000)
    {:ok, lv, _html} = live(conn, ~p"/")

    {:ok, _bid} = Auctions.place_bid(bidder, auction.id, 2_500)

    assert has_element?(lv, "#auctions-#{auction.id}", "$25.00")
  end

  test "an extension updates the countdown's end time",
       %{conn: conn, seller: seller, bidder: bidder} do
    auction = live_auction_fixture(seller, ends_at: in_ms(300))
    :ok = Auctions.subscribe(auction.id)
    {:ok, lv, _html} = live(conn, ~p"/")

    {:ok, _bid} = Auctions.place_bid(bidder, auction.id, 1_000)
    auction_id = auction.id
    assert_receive {:auction_extended, ^auction_id, new_ends_at}

    assert has_element?(
             lv,
             ~s|#auctions-#{auction.id} [data-ends-at="#{DateTime.to_iso8601(new_ends_at)}"]|
           )
  end

  test "a new auction appears", %{conn: conn, seller: seller} do
    {:ok, lv, _html} = live(conn, ~p"/")

    auction = live_auction_fixture(seller, title: "Fresh listing")

    assert has_element?(lv, "#auctions-#{auction.id}", "Fresh listing")
  end

  test "a closed auction disappears", %{conn: conn, seller: seller} do
    auction = live_auction_fixture(seller, ends_at: in_ms(300))
    :ok = Auctions.subscribe(auction.id)
    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, "#auctions-#{auction.id}")

    assert_receive {:auction_closed, _auction}, 2_000

    refute has_element?(lv, "#auctions-#{auction.id}")
  end

  defp in_ms(ms), do: DateTime.add(DateTime.utc_now(), ms, :millisecond)
end
