defmodule EventasaurusDiscovery.Geocoding.Providers.GooglePlaces do
  @moduledoc """
  Google Places API provider (Text Search + Place Details).

  **Cost**: $0.034 per request ($0.017 Text Search + $0.017 Place Details)
  **Rate Limit**: 100 requests/second
  **Quality**: 10/10 (highest quality)
  **Coverage**: Best-in-class global coverage

  ## API Documentation
  https://developers.google.com/maps/documentation/places/web-service/search-text
  https://developers.google.com/maps/documentation/places/web-service/details

  ## Configuration

  Requires `GOOGLE_PLACES_API_KEY` environment variable.

  **Note**: This provider is **DISABLED by default** due to high cost ($0.034/call).
  Enable only as absolute last resort.

  ## Cost Breakdown
  - Text Search: $0.017 per request
  - Place Details: $0.017 per request
  - **Total**: $0.034 per geocode

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.Provider

  require Logger

  @impl true
  def name, do: "google_places"

  @impl true
  def geocode(address) when is_binary(address) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("❌ GOOGLE_PLACES_API_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("🌐 Google Places request: #{address}")

      # Step 1: Text Search to find place_id
      case text_search(address, api_key) do
        {:ok, place_id} ->
          # Step 2: Place Details to get full information
          place_details(place_id, api_key)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  # Step 1: Text Search API
  defp text_search(address, api_key) do
    url = "https://maps.googleapis.com/maps/api/place/textsearch/json"

    params = [
      query: address,
      key: api_key
    ]

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_text_search_response(body)

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Google Places rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: 403}} ->
        Logger.error(
          "❌ Google Places authentication failed (invalid API key or billing not enabled)"
        )

        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Google Places HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Google Places request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Google Places request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_text_search_response(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => [first_result | _], "status" => "OK"}} ->
        place_id = Map.get(first_result, "place_id")

        if place_id do
          {:ok, place_id}
        else
          Logger.error("❌ Google Places: no place_id in result")
          {:error, :invalid_response}
        end

      {:ok, %{"results" => [], "status" => "ZERO_RESULTS"}} ->
        Logger.debug("📍 Google Places: no results found")
        {:error, :no_results}

      {:ok, %{"status" => status}} ->
        Logger.error("❌ Google Places error status: #{status}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("❌ Google Places: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  # Step 2: Place Details API
  defp place_details(place_id, api_key) do
    url = "https://maps.googleapis.com/maps/api/place/details/json"

    params = [
      place_id: place_id,
      fields: "geometry,address_components,formatted_address",
      key: api_key
    ]

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_place_details_response(body)

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Google Places Details rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: 403}} ->
        Logger.error(
          "❌ Google Places Details authentication failed (invalid API key or billing not enabled)"
        )

        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Google Places Details HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Google Places Details request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Google Places Details request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_place_details_response(body) do
    case Jason.decode(body) do
      {:ok, %{"result" => result, "status" => "OK"}} ->
        extract_result(result)

      {:ok, %{"status" => status}} ->
        Logger.error("❌ Google Places Details error status: #{status}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("❌ Google Places Details: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp extract_result(result) do
    # Extract coordinates
    lat = get_in(result, ["geometry", "location", "lat"])
    lng = get_in(result, ["geometry", "location", "lng"])

    # Extract city and country from address_components
    address_components = Map.get(result, "address_components", [])

    city = extract_city(address_components)
    country = extract_country(address_components)

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ Google Places: missing coordinates in response")
        {:error, :invalid_response}

      not is_number(lat) or not is_number(lng) ->
        Logger.warning("⚠️ Google Places: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning("⚠️ Google Places: could not extract city")
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

  # Extract city from address_components
  # Try: locality, postal_town, administrative_area_level_2
  defp extract_city(address_components) do
    Enum.find_value(address_components, fn component ->
      types = Map.get(component, "types", [])
      long_name = Map.get(component, "long_name")

      cond do
        "locality" in types -> long_name
        "postal_town" in types -> long_name
        "administrative_area_level_2" in types -> long_name
        true -> nil
      end
    end)
  end

  # Extract country from address_components
  defp extract_country(address_components) do
    Enum.find_value(address_components, fn component ->
      types = Map.get(component, "types", [])
      long_name = Map.get(component, "long_name")

      if "country" in types, do: long_name
    end)
  end

  defp get_api_key do
    System.get_env("GOOGLE_PLACES_API_KEY")
  end
end
