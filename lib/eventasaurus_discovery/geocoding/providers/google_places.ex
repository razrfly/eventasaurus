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

  Requires `GOOGLE_MAPS_API_KEY` environment variable.

  **Note**: This provider is **DISABLED by default** due to high cost ($0.034/call).
  Enable only as absolute last resort.

  ## Cost Breakdown
  - Text Search: $0.017 per request
  - Place Details: $0.017 per request
  - **Total**: $0.034 per geocode

  ## Capabilities

  - **Geocoding**: Text Search + Place Details for coordinates
  - **Images**: Place Photos API for venue images (up to 10 photos)
  - **Reviews**: Not implemented (available in API)
  - **Hours**: Not implemented (available in API)

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.MultiProvider

  require Logger

  alias EventasaurusDiscovery.Costs.ExternalServiceCost
  alias EventasaurusDiscovery.Geocoding.Pricing

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def name, do: "google_places"

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def capabilities do
    %{
      "geocoding" => true,
      "images" => true,
      "reviews" => false,
      "hours" => false
    }
  end

  @impl true
  def geocode(address) when is_binary(address) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("❌ GOOGLE_MAPS_API_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("🌐 Google Places request: #{address}")

      # Step 1: Text Search to find place_id
      case text_search(address, api_key) do
        {:ok, google_place_id} ->
          # Step 2: Place Details to get full information
          place_details(google_place_id, api_key)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  @doc """
  Searches for a venue by coordinates and optional name.

  Google Places doesn't support this for Phase 1 due to high cost ($0.034/call).
  Returns error to avoid unexpected charges.
  """
  def search_by_coordinates(_lat, _lng, _venue_name \\ nil) do
    Logger.warning("⚠️ Google Places search_by_coordinates disabled due to high cost")
    {:error, :not_implemented}
  end

  # Step 1: Text Search API
  defp text_search(address, api_key) do
    url = "https://maps.googleapis.com/maps/api/place/textsearch/json"
    start_time = System.monotonic_time(:millisecond)

    params = [
      query: address,
      key: api_key
    ]

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        record_cost("text_search", duration_ms)
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
    start_time = System.monotonic_time(:millisecond)

    params = [
      place_id: place_id,
      fields: "geometry,address_components,formatted_address",
      key: api_key
    ]

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        record_cost("details", duration_ms)
        parse_place_details_response(body, place_id)

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

  defp parse_place_details_response(body, place_id) do
    case Jason.decode(body) do
      {:ok, %{"result" => result, "status" => "OK"}} ->
        extract_result(result, place_id)

      {:ok, %{"status" => status}} ->
        Logger.error("❌ Google Places Details error status: #{status}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("❌ Google Places Details: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp extract_result(result, place_id) do
    # Extract coordinates
    lat = get_in(result, ["geometry", "location", "lat"])
    lng = get_in(result, ["geometry", "location", "lng"])

    # Extract formatted address
    formatted_address = Map.get(result, "formatted_address")

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
           country: country || "Unknown",
           # Formatted address from Google Places
           address: formatted_address,
           # New multi-provider field
           provider_id: place_id,
           # Keep for backwards compatibility
           place_id: place_id,
           # Store entire Google Places result object
           raw_response: result
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

  # Images Implementation

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def get_images(place_id) when is_binary(place_id) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("❌ GOOGLE_MAPS_API_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("📸 Google Places Photos request: #{place_id}")
      fetch_place_photos(place_id, api_key)
    end
  end

  def get_images(_), do: {:error, :invalid_place_id}

  defp fetch_place_photos(place_id, api_key) do
    # First get photo references from Place Details
    url = "https://maps.googleapis.com/maps/api/place/details/json"
    start_time = System.monotonic_time(:millisecond)

    params = [
      place_id: place_id,
      fields: "photos",
      key: api_key
    ]

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        record_cost("details_photos", duration_ms)
        parse_photos_response(body, api_key)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        # Parse the error message from Google's response
        error_message =
          case Jason.decode(body) do
            {:ok, %{"error_message" => msg}} -> msg
            {:ok, %{"status" => status_text}} -> status_text
            _ -> body
          end

        Logger.error("❌ Google Places Photos HTTP #{status}: #{error_message}")
        {:error, "HTTP #{status}: #{error_message}"}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Google Places Photos request timed out")
        {:error, :timeout}

      {:error, %HTTPoison.Error{reason: _reason}} = err ->
        Logger.error("❌ Google Places Photos request failed: #{inspect(err)}")
        {:error, :network_error}
    end
  end

  defp parse_photos_response(body, api_key) do
    case Jason.decode(body) do
      {:ok, %{"result" => %{"photos" => photos}, "status" => "OK"}} when is_list(photos) ->
        images =
          photos
          |> Enum.take(10)
          |> Enum.map(fn photo ->
            photo_reference = Map.get(photo, "photo_reference")
            width = Map.get(photo, "width")
            height = Map.get(photo, "height")
            attributions = Map.get(photo, "html_attributions", [])

            # Construct Google Places Photo URL
            # Note: This requires an API call per photo in production, or use static URL with maxwidth
            url =
              "https://maps.googleapis.com/maps/api/place/photo?maxwidth=#{width || 1600}&photo_reference=#{photo_reference}&key=#{api_key}"

            %{
              url: url,
              width: width,
              height: height,
              attribution: Enum.join(attributions, " | "),
              source_url: nil
            }
          end)

        if Enum.empty?(images) do
          {:error, :no_images}
        else
          {:ok, images}
        end

      {:ok, %{"result" => %{}, "status" => "OK"}} ->
        Logger.debug("📸 Google Places: no photos available")
        {:error, :no_images}

      {:ok, %{"status" => "ZERO_RESULTS"}} ->
        Logger.debug("📸 Google Places: place has no photos")
        {:error, :no_images}

      {:ok, %{"status" => status, "error_message" => error_msg}} ->
        case status do
          "OVER_QUERY_LIMIT" ->
            Logger.warning("⚠️ Google Places Photos rate limited: #{error_msg}")
            {:error, :rate_limited}

          "RESOURCE_EXHAUSTED" ->
            Logger.warning("⚠️ Google Places Photos resource exhausted: #{error_msg}")
            {:error, :rate_limited}

          _ ->
            Logger.error("❌ Google Places Photos error: #{status} - #{error_msg}")
            {:error, "API error: #{status}"}
        end

      {:ok, %{"status" => status}} ->
        case status do
          "OVER_QUERY_LIMIT" ->
            Logger.warning("⚠️ Google Places Photos rate limited")
            {:error, :rate_limited}

          "RESOURCE_EXHAUSTED" ->
            Logger.warning("⚠️ Google Places Photos resource exhausted")
            {:error, :rate_limited}

          _ ->
            Logger.error("❌ Google Places Photos error status: #{status}")
            {:error, "API error: #{status}"}
        end

      {:error, reason} ->
        Logger.error("❌ Google Places Photos: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp get_api_key do
    System.get_env("GOOGLE_MAPS_API_KEY")
  end

  # Cost tracking for external service monitoring (Issue #3443)
  defp record_cost(operation, duration_ms) do
    cost =
      case operation do
        "text_search" -> Pricing.google_places_text_search_cost()
        "details" -> Pricing.google_places_details_cost()
        "details_photos" -> Pricing.google_places_details_cost()
        _ -> 0.0
      end

    ExternalServiceCost.record_async(%{
      service_type: "geocoding",
      provider: "google_places",
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
