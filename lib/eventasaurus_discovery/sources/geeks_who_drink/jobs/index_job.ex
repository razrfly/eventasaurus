defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.IndexJob do
  @moduledoc """
  Fetches venues from Geeks Who Drink map API and schedules detail jobs.

  CRITICAL: Uses EventFreshnessChecker to avoid re-scraping fresh venues.

  ## Workflow
  1. Call WordPress AJAX API with nonce and map bounds
  2. Parse venue HTML blocks from response
  3. Extract venue data (GPS coordinates provided directly)
  4. Generate external_ids for venues
  5. Filter using EventFreshnessChecker (skip fresh venues within 7 days)
  6. Schedule detail jobs for stale venues only

  ## API Details
  - Endpoint: /wp-admin/admin-ajax.php
  - Action: mb_display_quizzes
  - Returns HTML blocks (one per venue)
  - GPS coordinates in data-lat/data-lon attributes
  - No pagination needed (single request with bounds)
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3,
    priority: 1

  require Logger

  alias EventasaurusDiscovery.Sources.GeeksWhoDrink.{
    Client,
    Extractors.VenueExtractor,
    Jobs.VenueDetailJob
  }

  alias EventasaurusDiscovery.Services.EventFreshnessChecker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source_id = args["source_id"]
    nonce = args["nonce"]
    bounds = args["bounds"]
    limit = args["limit"]

    Logger.info("🔄 Fetching Geeks Who Drink venues from map API")

    # Construct AJAX request parameters
    params = %{
      "action" => "mb_display_quizzes",
      "nonce" => nonce,
      "northLat" => bounds["northLat"],
      "southLat" => bounds["southLat"],
      "westLong" => bounds["westLong"],
      "eastLong" => bounds["eastLong"],
      "week" => "*",
      "city" => "*",
      "team" => "*"
    }

    case Client.post_ajax(params) do
      {:ok, html_response} ->
        venues = parse_venue_blocks(html_response)

        if Enum.empty?(venues) do
          Logger.info("✅ No venues found in response")
          {:ok, :complete}
        else
          Logger.info("📋 Found #{length(venues)} venues")

          # CRITICAL: EventFreshnessChecker filters out fresh venues
          scheduled_count = schedule_detail_jobs(venues, source_id, limit)

          Logger.info("""
          📤 Scheduled #{scheduled_count} detail jobs
          (#{length(venues) - scheduled_count} venues skipped - recently updated)
          """)

          {:ok, %{venues_found: length(venues), jobs_scheduled: scheduled_count}}
        end

      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch venues from map API: #{inspect(reason)}")
        error
    end
  end

  # Parse HTML response into venue blocks
  # Response contains multiple HTML blocks, each representing one venue
  defp parse_venue_blocks(html) do
    # Split HTML into individual venue blocks
    # Each block starts with <div id="quizBlock-{venue_id}" ...>
    html
    |> String.split(~r/<div[^>]*id="quizBlock-\d+"/)
    # First element is empty or header content
    |> Enum.drop(1)
    |> Enum.map(&restore_opening_tag/1)
    |> Enum.map(&parse_venue_block/1)
    |> Enum.reject(&is_nil/1)
  end

  # Restore the opening <div> tag that was removed during split
  defp restore_opening_tag(block_html) do
    # Extract the venue ID from the block
    case Regex.run(~r/data-venue-id="(\d+)"/, block_html) do
      [_, venue_id] ->
        "<div id=\"quizBlock-#{venue_id}\" #{block_html}"

      nil ->
        # Fallback: just prepend a generic div
        "<div #{block_html}"
    end
  end

  defp parse_venue_block(block_html) do
    case VenueExtractor.extract_venue_data(block_html) do
      {:ok, venue_data} ->
        venue_data

      {:error, reason} ->
        Logger.warning("⚠️ Failed to parse venue block: #{inspect(reason)}")
        nil
    end
  end

  # CRITICAL: EventFreshnessChecker integration
  defp schedule_detail_jobs(venues, source_id, limit) do
    # Generate external_ids for freshness checking
    venues_with_ids =
      Enum.map(venues, fn venue ->
        Map.put(venue, :external_id, "geeks_who_drink_venue_#{venue.venue_id}")
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
            "venue_title" => venue.title,
            "venue_data" => venue,
            "source_id" => source_id
          }
          |> VenueDetailJob.new(schedule_in: delay_seconds)

        case Oban.insert(job) do
          {:ok, _job} ->
            {ok + 1, err}

          {:error, reason} ->
            Logger.error(
              "❌ Failed to enqueue detail job for #{inspect(venue.title)}: #{inspect(reason)}"
            )

            {ok, err + 1}
        end
      end)

    ok_count
  end
end
