defmodule LetItBidWeb.PageController do
  @moduledoc """
  Static pages (currently just the home page).
  """

  use LetItBidWeb, :controller

  alias Plug.Conn

  @doc "Renders the home page."
  @spec home(Conn.t(), map()) :: Conn.t()
  def home(conn, _params) do
    render(conn, :home)
  end
end
