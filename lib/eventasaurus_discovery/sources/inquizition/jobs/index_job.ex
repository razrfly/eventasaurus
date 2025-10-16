defmodule EventasaurusDiscovery.Sources.Inquizition.Jobs.IndexJob do
  @moduledoc """
  Processes venues from StoreLocatorWidgets CDN and saves events directly.

  CRITICAL: Uses EventFreshnessChecker to avoid re-scraping fresh venues.

  ## Workflow
  1. Parse stores from CDN response (already fetched by SyncJob)
  2. Extract venue data using VenueExtractor
  3. Transform venues to event format using Transformer
  4. Generate external_ids for venues
  5. Filter using EventFreshnessChecker (skip fresh venues within 7 days)
  6. Process and save events using Processor.process_source_data/2

  ## Single-Stage Architecture
  Unlike Quizmeisters, Inquizition does not require detail page scraping:
  - All data available in CDN response
  - No detail jobs scheduled
  - Events saved directly in IndexJob
  - EventFreshnessChecker provides 80-90% API call reduction

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
    Extractors.VenueExtractor,
    Transformer
  }

  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Sources.Processor

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

          # Transform venues to event format and process
          process_venues(venues, source_id, limit)
        end
    end
  end

  # Process venues: transform, filter by freshness, and save events
  defp process_venues(venues, source_id, limit) do
    # Transform each venue to event format
    events =
      venues
      |> Enum.map(&transform_venue/1)
      |> Enum.reject(&is_nil/1)

    Logger.info("📤 Transformed #{length(events)} venues to events")

    if Enum.empty?(events) do
      Logger.warning("⚠️ No events generated after transformation")
      {:ok, :complete}
    else
      # CRITICAL: EventFreshnessChecker filters out fresh events
      events_to_process = filter_fresh_events(events, source_id, limit)

      Logger.info("""
      📋 Processing #{length(events_to_process)} events
      (#{length(events) - length(events_to_process)} events skipped - recently updated)
      """)

      # Process and save events using unified processor
      case Processor.process_source_data(events_to_process, source_id, "inquizition") do
        {:ok, processed_events} ->
          Logger.info("✅ Successfully processed #{length(processed_events)} events")
          {:ok, %{venues_found: length(venues), events_processed: length(processed_events)}}

        {:error, reason} = error ->
          Logger.error("❌ Failed to process events: #{inspect(reason)}")
          error

        {:discard, reason} ->
          Logger.error("🚫 Critical failure, discarding job: #{inspect(reason)}")
          {:discard, reason}
      end
    end
  end

  # Transform venue data to event format
  defp transform_venue(venue_data) do
    try do
      Transformer.transform_event(venue_data)
    rescue
      error ->
        Logger.error(
          "⚠️ Failed to transform venue #{inspect(venue_data.venue_id)}: #{inspect(error)}"
        )

        nil
    end
  end

  # CRITICAL: EventFreshnessChecker integration
  defp filter_fresh_events(events, source_id, limit) do
    # Filter out events that were recently updated (default: 7 days)
    events_to_process = EventFreshnessChecker.filter_events_needing_processing(events, source_id)

    # Apply limit if provided (for testing)
    if limit do
      Enum.take(events_to_process, limit)
    else
      events_to_process
    end
  end
end
