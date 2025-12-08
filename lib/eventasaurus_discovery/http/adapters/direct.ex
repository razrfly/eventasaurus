defmodule EventasaurusDiscovery.Http.Adapters.Direct do
  @moduledoc """
  Direct HTTP adapter using HTTPoison.

  This is the default adapter that makes plain HTTP requests without
  any proxy or browser rendering. It wraps HTTPoison with consistent
  error handling and timeout configuration.

  ## Features

  - Standard HTTP GET requests
  - Configurable timeouts
  - Redirect handling
  - Consistent error normalization
  - Always available (no external dependencies)

  ## Usage

      alias EventasaurusDiscovery.Http.Adapters.Direct

      # Simple fetch
      {:ok, body, metadata} = Direct.fetch("https://example.com")

      # With options
      {:ok, body, metadata} = Direct.fetch("https://api.example.com",
        headers: [{"Authorization", "Bearer token"}],
        timeout: 10_000
      )

  ## Error Handling

  Returns normalized errors:
  - `{:error, {:http_error, status_code, body, metadata}}` - Non-2xx response
  - `{:error, {:timeout, :connect}}` - Connection timeout
  - `{:error, {:timeout, :recv}}` - Receive timeout
  - `{:error, {:network_error, reason}}` - Network failure
  """

  @behaviour EventasaurusDiscovery.Http.Adapter

  require Logger

  @default_timeout 30_000
  @default_recv_timeout 30_000
  @default_max_redirects 5

  @impl true
  def fetch(url, opts \\ []) do
    headers = Keyword.get(opts, :headers, default_headers())
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    recv_timeout = Keyword.get(opts, :recv_timeout, @default_recv_timeout)
    follow_redirects = Keyword.get(opts, :follow_redirects, true)
    max_redirects = Keyword.get(opts, :max_redirects, @default_max_redirects)

    http_opts = [
      timeout: timeout,
      recv_timeout: recv_timeout,
      follow_redirect: follow_redirects,
      max_redirect: max_redirects
    ]

    start_time = System.monotonic_time(:millisecond)

    case HTTPoison.get(url, headers, http_opts) do
      {:ok, %HTTPoison.Response{status_code: status, body: body, headers: resp_headers}}
      when status >= 200 and status < 300 ->
        duration = System.monotonic_time(:millisecond) - start_time

        metadata = %{
          status_code: status,
          headers: resp_headers,
          adapter: name(),
          duration_ms: duration
        }

        {:ok, body, metadata}

      {:ok, %HTTPoison.Response{status_code: status, body: body, headers: resp_headers}} ->
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.debug(
          "Direct adapter received HTTP #{status} for #{url} (#{duration}ms)",
          adapter: name(),
          url: url,
          status: status
        )

        # Return body with metadata so caller can inspect for blocking patterns
        metadata = %{
          status_code: status,
          headers: resp_headers,
          adapter: name(),
          duration_ms: duration
        }

        {:error, {:http_error, status, body, metadata}}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("Direct adapter timeout connecting to #{url}",
          adapter: name(),
          url: url
        )

        {:error, {:timeout, :connect}}

      {:error, %HTTPoison.Error{reason: {:recv_timeout, _}}} ->
        Logger.warning("Direct adapter receive timeout for #{url}",
          adapter: name(),
          url: url
        )

        {:error, {:timeout, :recv}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("Direct adapter network error for #{url}: #{inspect(reason)}",
          adapter: name(),
          url: url,
          reason: reason
        )

        {:error, {:network_error, reason}}
    end
  end

  @impl true
  def name, do: "direct"

  @impl true
  def available?, do: true

  # Private helpers

  defp default_headers do
    [
      {"User-Agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.9"},
      {"Accept-Encoding", "gzip, deflate"},
      {"Connection", "keep-alive"}
    ]
  end
end
