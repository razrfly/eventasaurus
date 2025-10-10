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
  alias EventasaurusDiscovery.Helpers.CityResolver

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

  # Enrich venue data with city and country information
  # Uses conservative UK address parsing with CityResolver validation
  # UK addresses typically follow: "Street, City, Postcode" or "Venue, Street, City, Postcode"
  defp enrich_with_geocoding(venue_data) do
    address = Map.get(venue_data, :address)

    case parse_uk_address(address) do
      {:ok, {city_name, country_name}} ->
        enriched =
          venue_data
          |> Map.put(:city_name, city_name)
          |> Map.put(:country_name, country_name)

        Logger.debug("📍 Parsed #{address} → #{city_name}, #{country_name}")
        {:ok, enriched}

      {:error, reason} ->
        Logger.warning("⚠️ Address parsing failed for #{address}: #{reason}. Using nil.")
        # Fallback: Use nil values which will cause VenueProcessor to attempt its own geocoding
        enriched =
          venue_data
          |> Map.put(:city_name, nil)
          |> Map.put(:country_name, nil)

        {:ok, enriched}
    end
  end

  # Parse UK address to extract city_name and country_name
  # UK addresses typically: "Street, City, Postcode" or "Venue, Street, City, Postcode"
  defp parse_uk_address(address) when is_binary(address) do
    parts = String.split(address, ",") |> Enum.map(&String.trim/1)

    case parts do
      # 4+ parts: venue, street, city, postcode[, extras]
      [_venue, _street, city_candidate, _postcode | _rest] ->
        validate_and_return_city(city_candidate)

      # 3 parts: street, city, postcode
      [_street, city_candidate, _postcode] ->
        validate_and_return_city(city_candidate)

      # 2 parts: might be city, postcode
      [city_candidate, postcode_candidate] ->
        # Check if second part looks like postcode (UK pattern)
        if String.match?(postcode_candidate, ~r/^[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}$/i) do
          validate_and_return_city(city_candidate)
        else
          {:error, "Cannot determine city from 2-part address"}
        end

      # Not enough parts
      _ ->
        {:error, "Address format not recognized"}
    end
  end

  defp parse_uk_address(_), do: {:error, "Invalid address"}

  # Validate city candidate using CityResolver before returning
  defp validate_and_return_city(city_candidate) do
    case CityResolver.validate_city_name(city_candidate) do
      {:ok, validated_city} ->
        {:ok, {validated_city, "United Kingdom"}}

      {:error, reason} ->
        Logger.warning(
          "City candidate failed validation: #{inspect(city_candidate)} (#{reason})"
        )

        {:error, "Invalid city name: #{reason}"}
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
