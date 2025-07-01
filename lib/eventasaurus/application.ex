defmodule Eventasaurus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Load environment variables from .env file if in dev/test environment
    env = Application.get_env(:eventasaurus, :environment, :prod)
    if env in [:dev, :test] do
      # Simple approach to load .env file
      case File.read(Path.expand(".env")) do
        {:ok, body} ->
          body
          |> String.split("\n")
          |> Enum.each(fn line ->
            if String.contains?(line, "=") do
              [key, value] = String.split(line, "=", parts: 2)
              System.put_env(String.trim(key), String.trim(value))
            end
          end)
        _ -> :ok
      end
    end

    # Debug Google Maps API key
    api_key = System.get_env("GOOGLE_MAPS_API_KEY")
    IO.puts("DEBUG - Google Maps API key loaded: #{if api_key, do: "YES", else: "NO"}")

    # Debug Stripe environment variables (dev/test only)
    if env in [:dev, :test] do
      stripe_client_id = System.get_env("STRIPE_CLIENT_ID")
      stripe_secret = System.get_env("STRIPE_SECRET_KEY")
      IO.puts("DEBUG - Stripe Client ID loaded: #{if stripe_client_id, do: "YES", else: "NO"}")
      IO.puts("DEBUG - Stripe Secret Key loaded: #{if stripe_secret, do: "YES", else: "NO"}")
    end

    # Debug Supabase connection
    db_config = Application.get_env(:eventasaurus, EventasaurusApp.Repo)
    IO.puts("DEBUG - Database Connection Info:")
    IO.puts("  Hostname: #{db_config[:hostname]}")
    IO.puts("  Port: #{db_config[:port]}")
    IO.puts("  Database: #{db_config[:database]}")
    IO.puts("  Username: #{db_config[:username]}")
    IO.puts("DEBUG - Using Supabase PostgreSQL: #{db_config[:port] == 54322}")

    children = [
      EventasaurusWeb.Telemetry,
      # Start Ecto repository (used alongside Supabase)
      EventasaurusApp.Repo,
      {DNSCluster, query: Application.get_env(:eventasaurus, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Eventasaurus.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Eventasaurus.Finch},
      # Add a Task Supervisor for background jobs
      {Task.Supervisor, name: Eventasaurus.TaskSupervisor},
      # Start PostHog analytics service
      Eventasaurus.Services.PosthogService,
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
