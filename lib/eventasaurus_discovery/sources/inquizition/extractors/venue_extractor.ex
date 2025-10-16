defmodule EventasaurusDiscovery.Sources.Inquizition.Extractors.VenueExtractor do
  @moduledoc """
  Extracts and parses venue data from StoreLocatorWidgets CDN response.

  Responsible for:
  - Parsing venue objects from CDN response
  - Extracting required fields (name, address, GPS, schedule)
  - Validating data completeness
  - Filtering out invalid venues

  ## CDN Response Structure

      %{
        "stores" => [
          %{
            "storeid" => "97520779",
            "name" => "Andrea Ludgate Hill",
            "display_order" => "999999",
            "data" => %{
              "address" => "47 Ludgate Hill\\r\\nLondon\\r\\nEC4M 7JZ",
              "description" => "Tuesdays, 6.30pm",
              "website" => "https://andreabars.com/bookings/",
              "website_text" => "Book your table",
              "phone" => "020 7236 1942",
              "email" => "ludgatehill@andreabars.com",
              "map_lat" => "51.513898",
              "map_lng" => "-0.1026125"
            },
            "custom_data" => false,
            "filters" => ["Tuesday"],
            "google_placeid" => "",
            "timezone" => "Europe/London",
            "country" => "GB"
          }
        ],
        "settings" => %{...},
        "markers" => %{...}
      }

  ## Extracted Venue Structure

      %{
        venue_id: "97520779",
        name: "Andrea Ludgate Hill",
        address: "47 Ludgate Hill\\r\\nLondon\\r\\nEC4M 7JZ",
        latitude: 51.513898,
        longitude: -0.1026125,
        phone: "020 7236 1942",
        website: "https://andreabars.com/bookings/",
        email: "ludgatehill@andreabars.com",
        schedule_text: "Tuesdays, 6.30pm",
        day_filters: ["Tuesday"],
        timezone: "Europe/London",
        country: "GB"
      }
  """

  require Logger

  @doc """
  Extracts all venues from CDN response.

  Filters out venues with missing required fields:
  - storeid (must be present and non-empty)
  - name (must be present and non-empty)
  - address (must be present and non-empty)
  - map_lat and map_lng (must be valid floats)

  Returns list of venue maps with extracted data.

  ## Examples

      iex> VenueExtractor.extract_venues(%{"stores" => [...]})
      [
        %{
          venue_id: "97520779",
          name: "Andrea Ludgate Hill",
          latitude: 51.513898,
          ...
        }
      ]

      iex> VenueExtractor.extract_venues(%{"stores" => []})
      []

      iex> VenueExtractor.extract_venues(%{})
      {:error, :missing_stores_key}
  """
  def extract_venues(%{"stores" => stores}) when is_list(stores) do
    venues =
      stores
      |> Enum.map(&parse_venue/1)
      |> Enum.reject(&is_nil/1)

    valid_count = length(venues)
    total_count = length(stores)
    invalid_count = total_count - valid_count

    if invalid_count > 0 do
      Logger.warning(
        "[Inquizition.VenueExtractor] Filtered out #{invalid_count} invalid venues (#{valid_count}/#{total_count} valid)"
      )
    else
      Logger.info("[Inquizition.VenueExtractor] Extracted #{valid_count} valid venues")
    end

    venues
  end

  def extract_venues(_response) do
    Logger.error("[Inquizition.VenueExtractor] Invalid response: missing 'stores' key")
    {:error, :missing_stores_key}
  end

  # Private functions

  defp parse_venue(store) when is_map(store) do
    venue_id = get_in(store, ["storeid"])
    name = get_in(store, ["name"])
    data = get_in(store, ["data"]) || %{}

    address = get_in(data, ["address"])
    lat_string = get_in(data, ["map_lat"])
    lng_string = get_in(data, ["map_lng"])

    # Required fields validation
    with true <- is_valid_string?(venue_id),
         true <- is_valid_string?(name),
         true <- is_valid_string?(address),
         {:ok, latitude} <- parse_coordinate(lat_string),
         {:ok, longitude} <- parse_coordinate(lng_string) do
      %{
        venue_id: venue_id,
        name: String.trim(name),
        address: normalize_address(address),
        latitude: latitude,
        longitude: longitude,
        phone: parse_optional_string(get_in(data, ["phone"])),
        website: parse_optional_string(get_in(data, ["website"])),
        email: parse_optional_string(get_in(data, ["email"])),
        schedule_text: parse_optional_string(get_in(data, ["description"])),
        day_filters: parse_filters(get_in(store, ["filters"])),
        timezone: get_in(store, ["timezone"]) || "Europe/London",
        country: get_in(store, ["country"]) || "GB"
      }
    else
      _ ->
        Logger.debug(
          "[Inquizition.VenueExtractor] Skipping invalid venue: #{inspect(venue_id)} - missing required fields"
        )

        nil
    end
  end

  defp parse_venue(_non_map) do
    nil
  end

  defp is_valid_string?(value) do
    is_binary(value) and String.trim(value) != ""
  end

  defp parse_coordinate(nil), do: {:error, :missing}
  defp parse_coordinate(""), do: {:error, :empty}

  defp parse_coordinate(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {float, _rest} when is_float(float) -> {:ok, float}
      _ -> {:error, :invalid_float}
    end
  end

  defp parse_coordinate(value) when is_float(value), do: {:ok, value}
  defp parse_coordinate(value) when is_integer(value), do: {:ok, value * 1.0}
  defp parse_coordinate(_), do: {:error, :invalid_type}

  defp parse_optional_string(nil), do: nil
  defp parse_optional_string(""), do: nil

  defp parse_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp parse_optional_string(_), do: nil

  defp normalize_address(address) when is_binary(address) do
    # Normalize line breaks: \r\n → \n
    address
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.trim()
  end

  defp normalize_address(_), do: ""

  defp parse_filters(filters) when is_list(filters) do
    # Filter out empty strings and nil values
    Enum.filter(filters, fn
      nil -> false
      "" -> false
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end)
  end

  defp parse_filters(_), do: []
end
