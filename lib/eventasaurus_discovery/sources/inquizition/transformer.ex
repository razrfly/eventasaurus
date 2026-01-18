defmodule EventasaurusDiscovery.Sources.Inquizition.Transformer do
  @moduledoc """
  Transforms Inquizition venue data into unified event format with recurrence patterns.

  Inquizition provides weekly recurring trivia events at UK venues with:
  - GPS coordinates provided directly by StoreLocatorWidgets CDN (no geocoding needed)
  - Weekly recurring schedule with recurrence_rule support
  - UK-based events (Europe/London timezone)
  - Standard £2.50 entry fee for all events
  - No performer information
  - No event images

  ## Transformation Strategy
  - Use provided GPS coordinates (latitude/longitude)
  - Resolve city names using offline geocoding via CityResolver
  - Parse schedule text and filters to extract day of week and start time
  - Create recurrence_rule for pattern-based occurrences
  - Calculate next occurrence of the event in Europe/London
  - Create stable external_id for deduplication
  - Set category to "trivia"
  - Set standard pricing: £2.50, ticketed

  ## Recurring Event Pattern
  Uses `recurrence_rule` field to enable frontend generation of future dates:
  - One database record represents all future occurrences
  - Frontend generates next 4+ dates dynamically
  - Always shows upcoming events (no stale past dates)
  """

  require Logger

  alias EventasaurusDiscovery.Helpers.CityResolver
  alias EventasaurusDiscovery.Sources.Inquizition.Helpers.ScheduleHelper

  @doc """
  Transform venue data to unified event format.

  ## Parameters
  - `venue_data` - Map with extracted venue fields
  - `options` - Optional configuration (unused currently)

  ## Returns
  - Unified event format map (see SCRAPER_SPECIFICATION.md)

  ## Required venue_data Fields
  - venue_id, name, address, latitude, longitude, day_filters, schedule_text

  ## Optional venue_data Fields
  - phone, website, email
  """
  def transform_event(venue_data, _options \\ %{}) do
    name = venue_data.name
    address = venue_data.address

    # GPS coordinates provided directly by CDN
    latitude = venue_data.latitude
    longitude = venue_data.longitude

    # Parse schedule to get day and time (with fallback to weekly defaults)
    {day_of_week, start_time, starts_at, recurrence_rule} =
      parse_schedule(venue_data[:day_filters], venue_data[:schedule_text])

    # Track whether schedule was inferred (guard against nil recurrence_rule)
    schedule_inferred =
      case recurrence_rule do
        m when is_map(m) -> Map.get(m, "schedule_inferred", false)
        _ -> false
      end

    # Generate stable external_id for recurring events
    # Format: inquizition_{venue_id} (NO date - one record per venue pattern)
    # See docs/EXTERNAL_ID_CONVENTIONS.md - dates in recurring event IDs cause duplicates
    external_id = "inquizition_#{venue_data.venue_id}"

    # Resolve city and country using offline geocoding
    {city, country} = resolve_location(latitude, longitude, address)

    %{
      # Required fields
      external_id: external_id,
      title: "Inquizition Trivia at #{name}",
      starts_at: starts_at,

      # Venue data (REQUIRED - GPS coordinates provided by CDN)
      venue_data: %{
        name: name,
        address: address,
        city: city,
        country: country,
        latitude: latitude,
        longitude: longitude,
        phone: venue_data[:phone],
        postcode: extract_postcode(address),
        external_id: "inquizition_venue_#{venue_data.venue_id}",
        metadata: %{}
      },

      # Optional fields
      ends_at: if(match?(%DateTime{}, starts_at), do: add_hours(starts_at, 2), else: nil),
      description: build_description(venue_data, day_of_week, start_time),
      source_url: "https://inquizition.com/find-a-quiz/",

      # No images available from Inquizition
      image_url: nil,

      # Recurring pattern (enables frontend to generate future dates)
      recurrence_rule: recurrence_rule,

      # Pricing - all Inquizition events are £2.50
      is_ticketed: true,
      is_free: false,
      min_price: 2.50,
      max_price: 2.50,
      currency: "GBP",

      # Metadata
      metadata: %{
        schedule_text: venue_data[:schedule_text],
        venue_id: venue_data.venue_id,
        recurring: true,
        frequency: "weekly",
        day_of_week: if(day_of_week, do: Atom.to_string(day_of_week), else: nil),
        start_time: if(start_time, do: Time.to_string(start_time), else: nil),
        timezone: venue_data[:timezone] || "Europe/London",
        schedule_inferred: schedule_inferred,
        website: venue_data[:website],
        email: venue_data[:email],
        # Raw upstream data for debugging
        _raw_upstream: venue_data
      },

      # Category
      category: "trivia"
    }
  end

  @doc """
  Parse schedule from day filters and schedule text.

  Returns tuple: {day_atom, time_struct, next_occurrence_datetime, recurrence_rule_map}

  ## Minimum Requirements
  - MUST have day information from either day_filters OR schedule_text
  - If day found but time missing: defaults to 8:00 PM (common trivia start time)
  - If neither day nor time can be parsed: returns {nil, nil, nil, nil} to reject venue

  ## Examples

      iex> parse_schedule(["Tuesday"], "Tuesdays, 6.30pm")
      {:tuesday, ~T[18:30:00], %DateTime{...}, %{"frequency" => "weekly", ...}}

      iex> parse_schedule(["Tuesday"], nil)
      {:tuesday, ~T[20:00:00], %DateTime{...}, %{"frequency" => "weekly", ...}}  # Time fallback

      iex> parse_schedule([], nil)
      {nil, nil, nil, nil}  # Rejected - no day information
  """
  def parse_schedule(day_filters, schedule_text) do
    # Try to get day from filters first, then from schedule text
    day_result =
      case ScheduleHelper.parse_day_from_filters(day_filters) do
        {:ok, day} -> {:ok, day}
        _ when is_binary(schedule_text) -> parse_day_from_text(schedule_text)
        _ -> {:error, "Could not parse day"}
      end

    # Try to get time from schedule text
    time_result =
      case schedule_text do
        text when is_binary(text) -> ScheduleHelper.parse_time_from_text(text)
        _ -> {:error, "Could not parse time"}
      end

    # MINIMUM REQUIREMENT: Must have day information
    # We can default time to 8:00 PM, but we CANNOT assume a day of the week
    case {day_result, time_result} do
      {{:ok, day}, {:ok, time}} ->
        # Perfect: both day and time parsed
        starts_at = ScheduleHelper.next_occurrence(day, time, "Europe/London")

        recurrence_rule = %{
          "frequency" => "weekly",
          "days_of_week" => [Atom.to_string(day)],
          "time" => Time.to_string(time) |> String.slice(0, 5),
          "timezone" => "Europe/London",
          "schedule_inferred" => false
        }

        {day, time, starts_at, recurrence_rule}

      {{:ok, day}, {:error, time_reason}} ->
        # Day found, time missing: use 8:00 PM default
        Logger.warning(
          "⚠️ Could not parse time: #{time_reason}. Defaulting to 8:00 PM for day #{day}."
        )

        {:ok, fallback_time} = Time.new(20, 0, 0)
        starts_at = ScheduleHelper.next_occurrence(day, fallback_time, "Europe/London")

        recurrence_rule = %{
          "frequency" => "weekly",
          "days_of_week" => [Atom.to_string(day)],
          "time" => "20:00",
          "timezone" => "Europe/London",
          "schedule_inferred" => true
        }

        {day, fallback_time, starts_at, recurrence_rule}

      {{:error, day_reason}, _} ->
        # No day information: REJECT venue
        Logger.warning(
          "⚠️ Could not parse day of week: #{day_reason}. Cannot create event without day information. Filters: #{inspect(day_filters)}, Schedule: #{inspect(schedule_text)}"
        )

        {nil, nil, nil, nil}
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
          # Unknown country code - log and fall back to UK default
          Logger.warning(
            "Unknown country code #{inspect(country_code)} for (#{latitude}, #{longitude}). Defaulting to United Kingdom."
          )

          {city_name, "United Kingdom"}
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

  # Parse day from schedule text
  defp parse_day_from_text(text) when is_binary(text) do
    day_patterns = %{
      monday: ~r/\b(mondays?|mon)\b/i,
      tuesday: ~r/\b(tuesdays?|tues?)\b/i,
      wednesday: ~r/\b(wednesdays?|wed)\b/i,
      thursday: ~r/\b(thursdays?|thurs?)\b/i,
      friday: ~r/\b(fridays?|fri)\b/i,
      saturday: ~r/\b(saturdays?|sat)\b/i,
      sunday: ~r/\b(sundays?|sun)\b/i
    }

    text_lower = String.downcase(text)

    case Enum.find(day_patterns, fn {_day, pattern} ->
           String.match?(text_lower, pattern)
         end) do
      {day, _pattern} -> {:ok, day}
      nil -> {:error, "Could not parse day from text: #{text}"}
    end
  end

  # Conservative fallback parser - only extracts city if high confidence
  defp parse_location_from_address_conservative(address) when is_binary(address) do
    # UK addresses typically: "Street\nCity\nPostcode"
    parts = String.split(address, "\n") |> Enum.map(&String.trim/1)

    case parts do
      # Has at least 3 parts (street, city, postcode)
      [_street, city_candidate, _postcode | _rest] ->
        city_trimmed = String.trim(city_candidate)

        # Validate the city candidate before using it
        case CityResolver.validate_city_name(city_trimmed) do
          {:ok, validated_city} ->
            {validated_city, "United Kingdom"}

          {:error, _reason} ->
            # City candidate failed validation (postcode, street address, etc.)
            Logger.warning(
              "Address parsing found invalid city candidate: #{inspect(city_trimmed)} from address: #{address}"
            )

            {nil, "United Kingdom"}
        end

      # Not enough parts or unexpected format - prefer nil
      _ ->
        Logger.debug("Could not parse city from address: #{address}")
        {nil, "United Kingdom"}
    end
  end

  defp parse_location_from_address_conservative(_), do: {nil, "United Kingdom"}

  # Extract UK postcode from address
  defp extract_postcode(address) when is_binary(address) do
    # UK postcode pattern: "SW1A 1AA", "EC4M 7JZ", etc.
    case Regex.run(~r/\b([A-Z]{1,2}\d{1,2}[A-Z]?\s?\d[A-Z]{2})\b/, address) do
      [_, postcode] -> String.trim(postcode)
      _ -> nil
    end
  end

  defp extract_postcode(_), do: nil

  # Build description from venue data
  defp build_description(venue_data, day_of_week, start_time) do
    base_description = "Weekly trivia night at #{venue_data.name}"

    schedule_info =
      cond do
        day_of_week && start_time ->
          day_name = day_of_week |> Atom.to_string() |> String.capitalize()
          time_string = Time.to_string(start_time) |> String.slice(0, 5)
          "#{day_name}s at #{time_string}"

        venue_data[:schedule_text] ->
          venue_data[:schedule_text]

        true ->
          nil
      end

    additional_info =
      [
        "£2.50 entry fee",
        schedule_info
      ]
      |> Enum.reject(&is_nil/1)
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
