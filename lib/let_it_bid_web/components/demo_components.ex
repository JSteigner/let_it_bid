defmodule LetItBidWeb.DemoComponents do
  @moduledoc """
  Components for trying the app without a real account.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: LetItBidWeb.Endpoint,
    router: LetItBidWeb.Router,
    statics: LetItBidWeb.static_paths()

  @doc """
  A button that creates a fresh demo user and logs them in, skipping the
  magic-link email.
  """
  @spec demo_login_button(map()) :: Phoenix.LiveView.Rendered.t()
  attr :class, :any, default: "btn btn-soft btn-primary w-full"

  def demo_login_button(assigns) do
    ~H"""
    <.form for={%{}} as={:demo} id="demo-login-form" action={~p"/users/demo"} method="post">
      <button type="submit" class={@class}>Try it as a demo user</button>
    </.form>
    """
  end
end
