defmodule EventasaurusDiscovery.Sources.Inquizition.Jobs.SyncJob do
  @moduledoc """
  Main orchestration job for Inquizition scraper.

  Responsibilities:
  - Fetch venues from StoreLocatorWidgets CDN
  - Enqueue index job with CDN response
  - Supports limit parameter for testing

  ## Workflow
  1. Fetch venues from StoreLocatorWidgets CDN (no authentication required)
  2. Parse JSONP response and extract stores array
  3. Enqueue IndexJob with venue data
  4. IndexJob handles venue processing and event transformation

  ## CDN Details
  - Endpoint: https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7
  - Public CDN (no auth required)
  - Returns JSONP format (slw({...}))
  - Contains all 143 UK trivia venues
  - Single request fetches all venues (no pagination)
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3,
    priority: 1

  require Logger
  alias EventasaurusDiscovery.Sources.{SourceStore, Inquizition}
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # BaseJob callbacks - not used for CDN-based orchestration
  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # Inquizition uses CDN-based orchestration instead of city-based fetch
    Logger.warning("⚠️ fetch_events called on CDN-based source - not used")
    {:ok, []}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Inquizition transformation happens in detail jobs
    Logger.debug("🔄 transform_events called (not used in orchestration pattern)")
    raw_events
  end

  @doc """
  Source configuration for BaseJob.
  """
  def source_config do
    %{
      name: Inquizition.Source.name(),
      slug: Inquizition.Source.key(),
      website_url: "https://inquizition.com",
      priority: Inquizition.Source.priority(),
      domains: ["trivia", "entertainment"],
      aggregate_on_index: true,
      aggregation_type: "SocialEvent",
      config: %{
        "rate_limit_seconds" => Inquizition.Config.rate_limit(),
        "max_requests_per_hour" => 1800,
        "language" => "en",
        "coverage" => "United Kingdom",
        "data_source" => "StoreLocatorWidgets CDN",
        "cdn_endpoint" =>
          "https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7",
        "discovery_method" => "cdn_orchestration"
      }
    }
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "inquizition_sync_#{Date.utc_today()}"
    Logger.info("🔄 Starting Inquizition sync job")

    limit = args["limit"]
    force = args["force"] || false
    source = SourceStore.get_by_key!(Inquizition.Source.key())

    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    # Fetch venues from StoreLocatorWidgets CDN
    case Inquizition.Client.fetch_venues() do
      {:ok, response} when is_map(response) ->
        Logger.info("✅ Successfully fetched venues from StoreLocatorWidgets CDN")

        case Map.get(response, "stores") do
          stores when is_list(stores) ->
            Logger.info("📋 Found #{length(stores)} venues")

            # Enqueue index job with stores data
            %{
              "source_id" => source.id,
              "stores" => stores,
              "limit" => limit,
              "force" => force
            }
            |> Inquizition.Jobs.IndexPageJob.new()
            |> Oban.insert()
            |> case do
              {:ok, _job} ->
                Logger.info("✅ Enqueued index job for Inquizition")
                MetricsTracker.record_success(job, external_id)
                {:ok, %{source_id: source.id, venues_count: length(stores), limit: limit}}

              {:error, reason} = error ->
                Logger.error("❌ Failed to enqueue index job: #{inspect(reason)}")

                MetricsTracker.record_failure(
                  job,
                  "Failed to enqueue index job: #{inspect(reason)}",
                  external_id
                )

                error
            end

          nil ->
            Logger.error("❌ Invalid CDN response: missing 'stores' key")

            MetricsTracker.record_failure(
              job,
              "Invalid CDN response: missing 'stores' key",
              external_id
            )

            {:error, "Invalid CDN response format - expected {stores: [...]}"}

          _ ->
            Logger.error("❌ Invalid CDN response: 'stores' is not a list")

            MetricsTracker.record_failure(
              job,
              "Invalid CDN response: 'stores' is not a list",
              external_id
            )

            {:error, "Invalid CDN response format - 'stores' must be a list"}
        end

      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch venues from CDN: #{inspect(reason)}")

        MetricsTracker.record_failure(
          job,
          "Failed to fetch venues: #{inspect(reason)}",
          external_id
        )

        error
    end
  end
end
