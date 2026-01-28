defmodule EventasaurusDiscovery.Http.Adapters.Zyte do
  @moduledoc """
  Zyte API adapter for browser-rendered HTTP requests.

  This adapter uses the Zyte API to fetch web pages with full JavaScript
  rendering, making it effective for bypassing Cloudflare and other
  anti-bot protections.

  ## Features

  - Browser-rendered HTML via `browserHtml` mode
  - Simple HTTP responses via `httpResponseBody` mode
  - Automatic JavaScript execution
  - Configurable viewport for responsive sites
  - Zyte-specific error handling

  ## Configuration

  Requires `ZYTE_API_KEY` environment variable to be set.

  ```elixir
  # config/runtime.exs
  config :eventasaurus, :zyte_api_key,
    System.get_env("ZYTE_API_KEY") || ""
  ```

  ## Usage

      alias EventasaurusDiscovery.Http.Adapters.Zyte

      # Check if available (API key configured)
      if Zyte.available?() do
        # Browser-rendered HTML (default)
        {:ok, html, metadata} = Zyte.fetch("https://example.com")

        # Simple HTTP response (faster, cheaper)
        {:ok, body, metadata} = Zyte.fetch("https://api.example.com",
          mode: :http_response_body
        )
      end

  ## Modes

  - `:browser_html` (default) - Full browser rendering with JavaScript
  - `:http_response_body` - Simple HTTP request without browser rendering

  ## Error Handling

  Returns normalized errors:
  - `{:error, {:zyte_error, status, message}}` - Zyte API error
  - `{:error, {:rate_limit, retry_after}}` - Rate limited by Zyte
  - `{:error, {:timeout, type}}` - Connection or receive timeout
  - `{:error, {:network_error, reason}}` - Network failure
  - `{:error, :not_configured}` - API key not set

  ## Pricing Considerations

  - `browserHtml` mode costs more but bypasses anti-bot protections
  - `httpResponseBody` mode is cheaper for simple API requests
  - Consider using fallback chains (direct → zyte) to minimize costs
  """

  @behaviour EventasaurusDiscovery.Http.Adapter

  require Logger

  alias EventasaurusDiscovery.Costs.{ExternalServiceCost, Pricing}

  @zyte_api_url "https://api.zyte.com/v1/extract"
  @default_timeout 60_000
  @default_recv_timeout 60_000
  @default_viewport %{width: 1920, height: 1080}

  @impl true
  def fetch(url, opts \\ []) do
    if available?() do
      do_fetch(url, opts)
    else
      {:error, :not_configured}
    end
  end

  @impl true
  def name, do: "zyte"

  @impl true
  def available? do
    api_key = get_api_key()
    is_binary(api_key) and api_key != ""
  end

  # Private implementation

  defp do_fetch(url, opts) do
    mode = Keyword.get(opts, :mode, :browser_html)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    recv_timeout = Keyword.get(opts, :recv_timeout, @default_recv_timeout)
    viewport = Keyword.get(opts, :viewport, @default_viewport)

    request_body = build_request_body(url, mode, viewport)
    headers = build_headers()

    http_opts = [
      timeout: timeout,
      recv_timeout: recv_timeout
    ]

    start_time = System.monotonic_time(:millisecond)

    case HTTPoison.post(@zyte_api_url, request_body, headers, http_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        handle_success_response(response_body, mode, start_time)

      {:ok, %HTTPoison.Response{status_code: 429, headers: resp_headers}} ->
        retry_after = extract_retry_after(resp_headers)

        Logger.warning("Zyte adapter rate limited, retry after #{retry_after}s",
          adapter: name(),
          retry_after: retry_after
        )

        {:error, {:rate_limit, retry_after}}

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        handle_error_response(status, response_body, url)

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("Zyte adapter timeout connecting",
          adapter: name(),
          url: url
        )

        {:error, {:timeout, :connect}}

      {:error, %HTTPoison.Error{reason: {:recv_timeout, _}}} ->
        Logger.warning("Zyte adapter receive timeout",
          adapter: name(),
          url: url
        )

        {:error, {:timeout, :recv}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("Zyte adapter network error: #{inspect(reason)}",
          adapter: name(),
          url: url,
          reason: reason
        )

        {:error, {:network_error, reason}}
    end
  end

  defp build_request_body(url, mode, viewport) do
    base = %{url: url}

    body =
      case mode do
        :browser_html ->
          base
          |> Map.put(:browserHtml, true)
          |> Map.put(:javascript, true)
          |> Map.put(:viewport, viewport)

        :http_response_body ->
          Map.put(base, :httpResponseBody, true)

        _ ->
          # Default to browser_html for unknown modes
          base
          |> Map.put(:browserHtml, true)
          |> Map.put(:javascript, true)
          |> Map.put(:viewport, viewport)
      end

    Jason.encode!(body)
  end

  defp build_headers do
    api_key = get_api_key()
    auth = Base.encode64("#{api_key}:")

    [
      {"Authorization", "Basic #{auth}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  defp handle_success_response(response_body, mode, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time

    case Jason.decode(response_body) do
      {:ok, %{"browserHtml" => html}} ->
        metadata = %{
          status_code: 200,
          adapter: name(),
          duration_ms: duration,
          mode: :browser_html,
          headers: []
        }

        # Record cost asynchronously
        record_cost(:browser_html, duration)

        {:ok, html, metadata}

      {:ok, %{"httpResponseBody" => body_base64}} ->
        # httpResponseBody returns base64-encoded content
        case Base.decode64(body_base64) do
          {:ok, decoded_body} ->
            metadata = %{
              status_code: 200,
              adapter: name(),
              duration_ms: duration,
              mode: :http_response_body,
              headers: []
            }

            # Record cost asynchronously
            record_cost(:http_response_body, duration)

            {:ok, decoded_body, metadata}

          :error ->
            Logger.error("Zyte adapter failed to decode base64 response",
              adapter: name()
            )

            {:error, {:zyte_error, 200, "Failed to decode base64 response"}}
        end

      {:ok, response} ->
        # Unexpected response format
        Logger.warning("Zyte adapter received unexpected response format",
          adapter: name(),
          keys: Map.keys(response),
          mode: mode
        )

        # Try to extract any HTML-like content
        cond do
          Map.has_key?(response, "browserHtml") ->
            html = Map.get(response, "browserHtml")

            metadata = %{
              status_code: 200,
              adapter: name(),
              duration_ms: duration,
              mode: :browser_html,
              headers: []
            }

            # Record cost asynchronously
            record_cost(:browser_html, duration)

            {:ok, html, metadata}

          Map.has_key?(response, "httpResponseBody") ->
            body = Map.get(response, "httpResponseBody")

            case Base.decode64(body) do
              {:ok, decoded} ->
                metadata = %{
                  status_code: 200,
                  adapter: name(),
                  duration_ms: duration,
                  mode: :http_response_body,
                  headers: []
                }

                # Record cost asynchronously
                record_cost(:http_response_body, duration)

                {:ok, decoded, metadata}

              :error ->
                {:error, {:zyte_error, 200, "Unexpected response format"}}
            end

          true ->
            {:error,
             {:zyte_error, 200, "Unexpected response format: #{inspect(Map.keys(response))}"}}
        end

      {:error, decode_error} ->
        Logger.error("Zyte adapter failed to decode JSON response: #{inspect(decode_error)}",
          adapter: name()
        )

        {:error, {:zyte_error, 200, "JSON decode error"}}
    end
  end

  defp handle_error_response(status, response_body, url) do
    message =
      case Jason.decode(response_body) do
        {:ok, %{"detail" => detail}} -> detail
        {:ok, %{"message" => msg}} -> msg
        {:ok, %{"error" => error}} -> error
        _ -> "HTTP #{status}"
      end

    Logger.warning("Zyte adapter error (#{status}): #{message}",
      adapter: name(),
      url: url,
      status: status
    )

    {:error, {:zyte_error, status, message}}
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

  defp get_api_key do
    # Try application config first, then environment variable
    Application.get_env(:eventasaurus, :zyte_api_key) ||
      System.get_env("ZYTE_API_KEY") ||
      ""
  end

  # Cost tracking

  defp record_cost(mode, duration_ms) do
    operation = Atom.to_string(mode)
    cost = Pricing.zyte_cost(mode)

    ExternalServiceCost.record_async(%{
      service_type: "scraping",
      provider: "zyte",
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
