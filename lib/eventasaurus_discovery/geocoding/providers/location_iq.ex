defmodule EventasaurusDiscovery.Geocoding.Providers.LocationIQ do
  @moduledoc """
  LocationIQ Geocoding API provider (OpenStreetMap-based).

  **Free Tier**: 150,000 requests/month (5,000/day)
  **Rate Limit**: 2 requests/second
  **Quality**: 7/10 (OSM-based)
  **Coverage**: Good global coverage via OpenStreetMap

  ## API Documentation
  https://locationiq.com/docs

  ## Configuration

  Requires `LOCATION_IQ_ACCESS_TOKEN` environment variable.

  Sign up at: https://locationiq.com/

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.Provider

  require Logger

  @impl true
  def name, do: "locationiq"

  @impl true
  def geocode(address) when is_binary(address) do
    access_token = get_access_token()

    if is_nil(access_token) do
      Logger.error("❌ LOCATION_IQ_ACCESS_TOKEN not configured")
      {:error, :api_key_missing}
    else
      make_request(address, access_token)
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  defp make_request(address, access_token) do
    url = "https://us1.locationiq.com/v1/search.php"

    params = [
      q: address,
      key: access_token,
      format: "json",
      limit: 1,
      addressdetails: 1
    ]

    Logger.debug("🌐 LocationIQ request: #{address}")

    case HTTPoison.get(url, [], params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_response(body)

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("❌ LocationIQ authentication failed (invalid access token)")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ LocationIQ rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ LocationIQ HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ LocationIQ request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ LocationIQ request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, [first_result | _]} when is_map(first_result) ->
        extract_result(first_result)

      {:ok, []} ->
        Logger.debug("📍 LocationIQ: no results found")
        {:error, :no_results}

      {:ok, _other} ->
        Logger.error("❌ LocationIQ: unexpected response format")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ LocationIQ: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp extract_result(result) do
    # Extract coordinates (already in correct order: lat, lon)
    lat = Map.get(result, "lat")
    lng = Map.get(result, "lon")

    # Parse string coordinates to float
    {lat, lng} =
      case {lat, lng} do
        {lat_str, lng_str} when is_binary(lat_str) and is_binary(lng_str) ->
          {String.to_float(lat_str), String.to_float(lng_str)}

        _ ->
          {nil, nil}
      end

    # Extract address details
    address = Map.get(result, "address", %{})

    # Try multiple city fields in order
    city =
      Map.get(address, "city") ||
        Map.get(address, "town") ||
        Map.get(address, "village") ||
        Map.get(address, "municipality") ||
        Map.get(address, "county")

    country = Map.get(address, "country")

    # Extract LocationIQ place ID and convert to string (may be integer in response)
    place_id =
      case Map.get(result, "place_id") do
        nil -> nil
        id when is_integer(id) -> Integer.to_string(id)
        id when is_binary(id) -> id
        other -> to_string(other)
      end

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ LocationIQ: missing or invalid coordinates in response")
        {:error, :invalid_response}

      not is_number(lat) or not is_number(lng) ->
        Logger.warning("⚠️ LocationIQ: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning("⚠️ LocationIQ: could not extract city. Address: #{inspect(address)}")

        {:error, :no_city_found}

      true ->
        {:ok,
         %{
           latitude: lat,
           longitude: lng,
           city: city,
           country: country || "Unknown",
           # New multi-provider field
           provider_id: place_id,
           # Keep for backwards compatibility
           place_id: place_id,
           # Store entire LocationIQ result object
           raw_response: result
         }}
    end
  end

  defp get_access_token do
    System.get_env("LOCATION_IQ_ACCESS_TOKEN")
  end
end
