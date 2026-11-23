defmodule LetItBid.Auctions.Rehydrator do
  @moduledoc """
  Runs once at boot and starts a server for every open auction, so a deploy
  or a node restart doesn't leave auctions without one. Each server reloads
  its state from Postgres; an auction that ended while the node was down
  closes right away.

  Turned off in tests with `config :let_it_bid, start_rehydrator: false`.
  """

  use Task, restart: :transient

  alias LetItBid.Auctions

  @doc """
  Starts the task as part of the supervision tree, or returns `:ignore`
  when `start_rehydrator` is off.
  """
  @spec start_link(term()) :: {:ok, pid()} | :ignore
  def start_link(_arg) do
    if Application.get_env(:let_it_bid, :start_rehydrator, true) do
      Task.start_link(&run/0)
    else
      :ignore
    end
  end

  @doc "Starts a server for every open auction."
  @spec run() :: :ok
  def run do
    for auction <- Auctions.list_open_auctions() do
      {:ok, _pid} = Auctions.ensure_server_started(auction.id)
    end

    :ok
  end
end
