defmodule EventasaurusDiscovery.Sources.CinemaCity.Extractors.CinemaExtractor do
  @moduledoc """
  Extracts cinema venue data from Cinema City API responses.

  The Cinema City API provides complete venue information including:
  - Cinema name and ID
  - Full address
  - GPS coordinates
  - City and region information
  - Website link

  This data is used to create/update Venue records in the database.
  """

  require Logger

  @doc """
  Extract venue data from a cinema API object.

  ## Input Example
  ```json
  {
    "id": "1088",
    "groupId": "10103",
    "displayName": "Kraków - Bonarka",
    "city": "Kraków",
    "addressLine1": "ul. Kamieńskiego 11",
    "addressLine2": null,
    "postalCode": "30-644",
    "latitude": "50.0476",
    "longitude": "19.9598",
    "link": "https://www.cinema-city.pl/krakow-bonarka"
  }
  ```

  ## Returns
  Map with standardized venue fields:
  - name: String
  - address: String (full formatted address)
  - city: String
  - country: String (always "Poland" for Cinema City)
  - latitude: Float
  - longitude: Float
  - cinema_city_id: String (original API ID)
  - website: String
  - metadata: Map (additional fields)
  """
  def extract(cinema_data) when is_map(cinema_data) do
    %{
      name: extract_name(cinema_data),
      address: extract_address(cinema_data),
      city: extract_city(cinema_data),
      country: "Poland",
      latitude: extract_latitude(cinema_data),
      longitude: extract_longitude(cinema_data),
      cinema_city_id: extract_id(cinema_data),
      website: extract_website(cinema_data),
      metadata: extract_metadata(cinema_data)
    }
  end

  @doc """
  Filter cinemas by target cities.

  Returns only cinemas from cities in the target list.
  """
  def filter_by_cities(cinemas, target_cities) when is_list(cinemas) and is_list(target_cities) do
    # Normalize target cities for comparison (lowercase, handle accents)
    normalized_targets =
      target_cities
      |> Enum.map(&normalize_city_name/1)
      |> MapSet.new()

    cinemas
    |> Enum.filter(fn cinema ->
      city = extract_city(cinema)
      normalized_city = normalize_city_name(city)

      MapSet.member?(normalized_targets, normalized_city)
    end)
  end

  # Extract cinema name
  defp extract_name(%{"displayName" => name}) when is_binary(name), do: String.trim(name)
  defp extract_name(%{"name" => name}) when is_binary(name), do: String.trim(name)
  defp extract_name(_), do: "Cinema City"

  # Extract and format full address
  defp extract_address(cinema) do
    # Try addressInfo first (new API format), then fallback to old format
    address_info = Map.get(cinema, "addressInfo", %{})

    parts =
      [
        Map.get(address_info, "address1") || Map.get(cinema, "addressLine1"),
        Map.get(address_info, "address2") || Map.get(cinema, "addressLine2"),
        format_postal_city(cinema)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.trim/1)

    case parts do
      [] -> nil
      _ -> Enum.join(parts, ", ")
    end
  end

  # Format postal code + city
  defp format_postal_city(cinema) do
    # Try addressInfo first (new format)
    address_info = Map.get(cinema, "addressInfo", %{})
    postal = Map.get(address_info, "postalCode") || Map.get(cinema, "postalCode")
    city = Map.get(address_info, "city") || Map.get(cinema, "city")

    cond do
      postal && city -> "#{postal} #{city}"
      city -> city
      postal -> postal
      true -> nil
    end
  end

  # Extract city name
  defp extract_city(%{"addressInfo" => %{"city" => city}}) when is_binary(city),
    do: String.trim(city)

  defp extract_city(%{"city" => city}) when is_binary(city), do: String.trim(city)
  defp extract_city(_), do: nil

  # Extract latitude as float
  defp extract_latitude(%{"latitude" => lat}) when is_binary(lat) do
    case Float.parse(lat) do
      {float_val, _} -> float_val
      :error -> nil
    end
  end

  defp extract_latitude(%{"latitude" => lat}) when is_float(lat), do: lat
  defp extract_latitude(%{"latitude" => lat}) when is_integer(lat), do: lat * 1.0
  defp extract_latitude(_), do: nil

  # Extract longitude as float
  defp extract_longitude(%{"longitude" => lon}) when is_binary(lon) do
    case Float.parse(lon) do
      {float_val, _} -> float_val
      :error -> nil
    end
  end

  defp extract_longitude(%{"longitude" => lon}) when is_float(lon), do: lon
  defp extract_longitude(%{"longitude" => lon}) when is_integer(lon), do: lon * 1.0
  defp extract_longitude(_), do: nil

  # Extract Cinema City ID
  defp extract_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_id(%{"id" => id}) when is_integer(id), do: Integer.to_string(id)
  defp extract_id(_), do: nil

  # Extract website link
  defp extract_website(%{"link" => link}) when is_binary(link), do: String.trim(link)
  defp extract_website(_), do: nil

  # Extract additional metadata
  defp extract_metadata(cinema) do
    %{
      group_id: Map.get(cinema, "groupId"),
      postal_code: Map.get(cinema, "postalCode"),
      region: Map.get(cinema, "region"),
      # Store any additional fields that might be useful
      raw_data: cinema
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Normalize city name for comparison
  # Handles: "Kraków" / "Krakow" / "KRAKÓW" / "Cracow"
  defp normalize_city_name(city) when is_binary(city) do
    city
    |> String.downcase()
    |> String.trim()
    # Remove Polish diacritics for comparison
    |> String.replace("ą", "a")
    |> String.replace("ć", "c")
    |> String.replace("ę", "e")
    |> String.replace("ł", "l")
    |> String.replace("ń", "n")
    |> String.replace("ó", "o")
    |> String.replace("ś", "s")
    |> String.replace("ź", "z")
    |> String.replace("ż", "z")
  end

  defp normalize_city_name(_), do: ""

  @doc """
  Validate that a cinema has all required fields.

  Returns {:ok, cinema} or {:error, reason}.
  """
  def validate(cinema) when is_map(cinema) do
    required_fields = [:name, :city, :cinema_city_id]

    missing_fields =
      required_fields
      |> Enum.reject(fn field -> Map.get(cinema, field) end)

    case missing_fields do
      [] ->
        {:ok, cinema}

      fields ->
        {:error, {:missing_required_fields, fields}}
    end
  end
end
