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

    # GPS coordinates provided directly
    latitude = venue_data.latitude
    longitude = venue_data.longitude

    # starts_at already calculated by VenueDetailJob
    starts_at = venue_data.starts_at

    # Generate stable external_id from venue_id
    external_id = "geeks_who_drink_#{venue_data.venue_id}"

    # Extract city and country from address
    {city, country} = parse_location_from_address(address)

    # Parse pricing from fee_text
    {is_free, min_price} = parse_pricing(venue_data[:fee_text])

    # Parse schedule to recurrence_rule (for pattern-based occurrences)
    recurrence_rule =
      case parse_schedule_to_recurrence(venue_data[:time_text], venue_data[:start_time]) do
        {:ok, rule} ->
          rule

        {:error, reason} ->
          Logger.warning("⚠️ Could not create recurrence_rule: #{reason}")
          nil
      end

    %{
      # Required fields
      external_id: external_id,
      title: "Geeks Who Drink Trivia at #{title}",
      starts_at: starts_at,

      # Venue data (REQUIRED - GPS coordinates provided)
      venue_data: %{
        name: title,
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
      description: build_description(venue_data),
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
        instagram: venue_data[:instagram]
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
  - `start_time` - Pre-parsed start time in HH:MM format (fallback if time_text parsing fails)

  ## Examples

      iex> parse_schedule_to_recurrence("Tuesdays at 7:00 pm", "19:00")
      {:ok, %{
        "frequency" => "weekly",
        "days_of_week" => ["tuesday"],
        "time" => "19:00",
        "timezone" => "America/New_York"
      }}

      iex> parse_schedule_to_recurrence("Wednesdays at 8pm", nil)
      {:ok, %{
        "frequency" => "weekly",
        "days_of_week" => ["wednesday"],
        "time" => "20:00",
        "timezone" => "America/New_York"
      }}

  ## Returns
  - `{:ok, recurrence_rule_map}` - Successfully parsed schedule
  - `{:error, reason}` - Parsing failed
  """
  def parse_schedule_to_recurrence(time_text, start_time \\ nil)

  def parse_schedule_to_recurrence(time_text, start_time) when is_binary(time_text) do
    alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Helpers.TimeParser

    case TimeParser.parse_time_text(time_text) do
      {:ok, {day_of_week, time_struct}} ->
        # Convert Time struct to HH:MM string format
        time_string = Time.to_string(time_struct) |> String.slice(0, 5)

        recurrence_rule = %{
          "frequency" => "weekly",
          "days_of_week" => [Atom.to_string(day_of_week)],
          "time" => time_string,
          # US/Canada events use America/New_York timezone by default
          # TODO: Could enhance to detect timezone from venue location (state-based)
          "timezone" => "America/New_York"
        }

        {:ok, recurrence_rule}

      {:error, _reason} ->
        # Fallback to start_time if provided
        if start_time do
          # Still need day of week, can't create full recurrence_rule
          {:error, "Could not extract day of week from time_text: #{time_text}"}
        else
          {:error, "Could not parse time_text and no start_time fallback"}
        end
    end
  end

  def parse_schedule_to_recurrence(nil, _start_time), do: {:error, "Time text is nil"}

  # Parse location from address string
  # US addresses typically: "Street, City, State ZIP"
  defp parse_location_from_address(address) when is_binary(address) do
    parts = String.split(address, ",")

    case parts do
      # Has at least city
      [_street, city | _rest] ->
        {String.trim(city), "United States"}

      # Fallback: use whole address as city
      _ ->
        {address, "United States"}
    end
  end

  defp parse_location_from_address(_), do: {nil, "United States"}

  # Build description from venue data
  defp build_description(venue_data) do
    base_description = venue_data[:description] || "Weekly trivia night at #{venue_data.title}"

    additional_info =
      [
        venue_data[:fee_text],
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


  # Add hours to a DateTime
  defp add_hours(datetime, hours) do
    DateTime.add(datetime, hours * 3600, :second)
  end
end
