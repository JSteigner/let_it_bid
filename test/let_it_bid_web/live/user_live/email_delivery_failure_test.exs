defmodule LetItBidWeb.UserLive.EmailDeliveryFailureTest do
  # Not async: swaps the global mailer adapter. ExUnit runs sync modules
  # after the async ones and one at a time, so no other test sees the swap.
  use LetItBidWeb.ConnCase, async: false

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias LetItBid.FailingMailAdapter
  alias LetItBid.Mailer

  # The user is created first: user_fixture/0 confirms the account through a
  # real magic-link email, which needs the working adapter.
  setup do
    user = user_fixture()

    original = Application.fetch_env!(:let_it_bid, Mailer)
    Application.put_env(:let_it_bid, Mailer, adapter: FailingMailAdapter)
    on_exit(fn -> Application.put_env(:let_it_bid, Mailer, original) end)

    %{user: user}
  end

  describe "magic link login" do
    test "logs the failure but shows the usual message", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {{:ok, lv, _html}, log} =
        with_log(fn ->
          lv
          |> form("#login_form_magic", user: %{email: user.email})
          |> render_submit()
          |> follow_redirect(conn, ~p"/users/log-in")
        end)

      # Same message as success, so the page never reveals which emails exist.
      assert has_element?(lv, "#flash-info", "If your email is in our system")
      refute has_element?(lv, "#flash-error")
      assert log =~ "Failed to send login email"
      assert log =~ "mail_server_unavailable"
    end
  end

  describe "change email" do
    test "shows an error instead of claiming the link was sent", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      {_html, log} =
        with_log(fn ->
          lv
          |> form("#email_form", %{"user" => %{"email" => unique_user_email()}})
          |> render_submit()
        end)

      assert has_element?(lv, "#flash-error", "couldn't send the confirmation email")
      refute has_element?(lv, "#flash-info")
      assert log =~ "Failed to send email change confirmation"
    end
  end
end
