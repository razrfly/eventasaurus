defmodule EventasaurusDiscovery.Http.Adapters.Crawlbase do
  @moduledoc """
  Crawlbase API adapter for web scraping with anti-bot bypass.

  This adapter uses the Crawlbase API to fetch web pages with optional
  JavaScript rendering, making it effective for bypassing Cloudflare
  and other anti-bot protections.

  ## Features

  - Normal mode for static HTML scraping
  - JavaScript mode for browser-rendered content
  - Automatic CAPTCHA bypass (included in API)
  - Configurable page wait for dynamic content
  - Crawlbase-specific error handling

  ## Configuration

  Requires one or both environment variables:
  - `CRAWLBASE_NORMAL_API_KEY` - For static HTML requests
  - `CRAWLBASE_JS_API_KEY` - For JavaScript-rendered requests

  ```elixir
  # config/runtime.exs
  config :eventasaurus, :crawlbase_normal_api_key,
    System.get_env("CRAWLBASE_NORMAL_API_KEY")

  config :eventasaurus, :crawlbase_js_api_key,
    System.get_env("CRAWLBASE_JS_API_KEY")
  ```

  ## Usage

      alias EventasaurusDiscovery.Http.Adapters.Crawlbase

      # Check if available (at least one API key configured)
      if Crawlbase.available?() do
        # JavaScript-rendered HTML (default for protected sites)
        {:ok, html, metadata} = Crawlbase.fetch("https://example.com",
          mode: :javascript
        )

        # Normal/static HTML (faster, cheaper)
        {:ok, html, metadata} = Crawlbase.fetch("https://example.com",
          mode: :normal
        )
      end

  ## Modes

  - `:javascript` (default) - Browser rendering with JavaScript execution
  - `:normal` - Simple HTTP request without JavaScript rendering

  ## Error Handling

  Returns normalized errors:
  - `{:error, {:crawlbase_error, status, message}}` - Crawlbase API error
  - `{:error, {:rate_limit, retry_after}}` - Rate limited
  - `{:error, {:timeout, type}}` - Connection or receive timeout
  - `{:error, {:network_error, reason}}` - Network failure
  - `{:error, :not_configured}` - Required API key not set for mode

  ## Pricing Considerations

  - JavaScript token costs 2x normal token
  - Only charged for successful requests
  - Consider using fallback chains (direct → crawlbase) to minimize costs
  """

  @behaviour EventasaurusDiscovery.Http.Adapter

  require Logger

  @crawlbase_api_url "https://api.crawlbase.com/"
  @default_timeout 60_000
  @default_recv_timeout 60_000
  @default_page_wait 2000

  @impl true
  def fetch(url, opts \\ []) do
    mode = Keyword.get(opts, :mode, :javascript)

    if available_for_mode?(mode) do
      do_fetch(url, opts)
    else
      {:error, :not_configured}
    end
  end

  @impl true
  def name, do: "crawlbase"

  @impl true
  def available? do
    # Available if either token is configured
    has_normal_key?() or has_js_key?()
  end

  @doc """
  Checks if the adapter is available for a specific mode.

  ## Examples

      iex> Crawlbase.available_for_mode?(:javascript)
      true  # when CRAWLBASE_JS_API_KEY is set

      iex> Crawlbase.available_for_mode?(:normal)
      true  # when CRAWLBASE_NORMAL_API_KEY is set
  """
  @spec available_for_mode?(atom()) :: boolean()
  def available_for_mode?(:javascript), do: has_js_key?()
  def available_for_mode?(:normal), do: has_normal_key?()
  def available_for_mode?(_), do: has_js_key?()

  # Private implementation

  defp do_fetch(url, opts) do
    mode = Keyword.get(opts, :mode, :javascript)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    recv_timeout = Keyword.get(opts, :recv_timeout, @default_recv_timeout)
    page_wait = Keyword.get(opts, :page_wait, @default_page_wait)
    ajax_wait = Keyword.get(opts, :ajax_wait, true)

    request_url = build_request_url(url, mode, page_wait, ajax_wait)

    http_opts = [
      timeout: timeout,
      recv_timeout: recv_timeout
    ]

    start_time = System.monotonic_time(:millisecond)

    case HTTPoison.get(request_url, [], http_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body, headers: headers}} ->
        handle_success_response(response_body, headers, mode, start_time)

      {:ok, %HTTPoison.Response{status_code: 429, headers: resp_headers}} ->
        retry_after = extract_retry_after(resp_headers)

        Logger.warning("Crawlbase adapter rate limited, retry after #{retry_after}s",
          adapter: name(),
          retry_after: retry_after
        )

        {:error, {:rate_limit, retry_after}}

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        handle_error_response(status, response_body, url)

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("Crawlbase adapter timeout connecting",
          adapter: name(),
          url: url
        )

        {:error, {:timeout, :connect}}

      {:error, %HTTPoison.Error{reason: {:recv_timeout, _}}} ->
        Logger.warning("Crawlbase adapter receive timeout",
          adapter: name(),
          url: url
        )

        {:error, {:timeout, :recv}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("Crawlbase adapter network error: #{inspect(reason)}",
          adapter: name(),
          url: url,
          reason: reason
        )

        {:error, {:network_error, reason}}
    end
  end

  defp build_request_url(url, mode, page_wait, ajax_wait) do
    token = get_token_for_mode(mode)
    encoded_url = URI.encode(url)

    query_params = [
      {"token", token},
      {"url", encoded_url},
      {"format", "json"}
    ]

    # Add JavaScript-specific parameters
    query_params =
      if mode == :javascript do
        query_params
        |> Kernel.++([{"page_wait", to_string(page_wait)}])
        |> Kernel.++(if ajax_wait, do: [{"ajax_wait", "true"}], else: [])
      else
        query_params
      end

    query_string =
      query_params
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("&")

    "#{@crawlbase_api_url}?#{query_string}"
  end

  defp handle_success_response(response_body, _headers, mode, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time

    case Jason.decode(response_body) do
      {:ok, %{"body" => body, "original_status" => original_status}} ->
        # Crawlbase returns the page content in the "body" field
        metadata = %{
          status_code: original_status,
          adapter: name(),
          duration_ms: duration,
          mode: mode,
          headers: []
        }

        {:ok, body, metadata}

      {:ok, %{"body" => body}} ->
        # Sometimes original_status is not included
        metadata = %{
          status_code: 200,
          adapter: name(),
          duration_ms: duration,
          mode: mode,
          headers: []
        }

        {:ok, body, metadata}

      {:ok, %{"pc_status" => pc_status, "url" => _original_url} = response}
      when pc_status >= 200 and pc_status < 300 ->
        # Alternative response format - body might be at top level or HTML directly
        body = Map.get(response, "body", response_body)

        metadata = %{
          status_code: pc_status,
          adapter: name(),
          duration_ms: duration,
          mode: mode,
          headers: []
        }

        {:ok, body, metadata}

      {:ok, %{"pc_status" => pc_status} = response} when pc_status >= 400 ->
        # Crawlbase error status
        error_msg = Map.get(response, "error", "HTTP #{pc_status}")

        Logger.warning("Crawlbase adapter returned error status",
          adapter: name(),
          pc_status: pc_status,
          error: error_msg
        )

        {:error, {:crawlbase_error, pc_status, error_msg}}

      {:ok, response} ->
        # Unexpected response format - try to extract body anyway
        Logger.warning("Crawlbase adapter received unexpected response format",
          adapter: name(),
          keys: Map.keys(response),
          mode: mode
        )

        # Try to use the response as-is if it looks like HTML
        body = Map.get(response, "body", response_body)

        if is_binary(body) and (String.contains?(body, "<") or String.length(body) > 100) do
          metadata = %{
            status_code: 200,
            adapter: name(),
            duration_ms: duration,
            mode: mode,
            headers: []
          }

          {:ok, body, metadata}
        else
          {:error, {:crawlbase_error, 200, "Unexpected response format: #{inspect(Map.keys(response))}"}}
        end

      {:error, decode_error} ->
        # Response might be raw HTML (non-JSON format)
        if String.contains?(response_body, "<!") or String.contains?(response_body, "<html") do
          metadata = %{
            status_code: 200,
            adapter: name(),
            duration_ms: duration,
            mode: mode,
            headers: []
          }

          {:ok, response_body, metadata}
        else
          Logger.error("Crawlbase adapter failed to decode JSON response: #{inspect(decode_error)}",
            adapter: name()
          )

          {:error, {:crawlbase_error, 200, "JSON decode error"}}
        end
    end
  end

  defp handle_error_response(status, response_body, url) do
    message =
      case Jason.decode(response_body) do
        {:ok, %{"error" => error}} -> error
        {:ok, %{"message" => msg}} -> msg
        {:ok, %{"pc_status" => pc_status}} -> "PC Status #{pc_status}"
        _ -> "HTTP #{status}"
      end

    Logger.warning("Crawlbase adapter error (#{status}): #{message}",
      adapter: name(),
      url: url,
      status: status
    )

    {:error, {:crawlbase_error, status, message}}
  end

  defp extract_retry_after(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "retry-after" end)
    |> case do
      {_, value} ->
        case Integer.parse(value) do
          {seconds, _} -> seconds
          :error -> 60
        end

      nil ->
        60
    end
  end

  defp get_token_for_mode(:javascript), do: get_js_api_key()
  defp get_token_for_mode(:normal), do: get_normal_api_key()
  defp get_token_for_mode(_), do: get_js_api_key()

  defp has_normal_key? do
    key = get_normal_api_key()
    is_binary(key) and key != ""
  end

  defp has_js_key? do
    key = get_js_api_key()
    is_binary(key) and key != ""
  end

  defp get_normal_api_key do
    Application.get_env(:eventasaurus, :crawlbase_normal_api_key) ||
      System.get_env("CRAWLBASE_NORMAL_API_KEY") ||
      ""
  end

  defp get_js_api_key do
    Application.get_env(:eventasaurus, :crawlbase_js_api_key) ||
      System.get_env("CRAWLBASE_JS_API_KEY") ||
      ""
  end
end
