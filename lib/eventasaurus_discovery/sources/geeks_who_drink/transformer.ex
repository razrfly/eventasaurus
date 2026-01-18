defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Transformer do
  @moduledoc """
  Transforms Geeks Who Drink venue data into unified event format with recurrence patterns.

  Geeks Who Drink provides weekly recurring trivia events at venues with:
  - GPS coordinates provided directly (no geocoding needed)
  - Performer information via AJAX endpoint
  - Weekly recurring schedule with recurrence_rule support
  - US/Canada-based events (America/New_York timezone primarily)

  ## Transformation Strategy
  - Use provided GPS coordinates (latitude/longitude)
  - Resolve city names using offline geocoding via CityResolver
  - Parse time_text to extract day of week and start time
  - Create recurrence_rule for pattern-based occurrences (following PubQuiz pattern)
  - Calculate next occurrence of the event in America/New_York
  - Create stable external_id for deduplication
  - Handle pricing from fee_text
  - Set category to "trivia"
  - Link performer via metadata

  ## Recurring Event Pattern
  Uses `recurrence_rule` field to enable frontend generation of future dates:
  - One database record represents all future occurrences
  - Frontend generates next 4+ dates dynamically
  - Always shows upcoming events (no stale past dates)
  - See docs/RECURRING_EVENT_PATTERNS.md for full specification
  """

  require Logger

  alias EventasaurusDiscovery.Helpers.CityResolver
  alias EventasaurusDiscovery.Sources.Shared.RecurringEventParser

  @doc """
  Transform extracted venue data to unified format.

  ## Parameters
  - `venue_data` - Map with extracted venue fields
  - `options` - Optional configuration (unused currently)

  ## Returns
  - Unified event format map (see SCRAPER_SPECIFICATION.md)

  ## Required venue_data Fields
  - venue_id, title, address, latitude, longitude, starts_at, source_url

  ## Optional venue_data Fields
  - fee_text, phone, website, description, facebook, instagram
  - brand, logo_url, time_text (for metadata)
  """
  def transform_event(venue_data, _options \\ %{}) do
    title = venue_data.title
    address = venue_data.address

    # Clean venue name by removing location suffixes and parenthetical notes
    clean_title = clean_venue_name(title)

    # GPS coordinates provided directly
    latitude = venue_data.latitude
    longitude = venue_data.longitude

    # starts_at already calculated by VenueDetailJob
    starts_at = venue_data.starts_at

    # Generate stable external_id from venue_id
    external_id = "geeks_who_drink_#{venue_data.venue_id}"

    # Resolve city and country using offline geocoding
    {city, country} = resolve_location(latitude, longitude, address)

    # Parse pricing from fee_text
    {is_free, min_price} = parse_pricing(venue_data[:fee_text])

    # Parse schedule to recurrence_rule (for pattern-based occurrences)
    # Pass starts_at and venue_data for timezone detection
    recurrence_rule =
      case parse_schedule_to_recurrence(venue_data[:time_text], starts_at, venue_data) do
        {:ok, rule} ->
          rule

        {:error, reason} ->
          Logger.warning("⚠️ Could not create recurrence_rule: #{reason}")
          nil
      end

    %{
      # Required fields
      external_id: external_id,
      title: "Geeks Who Drink Trivia at #{clean_title}",
      starts_at: starts_at,

      # Venue data (REQUIRED - GPS coordinates provided)
      venue_data: %{
        name: clean_title,
        address: address,
        city: city,
        country: country,
        latitude: latitude,
        longitude: longitude,
        phone: venue_data[:phone],
        website: venue_data[:website],
        external_id: "geeks_who_drink_venue_#{venue_data.venue_id}",
        metadata: %{
          brand: venue_data[:brand],
          logo_url: venue_data[:logo_url],
          facebook: venue_data[:facebook],
          instagram: venue_data[:instagram]
        }
      },

      # Optional fields
      ends_at: if(match?(%DateTime{}, starts_at), do: add_hours(starts_at, 2), else: nil),
      description_translations: %{"en" => build_description(venue_data)},
      source_url: venue_data.source_url,
      image_url: venue_data[:logo_url],

      # Recurring pattern (enables frontend to generate future dates)
      recurrence_rule: recurrence_rule,

      # Pricing
      is_ticketed: not is_free,
      is_free: is_free,
      min_price: min_price,
      max_price: nil,
      currency: "USD",

      # Metadata
      metadata: %{
        time_text: venue_data[:time_text],
        fee_text: venue_data[:fee_text],
        venue_id: venue_data.venue_id,
        recurring: true,
        frequency: "weekly",
        brand: venue_data[:brand],
        start_time: venue_data[:start_time],
        facebook: venue_data[:facebook],
        instagram: venue_data[:instagram],
        # Quizmaster stored in metadata (hybrid approach - not in performers table)
        quizmaster: venue_data[:performer],
        # Raw upstream data for debugging
        _raw_upstream: venue_data
      },

      # Category
      category: "trivia"
    }
  end

  @doc """
  Parses time_text into recurrence_rule JSON for pattern-based event occurrences.

  Following the PubQuiz pattern, this enables the frontend to generate multiple
  future dates from a single recurring event record.

  ## Parameters
  - `time_text` - Schedule text (e.g., "Tuesdays at 7:00 pm")
  - `starts_at` - DateTime with correct timezone from VenueDetailJob calculation
  - `venue_data` - Full venue data map (for timezone fallback from metadata)

  ## Examples

      iex> starts_at = %DateTime{time_zone: "America/Chicago", ...}
      iex> parse_schedule_to_recurrence("Tuesdays at 7:00 pm", starts_at, %{})
      {:ok, %{
        "frequency" => "weekly",
        "days_of_week" => ["tuesday"],
        "time" => "19:00",
        "timezone" => "America/Chicago"
      }}

  ## Returns
  - `{:ok, recurrence_rule_map}` - Successfully parsed schedule
  - `{:error, reason}` - Parsing failed

  ## Timezone Detection Priority
  1. Extract from starts_at DateTime (calculated by VenueDetailJob with correct zone)
  2. Use venue_data[:timezone] if present
  3. Fallback to "America/New_York" (Eastern Time)
  """
  def parse_schedule_to_recurrence(time_text, starts_at \\ nil, venue_data \\ %{})

  def parse_schedule_to_recurrence(nil, _starts_at, _venue_data),
    do: {:error, "Time text is nil"}

  def parse_schedule_to_recurrence(time_text, starts_at, venue_data) when is_binary(time_text) do
    # Extract recurrence information from starts_at DateTime
    # VenueDetailJob already calculated correct next occurrence with timezone
    # We just need to extract day_of_week and time from it
    # timezone comes from venue_data (VenueDetailJob adds it)

    case extract_from_datetime(starts_at, venue_data) do
      {:ok, {day_of_week, time_string, timezone}} ->
        # Log for debugging pattern-type occurrence creation
        Logger.debug("""
        [Transformer] Creating recurrence_rule from starts_at:
        - Day of week: #{day_of_week}
        - Time: #{time_string}
        - Timezone: #{timezone}
        """)

        recurrence_rule = %{
          "frequency" => "weekly",
          "days_of_week" => [day_of_week],
          "time" => time_string,
          "timezone" => timezone
        }

        {:ok, recurrence_rule}

      {:error, reason} ->
        # Fallback: try parsing time_text if starts_at extraction failed
        Logger.warning("Failed to extract from starts_at (#{reason}), trying time_text...")
        fallback_parse_time_text(time_text, venue_data)
    end
  end

  # Extract day_of_week, time, and timezone from DateTime
  # Uses timezone from venue_data since UTC DateTime loses original timezone info
  defp extract_from_datetime(%DateTime{} = dt, venue_data) when is_map(venue_data) do
    # Get timezone from venue_data (VenueDetailJob MUST provide this)
    timezone =
      cond do
        is_binary(venue_data[:timezone]) ->
          venue_data[:timezone]

        is_binary(venue_data["timezone"]) ->
          venue_data["timezone"]

        true ->
          # This should never happen now that VenueDetailJob determines timezone
          Logger.error(
            "Missing timezone in venue_data for venue #{venue_data[:venue_id]}. VenueDetailJob should always provide timezone."
          )

          {:error, "Missing timezone in venue_data"}
      end

    case timezone do
      {:error, _} = error ->
        error

      tz when is_binary(tz) ->
        # Convert UTC DateTime to local timezone to get correct day/time
        local_dt = DateTime.shift_zone!(dt, tz)

        # Get day of week as string (e.g., "tuesday") from LOCAL time
        day_num = Date.day_of_week(DateTime.to_date(local_dt), :monday)
        day_of_week = number_to_day(day_num)

        # Get time in HH:MM format from LOCAL time
        time_string =
          local_dt
          |> DateTime.to_time()
          |> Time.to_string()
          |> String.slice(0, 5)

        {:ok, {day_of_week, time_string, tz}}
    end
  rescue
    error ->
      {:error, "DateTime extraction failed: #{inspect(error)}"}
  end

  defp extract_from_datetime(_, _), do: {:error, "Invalid or missing DateTime"}

  # Convert ISO day number to day name string
  defp number_to_day(1), do: "monday"
  defp number_to_day(2), do: "tuesday"
  defp number_to_day(3), do: "wednesday"
  defp number_to_day(4), do: "thursday"
  defp number_to_day(5), do: "friday"
  defp number_to_day(6), do: "saturday"
  defp number_to_day(7), do: "sunday"

  # Fallback: parse time_text using RecurringEventParser (for backward compatibility)
  defp fallback_parse_time_text(time_text, venue_data) do
    # RecurringEventParser doesn't have parse_time_text, so we need to parse day and time separately
    with {:ok, day_of_week} <- RecurringEventParser.parse_day_of_week(time_text),
         {:ok, time_struct} <- RecurringEventParser.parse_time(time_text) do
      # Convert Time struct to HH:MM string format
      time_string = Time.to_string(time_struct) |> String.slice(0, 5)

      # Get timezone from venue_data (VenueDetailJob MUST provide this)
      timezone =
        cond do
          is_binary(venue_data[:timezone]) ->
            venue_data[:timezone]

          is_binary(venue_data["timezone"]) ->
            venue_data["timezone"]

          true ->
            # This should never happen now that VenueDetailJob determines timezone
            Logger.error(
              "Missing timezone in venue_data for venue #{venue_data[:venue_id]} during fallback parse. VenueDetailJob should always provide timezone."
            )

            nil
        end

      case timezone do
        nil ->
          {:error, "Missing timezone in venue_data"}

        tz when is_binary(tz) ->
          recurrence_rule = %{
            "frequency" => "weekly",
            "days_of_week" => [Atom.to_string(day_of_week)],
            "time" => time_string,
            "timezone" => tz
          }

          {:ok, recurrence_rule}
      end
    else
      {:error, _reason} ->
        {:error, "Could not extract day of week from time_text: #{time_text}"}
    end
  end

  @doc """
  Resolves city and country from GPS coordinates using offline geocoding.

  Uses CityResolver for reliable city name extraction from coordinates.
  Falls back to conservative address parsing if geocoding fails.

  ## Parameters
  - `latitude` - GPS latitude coordinate
  - `longitude` - GPS longitude coordinate
  - `address` - Full address string (fallback only)

  ## Returns
  - `{city_name, country}` tuple

  ## Examples

      iex> resolve_location(40.7128, -74.0060, "123 Main St, New York, NY 10001")
      {"New York City", "United States"}

      iex> resolve_location(nil, nil, "123 Main St, New York, NY 10001")
      {"New York", "United States"}  # or {nil, "United States"} if validation fails
  """
  def resolve_location(latitude, longitude, address) do
    case CityResolver.resolve_city(latitude, longitude) do
      {:ok, city_name} ->
        # Successfully resolved city from coordinates
        {city_name, "United States"}

      {:error, reason} ->
        # Geocoding failed - log and fall back to conservative parsing
        Logger.warning(
          "Geocoding failed for (#{inspect(latitude)}, #{inspect(longitude)}): #{reason}. Falling back to address parsing."
        )

        parse_location_from_address_conservative(address)
    end
  end

  # Conservative fallback parser - only extracts city if high confidence
  # Prefers nil over garbage data
  defp parse_location_from_address_conservative(address) when is_binary(address) do
    parts = String.split(address, ",")

    case parts do
      # Has at least 3 parts (street, city, state+zip)
      [_street, city_candidate, _state_zip | _rest] ->
        city_trimmed = String.trim(city_candidate)

        # Validate the city candidate before using it
        case CityResolver.validate_city_name(city_trimmed) do
          {:ok, validated_city} ->
            {validated_city, "United States"}

          {:error, _reason} ->
            # City candidate failed validation (postcode, street address, etc.)
            Logger.warning(
              "Address parsing found invalid city candidate: #{inspect(city_trimmed)} from address: #{address}"
            )

            {nil, "United States"}
        end

      # Not enough parts or unexpected format - prefer nil
      _ ->
        Logger.debug("Could not parse city from address: #{address}")
        {nil, "United States"}
    end
  end

  defp parse_location_from_address_conservative(_), do: {nil, "United States"}

  # Build description from venue data
  # Includes quizmaster name and schedule details (hybrid approach - not stored in performers table)
  defp build_description(venue_data) do
    # Clean venue name for description
    clean_title = clean_venue_name(venue_data.title)

    # Parse day and time from time_text for enhanced description
    day_info = parse_day_from_time_text(venue_data[:time_text])

    # Get timezone from venue_data (VenueDetailJob provides this)
    timezone = venue_data[:timezone] || venue_data["timezone"]

    time_info =
      parse_time_from_time_text(venue_data[:time_text]) ||
        parse_time_from_starts_at(venue_data[:starts_at], timezone)

    # Build base description with schedule if available
    base_description =
      if day_info && time_info do
        "Weekly trivia every #{day_info} at #{time_info} at #{clean_title}"
      else
        venue_data[:description] || "Weekly trivia night at #{clean_title}"
      end

    # Add quizmaster to description if present
    base_description =
      if venue_data[:performer] && venue_data[:performer][:name] do
        "#{base_description} with Quizmaster #{venue_data[:performer][:name]}"
      else
        base_description
      end

    # Add fee information if available (time_text now incorporated into base description)
    additional_info =
      [venue_data[:fee_text]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    if additional_info != "" do
      "#{base_description}\n\n#{additional_info}"
    else
      base_description
    end
  end

  # Parse day of week from time_text (e.g., "Tuesdays at 7pm" -> "Tuesday")
  defp parse_day_from_time_text(time_text) when is_binary(time_text) do
    case RecurringEventParser.parse_day_of_week(time_text) do
      {:ok, day_atom} ->
        day_atom
        |> Atom.to_string()
        |> String.capitalize()

      _ ->
        nil
    end
  end

  defp parse_day_from_time_text(_), do: nil

  # Parse time from time_text (e.g., "Tuesdays at 7pm" -> "7pm")
  defp parse_time_from_time_text(time_text) when is_binary(time_text) do
    case Regex.run(~r/at\s+(\d+(?::\d+)?\s*[ap]m)/i, time_text) do
      [_, time] -> time
      _ -> nil
    end
  end

  defp parse_time_from_time_text(_), do: nil

  # Parse time from starts_at DateTime (fallback)
  # IMPORTANT: Must convert UTC to local timezone before extracting time
  # See Issue #3022 - without timezone conversion, UTC times like 04:00 are displayed
  # instead of local times like 8:00 PM
  defp parse_time_from_starts_at(%DateTime{} = dt, timezone) when is_binary(timezone) do
    # Convert UTC DateTime to local timezone before extracting time
    local_dt = DateTime.shift_zone!(dt, timezone)

    local_dt
    |> DateTime.to_time()
    |> Calendar.strftime("%I:%M%p")
    |> String.downcase()
    # "07:00pm" -> "7pm", "08:00pm" -> "8pm"
    |> String.replace(~r/^0/, "")
    |> String.replace(~r/:00/, "")
  rescue
    # If timezone conversion fails, log and return nil
    error ->
      Logger.warning("Failed to convert time to timezone #{timezone}: #{inspect(error)}")
      nil
  end

  defp parse_time_from_starts_at(%DateTime{} = _dt, nil) do
    # No timezone available - can't safely convert
    Logger.warning("Cannot format time from starts_at: no timezone provided")
    nil
  end

  defp parse_time_from_starts_at(_, _), do: nil

  # Parse pricing information from fee_text
  # Returns {is_free, min_price}
  defp parse_pricing(nil), do: {true, nil}

  defp parse_pricing(fee_text) when is_binary(fee_text) do
    fee_lower = String.downcase(fee_text)

    cond do
      # Check for "free" keyword
      String.contains?(fee_lower, "free") ->
        {true, nil}

      # Try to extract price (e.g., "$5", "$10.00")
      price_match = Regex.run(~r/\$(\d+(?:\.\d{2})?)/, fee_text) ->
        [_, price_str] = price_match
        {false, Decimal.new(price_str)}

      # Try to extract price without dollar sign
      price_match = Regex.run(~r/(\d+(?:\.\d{2})?)\s*(?:per|pp|p\/p|dollars?)/i, fee_text) ->
        [_, price_str] = price_match
        {false, Decimal.new(price_str)}

      # Can't determine - assume not free but price unknown
      true ->
        {false, nil}
    end
  end

  @doc """
  Cleans venue names by removing extraneous text from Geeks Who Drink API.

  Removes:
  - Location suffixes after @ symbol (e.g., "@Alamo Drafthouse Westminster")
  - Parenthetical notes (e.g., "(check venue for reservations!)", "(Monday)")
  - Extra whitespace

  ## Examples

      iex> clean_venue_name("Wild Corgi Pub (check venue for reservations!)")
      "Wild Corgi Pub"

      iex> clean_venue_name("Pandora's Box @Alamo Drafthouse Westminster (Monday)")
      "Pandora's Box"

      iex> clean_venue_name("Glass Half Full @Alamo Drafthouse Littleton (Wednesday)")
      "Glass Half Full"
  """
  def clean_venue_name(name) when is_binary(name) do
    name
    # Remove everything after @ (location suffixes)
    |> String.split("@")
    |> List.first()
    # Remove parenthetical notes
    |> String.replace(~r/\s*\([^)]*\)/, "")
    # Trim extra whitespace
    |> String.trim()
  end

  def clean_venue_name(nil), do: nil

  # Add hours to a DateTime
  defp add_hours(datetime, hours) do
    DateTime.add(datetime, hours * 3600, :second)
  end
end
