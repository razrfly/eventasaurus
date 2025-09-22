defmodule EventasaurusWeb.Services.GooglePlaces.VenueGeocoder do
  @moduledoc """
  Handles geocoding of venue addresses to obtain GPS coordinates.
  Used as a fallback when scrapers don't provide coordinates.
  """

  alias EventasaurusWeb.Services.GooglePlaces.Client
  require Logger

  @base_url "https://maps.googleapis.com/maps/api/geocode/json"
  @cache_ttl :timer.hours(24)  # Cache geocoding results for 24 hours

  @doc """
  Geocodes a venue address to get latitude and longitude coordinates.

  ## Parameters
    - venue_data: Map containing venue information with at least:
      - name: Venue name
      - address: Street address (optional)
      - city_name: City name (required)
      - country_name: Country name (required)
      - state: State/province (optional)

  ## Returns
    - {:ok, %{latitude: float, longitude: float}} on success
    - {:error, reason} on failure
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
    parts = []

    # Add venue name for context (helps with landmark venues)
    parts = if venue_data[:name], do: [venue_data[:name] | parts], else: parts

    # Add street address if available
    parts = if venue_data[:address] && venue_data[:address] != "",
            do: [venue_data[:address] | parts],
            else: parts

    # Add city
    parts = if venue_data[:city_name], do: [venue_data[:city_name] | parts], else: parts

    # Add state/province if available
    parts = if venue_data[:state] && venue_data[:state] != "",
            do: [venue_data[:state] | parts],
            else: parts

    # Add country
    parts = if venue_data[:country_name], do: [venue_data[:country_name] | parts], else: parts

    # Join all parts with commas
    parts
    |> Enum.reverse()
    |> Enum.filter(&(&1 && &1 != ""))
    |> Enum.join(", ")
  end

  defp perform_geocoding(query, venue_data) do
    api_key = Client.get_api_key()

    if api_key do
      url = build_url(query, api_key)

      Logger.info("Geocoding venue: #{query}")

      case Client.get_json(url) do
        {:ok, %{"results" => [result | _], "status" => "OK"}} ->
          # Extract coordinates from the first result
          location = get_in(result, ["geometry", "location"])

          if location do
            coordinates = %{
              latitude: location["lat"],
              longitude: location["lng"]
            }

            Logger.info("Successfully geocoded venue '#{venue_data[:name]}': #{inspect(coordinates)}")
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
end