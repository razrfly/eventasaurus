defmodule EventasaurusDiscovery.Geocoding.Providers.Mapbox do
  @moduledoc """
  Mapbox Geocoding API provider.

  **Free Tier**: 100,000 requests/month
  **Rate Limit**: 600 requests/minute
  **Quality**: 9/10
  **Coverage**: Global, excellent quality

  ## API Documentation
  https://docs.mapbox.com/api/search/geocoding/

  ## Configuration

  Requires `MAPBOX_ACCESS_TOKEN` environment variable (already configured in .env).

  Sign up at: https://www.mapbox.com/

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.Provider

  require Logger

  @impl true
  def name, do: "mapbox"

  @impl true
  def geocode(address) when is_binary(address) do
    access_token = get_access_token()

    if is_nil(access_token) do
      Logger.error("❌ MAPBOX_ACCESS_TOKEN not configured")
      {:error, :api_key_missing}
    else
      make_request(address, access_token)
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  defp make_request(address, api_key) do
    url = "https://api.mapbox.com/geocoding/v5/mapbox.places/#{URI.encode(address)}.json"

    params = [
      access_token: api_key,
      limit: 1,
      types: "place,locality,neighborhood,address"
    ]

    Logger.debug("🌐 Mapbox request: #{address}")

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_response(body)

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Mapbox rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("❌ Mapbox authentication failed (invalid API key)")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Mapbox HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Mapbox request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Mapbox request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"features" => features}} when is_list(features) and length(features) > 0 ->
        extract_result(features)

      {:ok, %{"features" => []}} ->
        Logger.debug("📍 Mapbox: no results found")
        {:error, :no_results}

      {:ok, _other} ->
        Logger.error("❌ Mapbox: unexpected response format")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ Mapbox: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp extract_result([feature | _]) do
    # Extract coordinates
    coordinates = get_in(feature, ["geometry", "coordinates"])
    # Mapbox returns [lng, lat] - we need to swap to [lat, lng]
    {lng, lat} =
      case coordinates do
        [lng, lat] when is_float(lng) and is_float(lat) -> {lng, lat}
        [lng, lat] when is_number(lng) and is_number(lat) -> {lng * 1.0, lat * 1.0}
        _ -> {nil, nil}
      end

    # Extract place name (city)
    place_name = get_in(feature, ["place_name"]) || ""

    # Extract Mapbox place ID
    place_id = get_in(feature, ["id"])

    # Extract context for city and country
    context = get_in(feature, ["context"]) || []

    city = extract_city(feature, context)
    country = extract_country(context)

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ Mapbox: missing coordinates in response")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning("⚠️ Mapbox: could not extract city from: #{place_name}")
        {:error, :no_city_found}

      true ->
        {:ok,
         %{
           latitude: lat,
           longitude: lng,
           city: city,
           country: country || "Unknown",
           place_id: place_id,
           # Store entire Mapbox feature object
           raw_response: feature
         }}
    end
  end

  # Extract city from Mapbox response
  # Try multiple context types: place, locality, district
  defp extract_city(feature, context) do
    # First try the place_type
    place_type = get_in(feature, ["place_type"])
    text = get_in(feature, ["text"])

    city_from_feature =
      if place_type in [["place"], ["locality"], ["district"]] do
        text
      else
        nil
      end

    # If not found in feature, try context
    city_from_context =
      Enum.find_value(context, fn item ->
        id = Map.get(item, "id", "")
        text = Map.get(item, "text")

        cond do
          String.starts_with?(id, "place.") -> text
          String.starts_with?(id, "locality.") -> text
          String.starts_with?(id, "district.") -> text
          true -> nil
        end
      end)

    city_from_feature || city_from_context
  end

  # Extract country from Mapbox context
  defp extract_country(context) do
    Enum.find_value(context, fn item ->
      id = Map.get(item, "id", "")
      text = Map.get(item, "text")

      if String.starts_with?(id, "country.") do
        text
      end
    end)
  end

  defp get_access_token do
    System.get_env("MAPBOX_ACCESS_TOKEN")
  end
end
