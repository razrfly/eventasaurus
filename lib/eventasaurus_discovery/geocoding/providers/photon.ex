defmodule EventasaurusDiscovery.Geocoding.Providers.Photon do
  @moduledoc """
  Photon Geocoding API provider (OpenStreetMap-based).

  **Free Tier**: Unlimited (community-supported)
  **Rate Limit**: Fair use policy (no hard limit, but respect the service)
  **Quality**: 7/10 (OSM-based)
  **Coverage**: Good global coverage via OpenStreetMap

  ## API Documentation
  https://photon.komoot.io/

  ## Configuration

  No API key required! Completely free and open source.

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.

  ## Usage Policy

  Photon is a free, open-source service. Please use responsibly:
  - Implement reasonable rate limiting in your application
  - Cache results when possible
  - Consider self-hosting for high-volume usage
  """

  @behaviour EventasaurusDiscovery.Geocoding.Provider

  require Logger

  @impl true
  def name, do: "photon"

  @impl true
  def geocode(address) when is_binary(address) do
    make_request(address)
  end

  def geocode(_), do: {:error, :invalid_address}

  @doc """
  Reverse geocode coordinates to get address information.

  Used for venues that have coordinates but no address (e.g., Resident Advisor).
  """
  def search_by_coordinates(lat, lng, _venue_name \\ nil)
      when is_number(lat) and is_number(lng) do
    Logger.debug("🔍 Photon reverse geocode: #{lat},#{lng}")
    reverse_geocode_request(lat, lng)
  end

  defp reverse_geocode_request(lat, lng) do
    url = "https://photon.komoot.io/reverse"

    params = [
      lat: lat,
      lon: lng,
      limit: 1
    ]

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_reverse_response(body)

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Photon reverse geocode rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Photon reverse geocode HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Photon reverse geocode timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Photon reverse geocode failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_reverse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"features" => [first_feature | _]}} ->
        # Extract name field (Photon uses 'name' for display)
        properties = Map.get(first_feature, "properties", %{})
        formatted_address = Map.get(properties, "name")

        if formatted_address do
          Logger.debug("✅ Photon found address: #{formatted_address}")
          {:ok, formatted_address}
        else
          Logger.debug("📍 Photon: no address in response")
          {:error, :no_results}
        end

      {:ok, %{"features" => []}} ->
        Logger.debug("📍 Photon reverse geocode: no results found")
        {:error, :no_results}

      {:ok, _other} ->
        Logger.error("❌ Photon reverse: unexpected response format")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ Photon reverse: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp make_request(address) do
    url = "https://photon.komoot.io/api/"

    params = [
      q: address,
      limit: 1
    ]

    Logger.debug("🌐 Photon request: #{address}")

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_response(body)

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Photon rate limited (please use responsibly)")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Photon HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Photon request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Photon request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"features" => [first_feature | _]}} ->
        extract_result(first_feature)

      {:ok, %{"features" => []}} ->
        Logger.debug("📍 Photon: no results found")
        {:error, :no_results}

      {:ok, _other} ->
        Logger.error("❌ Photon: unexpected response format")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ Photon: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp extract_result(feature) do
    # Extract coordinates from GeoJSON format
    coordinates = get_in(feature, ["geometry", "coordinates"])

    # Photon returns [lng, lat] in GeoJSON format - swap to [lat, lng]
    {lng, lat} =
      case coordinates do
        [lng, lat] when is_number(lng) and is_number(lat) -> {lng, lat}
        _ -> {nil, nil}
      end

    # Extract properties
    properties = Map.get(feature, "properties", %{})

    # Try multiple city fields in order
    city =
      Map.get(properties, "city") ||
        Map.get(properties, "town") ||
        Map.get(properties, "village") ||
        Map.get(properties, "municipality") ||
        Map.get(properties, "county")

    country = Map.get(properties, "country")

    # Extract formatted address (Photon uses 'name' field for display)
    formatted_address = Map.get(properties, "name")

    # Extract Photon/OSM place ID and convert to string (may be integer in response)
    place_id =
      case Map.get(properties, "osm_id") || Map.get(properties, "place_id") do
        nil -> nil
        id when is_integer(id) -> Integer.to_string(id)
        id when is_binary(id) -> id
        other -> to_string(other)
      end

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ Photon: missing coordinates in response")
        {:error, :invalid_response}

      not is_number(lat) or not is_number(lng) ->
        Logger.warning("⚠️ Photon: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning("⚠️ Photon: could not extract city. Properties: #{inspect(properties)}")

        {:error, :no_city_found}

      true ->
        {:ok,
         %{
           latitude: lat * 1.0,
           longitude: lng * 1.0,
           city: city,
           country: country || "Unknown",
           # Formatted address from Photon
           address: formatted_address,
           # New multi-provider field
           provider_id: place_id,
           # Keep for backwards compatibility
           place_id: place_id,
           # Store entire Photon GeoJSON feature
           raw_response: feature
         }}
    end
  end
end
