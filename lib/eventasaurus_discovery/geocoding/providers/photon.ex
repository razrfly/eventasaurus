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

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ Photon: missing coordinates in response")
        {:error, :invalid_response}

      not is_number(lat) or not is_number(lng) ->
        Logger.warning("⚠️ Photon: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning(
          "⚠️ Photon: could not extract city. Properties: #{inspect(properties)}"
        )

        {:error, :no_city_found}

      true ->
        {:ok,
         %{
           latitude: lat * 1.0,
           longitude: lng * 1.0,
           city: city,
           country: country || "Unknown"
         }}
    end
  end
end
