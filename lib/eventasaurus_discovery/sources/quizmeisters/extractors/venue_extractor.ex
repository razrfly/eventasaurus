defmodule EventasaurusDiscovery.Sources.Quizmeisters.Extractors.VenueExtractor do
  @moduledoc """
  Extracts venue data from storerocket.io API JSON response.

  The API returns a list of location objects with venue information,
  GPS coordinates, and schedule details in the "fields" array.

  ## Data Fields Extracted
  - venue_id: Generated from URL slug or name
  - name: Venue name
  - address: Full address string
  - latitude: GPS latitude (Float)
  - longitude: GPS longitude (Float)
  - phone: Phone number
  - postcode: ZIP/postal code
  - url: Venue detail page URL
  - time_text: Schedule text from fields array (e.g., "Wednesdays at 7pm")

  ## Example API Response
  ```json
  {
    "name": "The Library Bar",
    "address": "123 Main St, Brooklyn, NY",
    "lat": 40.7128,
    "lng": -74.0060,
    "phone": "555-1234",
    "postcode": "11201",
    "url": "https://quizmeisters.com/venues/library-bar",
    "fields": [
      {
        "name": "Trivia",
        "pivot_field_value": "Wednesdays at 7pm"
      }
    ]
  }
  ```
  """

  require Logger

  @doc """
  Extracts venue data from a storerocket.io API location object.

  ## Parameters
  - `location` - Map containing venue data from API

  ## Returns
  - `{:ok, venue_data}` - Successfully extracted all required fields
  - `{:error, :missing_required_field}` - One or more required fields missing
  - `{:error, reason}` - Parsing error
  """
  def extract_venue_data(location) when is_map(location) do
    fields = [
      {:venue_id, extract_venue_id(location)},
      {:name, extract_name(location)},
      {:address, extract_address(location)},
      {:latitude, extract_latitude(location)},
      {:longitude, extract_longitude(location)},
      {:phone, extract_phone(location)},
      {:postcode, extract_postcode(location)},
      {:url, extract_url(location)},
      {:time_text, extract_time_text(location)}
    ]

    # Check for missing required fields (phone and postcode are optional)
    missing_fields =
      Enum.filter(fields, fn {name, value} ->
        is_nil(value) and name not in [:phone, :postcode]
      end)

    if Enum.empty?(missing_fields) do
      fields_map = Map.new(fields)

      {:ok,
       %{
         venue_id: fields_map.venue_id,
         name: fields_map.name,
         address: fields_map.address,
         latitude: fields_map.latitude,
         longitude: fields_map.longitude,
         phone: fields_map.phone,
         postcode: fields_map.postcode,
         url: fields_map.url,
         time_text: fields_map.time_text,
         source_url: fields_map.url
       }}
    else
      missing = missing_fields |> Enum.map(&elem(&1, 0)) |> Enum.join(", ")
      Logger.warning("⚠️  Missing required fields: #{missing} in venue: #{inspect(location)}")
      {:error, :missing_required_field}
    end
  end

  # Private extraction functions

  defp extract_venue_id(location) do
    # Extract venue ID from URL slug (e.g., "/venues/library-bar" -> "library-bar")
    # or generate from name if URL is missing
    case location["url"] do
      url when is_binary(url) ->
        url
        |> String.split("/")
        |> List.last()
        |> case do
          nil -> generate_id_from_name(location["name"])
          "" -> generate_id_from_name(location["name"])
          slug -> slug
        end

      _ ->
        generate_id_from_name(location["name"])
    end
  end

  defp generate_id_from_name(nil), do: nil

  defp generate_id_from_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
  end

  defp extract_name(location), do: location["name"]

  defp extract_address(location), do: location["address"]

  defp extract_latitude(location) do
    case location["lat"] do
      lat when is_float(lat) -> lat
      lat when is_binary(lat) -> parse_float(lat)
      lat when is_integer(lat) -> lat * 1.0
      _ -> nil
    end
  end

  defp extract_longitude(location) do
    case location["lng"] do
      lng when is_float(lng) -> lng
      lng when is_binary(lng) -> parse_float(lng)
      lng when is_integer(lng) -> lng * 1.0
      _ -> nil
    end
  end

  defp extract_phone(location), do: location["phone"]

  defp extract_postcode(location), do: location["postcode"]

  defp extract_url(location), do: location["url"]

  defp extract_time_text(location) do
    # Find trivia time in fields array
    # Look for fields named "Trivia" or "Survey Says"
    fields = location["fields"] || []

    Enum.find_value(fields, fn field ->
      if field["name"] in ["Trivia", "Survey Says"], do: field["pivot_field_value"]
    end)
  end

  defp parse_float(nil), do: nil

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {float, _} -> float
      :error -> nil
    end
  end
end
