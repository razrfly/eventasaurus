defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Transformer do
  @moduledoc """
  Transforms Speed Quizzing venue data into unified event format with recurrence patterns.

  Speed Quizzing provides weekly recurring trivia events at venues with:
  - GPS coordinates provided directly in detail pages (no geocoding needed)
  - Performer information from venue detail pages
  - Weekly recurring schedule with recurrence_rule support
  - Primarily UK-based events (Europe/London timezone)

  ## Transformation Strategy
  - Use provided GPS coordinates (latitude/longitude)
  - Resolve city names using offline geocoding via CityResolver
  - Parse time_text to extract day of week and start time
  - Create recurrence_rule for pattern-based occurrences
  - Calculate next occurrence in appropriate timezone (UK, US, UAE)
  - Create stable external_id for deduplication
  - Set category to "trivia"
  - Link performer via metadata (if available)

  ## Recurring Event Pattern
  Uses `recurrence_rule` field to enable frontend generation of future dates:
  - One database record represents all future occurrences
  - Frontend generates next 4+ dates dynamically
  - Always shows upcoming events (no stale past dates)
  """

  require Logger

  alias EventasaurusDiscovery.Helpers.CityResolver
  alias EventasaurusDiscovery.Sources.Shared.RecurringEventParser

  @doc """
  Transform venue data to unified event format.

  ## Parameters
  - `venue_data` - Map with extracted venue fields from VenueExtractor
  - `source_id` - Source database ID

  ## Returns
  - Unified event format map (see SCRAPER_SPECIFICATION.md)

  ## Required venue_data Fields
  - event_id, venue_name, address, lat, lng, event_url

  ## Optional venue_data Fields
  - postcode, description, start_time, day_of_week, date, fee, performer
  """
  def transform_event(venue_data, source_id) do
    name = venue_data.venue_name
    address = venue_data.address

    # GPS coordinates provided directly by detail page
    latitude = parse_coordinate(venue_data.lat)
    longitude = parse_coordinate(venue_data.lng)

    # Generate stable external_id from event_id
    external_id = "speed_quizzing_#{venue_data.event_id}"

    # Resolve city and country using offline geocoding
    {city, country} = resolve_location(latitude, longitude, address)

    # Build time_text for parsing
    time_text = build_time_text(venue_data)

    # Detect timezone based on country
    timezone = detect_timezone(country, address)

    # Calculate next occurrence using RecurringEventParser
    starts_at = calculate_starts_at(time_text, timezone, venue_data)

    # Parse schedule to recurrence_rule (for pattern-based occurrences)
    recurrence_rule =
      case parse_schedule_to_recurrence(time_text, starts_at, timezone) do
        {:ok, rule} ->
          rule

        {:error, reason} ->
          Logger.warning("⚠️ Could not create recurrence_rule: #{reason}")
          nil
      end

    # Parse pricing
    {is_free, min_price, max_price, currency} = parse_pricing(venue_data.fee, country)

    %{
      # Required fields
      external_id: external_id,
      title: "SpeedQuizzing at #{name}",
      starts_at: starts_at,

      # Venue data (REQUIRED - GPS coordinates provided by detail page)
      venue_data: %{
        name: name,
        address: address,
        city: city,
        country: country,
        latitude: latitude,
        longitude: longitude,
        phone: nil,
        postcode: venue_data.postcode,
        external_id: "speed_quizzing_venue_#{venue_data.event_id}",
        metadata: %{}
      },

      # Optional fields
      ends_at: if(match?(%DateTime{}, starts_at), do: add_hours(starts_at, 2), else: nil),
      description_translations: %{"en" => build_description(venue_data)},
      source_url: venue_data.event_url,

      # Event image (none available from Speed Quizzing)
      image_url: nil,

      # Recurring pattern (enables frontend to generate future dates)
      recurrence_rule: recurrence_rule,

      # Pricing
      is_ticketed: !is_free,
      is_free: is_free,
      min_price: min_price,
      max_price: max_price,
      currency: currency,

      # Metadata
      metadata: %{
        time_text: time_text,
        event_id: venue_data.event_id,
        recurring: true,
        frequency: "weekly",
        start_time: venue_data.start_time,
        day_of_week: venue_data.day_of_week,
        performer: venue_data.performer,
        source_id: source_id,
        # Raw upstream data for debugging
        _raw_upstream: venue_data
      },

      # Category
      category: "trivia"
    }
  end

  @doc """
  Parses time_text into recurrence_rule JSON for pattern-based event occurrences.

  ## Parameters
  - `time_text` - Schedule text (e.g., "Wednesdays at 7pm", "Tuesday 8pm")
  - `starts_at` - DateTime with correct timezone
  - `timezone` - IANA timezone string

  ## Returns
  - `{:ok, recurrence_rule_map}` - Successfully parsed schedule
  - `{:error, reason}` - Parsing failed
  """
  def parse_schedule_to_recurrence(time_text, _starts_at, timezone)
      when is_binary(time_text) and is_binary(timezone) do
    with {:ok, day_of_week} <- RecurringEventParser.parse_day_of_week(time_text),
         {:ok, time_struct} <- RecurringEventParser.parse_time_with_fallback(time_text) do
      # Use provided timezone (already detected from country/address)
      recurrence_rule =
        RecurringEventParser.build_recurrence_rule(day_of_week, time_struct, timezone)

      {:ok, recurrence_rule}
    else
      {:error, reason} ->
        {:error, "Could not extract day of week or time from time_text: #{time_text} - #{reason}"}
    end
  end

  def parse_schedule_to_recurrence(nil, _starts_at, _timezone),
    do: {:error, "Time text is nil"}

  def parse_schedule_to_recurrence(_time_text, _starts_at, nil),
    do: {:error, "Timezone is nil"}

  @doc """
  Resolves city and country from GPS coordinates using offline geocoding.

  Uses CityResolver for reliable city and country extraction from coordinates.
  The geocoding library returns ISO country codes which are converted to full
  country names using the Countries library.

  Falls back to conservative address parsing if geocoding fails.
  """
  def resolve_location(latitude, longitude, address) do
    case CityResolver.resolve_city_and_country(latitude, longitude) do
      {:ok, {city_name, country_code}} ->
        # Successfully resolved city and country from coordinates
        # Convert ISO code to full country name using Countries library
        country_name = country_name_from_code(country_code)

        if country_name do
          {city_name, country_name}
        else
          # Unknown country code - log and fall back to address detection
          Logger.warning(
            "Unknown country code #{inspect(country_code)} for (#{latitude}, #{longitude}). Falling back to address parsing."
          )

          {city_name, detect_country_from_address(address)}
        end

      {:error, reason} ->
        # Geocoding failed - log and fall back to conservative parsing
        Logger.warning(
          "Geocoding failed for (#{inspect(latitude)}, #{inspect(longitude)}): #{reason}. Falling back to address parsing."
        )

        parse_location_from_address_conservative(address)
    end
  end

  # Convert ISO 2-letter country code to full country name using Countries library
  # Uses common/short names for better readability
  @common_country_names %{
    "GB" => "United Kingdom",
    "US" => "United States"
  }

  defp country_name_from_code(code) when is_binary(code) do
    upcase_code = String.upcase(code)

    # First check our common names mapping for better readability
    case Map.get(@common_country_names, upcase_code) do
      nil ->
        # Fall back to Countries library
        case Countries.get(upcase_code) do
          nil -> nil
          country -> country.name
        end

      common_name ->
        common_name
    end
  end

  defp country_name_from_code(_), do: nil

  # Private functions

  # Parse coordinate string to float
  defp parse_coordinate(coord) when is_binary(coord) do
    case Float.parse(coord) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp parse_coordinate(coord) when is_float(coord), do: coord
  defp parse_coordinate(_), do: nil

  # Build time_text from venue_data components
  defp build_time_text(venue_data) do
    day = venue_data.day_of_week || "Unknown"

    # Handle both nil and empty string from venue extractor
    # Return nil to trigger 8pm fallback in parse_time_with_fallback
    time =
      case venue_data.start_time do
        "" -> nil
        nil -> nil
        t -> t
      end

    "#{day} at #{time}"
  end

  # Detect timezone from country and address
  defp detect_timezone(country, address) do
    cond do
      # UK events (most common)
      country == "United Kingdom" ->
        "Europe/London"

      # Ireland - same timezone as UK
      country == "Ireland" ->
        "Europe/Dublin"

      # US events - check address for state/city clues
      country == "United States" ->
        detect_us_timezone(address)

      # UAE events
      country == "United Arab Emirates" ->
        "Asia/Dubai"

      # Australia
      country == "Australia" ->
        "Australia/Sydney"

      # Default to Europe/London for unknown countries (most Speed Quizzing events are UK-based)
      true ->
        Logger.debug("Unknown country #{country}, defaulting to Europe/London")
        "Europe/London"
    end
  end

  # Detect US timezone from address (basic heuristic)
  defp detect_us_timezone(address) when is_binary(address) do
    address_lower = String.downcase(address)

    cond do
      # West Coast
      String.contains?(address_lower, [
        "ca ",
        "california",
        "seattle",
        "portland",
        "san francisco",
        "los angeles"
      ]) ->
        "America/Los_Angeles"

      # Mountain
      String.contains?(address_lower, ["co ", "colorado", "denver", "phoenix", "az ", "arizona"]) ->
        "America/Denver"

      # Central
      String.contains?(address_lower, ["tx ", "texas", "chicago", "il ", "illinois"]) ->
        "America/Chicago"

      # Default to Eastern (most populous)
      true ->
        "America/New_York"
    end
  end

  defp detect_us_timezone(_), do: "America/New_York"

  # Calculate starts_at DateTime using RecurringEventParser
  defp calculate_starts_at(time_text, timezone, _venue_data) do
    with {:ok, day_of_week} <- RecurringEventParser.parse_day_of_week(time_text),
         {:ok, time_struct} <- RecurringEventParser.parse_time_with_fallback(time_text) do
      RecurringEventParser.next_occurrence(day_of_week, time_struct, timezone)
    else
      {:error, reason} ->
        Logger.warning("Could not calculate starts_at: #{reason}")
        nil
    end
  end

  # Conservative fallback parser - only extracts city if high confidence
  defp parse_location_from_address_conservative(address) when is_binary(address) do
    parts = String.split(address, ",")

    case parts do
      # Has at least 3 parts (street, city, state+zip)
      [_street, city_candidate, _state_zip | _rest] ->
        city_trimmed = String.trim(city_candidate)

        # Validate the city candidate before using it
        case CityResolver.validate_city_name(city_trimmed) do
          {:ok, validated_city} ->
            country = detect_country_from_address(address)
            {validated_city, country}

          {:error, _reason} ->
            Logger.warning(
              "Address parsing found invalid city candidate: #{inspect(city_trimmed)} from address: #{address}"
            )

            country = detect_country_from_address(address)
            {nil, country}
        end

      # Not enough parts or unexpected format - prefer nil
      _ ->
        Logger.debug("Could not parse city from address: #{address}")
        country = detect_country_from_address(address)
        {nil, country}
    end
  end

  defp parse_location_from_address_conservative(_) do
    {nil, "United Kingdom"}
  end

  # Irish cities for country detection (lowercase for matching)
  @irish_cities ~w(dublin galway cork limerick waterford wexford sligo kilkenny
                   drogheda dundalk tralee killarney athlone ennis navan letterkenny
                   carlow cavan longford mullingar newbridge naas bray greystones
                   arklow wicklow tullamore portlaoise clonmel thurles nenagh
                   carrick-on-shannon roscommon castlebar westport ballina
                   tuam ballinasloe loughrea clifden)

  # Detect country from address postcode patterns
  defp detect_country_from_address(address) when is_binary(address) do
    address_lower = String.downcase(address)

    cond do
      # Irish Eircode pattern (e.g., "H91 F880", "D02 XY45", "A65 T123")
      # Format: one letter + 2 digits + space + 4 alphanumeric
      String.match?(address, ~r/\b[A-Z][0-9]{2}\s?[A-Z0-9]{4}\b/i) ->
        "Ireland"

      # "Ireland" explicitly in address
      String.contains?(address_lower, "ireland") ->
        "Ireland"

      # Irish city names in address
      contains_irish_city?(address_lower) ->
        "Ireland"

      # UK postcode pattern (e.g., "SW1A 1AA", "M1 1AE")
      # Must come AFTER Eircode check since patterns can overlap
      String.match?(address, ~r/\b[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}\b/) ->
        "United Kingdom"

      # US zip code pattern (e.g., "12345" or "12345-6789")
      String.match?(address, ~r/\b[0-9]{5}(?:-[0-9]{4})?\b/) ->
        "United States"

      # UAE indicators
      String.contains?(address_lower, ["dubai", "abu dhabi", "uae"]) ->
        "United Arab Emirates"

      # Australia indicators
      String.contains?(address_lower, ["australia", "sydney", "melbourne"]) ->
        "Australia"

      # Default to UK (most common for Speed Quizzing)
      true ->
        "United Kingdom"
    end
  end

  defp detect_country_from_address(_), do: "United Kingdom"

  # Check if address contains any Irish city name
  defp contains_irish_city?(address_lower) do
    Enum.any?(@irish_cities, fn city ->
      # Match city as whole word (with word boundaries)
      String.match?(address_lower, ~r/\b#{Regex.escape(city)}\b/)
    end)
  end

  # Parse pricing from fee text
  defp parse_pricing(fee_text, country) when is_binary(fee_text) do
    # Detect currency from fee text or country
    currency = detect_currency(fee_text, country)

    # Check for free indicators
    free_patterns = [~r/free/i, ~r/no charge/i, ~r/£0/i, ~r/\$0/i, ~r/€0/i]
    is_free = Enum.any?(free_patterns, fn pattern -> String.match?(fee_text, pattern) end)

    if is_free do
      {true, nil, nil, currency}
    else
      # Extract amount from fee text
      case Regex.run(~r/(£|\$|€)\s*([0-9]+(?:\.[0-9]{2})?)/, fee_text) do
        [_, _symbol, amount] ->
          # Handle both integer ("2") and float ("2.50") strings
          price =
            if String.contains?(amount, ".") do
              String.to_float(amount)
            else
              String.to_integer(amount) * 1.0
            end

          {false, price, price, currency}

        _ ->
          # Default: assume £2 based on VenueExtractor default
          {false, 2.0, 2.0, currency}
      end
    end
  end

  defp parse_pricing(_, country) do
    # No fee text - default to £2 based on VenueExtractor
    currency = detect_currency("", country)
    {false, 2.0, 2.0, currency}
  end

  # Detect currency from fee text or country
  defp detect_currency(fee_text, country) when is_binary(fee_text) do
    cond do
      String.contains?(fee_text, "£") -> "GBP"
      String.contains?(fee_text, "$") and country == "United States" -> "USD"
      String.contains?(fee_text, "$") -> "USD"
      String.contains?(fee_text, "€") -> "EUR"
      country == "United Kingdom" -> "GBP"
      country == "Ireland" -> "EUR"
      country == "United States" -> "USD"
      country == "United Arab Emirates" -> "AED"
      country == "Australia" -> "AUD"
      true -> "GBP"
    end
  end

  defp detect_currency(_, country), do: detect_currency("", country)

  # Build description from venue data
  # Includes host name if available (hybrid approach - not stored in performers table)
  defp build_description(venue_data) do
    base_description = venue_data.description || "Weekly trivia night at #{venue_data.venue_name}"

    # Add host to description if present
    base_description =
      if venue_data.performer && venue_data.performer[:name] do
        "#{base_description} with host #{venue_data.performer[:name]}"
      else
        base_description
      end

    additional_info =
      [
        venue_data.fee,
        "#{venue_data.day_of_week} at #{venue_data.start_time}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == "" or &1 == "Unknown"))
      |> Enum.join(" • ")

    if additional_info != "" do
      "#{base_description}\n\n#{additional_info}"
    else
      base_description
    end
  end

  # Add hours to a DateTime
  defp add_hours(datetime, hours) do
    DateTime.add(datetime, hours * 3600, :second)
  end
end
