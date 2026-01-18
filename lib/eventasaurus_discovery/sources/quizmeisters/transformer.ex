defmodule EventasaurusDiscovery.Sources.Quizmeisters.Transformer do
  @moduledoc """
  Transforms Quizmeisters venue data into unified event format with recurrence patterns.

  Quizmeisters provides weekly recurring trivia events at venues with:
  - GPS coordinates provided directly by storerocket.io API (no geocoding needed)
  - Performer information from venue detail pages
  - Weekly recurring schedule with recurrence_rule support
  - Australia-based events (Australia/Sydney timezone primarily)

  ## Transformation Strategy
  - Use provided GPS coordinates (latitude/longitude)
  - Resolve city names using offline geocoding via CityResolver
  - Parse time_text to extract day of week and start time
  - Create recurrence_rule for pattern-based occurrences (following PubQuiz/GWD pattern)
  - Calculate next occurrence of the event in America/New_York
  - Create stable external_id for deduplication
  - Set category to "trivia"
  - Link performer via metadata (if available)

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
  alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

  @doc """
  Transform venue data to unified event format.

  ## Parameters
  - `venue_data` - Map with extracted venue fields
  - `options` - Optional configuration (unused currently)

  ## Returns
  - Unified event format map (see SCRAPER_SPECIFICATION.md)

  ## Required venue_data Fields
  - venue_id, name, address, latitude, longitude, starts_at, source_url

  ## Optional venue_data Fields
  - phone, postcode, description, time_text
  """
  def transform_event(venue_data, _options \\ %{}) do
    name = venue_data.name
    address = venue_data.address

    # GPS coordinates provided directly by API
    latitude = venue_data.latitude
    longitude = venue_data.longitude

    # starts_at already calculated by VenueDetailJob
    starts_at = venue_data.starts_at

    # Generate stable external_id from venue_id
    external_id = "quizmeisters_#{venue_data.venue_id}"

    # Resolve city and country using offline geocoding
    {city, country} = resolve_location(latitude, longitude, address)

    # Parse schedule to recurrence_rule (for pattern-based occurrences)
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
      title: "Quizmeisters Trivia at #{name}",
      starts_at: starts_at,

      # Venue data (REQUIRED - GPS coordinates provided by API)
      venue_data: %{
        name: name,
        address: address,
        city: city,
        country: country,
        latitude: latitude,
        longitude: longitude,
        phone: venue_data[:phone],
        postcode: venue_data[:postcode],
        external_id: "quizmeisters_venue_#{venue_data.venue_id}",
        metadata: %{}
      },

      # Optional fields
      ends_at: if(match?(%DateTime{}, starts_at), do: add_hours(starts_at, 2), else: nil),
      description_translations: %{"en" => build_description(venue_data)},
      source_url: venue_data.source_url,

      # Event/venue image
      image_url: validate_image_url(venue_data[:hero_image_url]),

      # Recurring pattern (enables frontend to generate future dates)
      recurrence_rule: recurrence_rule,

      # Pricing - all Quizmeisters events are free
      is_ticketed: false,
      is_free: true,
      min_price: nil,
      max_price: nil,
      currency: "AUD",

      # Metadata
      metadata: %{
        time_text: venue_data[:time_text],
        venue_id: venue_data.venue_id,
        recurring: true,
        frequency: "weekly",
        start_time: venue_data[:start_time],
        quizmaster: venue_data[:performer],
        # Raw upstream data for debugging (convert to JSON-safe format)
        _raw_upstream: JsonSanitizer.sanitize(venue_data)
      },

      # Category
      category: "trivia"
    }
  end

  @doc """
  Parses time_text into recurrence_rule JSON for pattern-based event occurrences.

  Following the PubQuiz/GWD pattern, this enables the frontend to generate multiple
  future dates from a single recurring event record.

  ## Parameters
  - `time_text` - Schedule text (e.g., "Wednesdays at 7pm")
  - `starts_at` - DateTime with correct timezone from VenueDetailJob calculation
  - `venue_data` - Full venue data map (for timezone fallback from metadata)

  ## Examples

      iex> starts_at = %DateTime{time_zone: "America/Chicago", ...}
      iex> parse_schedule_to_recurrence("Wednesdays at 7pm", starts_at, %{})
      {:ok, %{
        "frequency" => "weekly",
        "days_of_week" => ["wednesday"],
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

  def parse_schedule_to_recurrence(time_text, starts_at, venue_data) when is_binary(time_text) do
    with {:ok, day_of_week} <- RecurringEventParser.parse_day_of_week(time_text),
         {:ok, time_struct} <- RecurringEventParser.parse_time(time_text) do
      # Detect timezone with priority: starts_at > venue_data > default
      timezone =
        cond do
          # Priority 1: Extract from starts_at DateTime (most accurate)
          match?(%DateTime{}, starts_at) ->
            starts_at.time_zone

          # Priority 2: Use explicit timezone from venue metadata
          is_binary(venue_data[:timezone]) ->
            venue_data[:timezone]

          # Priority 3: Fallback to Australia/Sydney (most common for Australian trivia)
          true ->
            "Australia/Sydney"
        end

      # Build recurrence rule using shared helper
      recurrence_rule =
        RecurringEventParser.build_recurrence_rule(day_of_week, time_struct, timezone)

      {:ok, recurrence_rule}
    else
      {:error, _reason} ->
        {:error, "Could not extract day of week or time from time_text: #{time_text}"}
    end
  end

  def parse_schedule_to_recurrence(nil, _starts_at, _venue_data),
    do: {:error, "Time text is nil"}

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

      iex> resolve_location(40.7128, -74.0060, "123 Main St, Brooklyn, NY 11201")
      {"New York City", "United States"}

      iex> resolve_location(nil, nil, "123 Main St, Brooklyn, NY 11201")
      {"Brooklyn", "United States"}  # or {nil, "United States"} if validation fails
  """
  def resolve_location(latitude, longitude, address) do
    case CityResolver.resolve_city(latitude, longitude) do
      {:ok, city_name} ->
        # Successfully resolved city from coordinates
        {city_name, "Australia"}

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
            {validated_city, "Australia"}

          {:error, _reason} ->
            # City candidate failed validation (postcode, street address, etc.)
            Logger.warning(
              "Address parsing found invalid city candidate: #{inspect(city_trimmed)} from address: #{address}"
            )

            {nil, "Australia"}
        end

      # Not enough parts or unexpected format - prefer nil
      _ ->
        Logger.debug("Could not parse city from address: #{address}")
        {nil, "Australia"}
    end
  end

  defp parse_location_from_address_conservative(_), do: {nil, "Australia"}

  # Build description from venue data
  # Includes quizmaster/host name if available (hybrid approach - not stored in performers table)
  defp build_description(venue_data) do
    base_description = venue_data[:description] || "Weekly trivia night at #{venue_data.name}"

    # Add quizmaster/host to description if present
    base_description =
      if venue_data[:performer] && venue_data[:performer][:name] do
        "#{base_description} with Quizmaster #{venue_data[:performer][:name]}"
      else
        base_description
      end

    additional_info =
      [
        "Free to play",
        venue_data[:time_text]
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

  # Validate image URLs - filter out placeholder images
  defp validate_image_url(nil), do: nil
  defp validate_image_url(""), do: nil

  defp validate_image_url(url) when is_binary(url) do
    # Check for known invalid placeholder images
    downcased = String.downcase(url)

    cond do
      # Filter out Webflow placeholder images
      String.contains?(downcased, "/placeholder") -> nil
      # Filter out tiny thumbnails
      String.contains?(downcased, "/thumb/") -> nil
      # Valid URL
      true -> url
    end
  end

  defp validate_image_url(_), do: nil
end
