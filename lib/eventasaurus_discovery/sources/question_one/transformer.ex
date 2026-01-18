defmodule EventasaurusDiscovery.Sources.QuestionOne.Transformer do
  @moduledoc """
  Transforms Question One venue data into unified event format with recurrence patterns.

  Question One provides weekly recurring trivia events at venues.
  Each venue gets one event with a recurrence_rule that enables the frontend
  to generate multiple future occurrences.

  ## Transformation Strategy
  - Parse time_text to extract day of week and start time
  - Create recurrence_rule for pattern-based occurrences (following PubQuiz pattern)
  - Calculate next occurrence of the event
  - Create stable external_id for deduplication
  - Extract city from address
  - Handle pricing from fee_text
  - Set category to "trivia"

  ## Recurring Event Pattern
  Uses `recurrence_rule` field to enable frontend generation of future dates:
  - One database record represents all future occurrences
  - Frontend generates next 4+ dates dynamically
  - Always shows upcoming events (no stale past dates)
  - See docs/RECURRING_EVENT_PATTERNS.md for full specification
  """

  require Logger
  alias EventasaurusDiscovery.Sources.QuestionOne.Helpers.TextHelper
  alias EventasaurusDiscovery.Sources.Shared.RecurringEventParser
  alias EventasaurusDiscovery.Locations.CountryResolver

  @doc """
  Transform extracted venue data to unified format.

  ## Parameters
  - `venue_data` - Map with extracted venue fields
  - `options` - Optional configuration (unused currently)

  ## Returns
  - Unified event format map (see SCRAPER_SPECIFICATION.md)

  ## Required venue_data Fields
  - title, address, time_text, source_url

  ## Optional venue_data Fields
  - fee_text, phone, website, description, hero_image_url
  """
  def transform_event(venue_data, _options \\ %{}) do
    # HTML entities are now decoded in VenueExtractor.clean_title/1
    # No need to decode again here - just use the values directly
    title = venue_data.title
    raw_title = venue_data.raw_title
    address = venue_data.address
    description = venue_data.description

    # Parse time text to get day and time
    {day_of_week, start_time} = parse_time_data(venue_data.time_text)

    # Calculate next occurrence in UTC (Question One events are in Europe/London timezone)
    starts_at = RecurringEventParser.next_occurrence(day_of_week, start_time, "Europe/London")

    # Generate stable external_id for recurring events
    # Format: question_one_{venue_slug} (NO date - one record per venue pattern)
    # See docs/EXTERNAL_ID_CONVENTIONS.md - dates in recurring event IDs cause duplicates
    venue_slug = TextHelper.slugify(title)
    external_id = "question_one_#{venue_slug}"

    # Use geocoded city and country (enriched by venue_detail_job)
    # Default to United Kingdom since Question One is UK-specific
    city = Map.get(venue_data, :city_name)
    country = Map.get(venue_data, :country_name, "United Kingdom")

    # Determine currency from country
    currency = determine_currency(country)

    # Parse pricing from fee_text
    {is_free, min_price} = parse_pricing(venue_data.fee_text)

    # Parse schedule to recurrence_rule (for pattern-based occurrences)
    recurrence_rule =
      case parse_schedule_to_recurrence(venue_data.time_text) do
        {:ok, rule} ->
          rule

        {:error, reason} ->
          Logger.warning("⚠️ Could not create recurrence_rule: #{reason}")
          nil
      end

    %{
      # Required fields
      external_id: external_id,
      title: "Quiz Night at #{title}",
      starts_at: starts_at,

      # Venue data (REQUIRED - VenueProcessor will geocode if coordinates missing)
      venue_data: %{
        name: title,
        address: address,
        city: city,
        country: country,
        latitude: nil,
        longitude: nil,
        phone: venue_data.phone,
        website: venue_data.website,
        external_id: "question_one_venue_#{venue_slug}",
        metadata: %{
          raw_title: raw_title
        }
      },

      # Optional fields
      ends_at: add_hours(starts_at, 2),
      description: description,
      source_url: venue_data.source_url,
      image_url: venue_data.hero_image_url,

      # Recurring pattern (enables frontend to generate future dates)
      recurrence_rule: recurrence_rule,

      # Pricing
      is_ticketed: not is_free,
      is_free: is_free,
      min_price: min_price,
      max_price: nil,
      currency: currency,

      # Metadata
      metadata: %{
        time_text: venue_data.time_text,
        fee_text: venue_data.fee_text,
        day_of_week: Atom.to_string(day_of_week),
        recurring: true,
        frequency: "weekly",
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

  ## Examples

      iex> parse_schedule_to_recurrence("Wednesdays at 8pm")
      {:ok, %{
        "frequency" => "weekly",
        "days_of_week" => ["wednesday"],
        "time" => "20:00",
        "timezone" => "Europe/London"
      }}

      iex> parse_schedule_to_recurrence("Every Monday at 7:30pm")
      {:ok, %{
        "frequency" => "weekly",
        "days_of_week" => ["monday"],
        "time" => "19:30",
        "timezone" => "Europe/London"
      }}

  ## Returns
  - `{:ok, recurrence_rule_map}` - Successfully parsed schedule
  - `{:error, reason}` - Parsing failed
  """
  def parse_schedule_to_recurrence(time_text) when is_binary(time_text) do
    # Parse day and time separately using RecurringEventParser
    with {:ok, day_of_week} <- RecurringEventParser.parse_day_of_week(time_text),
         {:ok, time_struct} <- RecurringEventParser.parse_time(time_text) do
      # Convert Time struct to HH:MM string format
      time_string = Time.to_string(time_struct) |> String.slice(0, 5)

      recurrence_rule = %{
        "frequency" => "weekly",
        "days_of_week" => [Atom.to_string(day_of_week)],
        "time" => time_string,
        "timezone" => "Europe/London"
      }

      {:ok, recurrence_rule}
    else
      {:error, reason} ->
        {:error, "Could not parse time_text: #{reason}"}
    end
  end

  def parse_schedule_to_recurrence(nil), do: {:error, "Time text is nil"}

  # Parse time_text or return defaults if parsing fails
  defp parse_time_data(time_text) do
    # Parse day and time separately using RecurringEventParser
    with {:ok, day} <- RecurringEventParser.parse_day_of_week(time_text),
         {:ok, time} <- RecurringEventParser.parse_time(time_text) do
      {day, time}
    else
      {:error, reason} ->
        Logger.warning("⚠️ Failed to parse time_text '#{time_text}': #{reason}. Using defaults.")
        # Default to Monday at 7pm
        {:monday, ~T[19:00:00]}
    end
  end

  # Determine currency based on country name using Countries library
  defp determine_currency(country) when is_binary(country) do
    case CountryResolver.resolve(country) do
      %{currency_code: currency_code} when is_binary(currency_code) ->
        currency_code

      _ ->
        Logger.warning("Could not determine currency for country: #{country}, defaulting to GBP")
        # Default to GBP for Question One (primarily UK)
        "GBP"
    end
  end

  # Default if country is nil
  defp determine_currency(_), do: "GBP"

  # Parse pricing information from fee_text
  # Returns {is_free, min_price}
  defp parse_pricing(nil), do: {true, nil}

  defp parse_pricing(fee_text) when is_binary(fee_text) do
    fee_lower = String.downcase(fee_text)

    cond do
      # Check for "free" keyword
      String.contains?(fee_lower, "free") ->
        {true, nil}

      # Try to extract price (e.g., "£2", "£5.50")
      price_match = Regex.run(~r/£(\d+(?:\.\d{2})?)/, fee_text) ->
        [_, price_str] = price_match
        {false, Decimal.new(price_str)}

      # Try to extract price with "per person" etc
      price_match = Regex.run(~r/(\d+(?:\.\d{2})?)\s*(?:per|pp|p\/p)/i, fee_text) ->
        [_, price_str] = price_match
        {false, Decimal.new(price_str)}

      # Try to extract plain number (e.g., "2", "3", "1.5")
      price_match = Regex.run(~r/^(\d+(?:\.\d{1,2})?)$/, String.trim(fee_text)) ->
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
