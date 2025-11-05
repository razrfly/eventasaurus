defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Client do
  @moduledoc """
  HTTP client for Geeks Who Drink with rate limiting and error handling.

  Provides methods for:
  - Fetching the venues page to extract nonce
  - Making POST requests to the WordPress AJAX API
  - Fetching venue detail pages
  - Fetching performer data from AJAX endpoint
  - Automatic retry logic with exponential backoff
  """

  require Logger
  alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Config

  @doc """
  Fetch a page with GET request.

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

      # WordPress AJAX sometimes returns 500 with valid content
      # Accept 500 if the response body contains venue blocks
      {:ok, %HTTPoison.Response{status_code: 500, body: body}} when is_binary(body) ->
        if String.contains?(body, "quizBlock-") do
          Logger.warning("⚠️ Got HTTP 500 but response contains valid venue data, accepting")
          {:ok, %{status_code: 200, body: body}}
        else
          Logger.error("❌ HTTP 500 with invalid content when fetching: #{url}")
          maybe_retry(:get, url, 500, retries, max_retries, options)
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when fetching: #{url}")
        maybe_retry(:get, url, status, retries, max_retries, options)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Network error fetching #{url}: #{inspect(reason)}")
        maybe_retry(:get, url, reason, retries, max_retries, options)
    end
  end

  @doc """
  Make a GET request to the WordPress AJAX API with query parameters.

  ## Parameters
  - `params` - Map of parameters to send as query string
  - `options` - Optional map with retry settings

  ## Returns
  - `{:ok, body}` - Success with response body
  - `{:error, reason}` - Request failed
  """
  def get_ajax(params, options \\ %{}) do
    url = Config.ajax_url()
    retries = Map.get(options, :retries, 0)
    max_retries = Map.get(options, :max_retries, Config.max_retries())

    # Build URL with query parameters
    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"

    Logger.debug(
      "🔍 GET #{url} with action: #{params["action"]} (attempt #{retries + 1}/#{max_retries + 1})"
    )

    case HTTPoison.get(full_url, Config.headers(),
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when calling AJAX API")
        maybe_retry(:ajax_get, {url, params}, status, retries, max_retries, options)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Network error calling AJAX API: #{inspect(reason)}")
        maybe_retry(:ajax_get, {url, params}, reason, retries, max_retries, options)
    end
  end

  @doc """
  Make a POST request to the WordPress AJAX API.

  ## Parameters
  - `params` - Map of parameters to send in the POST body
  - `options` - Optional map with retry settings

  ## Returns
  - `{:ok, body}` - Success with response body
  - `{:error, reason}` - Request failed
  """
  def post_ajax(params, options \\ %{}) do
    url = Config.ajax_url()
    retries = Map.get(options, :retries, 0)
    max_retries = Map.get(options, :max_retries, Config.max_retries())

    body = URI.encode_query(params)
    headers = Config.headers() ++ [{"Content-Type", "application/x-www-form-urlencoded"}]

    Logger.debug(
      "🔍 POST #{url} with action: #{params["action"]} (attempt #{retries + 1}/#{max_retries + 1})"
    )

    case HTTPoison.post(url, body, headers,
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when posting to AJAX API")
        maybe_retry(:post, {url, params}, status, retries, max_retries, options)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Network error posting to AJAX API: #{inspect(reason)}")
        maybe_retry(:post, {url, params}, reason, retries, max_retries, options)
    end
  end

  # Private retry logic with exponential backoff
  defp maybe_retry(method, _request_data, _error, retries, max_retries, _options)
       when retries >= max_retries do
    Logger.error("❌ Max retries (#{max_retries}) exceeded for #{method} request")
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
      :get ->
        fetch_page(request_data, updated_options)

      :ajax_get ->
        {_url, params} = request_data
        get_ajax(params, updated_options)

      :post ->
        {_url, params} = request_data
        post_ajax(params, updated_options)
    end
  end
end
