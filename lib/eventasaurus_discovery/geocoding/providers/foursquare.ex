defmodule EventasaurusDiscovery.Geocoding.Providers.Foursquare do
  @moduledoc """
  Foursquare Places API provider (multi-capability).

  **Cost**: Free tier available (regular request limits)
  **Rate Limit**: 500 requests/day (free), higher for paid
  **Quality**: 9/10 (excellent POI data, venue photos)
  **Coverage**: Best-in-class for businesses and venues globally

  ## API Documentation
  https://docs.foursquare.com/developer/reference/places-api-overview

  ## Configuration

  Requires `FOURSQUARE_API_KEY` environment variable.

  Sign up at: https://foursquare.com/developers/

  ## Capabilities

  - **Geocoding**: Address search to find venues and coordinates
  - **Images**: High-quality venue photos with attribution
  - **Reviews**: Not implemented (use Foursquare's tips/ratings separately)
  - **Hours**: Not implemented yet (available in API)

  ## Response Format

  Returns standardized results for geocoding and images with Foursquare place IDs.
  """

  @behaviour EventasaurusDiscovery.Geocoding.MultiProvider

  require Logger

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def name, do: "foursquare"

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def capabilities do
    %{
      "geocoding" => true,
      "images" => true,
      "reviews" => false,
      "hours" => false
    }
  end

  # Geocoding Implementation

  @impl true
  def geocode(address) when is_binary(address) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("❌ FOURSQUARE_API_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("🌐 Foursquare geocode request: #{address}")
      search_places(address, api_key)
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  defp search_places(address, api_key) do
    url = "https://places-api.foursquare.com/places/search"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Accept", "application/json"},
      {"X-Places-Api-Version", "2025-06-17"}
    ]

    params = [
      query: address,
      limit: 1
    ]

    case HTTPoison.get(url, headers, params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_geocode_response(body)

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("❌ Foursquare authentication failed (invalid API key)")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Foursquare rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Foursquare HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Foursquare request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Foursquare request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_geocode_response(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => [first_result | _]}} ->
        extract_geocode_result(first_result)

      {:ok, %{"results" => []}} ->
        Logger.debug("📍 Foursquare: no results found")
        {:error, :no_results}

      {:ok, other} ->
        Logger.error("❌ Foursquare: unexpected response format: #{inspect(other)}")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ Foursquare: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp extract_geocode_result(result) do
    # Extract coordinates - new API has them at root level
    lat = Map.get(result, "latitude")
    lng = Map.get(result, "longitude")

    # Extract location information
    location = get_in(result, ["location"]) || %{}
    city = Map.get(location, "locality") || Map.get(location, "region")
    country = Map.get(location, "country")

    # Extract Foursquare place ID (fsq_place_id in new API)
    place_id = Map.get(result, "fsq_place_id")

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ Foursquare: missing coordinates in response")
        {:error, :invalid_response}

      not is_number(lat) or not is_number(lng) ->
        Logger.warning("⚠️ Foursquare: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning("⚠️ Foursquare: missing city; returning coordinates anyway")
        {:ok,
         %{
           latitude: lat * 1.0,
           longitude: lng * 1.0,
           city: nil,
           country: country || "Unknown",
           provider_id: place_id,
           raw_response: result
         }}

      true ->
        {:ok,
         %{
           latitude: lat * 1.0,
           longitude: lng * 1.0,
           city: city,
           country: country || "Unknown",
           provider_id: place_id,
           raw_response: result
         }}
    end
  end

  # Search by Coordinates (for backfill)

  @doc """
  Searches for a venue by coordinates and optional name.

  Used for backfilling provider IDs when we have venue coordinates but no Foursquare ID.

  ## Parameters
  - `lat` - Latitude
  - `lng` - Longitude
  - `venue_name` - Optional venue name for better matching (can be nil)

  ## Returns
  - `{:ok, provider_id}` - Found venue ID
  - `{:error, reason}` - No venue found or API error
  """
  def search_by_coordinates(lat, lng, venue_name \\ nil)
      when is_number(lat) and is_number(lng) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("❌ FOURSQUARE_API_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("🔍 Foursquare search by coordinates: #{lat},#{lng} name=#{inspect(venue_name)}")
      do_coordinate_search(lat, lng, venue_name, api_key)
    end
  end

  defp do_coordinate_search(lat, lng, venue_name, api_key) do
    url = "https://places-api.foursquare.com/places/search"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Accept", "application/json"},
      {"X-Places-Api-Version", "2025-06-17"}
    ]

    # Build params - use name query if provided, otherwise just search by location
    base_params = [
      ll: "#{lat},#{lng}",
      radius: 100,  # 100 meter radius
      limit: 5      # Get top 5 results for matching
    ]

    params = if venue_name && String.trim(venue_name) != "" do
      [{:query, venue_name} | base_params]
    else
      base_params
    end

    case HTTPoison.get(url, headers, params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_search_response(body, venue_name)

      {:ok, %HTTPoison.Response{status_code: 401, body: body}} ->
        Logger.error("❌ Foursquare search authentication failed. Response: #{body}")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Foursquare search rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Foursquare search HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Foursquare search timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Foursquare search failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_search_response(body, venue_name) do
    case Jason.decode(body) do
      {:ok, %{"results" => results}} when is_list(results) and length(results) > 0 ->
        # If we have a venue name, try to find best match
        # Otherwise just take the first result (closest by distance)
        provider_id = if venue_name && String.trim(venue_name) != "" do
          find_best_match(results, venue_name)
        else
          # Just take first result (closest to coordinates)
          first = List.first(results)
          Map.get(first, "fsq_place_id")
        end

        if provider_id do
          Logger.debug("✅ Foursquare found venue: #{provider_id}")
          {:ok, provider_id}
        else
          Logger.debug("📍 Foursquare: no matching venue found")
          {:error, :no_results}
        end

      {:ok, %{"results" => []}} ->
        Logger.debug("📍 Foursquare: no results found")
        {:error, :no_results}

      {:ok, other} ->
        Logger.error("❌ Foursquare search: unexpected response: #{inspect(other)}")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ Foursquare search: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp find_best_match(results, venue_name) do
    # Normalize venue name for comparison
    normalized_name = String.downcase(String.trim(venue_name))

    # Try to find exact or partial match
    matched = Enum.find(results, fn result ->
      result_name = get_in(result, ["name"]) || ""
      normalized_result = String.downcase(result_name)

      # Check if names match (exact or contains)
      normalized_result == normalized_name ||
        String.contains?(normalized_result, normalized_name) ||
        String.contains?(normalized_name, normalized_result)
    end)

    case matched do
      nil ->
        # No name match, just use first result (closest by distance)
        first = List.first(results)
        Map.get(first, "fsq_place_id")
      result ->
        Map.get(result, "fsq_place_id")
    end
  end

  # Images Implementation

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def get_images(place_id) when is_binary(place_id) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("❌ FOURSQUARE_API_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("📸 Foursquare images request: #{place_id}")
      fetch_photos(place_id, api_key)
    end
  end

  def get_images(_), do: {:error, :invalid_place_id}

  defp fetch_photos(place_id, api_key) do
    url = "https://places-api.foursquare.com/places/#{place_id}/photos"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Accept", "application/json"},
      {"X-Places-Api-Version", "2025-06-17"}
    ]

    params = [
      limit: 10,
      # Get up to 10 photos
      sort: "POPULAR"
    ]

    case HTTPoison.get(url, headers, params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_photos_response(body)

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.debug("📍 Foursquare: place not found")
        {:error, :no_results}

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("❌ Foursquare photos authentication failed")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Foursquare photos rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Foursquare photos HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Foursquare photos request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Foursquare photos request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_photos_response(body) do
    case Jason.decode(body) do
      {:ok, photos} when is_list(photos) and length(photos) > 0 ->
        images =
          Enum.map(photos, fn photo ->
            # Foursquare photo URL format: prefix + size + suffix
            prefix = Map.get(photo, "prefix")
            suffix = Map.get(photo, "suffix")
            width = Map.get(photo, "width")
            height = Map.get(photo, "height")

            # Construct URL with original size
            url =
              if prefix && suffix do
                "#{prefix}original#{suffix}"
              else
                nil
              end

            %{
              url: url,
              width: width,
              height: height,
              attribution: "Foursquare",
              source_url: nil
            }
          end)
          |> Enum.reject(fn img -> is_nil(img.url) end)

        if Enum.empty?(images) do
          {:error, :no_images}
        else
          {:ok, images}
        end

      {:ok, []} ->
        Logger.debug("📸 Foursquare: no photos found")
        {:error, :no_images}

      {:ok, other} ->
        Logger.error("❌ Foursquare photos: unexpected response format: #{inspect(other)}")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ Foursquare photos: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp get_api_key do
    System.get_env("FOURSQUARE_API_KEY")
  end
end
