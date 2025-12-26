defmodule EventasaurusDiscovery.Sources.Inquizition.Jobs.IndexPageJob do
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
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    source_id = args["source_id"]
    stores = args["stores"]
    limit = args["limit"]
    force = args["force"] || false
    external_id = "inquizition_index_src#{source_id}_#{Date.utc_today()}"

    Logger.info("🔄 Processing #{length(stores)} Inquizition venues")

    # Extract venue data from stores
    venues = VenueExtractor.extract_venues(%{"stores" => stores})

    case venues do
      {:error, reason} ->
        Logger.error("❌ Failed to extract venues: #{inspect(reason)}")

        MetricsTracker.record_failure(
          job,
          "Venue extraction failed: #{inspect(reason)}",
          external_id
        )

        {:error, reason}

      venues when is_list(venues) ->
        if Enum.empty?(venues) do
          Logger.info("✅ No valid venues found in response")
          MetricsTracker.record_success(job, external_id)
          {:ok, :complete}
        else
          Logger.info("📋 Successfully parsed #{length(venues)} venues")

          # Filter and enqueue detail jobs
          {:ok, _result} = success = process_venues(venues, source_id, limit, force)
          MetricsTracker.record_success(job, external_id)
          success
        end
    end
  end

  # Filter venues by freshness and enqueue detail jobs
  defp process_venues(venues, source_id, limit, force) do
    # Filter venues using freshness checker (skip if force=true)
    venues_to_process =
      if force do
        Logger.info(
          "⚡ Force mode enabled - bypassing EventFreshnessChecker for all #{length(venues)} venues"
        )

        # Apply limit but skip freshness filtering
        if limit, do: Enum.take(venues, limit), else: venues
      else
        filter_fresh_venues(venues, source_id, limit)
      end

    skipped_count = length(venues) - length(venues_to_process)

    Logger.info("""
    📋 Enqueueing #{length(venues_to_process)} detail jobs
    #{if force, do: "(Force mode - freshness check bypassed)", else: "(#{skipped_count} venues skipped - recently updated)"}
    """)

    # Enqueue detail jobs for each venue
    enqueue_detail_jobs(venues_to_process, source_id)
  end

  # CRITICAL: EventFreshnessChecker integration
  defp filter_fresh_venues(venues, source_id, limit) do
    # Generate external_ids for each venue using safe access
    # IMPORTANT: Mark as recurring so EventFreshnessChecker bypasses freshness check
    # All Inquizition venues are weekly recurring trivia events
    venues_with_external_ids =
      Enum.map(venues, fn venue ->
        venue_id = Map.get(venue, :venue_id) || Map.get(venue, "venue_id")
        # Skip setting external_id if venue_id is nil
        if venue_id do
          venue
          |> Map.put(:external_id, "inquizition_#{to_string(venue_id)}")
          # Mark as recurring - triggers bypass in EventFreshnessChecker
          # The actual recurrence_rule is added later by Transformer
          |> Map.put(:recurrence_rule, %{"frequency" => "weekly"})
        else
          venue
        end
      end)
      |> Enum.reject(fn venue -> is_nil(Map.get(venue, :external_id)) end)

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
        venue_id = Map.get(venue, :venue_id) || Map.get(venue, "venue_id")

        %{
          "source_id" => source_id,
          "venue_id" => if(venue_id, do: to_string(venue_id), else: nil),
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
