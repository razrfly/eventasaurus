defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob do
  @moduledoc """
  Main orchestration job for Geeks Who Drink scraper.

  Responsibilities:
  - Enqueue index job with US map bounds
  - Supports limit parameter for testing

  ## Workflow
  1. Enqueue IndexJob with map bounds
  2. IndexJob fetches fresh nonce (WordPress nonces expire in 12-24 hours)
  3. IndexJob handles venue discovery and schedules detail jobs

  Note: IndexJob fetches its own fresh nonce to avoid stale nonce issues
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3,
    priority: 1

  require Logger
  alias EventasaurusDiscovery.Sources.{SourceStore, GeeksWhoDrink}
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # BaseJob callbacks - not used for map-based orchestration
  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # Geeks Who Drink uses map-based orchestration instead of city-based fetch
    Logger.warning("⚠️ fetch_events called on map-based source - not used")
    {:ok, []}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Geeks Who Drink transformation happens in detail jobs
    Logger.debug("🔄 transform_events called (not used in orchestration pattern)")
    raw_events
  end

  @doc """
  Source configuration for BaseJob.
  """
  def source_config do
    %{
      name: GeeksWhoDrink.Source.name(),
      slug: GeeksWhoDrink.Source.key(),
      website_url: "https://www.geekswhodrink.com",
      priority: GeeksWhoDrink.Source.priority(),
      config: %{
        "rate_limit_seconds" => GeeksWhoDrink.Config.rate_limit(),
        "max_requests_per_hour" => 1800,
        "language" => "en",
        "coverage" => "United States",
        "api_type" => "wordpress_map",
        "requires_nonce" => true,
        "discovery_method" => "map_orchestration"
      }
    }
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "geeks_who_drink_sync_#{Date.utc_today()}"
    Logger.info("🔄 Starting Geeks Who Drink sync job")

    limit = args["limit"]
    force = args["force"] || false
    source = SourceStore.get_by_key!(GeeksWhoDrink.Source.key())

    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    # Enqueue index job with US bounds
    # Note: IndexJob fetches its own fresh nonce to avoid expiration issues
    %{
      "source_id" => source.id,
      "bounds" => GeeksWhoDrink.Config.us_bounds(),
      "limit" => limit,
      "force" => force
    }
    |> GeeksWhoDrink.Jobs.IndexPageJob.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.info("✅ Enqueued index job for Geeks Who Drink")
        MetricsTracker.record_success(job, external_id)
        {:ok, %{source_id: source.id, limit: limit}}

      {:error, reason} = error ->
        Logger.error("❌ Failed to enqueue index job: #{inspect(reason)}")

        MetricsTracker.record_failure(
          job,
          "Failed to enqueue index job: #{inspect(reason)}",
          external_id
        )

        error
    end
  end
end
