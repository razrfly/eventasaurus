defmodule EventasaurusDiscovery.Sources.Quizmeisters.Jobs.SyncJob do
  @moduledoc """
  Main orchestration job for Quizmeisters scraper.

  Responsibilities:
  - Fetch venues from storerocket.io public API
  - Enqueue index job with API response
  - Supports limit parameter for testing

  ## Workflow
  1. Fetch venues from storerocket.io API (no authentication required)
  2. Enqueue IndexJob with venue data
  3. IndexJob handles venue processing and schedules detail jobs

  ## API Details
  - Endpoint: https://storerocket.io/api/user/kDJ3BbK4mn/locations
  - Public API (no auth required)
  - Returns JSON array of venue objects with GPS coordinates
  - Single request fetches all venues (no pagination)
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3,
    priority: 1

  require Logger
  alias EventasaurusDiscovery.Sources.{SourceStore, Quizmeisters}
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "quizmeisters_sync_#{Date.utc_today()}"
    Logger.info("🔄 Starting Quizmeisters sync job")

    limit = args["limit"]
    force = args["force"] || false
    source = SourceStore.get_by_key!(Quizmeisters.Source.key())

    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    # Fetch venues from storerocket.io API
    case Quizmeisters.Client.fetch_locations() do
      {:ok, %{body: body}} ->
        Logger.info("✅ Successfully fetched locations from storerocket.io API")

        case Jason.decode(body) do
          {:ok, %{"results" => %{"locations" => locations}}} when is_list(locations) ->
            Logger.info("📋 Found #{length(locations)} locations")

            # Enqueue index job with locations data
            %{
              "source_id" => source.id,
              "locations" => locations,
              "limit" => limit,
              "force" => force
            }
            |> Quizmeisters.Jobs.IndexJob.new()
            |> Oban.insert()
            |> case do
              {:ok, _job} ->
                Logger.info("✅ Enqueued index job for Quizmeisters")
                MetricsTracker.record_success(job, external_id)
                {:ok, %{source_id: source.id, locations_count: length(locations), limit: limit}}

              {:error, reason} = error ->
                Logger.error("❌ Failed to enqueue index job: #{inspect(reason)}")
                MetricsTracker.record_failure(job, "Failed to enqueue index job: #{inspect(reason)}", external_id)
                error
            end

          {:ok, response} ->
            Logger.error("❌ Invalid API response structure: #{inspect(response)}")
            MetricsTracker.record_failure(job, "Invalid API response format", external_id)
            {:error, "Invalid API response format - expected {results: {locations: [...]}}"}

          {:error, reason} = error ->
            Logger.error("❌ Failed to parse JSON response: #{inspect(reason)}")
            MetricsTracker.record_failure(job, "Failed to parse JSON: #{inspect(reason)}", external_id)
            error
        end

      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch locations from API: #{inspect(reason)}")
        MetricsTracker.record_failure(job, "Failed to fetch locations: #{inspect(reason)}", external_id)
        error
    end
  end
end
