defmodule LetItBid.Repo do
  use Ecto.Repo,
    otp_app: :let_it_bid,
    adapter: Ecto.Adapters.Postgres
end
