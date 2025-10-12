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

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.Provider

  require Logger

  @impl true
  def name, do: "geoapify"

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

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ Geoapify: missing coordinates in response")
        {:error, :invalid_response}

      not is_number(lat) or not is_number(lng) ->
        Logger.warning("⚠️ Geoapify: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning("⚠️ Geoapify: could not extract city. Result: #{inspect(result)}")
        {:ok,
         %{
           latitude: lat * 1.0,
           longitude: lng * 1.0,
           city: "Unknown",
           country: country || "Unknown"
         }}

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

  defp get_api_key do
    System.get_env("GEOAPIFY_API_KEY")
  end
end
