defmodule EventasaurusDiscovery.Sources.Quizmeisters.Jobs.IndexJob do
  @moduledoc """
  Processes venues from storerocket.io API and schedules detail jobs.

  CRITICAL: Uses EventFreshnessChecker to avoid re-scraping fresh venues.

  ## Workflow
  1. Parse locations from API response (already fetched by SyncJob)
  2. Extract venue data using VenueExtractor
  3. Generate external_ids for venues
  4. Filter using EventFreshnessChecker (skip fresh venues within 7 days)
  5. Schedule detail jobs for stale venues only

  ## API Details
  - Receives pre-fetched locations array from SyncJob
  - GPS coordinates provided directly in API response
  - No pagination needed (single request fetches all venues)
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3,
    priority: 1

  require Logger

  alias EventasaurusDiscovery.Sources.Quizmeisters.{
    Extractors.VenueExtractor,
    Jobs.VenueDetailJob
  }

  alias EventasaurusDiscovery.Services.EventFreshnessChecker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source_id = args["source_id"]
    locations = args["locations"]
    limit = args["limit"]

    Logger.info("🔄 Processing #{length(locations)} Quizmeisters locations")

    venues = parse_venues(locations)

    if Enum.empty?(venues) do
      Logger.info("✅ No valid venues found in response")
      {:ok, :complete}
    else
      Logger.info("📋 Successfully parsed #{length(venues)} venues")

      # CRITICAL: EventFreshnessChecker filters out fresh venues
      scheduled_count = schedule_detail_jobs(venues, source_id, limit)

      Logger.info("""
      📤 Scheduled #{scheduled_count} detail jobs
      (#{length(venues) - scheduled_count} venues skipped - recently updated)
      """)

      {:ok, %{venues_found: length(venues), jobs_scheduled: scheduled_count}}
    end
  end

  # Parse locations into venue data structs
  defp parse_venues(locations) do
    locations
    |> Enum.map(&parse_venue/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_venue(location) do
    case VenueExtractor.extract_venue_data(location) do
      {:ok, venue_data} ->
        venue_data

      {:error, reason} ->
        Logger.warning("⚠️ Failed to parse venue: #{inspect(reason)}")
        nil
    end
  end

  # CRITICAL: EventFreshnessChecker integration
  defp schedule_detail_jobs(venues, source_id, limit) do
    # Generate external_ids for freshness checking
    venues_with_ids =
      Enum.map(venues, fn venue ->
        Map.put(venue, :external_id, "quizmeisters_venue_#{venue.venue_id}")
      end)

    # Filter out venues that were recently updated (default: 7 days)
    venues_to_process =
      EventFreshnessChecker.filter_events_needing_processing(venues_with_ids, source_id)

    # Apply limit if provided (for testing)
    venues_to_process =
      if limit do
        Enum.take(venues_to_process, limit)
      else
        venues_to_process
      end

    # Schedule detail jobs for stale venues
    {ok_count, _err_count} =
      venues_to_process
      |> Enum.with_index()
      |> Enum.reduce({0, 0}, fn {venue, index}, {ok, err} ->
        # Stagger jobs to respect rate limit (2 seconds between requests)
        delay_seconds = index * 3

        job =
          %{
            "venue_id" => venue.venue_id,
            "venue_url" => venue.url,
            "venue_name" => venue.name,
            "venue_data" => venue,
            "source_id" => source_id
          }
          |> VenueDetailJob.new(schedule_in: delay_seconds)

        case Oban.insert(job) do
          {:ok, _job} ->
            {ok + 1, err}

          {:error, reason} ->
            Logger.error(
              "❌ Failed to enqueue detail job for #{inspect(venue.name)}: #{inspect(reason)}"
            )

            {ok, err + 1}
        end
      end)

    ok_count
  end
end
