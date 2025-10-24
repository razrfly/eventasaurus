defmodule EventasaurusDiscovery.Sources.Quizmeisters.Client do
  @moduledoc """
  HTTP client for Quizmeisters with rate limiting and error handling.

  Provides methods for:
  - Fetching venues from storerocket.io API
  - Fetching venue detail pages
  - Automatic retry logic with exponential backoff
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Quizmeisters.Config

  @doc """
  Fetch all venues from the storerocket.io API.

  Returns raw HTTP response for parsing by caller.

  ## Returns
  - `{:ok, %{body: json_string}}` - Raw API response
  - `{:error, reason}` - Request failed
  """
  def fetch_locations(options \\ %{}) do
    retries = Map.get(options, :retries, 0)
    max_retries = Map.get(options, :max_retries, Config.max_retries())

    Logger.info(
      "🔍 Fetching venues from storerocket.io API (attempt #{retries + 1}/#{max_retries + 1})"
    )

    case HTTPoison.get(Config.api_url(), Config.headers(),
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, %{body: body}}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when fetching storerocket.io API")
        maybe_retry(:get_locations, Config.api_url(), status, retries, max_retries, options)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Network error fetching storerocket.io API: #{inspect(reason)}")
        maybe_retry(:get_locations, Config.api_url(), reason, retries, max_retries, options)
    end
  end

  @doc """
  Fetch all venues from the storerocket.io API with parsed response.

  ## Returns
  - `{:ok, locations}` - List of venue location maps
  - `{:error, reason}` - Request failed
  """
  def fetch_venues(options \\ %{}) do
    retries = Map.get(options, :retries, 0)
    max_retries = Map.get(options, :max_retries, Config.max_retries())

    Logger.info(
      "🔍 Fetching venues from storerocket.io API (attempt #{retries + 1}/#{max_retries + 1})"
    )

    case HTTPoison.get(Config.api_url(), Config.headers(),
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_api_response(body)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when fetching storerocket.io API")
        maybe_retry(:get, Config.api_url(), status, retries, max_retries, options)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Network error fetching storerocket.io API: #{inspect(reason)}")
        maybe_retry(:get, Config.api_url(), reason, retries, max_retries, options)
    end
  end

  @doc """
  Fetch a venue detail page with GET request.

  ## Parameters
  - `url` - Full URL to fetch
  - `options` - Optional map with retry settings

  ## Returns
  - `{:ok, %{status_code: 200, body: body}}` - Success
  - `{:error, reason}` - Request failed
  """
  def fetch_page(url, options \\ %{}) do
    retries = Map.get(options, :retries, 0)
    max_retries = Map.get(options, :max_retries, Config.max_retries())

    Logger.debug("🔍 GET #{url} (attempt #{retries + 1}/#{max_retries + 1})")

    case HTTPoison.get(url, Config.headers(),
           follow_redirect: true,
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, %{status_code: 200, body: body}}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when fetching: #{url}")
        maybe_retry(:get, url, status, retries, max_retries, options)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Network error fetching #{url}: #{inspect(reason)}")
        maybe_retry(:get, url, reason, retries, max_retries, options)
    end
  end

  # Parse JSON response from storerocket.io API
  defp parse_api_response(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => %{"locations" => locations}}} when is_list(locations) ->
        Logger.info("✅ Successfully parsed #{length(locations)} venues from API")
        {:ok, locations}

      {:ok, response} ->
        Logger.error("❌ Unexpected API response format: #{inspect(response)}")
        {:error, "Unexpected API response format"}

      {:error, reason} ->
        Logger.error("❌ Failed to parse JSON response: #{inspect(reason)}")
        {:error, "Failed to parse JSON response"}
    end
  end

  # Private retry logic with exponential backoff
  defp maybe_retry(_method, _request_data, _error, retries, max_retries, _options)
       when retries >= max_retries do
    Logger.error("❌ Max retries (#{max_retries}) exceeded")
    {:error, :max_retries_exceeded}
  end

  defp maybe_retry(method, request_data, _error, retries, max_retries, options) do
    # Exponential backoff: 500ms, 1000ms, 2000ms
    backoff_ms = (Config.retry_delay_ms() * :math.pow(2, retries)) |> round()
    Logger.info("⏱️  Retrying in #{backoff_ms}ms... (#{retries + 1}/#{max_retries})")

    Process.sleep(backoff_ms)

    # Update retry count and recurse
    updated_options = Map.put(options, :retries, retries + 1)

    case method do
      :get_locations ->
        fetch_locations(updated_options)

      :get when is_binary(request_data) ->
        if request_data == Config.api_url() do
          fetch_venues(updated_options)
        else
          fetch_page(request_data, updated_options)
        end
    end
  end
end
