defmodule EventasaurusDiscovery.Geocoding.Providers.OpenStreetMap do
  @moduledoc """
  OpenStreetMap Nominatim geocoding provider.

  **Free Tier**: Free (usage policy applies)
  **Rate Limit**: 1 request per second (strictly enforced)
  **Quality**: 7/10
  **Coverage**: Global

  ## Usage Policy
  https://operations.osmfoundation.org/policies/nominatim/

  **IMPORTANT**: Nominatim has strict rate limiting:
  - Maximum 1 request per second
  - Requires valid User-Agent header
  - No bulk geocoding
  - Subject to blocking if policy violated

  ## Configuration

  No API key required. Uses the `geocoder` library with OSM provider.

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.Provider

  require Logger

  @impl true
  def name, do: "openstreetmap"

  @impl true
  def geocode(address) when is_binary(address) do
    Logger.debug("🌐 OpenStreetMap request: #{address}")

    # CRITICAL: Enforce 1 req/sec rate limit BEFORE making request
    # NOTE: This Process.sleep is a simple per-worker delay and doesn't prevent
    # parallel workers from hitting OSM simultaneously. For production use with
    # high concurrency, this should be replaced with a shared rate limiter
    # (e.g., Hammer-based) to queue requests globally. However, since OSM is
    # priority 5 (only used as fallback), this simple approach is acceptable.
    Process.sleep(1000)

    try do
      case Geocoder.call(address, provider: Geocoder.Providers.OpenStreetMaps) do
        {:ok, coordinates} ->
          extract_result(coordinates)

        {:error, reason} ->
          Logger.debug("OpenStreetMap failed: #{inspect(reason)}")
          {:error, :api_error}
      end
    rescue
      Jason.DecodeError ->
        # OSM returns HTML when rate limited instead of JSON
        Logger.warning("⚠️ OSM returned HTML instead of JSON (likely rate limited)")
        {:error, :rate_limited}

      error ->
        Logger.error("❌ OSM unexpected error: #{inspect(error)}")
        {:error, :api_error}
    catch
      # Catch GenServer timeout exits from poolboy (5-second hardcoded timeout)
      :exit, {:timeout, _} ->
        Logger.warning("⏱️ OSM GenServer timeout (exceeded 5s)")
        {:error, :timeout}

      :exit, reason ->
        Logger.error("❌ OSM exited with reason: #{inspect(reason)}")
        {:error, :api_error}
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  defp extract_result(coordinates) do
    location = coordinates.location || %{}

    # Extract coordinates
    lat = coordinates.lat
    lon = coordinates.lon

    # Try multiple field names for city (varies by location type)
    # Priority: city > town > village > municipality > county > locality
    city =
      Map.get(location, :city) ||
        Map.get(location, "city") ||
        Map.get(location, :town) ||
        Map.get(location, "town") ||
        Map.get(location, :village) ||
        Map.get(location, "village") ||
        Map.get(location, :municipality) ||
        Map.get(location, "municipality") ||
        Map.get(location, :county) ||
        Map.get(location, "county") ||
        Map.get(location, :locality) ||
        Map.get(location, "locality")

    # Extract country
    country =
      Map.get(location, :country) ||
        Map.get(location, "country") ||
        Map.get(location, :country_name) ||
        Map.get(location, "country_name") ||
        "Unknown"

    # Extract OpenStreetMap place ID
    place_id =
      Map.get(location, :osm_id) ||
        Map.get(location, "osm_id") ||
        Map.get(location, :place_id) ||
        Map.get(location, "place_id")

    cond do
      is_nil(lat) or is_nil(lon) ->
        Logger.warning("⚠️ OSM: missing coordinates in response")
        {:error, :invalid_response}

      not is_float(lat) or not is_float(lon) ->
        Logger.warning("⚠️ OSM: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning(
          "⚠️ OSM: no city found for coordinates #{lat}, #{lon}. Location: #{inspect(location)}"
        )

        {:error, :no_city_found}

      true ->
        {:ok,
         %{
           latitude: lat,
           longitude: lon,
           city: city,
           country: country,
           place_id: place_id,
           raw_response: coordinates  # Store entire Geocoder coordinates struct
         }}
    end
  end
end
