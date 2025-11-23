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
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    venue_url = args["venue_url"]
    venue_title = args["venue_title"]
    source_id = args["source_id"]

    # Extract venue ID from URL for external_id (e.g., /venue/abc123 -> question_one_venue_abc123)
    venue_id = venue_url |> String.split("/") |> List.last() |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
    external_id = "question_one_venue_#{venue_id}"

    Logger.info("🔍 Processing Question One venue: #{venue_title}")

    result =
      with {:ok, body} <- Client.fetch_venue_page(venue_url),
           {:ok, document} <- parse_document(body),
           {:ok, venue_data} <-
             VenueExtractor.extract_venue_data(document, venue_url, venue_title),
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

    # Track metrics in job metadata
    case result do
      {:ok, _} ->
        MetricsTracker.record_success(job, external_id)
        result

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        result

      _other ->
        result
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

    case AddressGeocoder.geocode_address_with_metadata(address) do
      {:ok,
       %{
         city: city_name,
         country: country_name,
         latitude: lat,
         longitude: lng,
         geocoding_metadata: metadata
       }} ->
        enriched =
          venue_data
          |> Map.put(:city_name, city_name)
          |> Map.put(:country_name, country_name)
          |> Map.put(:latitude, lat)
          |> Map.put(:longitude, lng)
          |> Map.put(:geocoding_metadata, metadata)

        Logger.info("📍 Geocoded #{address} → #{city_name}, #{country_name}")
        {:ok, enriched}

      {:error, reason, metadata} ->
        Logger.warning("⚠️ Geocoding failed for #{address}: #{reason}. Using nil.")
        # Fallback: Use nil values but preserve metadata for failure tracking
        enriched =
          venue_data
          |> Map.put(:city_name, nil)
          |> Map.put(:country_name, nil)
          |> Map.put(:geocoding_metadata, metadata)

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

  # CRITICAL: Use Processor.process_source_data/3
  # This handles:
  # - VenueProcessor geocoding
  # - EventProcessor creation/update
  # - last_seen_at timestamps
  # - Deduplication via external_id
  # - Scraper attribution via explicit scraper name
  defp process_event(transformed, source_id) do
    case Processor.process_source_data([transformed], source_id, "question_one") do
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
