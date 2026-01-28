defmodule EventasaurusDiscovery.Geocoding.Providers.GoogleMaps do
  @moduledoc """
  Google Maps Geocoding API provider.

  **Cost**: $0.005 per request (no free tier)
  **Rate Limit**: 100 requests/second
  **Quality**: 9/10
  **Coverage**: Excellent global coverage

  ## API Documentation
  https://developers.google.com/maps/documentation/geocoding/overview

  ## Configuration

  Requires `GOOGLE_MAPS_API_KEY` environment variable.

  **Note**: This provider is **DISABLED by default** to prevent costs.
  Enable only if free providers are insufficient.

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.Provider

  require Logger

  alias EventasaurusDiscovery.Costs.ExternalServiceCost
  alias EventasaurusDiscovery.Geocoding.Pricing

  @impl true
  def name, do: "google_maps"

  @impl true
  def geocode(address) when is_binary(address) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("❌ GOOGLE_MAPS_API_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("🌐 Google Maps request: #{address}")
      start_time = System.monotonic_time(:millisecond)

      # Use the geocoder library with GoogleMaps provider
      case Geocoder.call(address, provider: Geocoder.Providers.GoogleMaps, key: api_key) do
        {:ok, coordinates} ->
          duration_ms = System.monotonic_time(:millisecond) - start_time
          record_cost("geocode", duration_ms)
          extract_result(coordinates)

        {:error, reason} ->
          Logger.error("Google Maps geocoding failed: #{inspect(reason)}")
          {:error, :api_error}
      end
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  defp extract_result(coordinates) do
    location = coordinates.location || %{}

    # Extract coordinates
    lat = coordinates.lat
    lon = coordinates.lon

    # Try multiple field names for city
    city =
      Map.get(location, :city) ||
        Map.get(location, "city") ||
        Map.get(location, :town) ||
        Map.get(location, "town") ||
        Map.get(location, :locality) ||
        Map.get(location, "locality")

    # Extract country
    country =
      Map.get(location, :country) ||
        Map.get(location, "country") ||
        Map.get(location, :country_name) ||
        Map.get(location, "country_name") ||
        "Unknown"

    cond do
      is_nil(lat) or is_nil(lon) ->
        Logger.warning("⚠️ Google Maps: missing coordinates in response")
        {:error, :invalid_response}

      not is_float(lat) or not is_float(lon) ->
        Logger.warning("⚠️ Google Maps: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning(
          "⚠️ Google Maps: no city found for coordinates #{lat}, #{lon}. Location: #{inspect(location)}"
        )

        {:error, :no_city_found}

      true ->
        {:ok,
         %{
           latitude: lat,
           longitude: lon,
           city: city,
           country: country
         }}
    end
  end

  defp get_api_key do
    # Try environment variable first, then config
    System.get_env("GOOGLE_MAPS_API_KEY") ||
      Application.get_env(:geocoder, Geocoder.Providers.GoogleMaps, [])
      |> Keyword.get(:api_key)
  end

  # Cost tracking for external service monitoring (Issue #3443)
  defp record_cost(operation, duration_ms) do
    cost = Pricing.google_maps_cost()

    ExternalServiceCost.record_async(%{
      service_type: "geocoding",
      provider: "google_maps",
      operation: operation,
      cost_usd: Decimal.from_float(cost),
      units: 1,
      unit_type: "request",
      metadata: %{
        duration_ms: duration_ms
      }
    })
  end
end
