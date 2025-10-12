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

  ## Response Format

  Returns standardized geocode result with coordinates, city, and country.
  """

  @behaviour EventasaurusDiscovery.Geocoding.Provider

  require Logger

  @impl true
  def name, do: "here"

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

    cond do
      is_nil(lat) or is_nil(lng) ->
        Logger.warning("⚠️ HERE: missing coordinates in response")
        {:error, :invalid_response}

      not is_number(lat) or not is_number(lng) ->
        Logger.warning("⚠️ HERE: invalid coordinate types")
        {:error, :invalid_response}

      is_nil(city) ->
        Logger.warning("⚠️ HERE: could not extract city. Address: #{inspect(address)}")
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
    System.get_env("HERE_API_KEY")
  end
end
