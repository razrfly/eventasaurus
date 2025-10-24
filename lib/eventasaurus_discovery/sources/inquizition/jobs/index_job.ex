defmodule EventasaurusDiscovery.Sources.Inquizition.Jobs.IndexJob do
  @moduledoc """
  Processes venues from StoreLocatorWidgets CDN and enqueues detail jobs.

  ## Workflow
  1. Parse stores from CDN response (already fetched by SyncJob)
  2. Extract venue data using VenueExtractor
  3. Generate external_ids for each venue
  4. Filter using EventFreshnessChecker (skip fresh venues within 7 days)
  5. Apply limit if provided (for testing)
  6. Enqueue VenueDetailJob for each venue
  7. VenueDetailJob will process venue/event data with MetricsTracker

  ## Two-Stage Architecture
  Like Speed Quizzing, Inquizition uses detail jobs for better observability:
  - Index parses venue list and filters by freshness
  - Detail jobs process individual venues with metadata tracking
  - VenueDetailJob handles venue geocoding and event transformation
  - EventFreshnessChecker provides 80-90% API call reduction
  - MetricsTracker provides per-venue success/failure tracking

  ## CDN Details
  - Receives pre-fetched stores array from SyncJob
  - GPS coordinates provided directly in CDN response
  - No pagination needed (single request fetches all venues)
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3,
    priority: 1

  require Logger

  alias EventasaurusDiscovery.Sources.Inquizition.{
    Extractors.VenueExtractor
  }

  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Sources.Inquizition

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source_id = args["source_id"]
    stores = args["stores"]
    limit = args["limit"]

    Logger.info("🔄 Processing #{length(stores)} Inquizition venues")

    # Extract venue data from stores
    venues = VenueExtractor.extract_venues(%{"stores" => stores})

    case venues do
      {:error, reason} ->
        Logger.error("❌ Failed to extract venues: #{inspect(reason)}")
        {:error, reason}

      venues when is_list(venues) ->
        if Enum.empty?(venues) do
          Logger.info("✅ No valid venues found in response")
          {:ok, :complete}
        else
          Logger.info("📋 Successfully parsed #{length(venues)} venues")

          # Filter and enqueue detail jobs
          process_venues(venues, source_id, limit)
        end
    end
  end

  # Filter venues by freshness and enqueue detail jobs
  defp process_venues(venues, source_id, limit) do
    # Filter venues using freshness checker
    venues_to_process = filter_fresh_venues(venues, source_id, limit)

    Logger.info("""
    📋 Enqueueing #{length(venues_to_process)} detail jobs
    (#{length(venues) - length(venues_to_process)} venues skipped - recently updated)
    """)

    # Enqueue detail jobs for each venue
    enqueue_detail_jobs(venues_to_process, source_id)
  end

  # CRITICAL: EventFreshnessChecker integration
  defp filter_fresh_venues(venues, source_id, limit) do
    # Generate external_ids for each venue
    venues_with_external_ids =
      Enum.map(venues, fn venue ->
        venue_id = venue.venue_id || venue[:venue_id]
        Map.put(venue, :external_id, "inquizition-#{venue_id}")
      end)

    # Filter out venues that were recently updated (default: 7 days)
    venues_to_process =
      EventFreshnessChecker.filter_events_needing_processing(
        venues_with_external_ids,
        source_id
      )

    # Apply limit if provided (for testing)
    if limit do
      Enum.take(venues_to_process, limit)
    else
      venues_to_process
    end
  end

  # Enqueue a VenueDetailJob for each venue
  defp enqueue_detail_jobs(venues, source_id) do
    jobs =
      Enum.map(venues, fn venue ->
        venue_id = venue.venue_id || venue[:venue_id]

        %{
          "source_id" => source_id,
          "venue_id" => venue_id,
          "venue_data" => venue
        }
        |> Inquizition.Jobs.VenueDetailJob.new()
      end)

    # Insert all jobs
    inserted_jobs = Oban.insert_all(jobs)
    count = length(inserted_jobs)
    Logger.info("✅ Enqueued #{count} detail jobs for Inquizition")
    {:ok, %{detail_jobs_enqueued: count}}
  end
end
