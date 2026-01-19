defmodule EventasaurusDiscovery.Sources.Bandsintown.Transformer do
  @moduledoc """
  Transforms Bandsintown event data into the unified format expected by the Processor.

  IMPORTANT: All events MUST have a venue with complete location data.
  Events without proper venue information will be rejected.
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Bandsintown.DateParser
  alias EventasaurusDiscovery.Helpers.CityResolver
  alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

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
  def transform_event(raw_event, city \\ nil) do
    # CRITICAL: Filter out events that are clearly not in the target city
    # If venue city is provided and doesn't match our city, reject the event
    if should_filter_event?(raw_event, city) do
      {:error, "Event is not in target city"}
    else
      # Extract and validate venue first since it's critical
      venue_data = extract_venue(raw_event, city)

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
            venue_data: venue_data,

            # Optional fields
            description: extract_description(raw_event),
            ticket_url: raw_event["ticket_url"] || raw_event["url"],
            min_price: parse_price(raw_event["min_price"]),
            max_price: parse_price(raw_event["max_price"]),
            # Bandsintown typically uses USD
            currency: "USD",

            # Image URL - extract from the event data and validate
            image_url:
              validate_image_url(raw_event["image_url"] || raw_event["artist_image_url"]),

            # Performer data - must be plural key with list for Processor compatibility
            performers: wrap_performer(extract_performer(raw_event)),

            # Categories and tags
            tags: extract_tags(raw_event),

            # Original URL for reference
            source_url: raw_event["url"],

            # Metadata with raw upstream data for debugging
            metadata: %{
              "_raw_upstream" => JsonSanitizer.sanitize(raw_event)
            }
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
  end

  @doc """
  Validates that venue data contains all required fields.
  Returns :ok if valid, {:error, reason} if not.
  """
  def validate_venue(nil), do: {:error, "Venue data is required"}

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

  defp should_filter_event?(raw_event, city) do
    # Check if venue city doesn't match our target city
    # Bandsintown API returns events from 200-300km radius
    # We need to filter out events that are clearly in the wrong city
    venue_city = raw_event["venue_city"]

    if venue_city && city && city.name do
      # Normalize city names for comparison
      venue_city_normalized = String.downcase(String.trim(venue_city || ""))
      city_name_normalized = String.downcase(String.trim(city.name || ""))

      # Only filter if we have a clear mismatch
      # We don't filter if no venue city is provided (will get GPS from detail page)
      if venue_city_normalized != "" && city_name_normalized != "" do
        # Check if it's a completely different city
        # Note: We're keeping events without venue_city since we'll get GPS from detail page
        # For now, don't filter - we'll rely on GPS coordinates
        false
      else
        false
      end
    else
      false
    end
  end

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
    # Get venue timezone for proper UTC conversion
    venue_timezone = get_venue_timezone(event)

    case DateParser.parse_start_date(event["date"], venue_timezone) do
      nil ->
        Logger.warning(
          "No valid start date found for Bandsintown event: #{inspect(event["title"] || event["artist_name"])}"
        )

        # Default to tomorrow if no date available
        DateTime.utc_now() |> DateTime.add(86400, :second)

      date ->
        date
    end
  end

  defp extract_ends_at(event) do
    if event["end_date"] do
      # Get venue timezone for proper UTC conversion
      venue_timezone = get_venue_timezone(event)
      DateParser.parse_end_date(event["end_date"], venue_timezone)
    else
      nil
    end
  end

  defp get_venue_timezone(event) do
    # Try to get timezone from venue coordinates
    cond do
      # If venue has coordinates, infer timezone
      event["venue_latitude"] && event["venue_longitude"] ->
        lat = parse_coordinate(event["venue_latitude"])
        lng = parse_coordinate(event["venue_longitude"])

        if lat && lng do
          EventasaurusDiscovery.Scraping.Helpers.TimezoneConverter.infer_timezone_from_location(
            lat,
            lng
          )
        else
          "Etc/UTC"
        end

      # Default to UTC for unknown venues
      true ->
        "Etc/UTC"
    end
  end

  defp extract_venue(event, city) do
    # CRITICAL: Venue with location is REQUIRED
    # We MUST always return valid venue data

    # Use the KNOWN country from city context, not the API response
    known_country = if city && city.country, do: city.country.name, else: nil

    venue_name = event["venue_name"]

    # Try to get coordinates
    latitude = parse_coordinate(event["venue_latitude"])
    longitude = parse_coordinate(event["venue_longitude"])

    # Resolve city name using CityResolver with coordinates
    {resolved_city, resolved_country} =
      resolve_location(latitude, longitude, event["venue_city"], known_country)

    # Build address components
    address_parts =
      [
        event["venue_address"],
        resolved_city,
        event["venue_state"],
        resolved_country
      ]
      |> Enum.filter(&(&1 && &1 != ""))

    address = if Enum.any?(address_parts), do: Enum.join(address_parts, ", "), else: nil

    cond do
      # We have all required venue data
      venue_name && latitude && longitude ->
        %{
          name: venue_name,
          latitude: latitude,
          longitude: longitude,
          address: address,
          city: resolved_city,
          state: event["venue_state"],
          country: resolved_country,
          postal_code: event["venue_postal_code"]
        }

      # We have venue name but missing coordinates - use city location
      venue_name && (event["venue_city"] || city) ->
        # Validate API city name before using
        {validated_city, validated_country} =
          validate_api_city(event["venue_city"], known_country)

        # Use city context if available, otherwise use validated API city
        actual_city_name =
          if city && city.name do
            city.name
          else
            validated_city || "Unknown City"
          end

        actual_country_name =
          if city && city.country do
            city.country.name
          else
            validated_country
          end

        Logger.warning("""
        ⚠️ Missing coordinates for Bandsintown venue, using city center:
        Venue: #{venue_name}
        City: #{actual_city_name}
        """)

        # Try to get coordinates from city context first
        {lat, lng} =
          if city && city.latitude && city.longitude do
            {Decimal.to_float(city.latitude), Decimal.to_float(city.longitude)}
          else
            get_city_coordinates(actual_city_name, actual_country_name)
          end

        %{
          name: venue_name,
          latitude: lat,
          longitude: lng,
          address: address,
          city: actual_city_name,
          state: event["venue_state"],
          country: actual_country_name,
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

        # Use the city context if provided, otherwise fall back to event data or defaults
        {city_name, country_name, lat, lng} =
          if city && city.name do
            # We have city context - use it!
            city_name = city.name
            country_name = if city.country, do: city.country.name, else: known_country
            lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
            lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

            # If city doesn't have coordinates, try to get them
            {lat, lng} =
              if lat && lng do
                {lat, lng}
              else
                get_city_coordinates(city_name, country_name)
              end

            {city_name, country_name, lat, lng}
          else
            # No city context - use event data if available
            city_name = event["venue_city"] || "New York"
            country_name = known_country || event["venue_country"] || "United States"
            {lat, lng} = get_city_coordinates(city_name, country_name)
            {city_name, country_name, lat, lng}
          end

        %{
          name: "Venue TBD - #{event["artist_name"] || "Unknown Artist"}",
          latitude: lat,
          longitude: lng,
          address: nil,
          city: city_name,
          state: event["venue_state"],
          country: country_name,
          postal_code: nil,
          metadata: %{placeholder: true}
        }
    end
  end

  defp get_city_coordinates(city, country) do
    # Common city coordinates for fallback
    case {String.downcase(city || ""), String.downcase(country || "")} do
      {"kraków", _} ->
        {50.0647, 19.9450}

      {"krakow", _} ->
        {50.0647, 19.9450}

      {"warsaw", _} ->
        {52.2297, 21.0122}

      {"warszawa", _} ->
        {52.2297, 21.0122}

      {"new york", _} ->
        {40.7128, -74.0060}

      {"los angeles", _} ->
        {34.0522, -118.2437}

      {"london", _} ->
        {51.5074, -0.1278}

      {"paris", _} ->
        {48.8566, 2.3522}

      {"berlin", _} ->
        {52.5200, 13.4050}

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
    parts =
      [
        event["description"],
        event["lineup_description"],
        event["bio"]
      ]
      |> Enum.filter(&(&1 && &1 != ""))

    if Enum.any?(parts), do: Enum.join(parts, "\n\n"), else: nil
  end

  defp extract_performer(event) do
    if event["artist_name"] do
      %{
        name: event["artist_name"],
        genres: event["genres"] || [],
        # The API returns image_url, not artist_image_url - validate it
        image_url: validate_image_url(event["image_url"] || event["artist_image_url"])
      }
    else
      nil
    end
  end

  # Wrap single performer in list for Processor compatibility
  # Processor expects `performers` key with a list value
  defp wrap_performer(nil), do: []
  defp wrap_performer(performer), do: [performer]

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

  # Validate image URLs - filter out null/invalid Bandsintown placeholder images
  defp validate_image_url(nil), do: nil
  defp validate_image_url(""), do: nil

  defp validate_image_url(url) when is_binary(url) do
    # Check for known invalid Bandsintown image URLs
    downcased = String.downcase(url)

    cond do
      # Filter out null placeholder images
      String.contains?(downcased, "/null.") -> nil
      # Filter out "undefined" placeholder images
      String.contains?(downcased, "/undefined.") -> nil
      # Filter out thumb placeholders (all zeros, default, etc)
      String.contains?(downcased, "/thumb/0000") -> nil
      String.contains?(downcased, "/thumb/default") -> nil
      # Filter out any suspiciously small thumb images (single digit names)
      Regex.match?(~r|/thumb/\d\.jpg|, downcased) -> nil
      # Valid URL
      true -> url
    end
  end

  defp validate_image_url(_), do: nil

  @doc """
  Resolves city and country from GPS coordinates using offline geocoding.

  Uses CityResolver for reliable city name extraction from coordinates.
  Falls back to conservative validation of API-provided city name if geocoding fails.

  ## Parameters
  - `latitude` - GPS latitude coordinate
  - `longitude` - GPS longitude coordinate
  - `api_city` - City name from Bandsintown API (fallback only)
  - `known_country` - Country from city context (preferred)

  ## Returns
  - `{city_name, country}` tuple
  """
  def resolve_location(latitude, longitude, api_city, known_country) do
    case CityResolver.resolve_city(latitude, longitude) do
      {:ok, city_name} ->
        # Successfully resolved city from coordinates
        country = known_country || "United States"
        {city_name, country}

      {:error, reason} ->
        # Geocoding failed - log and fall back to conservative validation
        Logger.warning(
          "Geocoding failed for (#{inspect(latitude)}, #{inspect(longitude)}): #{reason}. Falling back to API city validation."
        )

        validate_api_city(api_city, known_country)
    end
  end

  # Conservative fallback - validates API city name before using
  # Prefers nil over garbage data
  defp validate_api_city(api_city, known_country) when is_binary(api_city) do
    city_trimmed = String.trim(api_city)

    # CRITICAL: Validate city candidate before using
    case CityResolver.validate_city_name(city_trimmed) do
      {:ok, validated_city} ->
        country = known_country || "United States"
        {validated_city, country}

      {:error, reason} ->
        # City candidate failed validation (postcode, street address, etc.)
        Logger.warning(
          "Bandsintown API returned invalid city: #{inspect(city_trimmed)} (#{reason})"
        )

        {nil, known_country || "United States"}
    end
  end

  defp validate_api_city(_api_city, known_country) do
    {nil, known_country || "United States"}
  end
end
