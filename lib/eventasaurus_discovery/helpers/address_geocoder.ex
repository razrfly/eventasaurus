defmodule EventasaurusDiscovery.Helpers.AddressGeocoder do
  @moduledoc """
  Forward geocoding: convert full address strings to city names and coordinates.

  Simple strategy:
  1. Try OpenStreetMaps (free, no API key)
  2. If that fails, fallback to Google Maps API

  No manual validation - if the geocoding service returns a city, we trust it.

  ## Cost Tracking

  This module now supports cost tracking via the `geocode_address_with_metadata/1` function.
  The original `geocode_address/1` function remains unchanged for backward compatibility.
  """

  require Logger
  alias EventasaurusDiscovery.Geocoding.MetadataBuilder

  @doc """
  Geocode a full address string to extract city name, country, and coordinates.

  ## Examples

      iex> geocode_address("Pub Name, 123 Street, London, E5 8NN")
      {:ok, {"London", "United Kingdom", {51.5074, -0.1278}}}

      iex> geocode_address("invalid address")
      {:error, :geocoding_failed}
  """
  @spec geocode_address(String.t()) ::
          {:ok, {city :: String.t(), country :: String.t(), coordinates :: {float(), float()}}}
          | {:error, atom()}
  def geocode_address(address) when is_binary(address) do
    # Try OpenStreetMaps with retry, then fallback to Google if needed
    case try_openstreetmaps_with_retry(address) do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} ->
        Logger.warning("⚠️ OpenStreetMaps geocoding failed for: #{address}, trying Google Maps...")
        try_google_maps(address)
    end
  end

  def geocode_address(_), do: {:error, :invalid_address}

  @doc """
  Geocode an address and return result with cost tracking metadata.

  This is a non-breaking addition to the existing geocode_address/1 function.
  It returns the same location data plus geocoding metadata for cost tracking.

  ## Parameters
  - `address` - Full address string to geocode

  ## Returns
  - `{:ok, map}` - Map containing city, country, coordinates, and geocoding_metadata
  - `{:error, reason, metadata}` - Error with failure metadata for tracking

  ## Examples

      iex> geocode_address_with_metadata("Pub Name, 123 Street, London, E5 8NN")
      {:ok, %{
        city: "London",
        country: "United Kingdom",
        latitude: 51.5074,
        longitude: -0.1278,
        geocoding_metadata: %{
          provider: "openstreetmap",
          cost_per_call: 0.0,
          # ... other metadata
        }
      }}

      iex> geocode_address_with_metadata("invalid address")
      {:error, :all_geocoding_failed, %{provider: "google_maps", geocoding_failed: true, ...}}
  """
  @spec geocode_address_with_metadata(String.t()) ::
          {:ok,
           %{
             city: String.t(),
             country: String.t(),
             latitude: float(),
             longitude: float(),
             geocoding_metadata: map()
           }}
          | {:error, atom(), map()}
  def geocode_address_with_metadata(address) when is_binary(address) do
    # Try OpenStreetMaps with retry, then fallback to Google if needed
    case try_openstreetmaps_with_retry(address) do
      {:ok, {city, country, {lat, lng}}} ->
        # OSM succeeded - build OSM metadata
        metadata = MetadataBuilder.build_openstreetmap_metadata(address)

        {:ok,
         %{
           city: city,
           country: country,
           latitude: lat,
           longitude: lng,
           geocoding_metadata: metadata
         }}

      {:error, reason} ->
        Logger.warning(
          "⚠️ OpenStreetMaps failed for: #{address}, trying Google Maps... (reason: #{reason})"
        )

        # Try Google Maps fallback
        case try_google_maps(address) do
          {:ok, {city, country, {lat, lng}}} ->
            # Google Maps succeeded - build Google Maps metadata
            # Note: 3 attempts because OSM retries 3 times before falling back
            metadata = MetadataBuilder.build_google_maps_metadata(address, 3)

            {:ok,
             %{
               city: city,
               country: country,
               latitude: lat,
               longitude: lng,
               geocoding_metadata: metadata
             }}

          {:error, google_reason} ->
            # Both OSM and Google failed - return error with metadata
            Logger.error("❌ All geocoding failed for: #{address}")

            metadata =
              MetadataBuilder.build_google_maps_metadata(address, 3)
              |> MetadataBuilder.mark_failed(google_reason)

            {:error, :all_geocoding_failed, metadata}
        end
    end
  end

  def geocode_address_with_metadata(_) do
    metadata =
      MetadataBuilder.build_google_maps_metadata("invalid", 0)
      |> MetadataBuilder.mark_failed(:invalid_address)

    {:error, :invalid_address, metadata}
  end

  # Try OpenStreetMaps with exponential backoff retry
  # Retries up to 3 times with increasing delays (1s, 2s) before giving up
  # Handles both rate limiting AND timeouts
  defp try_openstreetmaps_with_retry(address, attempts_left \\ 3) do
    case try_openstreetmaps(address) do
      {:ok, result} ->
        {:ok, result}

      # Retry on rate limiting AND timeouts
      {:error, reason} when reason in [:osm_rate_limited, :osm_timeout] and attempts_left > 1 ->
        backoff_ms = (4 - attempts_left) * 1000  # 1s, then 2s
        Logger.info("🔄 Retrying OSM after #{backoff_ms}ms (#{attempts_left - 1} attempts left) - reason: #{reason}")
        Process.sleep(backoff_ms)
        try_openstreetmaps_with_retry(address, attempts_left - 1)

      {:error, reason} ->
        Logger.debug("❌ OSM failed after retries: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Try OpenStreetMaps (Nominatim) - free, no API key
  # Handles JSON decode errors from HTML responses (rate limiting)
  # Handles GenServer timeouts from poolboy connection pool
  defp try_openstreetmaps(address) do
    Logger.debug("Geocoding with OpenStreetMaps: #{address}")

    try do
      case Geocoder.call(address) do
        {:ok, coordinates} ->
          extract_location_data(coordinates, "OpenStreetMaps")

        {:error, reason} ->
          Logger.debug("OpenStreetMaps failed: #{inspect(reason)}")
          {:error, :osm_failed}
      end
    rescue
      Jason.DecodeError ->
        Logger.warning("⚠️ OSM returned HTML instead of JSON for: #{address} (likely rate limited)")
        {:error, :osm_rate_limited}

      error ->
        Logger.error("❌ OSM unexpected error for #{address}: #{inspect(error)}")
        {:error, :osm_failed}
    catch
      # Catch GenServer timeout exits from poolboy (5-second hardcoded timeout)
      :exit, {:timeout, _} ->
        Logger.warning("⏱️ OSM GenServer timeout for: #{address} (exceeded 5s)")
        {:error, :osm_timeout}

      :exit, reason ->
        Logger.error("❌ OSM exited with reason: #{inspect(reason)}")
        {:error, :osm_crashed}
    end
  end

  # Fallback to Google Maps Geocoding API
  defp try_google_maps(address) do
    Logger.debug("Geocoding with Google Maps: #{address}")

    # Get API key from environment or config (defensive fetching)
    api_key =
      System.get_env("GOOGLE_MAPS_API_KEY") ||
        (Application.get_env(:geocoder, Geocoder.Providers.GoogleMaps, [])
         |> Keyword.get(:api_key))

    # Warn if API key is missing
    if is_nil(api_key) do
      Logger.warning("⚠️ Google Maps API key not configured. Geocoding will fail.")
    end

    # Use Google Maps provider with explicit API key
    case Geocoder.call(address, provider: Geocoder.Providers.GoogleMaps, key: api_key) do
      {:ok, coordinates} ->
        extract_location_data(coordinates, "GoogleMaps")

      {:error, reason} ->
        Logger.error("Google Maps geocoding failed: #{inspect(reason)}")
        {:error, :all_geocoding_failed}
    end
  end

  # Extract city, country, and coordinates from geocoder response
  # Validates city names to prevent street addresses from being used
  defp extract_location_data(coordinates, provider) do
    location = coordinates.location || %{}

    # Extract coordinates
    lat = coordinates.lat
    lon = coordinates.lon

    # The location is a Geocoder.Location struct with direct fields
    # Try multiple field names for city (varies by provider and location type)
    # Priority order: city > town > village > municipality > county > locality > formatted_address
    # IMPORTANT: Validate ALL values to prevent street addresses from being used
    raw_city =
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
        Map.get(location, "locality") ||
        # Final fallback: extract from formatted address
        extract_city_from_formatted(Map.get(location, :formatted_address) || Map.get(location, "formatted_address"))

    # CRITICAL: Validate the extracted city name to reject street addresses
    # Google Maps sometimes puts street addresses in the :city field!
    city = validate_city_name(raw_city)

    # Extract country
    country =
      Map.get(location, :country) ||
        Map.get(location, "country") ||
        Map.get(location, :country_name) ||
        Map.get(location, "country_name") ||
        "Unknown"

    case {city, lat, lon} do
      {nil, _, _} ->
        Logger.warning(
          "No valid city found in #{provider} response for coordinates #{lat}, #{lon}. Raw value: #{inspect(raw_city)}. Location: #{inspect(location)}"
        )

        {:error, :no_city_found}

      {city, lat, lon} when is_binary(city) and is_float(lat) and is_float(lon) ->
        Logger.info("✅ Geocoded via #{provider}: #{city}, #{country} (#{lat}, #{lon})")
        {:ok, {city, country, {lat, lon}}}

      _ ->
        Logger.warning("Invalid data from #{provider}: #{inspect({city, lat, lon})}")
        {:error, :invalid_response}
    end
  end

  # Validate city names to reject street addresses and invalid values
  # Returns nil if the name looks like a street address or is invalid
  defp validate_city_name(nil), do: nil

  defp validate_city_name(name) when is_binary(name) do
    cond do
      # Contains house numbers like "3-4 Moulsham St" or "76-78 Fore St"
      Regex.match?(~r/^\d+-?\d*\s+/, name) ->
        Logger.debug("🚫 Rejecting locality '#{name}' - looks like street address with number")
        nil

      # Contains common street suffixes - likely a street not a city
      # Allow "St " prefix (like "St Albans") but reject " St" suffix (like "Moulsham St")
      Regex.match?(~r/\s+(St|Rd|Ave|Lane|Road|Street|Drive|Way|Court|Pl|Place|Cres|Crescent)$/i, name) ->
        Logger.debug("🚫 Rejecting locality '#{name}' - contains street suffix")
        nil

      # Too short (less than 3 chars) - likely abbreviation or invalid
      String.length(name) < 3 ->
        Logger.debug("🚫 Rejecting locality '#{name}' - too short")
        nil

      # Looks valid - return as-is
      true ->
        name
    end
  end

  # Try to extract city from formatted address as last resort
  # Formatted addresses vary by provider and country, so we try multiple patterns
  defp extract_city_from_formatted(nil), do: nil

  defp extract_city_from_formatted(formatted_address) when is_binary(formatted_address) do
    # formatted_address examples:
    # UK: "10 Peas Hill, Cambridge CB2 3QB, UK"
    # US: "123 Main St, San Francisco, CA 94102, USA"
    # General: "Venue, Street, City, Postcode, Country"

    parts =
      formatted_address
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reverse()

    # Try different patterns based on number of parts
    city = case parts do
      # Pattern: "10 Street Name, City PostCode, Country"
      [_country, city_postcode, _street_with_number] ->
        # Extract city from "City PostCode" by removing postcode
        extract_city_from_city_postcode(city_postcode)

      # Pattern: "Street, City, State/Postcode, Country"
      # This matches both "Street, City, State Postcode, Country" and "Street, City, Postcode, Country"
      [_country, _state_or_postcode, city, _street] ->
        city

      # Pattern: "City, Country"
      [_country, city] ->
        city

      # Unknown pattern
      _ ->
        nil
    end

    # Validate the extracted city
    city
  end

  # Extract city name from "City PostCode" string
  # Examples: "Cambridge CB2 3QB" → "Cambridge"
  #           "London W1A 1AA" → "London"
  defp extract_city_from_city_postcode(nil), do: nil

  defp extract_city_from_city_postcode(city_postcode) when is_binary(city_postcode) do
    # Split and take everything before the postcode
    # UK postcodes usually start with 1-2 letters, followed by digits
    # Pattern: "City CODE" where CODE contains letters and numbers
    parts = String.split(city_postcode, " ")

    case parts do
      # "Cambridge" "CB2" "3QB" → take first part
      [city | rest] when length(rest) >= 1 ->
        # Check if remaining parts look like a postcode
        if Enum.any?(rest, &String.match?(&1, ~r/[A-Z]+\d+/)) do
          city
        else
          # Might be multi-word city name
          city_postcode
        end

      # Single word, no postcode
      [city] ->
        city

      _ ->
        nil
    end
  end
end
