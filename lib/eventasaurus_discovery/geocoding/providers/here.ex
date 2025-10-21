defmodule EventasaurusDiscovery.Geocoding.Providers.Here do
  @moduledoc """
  HERE Geocoding API provider.

  **Free Tier**: 250,000 requests/month
  **Rate Limit**: Generous (100+ requests/second)
  **Quality**: 9/10
  **Coverage**: Excellent global coverage

  ## API Documentation
  https://developer.here.com/documentation/geocoding-search-api/

  ## Configuration

  Requires `HERE_API_KEY` environment variable (already configured in .env).

  Sign up at: https://developer.here.com/

  ## Capabilities

  - **Geocoding**: Geocode API for coordinates
  - **Images**: Browse API for venue images (limited availability)
  - **Reviews**: Not implemented
  - **Hours**: Not implemented

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.MultiProvider

  require Logger

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def name, do: "here"

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
      Logger.error("❌ HERE_API_KEY not configured")
      {:error, :api_key_missing}
    else
      make_request(address, api_key)
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  defp make_request(address, api_key) do
    url = "https://geocode.search.hereapi.com/v1/geocode"

    params = [
      q: address,
      apiKey: api_key,
      limit: 1
    ]

    Logger.debug("🌐 HERE request: #{address}")

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_response(body)

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("❌ HERE authentication failed (invalid API key)")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ HERE rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HERE HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ HERE request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ HERE request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"items" => [first_item | _]}} ->
        extract_result(first_item)

      {:ok, %{"items" => []}} ->
        Logger.debug("📍 HERE: no results found")
        {:error, :no_results}

      {:ok, _other} ->
        Logger.error("❌ HERE: unexpected response format")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ HERE: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp extract_result(item) do
    # Extract coordinates from position
    position = get_in(item, ["position"])
    lat = get_in(position, ["lat"])
    lng = get_in(position, ["lng"])

    # Extract address components
    address = get_in(item, ["address"]) || %{}

    # Try multiple fields for city
    city =
      Map.get(address, "city") ||
        Map.get(address, "district") ||
        Map.get(address, "county")

    country = Map.get(address, "countryName")

    # Extract HERE place ID and convert to string (may be integer in response)
    place_id =
      case Map.get(item, "id") do
        nil -> nil
        id when is_integer(id) -> Integer.to_string(id)
        id when is_binary(id) -> id
        other -> to_string(other)
      end

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ HERE: missing coordinates in response")
        {:error, :invalid_response}

      not is_number(lat) or not is_number(lng) ->
        Logger.warning("⚠️ HERE: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning("⚠️ HERE: could not extract city. Address: #{inspect(address)}")
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
           # Store entire HERE item object
           raw_response: item
         }}
    end
  end

  # Images Implementation

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def get_images(place_id) when is_binary(place_id) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("❌ HERE_API_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("📸 HERE images request: #{place_id}")
      fetch_place_images(place_id, api_key)
    end
  end

  def get_images(_), do: {:error, :invalid_place_id}

  defp fetch_place_images(place_id, api_key) do
    # HERE Lookup API to get place details including images
    url = "https://lookup.search.hereapi.com/v1/lookup"

    params = [
      id: place_id,
      apiKey: api_key
    ]

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_images_response(body)

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.debug("📍 HERE: place not found")
        {:error, :no_results}

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("❌ HERE images authentication failed")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ HERE images rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HERE images HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ HERE images request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ HERE images request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_images_response(body) do
    case Jason.decode(body) do
      {:ok, %{"images" => images}} when is_list(images) ->
        # Extract images from top-level images array
        mapped_images =
          Enum.map(images, fn img ->
            %{
              url: Map.get(img, "url") || Map.get(img, "src"),
              width: nil,
              height: nil,
              attribution: "HERE",
              source_url: nil
            }
          end)

        if Enum.empty?(mapped_images) do
          Logger.debug("📸 HERE: no images available for this place")
          {:error, :no_images}
        else
          {:ok, mapped_images}
        end

      {:ok, _} ->
        Logger.debug("📸 HERE: no results found or no images available")
        {:error, :no_images}

      {:error, reason} ->
        Logger.error("❌ HERE images: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp get_api_key do
    System.get_env("HERE_API_KEY")
  end
end
