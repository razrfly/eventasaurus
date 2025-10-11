defmodule EventasaurusDiscovery.Sources.QuestionOne.Jobs.VenueDetailJob do
  @moduledoc """
  Scrapes individual venue detail pages and creates events.

  ## Workflow
  1. Fetch venue HTML page
  2. Parse with VenueExtractor (icon-based extraction)
  3. Transform to unified format
  4. Process through Processor.process_source_data/2
  5. VenueProcessor geocodes address automatically
  6. EventProcessor creates/updates event and marks as seen

  ## Critical Features
  - Uses Processor.process_source_data/2 (NOT manual VenueStore/EventStore)
  - VenueProcessor handles geocoding (no manual Google Places calls)
  - EventProcessor updates last_seen_at timestamp
  - Stable external_ids for deduplication
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Sources.QuestionOne.{
    Client,
    Extractors.VenueExtractor,
    Transformer
  }

  alias EventasaurusDiscovery.Sources.Processor
  alias EventasaurusDiscovery.Helpers.AddressGeocoder

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    venue_url = args["venue_url"]
    venue_title = args["venue_title"]
    source_id = args["source_id"]

    Logger.info("🔍 Processing Question One venue: #{venue_title}")

    with {:ok, body} <- Client.fetch_venue_page(venue_url),
         {:ok, document} <- parse_document(body),
         {:ok, venue_data} <- VenueExtractor.extract_venue_data(document, venue_url, venue_title),
         {:ok, enriched_venue_data} <- enrich_with_geocoding(venue_data),
         {:ok, transformed} <- transform_and_validate(enriched_venue_data),
         {:ok, results} <- process_event(transformed, source_id) do
      Logger.info("✅ Successfully processed venue: #{venue_title}")
      log_results(results)
      {:ok, results}
    else
      {:error, reason} = error ->
        Logger.error("❌ Failed to process venue #{venue_url}: #{inspect(reason)}")
        error
    end
  end

  defp parse_document(html) do
    document = Floki.parse_document!(html)
    {:ok, document}
  rescue
    error ->
      {:error, "Failed to parse HTML: #{inspect(error)}"}
  end

  # Enrich venue data with city and country information using forward geocoding
  defp enrich_with_geocoding(venue_data) do
    address = Map.get(venue_data, :address)

    case AddressGeocoder.geocode_address(address) do
      {:ok, {city_name, country_name, {lat, lng}}} ->
        enriched =
          venue_data
          |> Map.put(:city_name, city_name)
          |> Map.put(:country_name, country_name)
          |> Map.put(:latitude, lat)
          |> Map.put(:longitude, lng)

        Logger.info("📍 Geocoded #{address} → #{city_name}, #{country_name}")
        {:ok, enriched}

      {:error, reason} ->
        Logger.warning("⚠️ Geocoding failed for #{address}: #{reason}. Using nil.")
        # Fallback: Use nil values
        enriched =
          venue_data
          |> Map.put(:city_name, nil)
          |> Map.put(:country_name, nil)

        {:ok, enriched}
    end
  end

  defp transform_and_validate(venue_data) do
    case Transformer.transform_event(venue_data) do
      transformed when is_map(transformed) ->
        {:ok, transformed}

      _ ->
        {:error, "Transformation failed"}
    end
  end

  # CRITICAL: Use Processor.process_source_data/2
  # This handles:
  # - VenueProcessor geocoding
  # - EventProcessor creation/update
  # - last_seen_at timestamps
  # - Deduplication via external_id
  defp process_event(transformed, source_id) do
    case Processor.process_source_data([transformed], source_id) do
      {:ok, results} -> {:ok, results}
      error -> error
    end
  end

  defp log_results(results) do
    # Results are PublicEvent structs, not maps with :action field
    # We can't distinguish between created/updated here
    count = length(results)

    Logger.info("""
    📊 Processing results:
    - Events processed: #{count}
    """)
  end
end
