defmodule LetItBid.Auctions.ServerSupervisor do
  @moduledoc """
  Supervises one `LetItBid.Auctions.Server` per open auction.

  Servers are `:transient`: one that crashes is restarted and reloads its
  state from Postgres; one that stops normally (its auction closed) is not.
  """

  use DynamicSupervisor

  alias LetItBid.Auctions.Server

  @doc "Starts the supervisor."
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(arg), do: DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @doc """
  Starts the server for an auction, or returns the one already running.
  """
  @spec start_server(integer()) :: {:ok, pid()}
  def start_server(auction_id) do
    case DynamicSupervisor.start_child(__MODULE__, {Server, auction_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  # The restart limit is shared by every auction. The default (3 in 5s) would
  # let a handful of unrelated crashes take down every auction at once; 50
  # still stops an auction stuck in a crash loop within seconds.
  @impl true
  def init(_arg),
    do: DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 50, max_seconds: 5)
end
