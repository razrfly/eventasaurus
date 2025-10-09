defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Transformer do
  @moduledoc """
  Transforms Geeks Who Drink venue data into unified event format.

  Geeks Who Drink provides weekly recurring trivia events at venues with:
  - GPS coordinates provided directly (no geocoding needed)
  - Performer information via AJAX endpoint
  - Weekly recurring schedule
  - US-based events (America/New_York timezone)

  ## Transformation Strategy
  - Use provided GPS coordinates (latitude/longitude)
  - Parse time_text to extract day of week and start time
  - Calculate next occurrence of the event in America/New_York
  - Create stable external_id for deduplication
  - Handle pricing from fee_text
  - Set category to "trivia"
  - Link performer via metadata
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
    venue_slug = slugify(title)
    external_id = "geeks_who_drink_#{venue_data.venue_id}"

    # Extract city and country from address
    {city, country} = parse_location_from_address(address)

    # Parse pricing from fee_text
    {is_free, min_price} = parse_pricing(venue_data[:fee_text])

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
      ends_at: add_hours(starts_at, 2),
      description: build_description(venue_data),
      source_url: venue_data.source_url,
      image_url: venue_data[:logo_url],

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

  # Generate URL-safe slug from title
  defp slugify(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp slugify(_), do: "unknown"

  # Add hours to a DateTime
  defp add_hours(datetime, hours) do
    DateTime.add(datetime, hours * 3600, :second)
  end
end
