defmodule Eventasaurus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Create ETS table for venue validation cache
    :ets.new(:venue_cache, [:named_table, :public, read_concurrency: true])

    # Add Sentry logger handler for capturing crash reports
    :logger.add_handler(:my_sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

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

        _ ->
          :ok
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

    # Seed the random number generator for this process
    # This ensures non-deterministic behavior for things like job scheduling jitter
    :rand.seed(:exsss, {System.system_time(), :erlang.phash2(node()), :erlang.unique_integer()})

    children = [
      EventasaurusWeb.Telemetry,
      # Start Ecto repository (used alongside Supabase)
      EventasaurusApp.Repo,
      # Start SessionRepo for Oban, migrations, and advisory locks
      EventasaurusApp.SessionRepo,
      # Start ReplicaRepo for read-heavy queries (connects to PlanetScale replicas)
      # Only started in production - dev/test use primary via Repo.replica() helper
      EventasaurusApp.ReplicaRepo,
      {DNSCluster, query: Application.get_env(:eventasaurus, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Eventasaurus.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Eventasaurus.Finch},
      # Start TzWorld backend for timezone lookups
      TzWorld.Backend.Memory,
      # Start Hammer rate limiter for geocoding providers
      EventasaurusDiscovery.Geocoding.RateLimiter,
      # Start Oban background job processor
      {Oban, Application.fetch_env!(:eventasaurus, Oban)},
      # Add a Task Supervisor for background jobs
      {Task.Supervisor, name: Eventasaurus.TaskSupervisor},
      # Start PostHog analytics service
      Eventasaurus.Services.PosthogService,
      # Start PostHog monitoring service
      Eventasaurus.Services.PosthogMonitor,
      # Start Stripe Currency Service for caching supported currencies
      EventasaurusWeb.Services.StripeCurrencyService,
      # Start TMDB Service for movie/TV data caching
      EventasaurusWeb.Services.TmdbService,
      # Start Spotify Service for music data
      EventasaurusWeb.Services.SpotifyService,
      # Start CocktailDB Service for cocktail data
      EventasaurusWeb.Services.CocktailDbService,
      # Start Rich Data Manager for external API providers
      EventasaurusWeb.Services.RichDataManager,
      # Start Broadcast Throttler for real-time poll updates
      EventasaurusWeb.Services.BroadcastThrottler,
      # Start Poll Stats Cache for performance optimization
      EventasaurusApp.Events.PollStatsCache,
      # Start Discovery Stats Cache for admin page performance optimization
      EventasaurusDiscovery.Admin.DiscoveryStatsCache,
      # Start City Page Cache for city page performance optimization
      EventasaurusWeb.Cache.CityPageCache,
      # Start Event Page Cache for event page performance optimization
      EventasaurusWeb.Cache.EventPageCache,
      # Start Dashboard Stats Cache for admin dashboard performance
      {Cachex, name: :dashboard_stats},
      # Start City Gallery Cache for Unsplash fallback image lookups
      EventasaurusApp.Cache.CityGalleryCache,
      # Start City Fallback Image Cache for pre-computed fallback images
      EventasaurusApp.Cache.CityFallbackImageCache,
      # Start a worker by calling: Eventasaurus.Worker.start_link(arg)
      # {Eventasaurus.Worker, arg},
      # Start to serve requests, typically the last entry
      EventasaurusWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eventasaurus.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Initialize venue source cache after repo is started
        EventasaurusApp.Venues.VenueSourceCache.init()

        # Attach Oban telemetry handler for job-level failure tracking
        attach_oban_telemetry()

        {:ok, pid}

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EventasaurusWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Attach telemetry handlers for comprehensive monitoring
  defp attach_oban_telemetry do
    # Attach comprehensive telemetry for all job events (start, stop, exception)
    EventasaurusApp.Monitoring.ObanTelemetry.attach()

    # Attach HTTP client telemetry for request monitoring
    EventasaurusDiscovery.Http.Telemetry.attach()

    # Also attach scraper-specific telemetry for backward compatibility
    :telemetry.attach(
      "oban-job-exception-logger",
      [:oban, :job, :exception],
      &handle_oban_exception/4,
      nil
    )
  end

  # Handle Oban job exceptions and log to scraper_processing_logs
  defp handle_oban_exception(_event_name, _measurements, metadata, _config) do
    %{job: job, reason: reason, stacktrace: _stacktrace} = metadata

    # Only log scraper jobs (jobs with source_id in args)
    if is_scraper_job?(job) do
      log_job_failure(job, reason)
    end
  end

  # Check if this is a scraper job by looking for source_id in args
  defp is_scraper_job?(%Oban.Job{args: args}) do
    Map.has_key?(args, "source_id")
  end

  # Log job-level failure to scraper_processing_logs
  defp log_job_failure(%Oban.Job{id: job_id, args: args, worker: worker}, reason) do
    source_id = args["source_id"]

    # Get source struct from database
    case EventasaurusApp.Repo.get(EventasaurusDiscovery.Sources.Source, source_id) do
      nil ->
        Logger.warning(
          "Cannot log job failure: Source ID #{source_id} not found (Job: #{worker})"
        )

      source ->
        # Extract metadata from job args for context
        metadata = extract_job_metadata(args, worker)

        # Add phase information to distinguish scraping vs processing failures
        metadata_with_phase = Map.put(metadata, "phase", "scraping")

        # Log the failure with error handling
        case EventasaurusDiscovery.ScraperProcessingLogs.log_failure(
               source,
               job_id,
               reason,
               metadata_with_phase
             ) do
          {:ok, _log} ->
            Logger.info(
              "📝 Logged job-level failure for #{source.name} (Job ID: #{job_id}, Phase: scraping)"
            )

          {:error, changeset} ->
            Logger.error(
              "Failed to persist job-level failure for #{source.name} (Job ID: #{job_id}): #{inspect(changeset.errors)}"
            )
        end
    end
  rescue
    error ->
      Logger.error("Failed to log Oban job failure: #{inspect(error)}")
  end

  # Extract relevant metadata from job args for logging context
  defp extract_job_metadata(args, worker) do
    metadata = %{
      "entity_type" => "job",
      "worker" => worker
    }

    # Add context-specific fields based on what's available in args
    metadata
    |> add_if_present(args, "venue_url", "venue_url")
    |> add_if_present(args, "venue_title", "venue_title")
    |> add_if_present(args, "city_id", "city_id")
    |> add_if_present(args, "event_url", "event_url")
    |> add_if_present(args, "external_id", "external_id")
  end

  defp add_if_present(metadata, args, key, metadata_key) do
    case Map.get(args, key) do
      nil -> metadata
      value -> Map.put(metadata, metadata_key, value)
    end
  end
end
