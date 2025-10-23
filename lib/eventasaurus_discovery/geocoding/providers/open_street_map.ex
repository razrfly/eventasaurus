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

  @doc """
  Reverse geocode coordinates to get address information.

  Used for venues that have coordinates but no address (e.g., Resident Advisor).
  """
  def search_by_coordinates(lat, lng, _venue_name \\ nil)
      when is_number(lat) and is_number(lng) do
    Logger.debug("🔍 OpenStreetMap reverse geocode: #{lat},#{lng}")

    # CRITICAL: Enforce 1 req/sec rate limit BEFORE making request
    Process.sleep(1000)

    try do
      # OSM Nominatim reverse geocoding
      url = "https://nominatim.openstreetmap.org/reverse"

      params = [
        lat: lat,
        lon: lng,
        format: "json",
        addressdetails: 1
      ]

      headers = [
        {"User-Agent", "EventasaurusDiscovery/1.0"}
      ]

      case HTTPoison.get(url, headers, params: params, recv_timeout: 10_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          parse_reverse_response(body)

        {:ok, %HTTPoison.Response{status_code: status}} ->
          Logger.error("❌ OSM reverse geocode HTTP error: #{status}")
          {:error, :api_error}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("❌ OSM reverse geocode failed: #{inspect(reason)}")
          {:error, :network_error}
      end
    rescue
      Jason.DecodeError ->
        Logger.warning("⚠️ OSM reverse returned HTML instead of JSON (likely rate limited)")
        {:error, :rate_limited}

      error ->
        Logger.error("❌ OSM reverse unexpected error: #{inspect(error)}")
        {:error, :api_error}
    catch
      :exit, {:timeout, _} ->
        Logger.warning("⏱️ OSM reverse GenServer timeout (exceeded 5s)")
        {:error, :timeout}

      :exit, reason ->
        Logger.error("❌ OSM reverse exited with reason: #{inspect(reason)}")
        {:error, :api_error}
    end
  end

  defp parse_reverse_response(body) do
    case Jason.decode(body) do
      {:ok, result} when is_map(result) ->
        # Extract formatted address (display_name in OSM)
        formatted_address = Map.get(result, "display_name")

        if formatted_address do
          Logger.debug("✅ OpenStreetMap found address: #{formatted_address}")
          {:ok, formatted_address}
        else
          Logger.debug("📍 OpenStreetMap: no address in response")
          {:error, :no_results}
        end

      {:ok, _other} ->
        Logger.error("❌ OpenStreetMap reverse: unexpected response format")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ OpenStreetMap reverse: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

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

    # Extract formatted address (OSM uses display_name)
    formatted_address =
      Map.get(location, :display_name) ||
        Map.get(location, "display_name")

    # Extract OpenStreetMap place ID and convert to string (may be integer in response)
    place_id =
      case Map.get(location, :osm_id) || Map.get(location, "osm_id") ||
             Map.get(location, :place_id) || Map.get(location, "place_id") do
        nil -> nil
        id when is_integer(id) -> Integer.to_string(id)
        id when is_binary(id) -> id
        other -> to_string(other)
      end

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
           # Formatted address from OpenStreetMap
           address: formatted_address,
           # New multi-provider field
           provider_id: place_id,
           # Keep for backwards compatibility
           place_id: place_id,
           # Store entire Geocoder coordinates struct
           raw_response: coordinates
         }}
    end
  end
end
