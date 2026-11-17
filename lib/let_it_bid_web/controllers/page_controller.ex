defmodule LetItBidWeb.PageController do
  use LetItBidWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
