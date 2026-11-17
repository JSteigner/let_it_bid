defmodule LetItBid.Repo do
  @moduledoc """
  The Postgres repository. Only contexts call it.
  """

  use Ecto.Repo,
    otp_app: :let_it_bid,
    adapter: Ecto.Adapters.Postgres
end
