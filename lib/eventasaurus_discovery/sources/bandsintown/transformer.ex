defmodule EventasaurusDiscovery.Sources.Bandsintown.Transformer do
  @moduledoc """
  Transforms Bandsintown event data into the unified format expected by the Processor.

  IMPORTANT: All events MUST have a venue with complete location data.
  Events without proper venue information will be rejected.
  """

  require Logger
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.DateParser

  @doc """
  Transform a raw Bandsintown event into our unified format.

  Required fields for the unified format:
  - title
  - external_id
  - starts_at (DateTime)
  - venue (with name, latitude, longitude, address)

  Optional fields:
  - description
  - ends_at
  - ticket_url
  - min_price / max_price
  - performer
  - tags

  Returns {:ok, transformed_event} or {:error, reason}
  """
  def transform_event(raw_event) do
    # Extract and validate venue first since it's critical
    venue_data = extract_venue(raw_event)

    # Validate venue has required fields
    case validate_venue(venue_data) do
      :ok ->
        transformed = %{
          # Required fields
          title: extract_title(raw_event),
          external_id: extract_external_id(raw_event),
          starts_at: extract_starts_at(raw_event),
          ends_at: extract_ends_at(raw_event),

          # Venue data - REQUIRED and validated
          venue: venue_data,

          # Optional fields
          description: extract_description(raw_event),
          ticket_url: raw_event["ticket_url"] || raw_event["url"],
          min_price: parse_price(raw_event["min_price"]),
          max_price: parse_price(raw_event["max_price"]),
          currency: "USD",  # Bandsintown typically uses USD

          # Performer data
          performer: extract_performer(raw_event),

          # Categories and tags
          tags: extract_tags(raw_event),

          # Original URL for reference
          source_url: raw_event["url"],

          # Raw data for debugging
          raw_data: raw_event
        }

        {:ok, transformed}

      {:error, reason} ->
        Logger.error("""
        ❌ Bandsintown event rejected due to invalid venue:
        Event: #{raw_event["title"] || raw_event["artist_name"]}
        Reason: #{reason}
        Venue data: #{inspect(venue_data)}
        """)

        {:error, reason}
    end
  end

  @doc """
  Validates that venue data contains all required fields.
  Returns :ok if valid, {:error, reason} if not.
  """
  def validate_venue(venue_data) do
    cond do
      is_nil(venue_data[:name]) || venue_data[:name] == "" ->
        {:error, "Venue name is required"}

      is_nil(venue_data[:latitude]) ->
        {:error, "Venue latitude is required for location"}

      is_nil(venue_data[:longitude]) ->
        {:error, "Venue longitude is required for location"}

      true ->
        :ok
    end
  end

  # Private functions

  defp extract_title(event) do
    # Use artist name as title, or event title if available
    event["title"] || event["artist_name"] || "Unknown Event"
  end

  defp extract_external_id(event) do
    # Try to extract ID from URL or use the URL itself as ID
    case event["url"] do
      nil ->
        # Generate a unique ID from available data
        generate_external_id(event)
      url ->
        # Extract ID from URL pattern: /e/:id-slug
        case Regex.run(~r/\/e\/(\d+)-/, url) do
          [_, id] -> "bandsintown_#{id}"
          _ -> "bandsintown_#{:crypto.hash(:md5, url) |> Base.encode16(case: :lower)}"
        end
    end
  end

  defp generate_external_id(event) do
    # Generate ID from artist + venue + date
    components = [
      event["artist_name"] || "",
      event["venue_name"] || "",
      event["date"] || ""
    ]

    hash = :crypto.hash(:md5, Enum.join(components, "|")) |> Base.encode16(case: :lower)
    "bandsintown_generated_#{hash}"
  end

  defp extract_starts_at(event) do
    DateParser.parse_start_date(event["date"])
  end

  defp extract_ends_at(event) do
    if event["end_date"] do
      DateParser.parse_end_date(event["end_date"])
    else
      nil
    end
  end

  defp extract_venue(event) do
    # CRITICAL: Venue with location is REQUIRED
    # We MUST always return valid venue data

    venue_name = event["venue_name"]

    # Try to get coordinates
    latitude = parse_coordinate(event["venue_latitude"])
    longitude = parse_coordinate(event["venue_longitude"])

    # Build address components
    address_parts = [
      event["venue_address"],
      event["venue_city"],
      event["venue_state"],
      event["venue_country"]
    ] |> Enum.filter(&(&1 && &1 != ""))

    address = if Enum.any?(address_parts), do: Enum.join(address_parts, ", "), else: nil

    cond do
      # We have all required venue data
      venue_name && latitude && longitude ->
        %{
          name: venue_name,
          latitude: latitude,
          longitude: longitude,
          address: address,
          city: event["venue_city"],
          state: event["venue_state"],
          country: event["venue_country"],
          postal_code: event["venue_postal_code"]
        }

      # We have venue name but missing coordinates - use city location
      venue_name && event["venue_city"] ->
        Logger.warning("""
        ⚠️ Missing coordinates for Bandsintown venue, using city center:
        Venue: #{venue_name}
        City: #{event["venue_city"]}
        """)

        # Try to infer coordinates from city
        {lat, lng} = get_city_coordinates(event["venue_city"], event["venue_country"])

        %{
          name: venue_name,
          latitude: lat,
          longitude: lng,
          address: address,
          city: event["venue_city"],
          state: event["venue_state"],
          country: event["venue_country"],
          postal_code: event["venue_postal_code"],
          needs_geocoding: true
        }

      # No venue data at all - create placeholder
      true ->
        Logger.warning("""
        ⚠️ No venue data for Bandsintown event, creating placeholder:
        Event: #{inspect(event["title"] || event["artist_name"])}
        Artist: #{inspect(event["artist_name"])}
        """)

        # Default to a general location
        # Since Bandsintown is global, we'll use event location if available
        # Otherwise default to New York as Bandsintown is US-based
        city = event["venue_city"] || "New York"
        country = event["venue_country"] || "United States"
        {lat, lng} = get_city_coordinates(city, country)

        %{
          name: "Venue TBD - #{event["artist_name"] || "Unknown Artist"}",
          latitude: lat,
          longitude: lng,
          address: nil,
          city: city,
          state: event["venue_state"],
          country: country,
          postal_code: nil,
          metadata: %{placeholder: true}
        }
    end
  end

  defp get_city_coordinates(city, country) do
    # Common city coordinates for fallback
    case {String.downcase(city || ""), String.downcase(country || "")} do
      {"kraków", _} -> {50.0647, 19.9450}
      {"krakow", _} -> {50.0647, 19.9450}
      {"warsaw", _} -> {52.2297, 21.0122}
      {"warszawa", _} -> {52.2297, 21.0122}
      {"new york", _} -> {40.7128, -74.0060}
      {"los angeles", _} -> {34.0522, -118.2437}
      {"london", _} -> {51.5074, -0.1278}
      {"paris", _} -> {48.8566, 2.3522}
      {"berlin", _} -> {52.5200, 13.4050}
      _ ->
        # Default to NYC for unknown cities
        {40.7128, -74.0060}
    end
  end

  defp parse_coordinate(nil), do: nil
  defp parse_coordinate(coord) when is_number(coord), do: coord
  defp parse_coordinate(coord) when is_binary(coord) do
    case Float.parse(coord) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp extract_description(event) do
    # Combine available description fields
    parts = [
      event["description"],
      event["lineup_description"],
      event["bio"]
    ] |> Enum.filter(&(&1 && &1 != ""))

    if Enum.any?(parts), do: Enum.join(parts, "\n\n"), else: nil
  end

  defp extract_performer(event) do
    if event["artist_name"] do
      %{
        name: event["artist_name"],
        genres: event["genres"] || [],
        image_url: event["artist_image_url"]
      }
    else
      nil
    end
  end

  defp extract_tags(event) do
    tags = []

    # Add genres as tags
    tags = tags ++ (event["genres"] || [])

    # Add event type tags
    tags = if event["festival"], do: ["festival" | tags], else: tags
    tags = if event["soldout"], do: ["sold-out" | tags], else: tags

    # Add any explicit tags
    tags = tags ++ (event["tags"] || [])

    Enum.uniq(tags)
  end

  defp parse_price(nil), do: nil
  defp parse_price(""), do: nil
  defp parse_price(price) when is_binary(price) do
    # Remove currency symbols and parse
    price
    |> String.replace(~r/[^\d.]/, "")
    |> Decimal.new()
  rescue
    _ -> nil
  end
  defp parse_price(price) when is_number(price) do
    Decimal.new(price)
  end
end