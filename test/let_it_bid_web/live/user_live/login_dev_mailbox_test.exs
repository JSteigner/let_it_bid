defmodule LetItBidWeb.UserLive.LoginDevMailboxTest do
  # Not async: swaps the global mailer adapter. ExUnit runs sync modules
  # after the async ones and one at a time, so no other test sees the swap.
  use LetItBidWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias LetItBid.Mailer

  setup do
    original = Application.fetch_env!(:let_it_bid, Mailer)
    Application.put_env(:let_it_bid, Mailer, adapter: Swoosh.Adapters.Local)
    on_exit(fn -> Application.put_env(:let_it_bid, Mailer, original) end)
  end

  test "links to the dev mailbox when emails are stored locally", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(lv, ~s|a[href="/dev/mailbox"]|)
  end
end
