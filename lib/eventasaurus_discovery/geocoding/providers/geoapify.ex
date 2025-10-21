defmodule EventasaurusDiscovery.Geocoding.Providers.Geoapify do
  @moduledoc """
  Geoapify Geocoding API provider.

  **Free Tier**: 90,000 requests/month (3,000/day)
  **Rate Limit**: 5 requests/second
  **Quality**: 8/10
  **Coverage**: Good global coverage

  ## API Documentation
  https://www.geoapify.com/geocoding-api

  ## Configuration

  Requires `GEOAPIFY_API_KEY` environment variable.

  Sign up at: https://www.geoapify.com/

  ## Capabilities

  - **Geocoding**: Geocode API for coordinates
  - **Images**: Places API for venue images (limited)
  - **Reviews**: Not implemented
  - **Hours**: Not implemented

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.MultiProvider

  require Logger

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def name, do: "geoapify"

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
      Logger.error("❌ GEOAPIFY_API_KEY not configured")
      {:error, :api_key_missing}
    else
      make_request(address, api_key)
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  defp make_request(address, api_key) do
    url = "https://api.geoapify.com/v1/geocode/search"

    params = [
      text: address,
      apiKey: api_key,
      limit: 1,
      format: "json"
    ]

    Logger.debug("🌐 Geoapify request: #{address}")

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_response(body)

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("❌ Geoapify authentication failed (invalid API key)")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Geoapify rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Geoapify HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Geoapify request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Geoapify request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => [first_result | _]}} ->
        extract_result(first_result)

      {:ok, %{"results" => []}} ->
        Logger.debug("📍 Geoapify: no results found")
        {:error, :no_results}

      {:ok, _other} ->
        Logger.error("❌ Geoapify: unexpected response format")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ Geoapify: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp extract_result(result) do
    # Extract coordinates
    lat = get_in(result, ["lat"])
    lng = get_in(result, ["lon"])

    # Extract city - try multiple fields
    city =
      Map.get(result, "city") ||
        Map.get(result, "municipality") ||
        Map.get(result, "county")

    # Extract country
    country = Map.get(result, "country")

    # Extract Geoapify place ID and convert to string (may be integer in response)
    place_id =
      case Map.get(result, "place_id") do
        nil -> nil
        id when is_integer(id) -> Integer.to_string(id)
        id when is_binary(id) -> id
        other -> to_string(other)
      end

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ Geoapify: missing coordinates in response")
        {:error, :invalid_response}

      not is_number(lat) or not is_number(lng) ->
        Logger.warning("⚠️ Geoapify: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning("⚠️ Geoapify: could not extract city. Result: #{inspect(result)}")
        {:error, :no_city_found}

      true ->
        {:ok,
         %{
           latitude: lat * 1.0,
           longitude: lng * 1.0,
           city: city,
           country: country || "Unknown",
           # New multi-provider field
           provider_id: place_id,
           # Keep for backwards compatibility
           place_id: place_id,
           # Store entire Geoapify result object
           raw_response: result
         }}
    end
  end

  # Images Implementation

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def get_images(place_id) when is_binary(place_id) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("❌ GEOAPIFY_API_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("📸 Geoapify images request: #{place_id}")
      fetch_place_images(place_id, api_key)
    end
  end

  def get_images(_), do: {:error, :invalid_place_id}

  defp fetch_place_images(place_id, api_key) do
    # Geoapify Places Details API
    url = "https://api.geoapify.com/v2/place-details"

    params = [
      id: place_id,
      apiKey: api_key
    ]

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_images_response(body)

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.debug("📍 Geoapify: place not found")
        {:error, :no_results}

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("❌ Geoapify images authentication failed")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Geoapify images rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Geoapify images HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Geoapify images request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Geoapify images request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_images_response(body) do
    case Jason.decode(body) do
      {:ok, %{"features" => [feature | _]}} ->
        properties = get_in(feature, ["properties"]) || %{}

        # Geoapify may have image URLs in properties
        images =
          case Map.get(properties, "image") do
            url when is_binary(url) ->
              [
                %{
                  url: url,
                  width: nil,
                  height: nil,
                  attribution: "Geoapify",
                  source_url: nil
                }
              ]

            _ ->
              []
          end

        if Enum.empty?(images) do
          Logger.debug("📸 Geoapify: no images available")
          {:error, :no_images}
        else
          {:ok, images}
        end

      {:ok, %{"features" => []}} ->
        Logger.debug("📸 Geoapify: no results found")
        {:error, :no_results}

      {:ok, _other} ->
        Logger.debug("📸 Geoapify: place has no images")
        {:error, :no_images}

      {:error, reason} ->
        Logger.error("❌ Geoapify images: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp get_api_key do
    System.get_env("GEOAPIFY_API_KEY")
  end
end
