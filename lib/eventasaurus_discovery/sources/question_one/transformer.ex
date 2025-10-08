defmodule EventasaurusDiscovery.Sources.QuestionOne.Transformer do
  @moduledoc """
  Transforms Question One venue data into unified event format.

  Question One provides weekly recurring trivia events at venues.
  Each venue gets one event representing the recurring schedule.

  ## Transformation Strategy
  - Parse time_text to extract day of week and start time
  - Calculate next occurrence of the event
  - Create stable external_id for deduplication
  - Extract city from address
  - Handle pricing from fee_text
  - Set category to "trivia"
  """

  require Logger
  alias EventasaurusDiscovery.Sources.QuestionOne.Helpers.DateParser

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
    # Parse time text to get day and time
    {day_of_week, start_time} = parse_time_data(venue_data.time_text)

    # Calculate next occurrence in UTC
    starts_at = DateParser.next_occurrence(day_of_week, start_time)

    # Generate stable external_id
    venue_slug = slugify(venue_data.title)
    external_id = "question_one_#{venue_slug}_#{day_of_week}"

    # Extract city from address
    city = extract_city_from_address(venue_data.address)

    # Parse pricing from fee_text
    {is_free, min_price} = parse_pricing(venue_data.fee_text)

    %{
      # Required fields
      external_id: external_id,
      title: "Trivia Night at #{venue_data.title}",
      starts_at: starts_at,

      # Venue data (REQUIRED - VenueProcessor will geocode)
      venue_data: %{
        name: venue_data.title,
        address: venue_data.address,
        city: city,
        country: "United Kingdom",
        latitude: nil,
        longitude: nil,
        phone: venue_data.phone,
        website: venue_data.website,
        external_id: "question_one_venue_#{venue_slug}",
        metadata: %{
          raw_title: venue_data.raw_title
        }
      },

      # Optional fields
      ends_at: add_hours(starts_at, 2),
      description: venue_data.description,
      source_url: venue_data.source_url,
      image_url: venue_data.hero_image_url,

      # Pricing
      is_ticketed: not is_free,
      is_free: is_free,
      min_price: min_price,
      max_price: nil,
      currency: "GBP",

      # Metadata
      metadata: %{
        time_text: venue_data.time_text,
        fee_text: venue_data.fee_text,
        day_of_week: Atom.to_string(day_of_week),
        recurring: true,
        frequency: "weekly"
      },

      # Category
      category: "trivia"
    }
  end

  # Parse time_text or return defaults if parsing fails
  defp parse_time_data(time_text) do
    case DateParser.parse_time_text(time_text) do
      {:ok, {day, time}} ->
        {day, time}

      {:error, reason} ->
        Logger.warning("⚠️ Failed to parse time_text '#{time_text}': #{reason}. Using defaults.")
        # Default to Monday at 7pm
        {:monday, ~T[19:00:00]}
    end
  end

  # Extract city from address string
  # UK addresses typically: "Street, City, Postcode"
  defp extract_city_from_address(address) when is_binary(address) do
    # Split by comma and try to get second-to-last part (before postcode)
    parts =
      address
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    case length(parts) do
      # If we have multiple parts, city is usually before the postcode
      n when n >= 2 ->
        Enum.at(parts, -2, "London")

      # Single part or empty - default to London
      _ ->
        "London"
    end
  end

  defp extract_city_from_address(_), do: "London"

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

      # Can't determine - assume not free but price unknown
      true ->
        {false, nil}
    end
  end

  # Generate URL-safe slug from title
  defp slugify(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  # Add hours to a DateTime
  defp add_hours(datetime, hours) do
    DateTime.add(datetime, hours * 3600, :second)
  end
end
