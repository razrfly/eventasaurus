defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.IndexPageJob do
  @moduledoc """
  Fetches venues from Geeks Who Drink map API and schedules detail jobs.

  CRITICAL: Uses EventFreshnessChecker to avoid re-scraping fresh venues.

  ## Workflow
  1. Fetch fresh nonce from venues page (expires in 12-24 hours)
  2. Call WordPress AJAX API with GET request, nonce, and map bounds
  3. Parse venue HTML blocks from response
  4. Extract venue data (GPS coordinates provided directly)
  5. Generate external_ids for venues
  6. Filter using EventFreshnessChecker (skip fresh venues within 7 days)
  7. Schedule detail jobs for stale venues only

  ## API Details
  - Endpoint: /wp-admin/admin-ajax.php
  - Method: GET request (not POST)
  - Action: mb_display_mapped_events
  - Returns HTML blocks (one per venue)
  - GPS coordinates in data-lat/data-lon attributes
  - No pagination needed (single request with bounds)
  - Parameter format: Array notation for bounds ("bounds[northLat]", etc.)
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3,
    priority: 1

  require Logger

  alias EventasaurusDiscovery.Sources.GeeksWhoDrink.{
    Client,
    Config,
    Extractors.VenueExtractor,
    Jobs.VenueDetailJob
  }

  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    source_id = args["source_id"]
    bounds = args["bounds"]
    limit = args["limit"]
    force = args["force"] || false
    external_id = "geeks_who_drink_index_#{Date.utc_today()}"

    Logger.info("🔄 Fetching Geeks Who Drink venues from map API")

    # CRITICAL: Fetch fresh nonce (WordPress nonces expire in 12-24 hours)
    # Do NOT reuse nonce from args - it may be stale
    with {:ok, nonce} <- fetch_fresh_nonce() do
      # Construct AJAX request parameters matching trivia_advisor's working format
      # CRITICAL: Use array notation for bounds and include all required parameters
      params = %{
        "action" => "mb_display_mapped_events",
        "nonce" => nonce,
        "bounds[northLat]" => bounds["northLat"],
        "bounds[southLat]" => bounds["southLat"],
        "bounds[westLong]" => bounds["westLong"],
        "bounds[eastLong]" => bounds["eastLong"],
        "days" => "",
        "brands" => "",
        "search" => "",
        "startLat" => "44.967243",
        "startLong" => "-103.771556",
        "searchInit" => "true",
        "tlCoord" => "",
        "brCoord" => "",
        "tlMapCoord" => "[#{bounds["westLong"]}, #{bounds["northLat"]}]",
        "brMapCoord" => "[#{bounds["eastLong"]}, #{bounds["southLat"]}]",
        "hasAll" => "true"
      }

      # Build URL with query parameters and use GET request (not POST)
      ajax_url = Config.ajax_url()
      url = ajax_url <> "?" <> URI.encode_query(params)

      Logger.debug("🔍 GET #{ajax_url} with action: mb_display_mapped_events")

      case Client.fetch_page(url) do
        {:ok, %{body: html_response}} ->
          venues = parse_venue_blocks(html_response)

          if Enum.empty?(venues) do
            Logger.info("✅ No venues found in response")
            MetricsTracker.record_success(job, external_id)
            {:ok, :complete}
          else
            Logger.info("📋 Found #{length(venues)} venues")

            # CRITICAL: EventFreshnessChecker filters out fresh venues (unless force=true)
            scheduled_count = schedule_detail_jobs(venues, source_id, limit, force)

            Logger.info("""
            📤 Scheduled #{scheduled_count} detail jobs
            (#{length(venues) - scheduled_count} venues skipped - recently updated)
            """)

            MetricsTracker.record_success(job, external_id)
            {:ok, %{venues_found: length(venues), jobs_scheduled: scheduled_count}}
          end

        # Use standard categories for ErrorCategories.categorize_error/1
        # See docs/error-handling-guide.md for category definitions
        {:error, %HTTPoison.Error{reason: :timeout}} = error ->
          Logger.error("❌ Network timeout fetching venues from map API")
          MetricsTracker.record_failure(job, :network_error, external_id)
          error

        {:error, %HTTPoison.Error{reason: _reason}} = error ->
          Logger.error("❌ Network error fetching venues")
          MetricsTracker.record_failure(job, :network_error, external_id)
          error

        {:error, _reason} = error ->
          Logger.error("❌ Failed to fetch venues from map API")
          MetricsTracker.record_failure(job, :network_error, external_id)
          error

        {:ok, response} ->
          Logger.error("❌ Unexpected response format from map API: #{inspect(response)}")
          MetricsTracker.record_failure(job, :parsing_error, external_id)
          {:error, :unexpected_response_format}
      end
    else
      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch fresh nonce: #{inspect(reason)}")
        MetricsTracker.record_failure(job, :authentication_error, external_id)
        error
    end
  end

  # Private function to fetch fresh nonce
  defp fetch_fresh_nonce do
    alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Extractors.NonceExtractor

    case NonceExtractor.fetch_nonce() do
      {:ok, nonce} ->
        Logger.info("✅ Successfully fetched fresh nonce")
        {:ok, nonce}

      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch nonce: #{inspect(reason)}")
        error
    end
  end

  # Parse HTML response into venue blocks
  # Response contains multiple HTML blocks, each representing one venue
  defp parse_venue_blocks(html) do
    # Split HTML into individual venue blocks
    # Each block starts with <a id="quizBlock-{venue_id}" ...> (not <div>)
    html
    |> String.split(~r/<a[^>]*id="quizBlock-/)
    # First element is empty or header content
    |> Enum.drop(1)
    |> Enum.map(&restore_opening_tag/1)
    |> Enum.map(&parse_venue_block/1)
    |> Enum.reject(&is_nil/1)
  end

  # Restore the opening <a> tag that was removed during split
  defp restore_opening_tag(block_html) do
    # Extract the venue ID from the block (matches patterns like quizBlock-12345 or quizBlock-virtual-0)
    case Regex.run(~r/^([^"]+)"/, block_html) do
      [_, venue_id] ->
        "<a id=\"quizBlock-#{venue_id}\" #{block_html}"

      nil ->
        # Fallback: just prepend a generic <a> tag
        "<a id=\"quizBlock-#{block_html}"
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
  defp schedule_detail_jobs(venues, source_id, limit, force) do
    # Generate external_ids for freshness checking
    venues_with_ids =
      Enum.map(venues, fn venue ->
        Map.put(venue, :external_id, "geeks_who_drink_venue_#{venue.venue_id}")
      end)

    # Filter out venues that were recently updated (default: 7 days)
    # In force mode, skip filtering to process all venues
    venues_to_process =
      if force do
        venues_with_ids
      else
        EventFreshnessChecker.filter_events_needing_processing(venues_with_ids, source_id)
      end

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
