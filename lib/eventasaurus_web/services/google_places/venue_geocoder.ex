defmodule EventasaurusWeb.Services.GooglePlaces.VenueGeocoder do
  @moduledoc """
  Handles geocoding of venue addresses to obtain GPS coordinates.
  Used as a fallback when scrapers don't provide coordinates.
  """

  alias EventasaurusWeb.Services.GooglePlaces.Client
  require Logger

  @base_url "https://maps.googleapis.com/maps/api/geocode/json"
  # Cache geocoding results for 24 hours
  @cache_ttl :timer.hours(24)

  @doc """
  Geocodes a venue address to get latitude, longitude, and official venue name from Google.

  ## Parameters
    - venue_data: Map containing venue information with at least:
      - name: Venue name
      - address: Street address (optional)
      - city_name: City name (required)
      - country_name: Country name (required)
      - state: State/province (optional)

  ## Returns
    - {:ok, %{latitude: float, longitude: float, name: string, place_id: string}} on success
    - {:error, reason} on failure

  The returned name is Google's official venue name which should be preferred over scraped names.
  """
  def geocode_venue(venue_data) do
    # Build the geocoding query from venue data
    query = build_geocoding_query(venue_data)

    if query == "" do
      Logger.warning("Cannot geocode venue without address information: #{inspect(venue_data)}")
      {:error, "Insufficient address data for geocoding"}
    else
      # Try to get from cache first
      cache_key = "venue_geocode:#{:crypto.hash(:sha256, query) |> Base.encode16()}"

      Client.get_cached_or_fetch(cache_key, @cache_ttl, fn ->
        perform_geocoding(query, venue_data)
      end)
    end
  end

  @doc """
  Builds a geocoding query string from venue data.
  Prioritizes specific address if available, falls back to venue name + location.
  """
  def build_geocoding_query(venue_data) do
    # Helper to get value from map with both atom and string keys
    get_value = fn map, key ->
      Map.get(map, key) || Map.get(map, to_string(key))
    end

    # Helper to clean and validate string values
    clean_value = fn
      nil -> nil
      "" -> nil
      value when is_binary(value) -> String.trim(value)
      value -> to_string(value)
    end

    # Extract and clean all components
    [
      get_value.(venue_data, :name),
      get_value.(venue_data, :address),
      get_value.(venue_data, :city_name),
      get_value.(venue_data, :state),
      get_value.(venue_data, :country_name)
    ]
    |> Enum.map(clean_value)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  defp perform_geocoding(query, venue_data) do
    api_key = Client.get_api_key()

    if api_key do
      url = build_url(query, api_key)

      # Log without exposing full address for privacy
      Logger.debug(
        "Geocoding venue: #{String.slice(query || "", 0, 50)}#{if String.length(query || "") > 50, do: "...", else: ""}"
      )

      case Client.get_json(url) do
        {:ok, %{"results" => [result | _], "status" => "OK"}} ->
          # Extract coordinates from the first result
          location = get_in(result, ["geometry", "location"])

          if location do
            # Extract Google's official venue name and place_id
            google_name = extract_venue_name(result)
            place_id = result["place_id"]
            original_name = venue_data[:name] || venue_data["name"]

            coordinates = %{
              latitude: location["lat"],
              longitude: location["lng"],
              name: google_name,
              place_id: place_id
            }

            if google_name && google_name != original_name do
              Logger.info(
                "🗺️ Geocoded '#{original_name}' → Google name: '#{google_name}' (place_id: #{place_id})"
              )
            else
              Logger.debug(
                "Successfully geocoded venue '#{original_name}'"
              )
            end

            {:ok, coordinates}
          else
            Logger.warning("No location data in geocoding result for: #{query}")
            {:error, "No location data in result"}
          end

        {:ok, %{"results" => [], "status" => "ZERO_RESULTS"}} ->
          Logger.warning("No geocoding results found for: #{query}")
          {:error, "No results found"}

        {:ok, %{"status" => status, "error_message" => message}} ->
          Logger.error("Google Geocoding API error for '#{query}': #{status} - #{message}")
          {:error, "Geocoding API error: #{status}"}

        {:ok, %{"status" => status}} ->
          Logger.error("Google Geocoding API returned status: #{status} for query: #{query}")
          {:error, "API returned status: #{status}"}

        {:error, reason} ->
          Logger.error("Geocoding request failed for '#{query}': #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("No Google Maps API key configured for geocoding")
      {:error, "No API key configured"}
    end
  end

  defp build_url(query, api_key) do
    params = %{
      address: query,
      key: api_key,
      # Request highest precision results
      result_type: "establishment|street_address|premise",
      # Prefer more accurate results
      location_type: "ROOFTOP|RANGE_INTERPOLATED"
    }

    "#{@base_url}?#{URI.encode_query(params)}"
  end

  @doc """
  Checks if coordinates are valid (not nil and within valid ranges).
  """
  def valid_coordinates?(lat, lng) do
    is_number(lat) && is_number(lng) &&
      lat >= -90 && lat <= 90 &&
      lng >= -180 && lng <= 180
  end

  # Extracts venue name from Google Geocoding API result.
  #
  # IMPORTANT: Only use if Google provides an actual establishment name.
  # Following the same pattern as GooglePlacesDataAdapter (line 83-84):
  #   raw_data["name"] || raw_data["title"] || "Unknown Place"
  #
  # Returns nil if no proper establishment name found - caller should keep original scraped name.
  defp extract_venue_name(result) do
    # Only use name field if it exists (for actual establishments)
    # Do NOT fall back to formatted_address - that's just an address string, not a venue name
    result["name"]
  end
end
