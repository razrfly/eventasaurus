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
  alias EventasaurusWeb.Services.GooglePlaces.Geocoding

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

  # Enrich venue data with geocoded city and country information
  # Uses Google Geocoding API to extract proper city_name and country_name from address
  defp enrich_with_geocoding(venue_data) do
    address = Map.get(venue_data, :address)

    case geocode_address(address) do
      {:ok, {city_name, country_name}} ->
        enriched =
          venue_data
          |> Map.put(:city_name, city_name)
          |> Map.put(:country_name, country_name)

        Logger.debug("📍 Geocoded #{address} → #{city_name}, #{country_name}")
        {:ok, enriched}

      {:error, reason} ->
        Logger.warning("⚠️ Geocoding failed for #{address}: #{reason}. Using fallback.")
        # Fallback: Use nil values which will cause VenueProcessor to attempt its own geocoding
        enriched =
          venue_data
          |> Map.put(:city_name, nil)
          |> Map.put(:country_name, nil)

        {:ok, enriched}
    end
  end

  # Geocode address to extract city_name and country_name
  defp geocode_address(address) when is_binary(address) do
    case Geocoding.search(address) do
      {:ok, [first_result | _]} ->
        address_components = Map.get(first_result, "address_components", [])
        city_name = extract_city(address_components)
        country_name = extract_country(address_components)

        if city_name && country_name do
          {:ok, {city_name, country_name}}
        else
          {:error, "Missing city or country in geocoding results"}
        end

      {:ok, []} ->
        {:error, "No geocoding results found"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp geocode_address(_), do: {:error, "Invalid address"}

  # Extract city from address_components (same logic as VenuePlacesAdapter)
  defp extract_city(address_components) when is_list(address_components) do
    find_component(address_components, "locality") ||
      find_component(address_components, "administrative_area_level_2")
  end

  defp extract_city(_), do: nil

  # Extract country name (long_name) from address_components
  defp extract_country(address_components) when is_list(address_components) do
    find_component(address_components, "country")
  end

  defp extract_country(_), do: nil

  # Find address component by type (returns long_name)
  defp find_component(components, type) do
    components
    |> Enum.find(fn component ->
      types = Map.get(component, "types", [])
      type in types
    end)
    |> case do
      %{"long_name" => name} -> name
      _ -> nil
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
