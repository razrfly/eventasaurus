defmodule Eventasaurus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EventasaurusWeb.Telemetry,
      # Removing Eventasaurus.Repo since we're using Supabase instead
      {DNSCluster, query: Application.get_env(:eventasaurus, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Eventasaurus.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Eventasaurus.Finch},
      # Start a worker by calling: Eventasaurus.Worker.start_link(arg)
      # {Eventasaurus.Worker, arg},
      # Start to serve requests, typically the last entry
      EventasaurusWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eventasaurus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EventasaurusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
