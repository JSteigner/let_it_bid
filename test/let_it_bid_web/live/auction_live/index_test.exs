defmodule LetItBidWeb.AuctionLive.IndexTest do
  use LetItBidWeb.ConnCase, async: true

  describe "listing" do
    test "shows open auctions with their current price", %{conn: conn} do
      unbid = auction_fixture(title: "Vintage watch", starting_price_cents: 1_000)
      bid = auction_fixture(title: "Brass lamp", starting_price_cents: 500)
      bid_fixture(bid, amount_cents: 1_550)

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#auctions-#{unbid.id}", "Vintage watch")
      assert has_element?(lv, "#auctions-#{unbid.id}", "$10.00")
      assert has_element?(lv, "#auctions-#{bid.id}", "Brass lamp")
      assert has_element?(lv, "#auctions-#{bid.id}", "$15.50")
    end

    test "labels the price as a starting price or the current bid", %{conn: conn} do
      unbid = auction_fixture()
      bid = auction_fixture()
      bid_fixture(bid)

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#auctions-#{unbid.id}", "starting price")
      assert has_element?(lv, "#auctions-#{bid.id}", "current bid")
    end

    test "names the seller without showing their full email", %{conn: conn} do
      seller = user_fixture(email: "maria.s@example.com")
      {:ok, demo_seller} = LetItBid.Accounts.create_demo_user()
      auction = auction_fixture(seller: seller)
      demo_auction = auction_fixture(seller: demo_seller)

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#auctions-#{auction.id}", "by maria.s")
      refute has_element?(lv, "#auctions-#{auction.id}", "example.com")
      assert has_element?(lv, "#auctions-#{demo_auction.id}", "by Demo user")
    end

    test "leaves out closed auctions", %{conn: conn} do
      closed = auction_fixture(status: :closed)

      {:ok, lv, _html} = live(conn, ~p"/")

      refute has_element?(lv, "#auctions-#{closed.id}")
    end

    test "gives each row a countdown to its end time", %{conn: conn} do
      auction = auction_fixture()

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(
               lv,
               ~s|#auctions-#{auction.id} [phx-hook="Countdown"][data-ends-at="#{DateTime.to_iso8601(auction.ends_at)}"]|
             )
    end

    test "has an empty state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#auctions-empty")
    end
  end

  describe "demo button" do
    test "is offered to logged-out visitors", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#demo-login-form")
    end

    test "isn't shown to logged-in users", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/")

      refute has_element?(lv, "#demo-login-form")
    end
  end
end
