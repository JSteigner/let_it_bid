defmodule LetItBid.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LetItBidWeb.Telemetry,
      LetItBid.Repo,
      {DNSCluster, query: Application.get_env(:let_it_bid, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LetItBid.PubSub},
      # Auction servers need Repo and PubSub; the Endpoint needs them running
      # before it takes requests.
      {Registry, keys: :unique, name: LetItBid.Auctions.Registry},
      LetItBid.Auctions.ServerSupervisor,
      # Needs the Registry and ServerSupervisor; runs before the Endpoint so
      # open auctions have servers before requests arrive.
      LetItBid.Auctions.Rehydrator,
      # Start to serve requests, typically the last entry
      LetItBidWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LetItBid.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LetItBidWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
