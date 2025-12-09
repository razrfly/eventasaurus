defmodule EventasaurusDiscovery.Http.Client do
  @moduledoc """
  Unified HTTP client with configurable adapter chains and automatic fallback.

  This module provides a single entry point for all HTTP requests in the
  discovery system. It supports:

  - Multiple adapters (Direct, Zyte, future adapters)
  - Per-source configuration
  - Automatic fallback on blocking detection
  - Intelligent blocking detection (Cloudflare, CAPTCHA, rate limits)
  - Request/response logging for debugging
  - Telemetry integration for monitoring

  ## Basic Usage

      alias EventasaurusDiscovery.Http.Client

      # Simple fetch using default adapter (Direct)
      {:ok, body, metadata} = Client.fetch("https://example.com")

      # With options
      {:ok, body, metadata} = Client.fetch("https://api.example.com",
        headers: [{"Authorization", "Bearer token"}],
        timeout: 10_000
      )

  ## Source-Specific Configuration

      # Uses configured strategy for the source
      {:ok, body, metadata} = Client.fetch(url, source: :bandsintown)

      # Force specific strategy
      {:ok, body, metadata} = Client.fetch(url, source: :bandsintown, strategy: :proxy)

  ## Strategies

  - `:direct` - Use direct adapter only (no proxy cost, may be blocked)
  - `:proxy` - Use proxy adapter only (bypasses blocking, has cost)
  - `:fallback` - Try direct first, fallback to proxy on blocking
  - `:auto` - Use per-source configuration from config (default)

  ## Response Format

  Returns:
  - `{:ok, body, metadata}` - Success with body and metadata
  - `{:error, reason}` - Failure with error reason

  Metadata includes:
  - `:status_code` - HTTP status code
  - `:headers` - Response headers
  - `:adapter` - Name of adapter that succeeded
  - `:duration_ms` - Request duration in milliseconds
  - `:attempts` - Number of adapters tried
  - `:blocked_by` - List of adapters that were blocked (if any)

  ## Fallback Behavior

  When using `:fallback` or `:auto` strategy with multiple adapters:

  1. Try the first adapter in the chain
  2. On success (200 OK, no blocking patterns), return response
  3. If blocked (Cloudflare, CAPTCHA, etc.), try the next adapter
  4. If all adapters fail or are blocked, return the last error

  Blocking is detected via:
  - HTTP 403/429/503 status codes
  - Cloudflare headers (cf-ray, cf-mitigated)
  - Challenge page patterns in response body
  - CAPTCHA patterns (reCAPTCHA, hCaptcha)

  ## Configuration

  Per-source strategies are configured in `config/runtime.exs`:

      config :eventasaurus, :http_strategies,
        default: [:direct, :zyte],           # Try direct first, fallback to Zyte
        bandsintown: [:zyte],                # Always use Zyte (known blocking)
        cinema_city: [:direct],              # Direct only (API works fine)
        karnet: [:direct, :zyte]             # Try direct, fallback on failure

  ## Telemetry Events

  This module emits the following telemetry events:

  - `[:eventasaurus, :http, :request, :start]` - Request started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{url: String.t, source: atom, strategy: atom, adapter_chain: [atom]}`

  - `[:eventasaurus, :http, :request, :stop]` - Request completed
    - Measurements: `%{duration: integer}` (native time units)
    - Metadata: `%{url: String.t, source: atom, adapter: String.t, status_code: integer, attempts: integer, blocked_by: [String.t]}`

  - `[:eventasaurus, :http, :request, :exception]` - Request failed with error
    - Measurements: `%{duration: integer}` (native time units)
    - Metadata: `%{url: String.t, source: atom, error: term}`

  - `[:eventasaurus, :http, :blocked]` - Adapter blocked (fallback triggered)
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{url: String.t, adapter: String.t, blocking_type: atom, status_code: integer}`
  """

  alias EventasaurusDiscovery.Http.{BlockingDetector, Config}
  alias EventasaurusDiscovery.Http.Adapters.{Direct, Zyte}

  require Logger

  @type url :: String.t()
  @type fetch_opts :: [
          {:headers, [{String.t(), String.t()}]}
          | {:timeout, non_neg_integer()}
          | {:recv_timeout, non_neg_integer()}
          | {:follow_redirects, boolean()}
          | {:max_redirects, non_neg_integer()}
          | {:source, atom()}
          | {:strategy, :direct | :proxy | :fallback | :auto}
          | {:mode, :browser_html | :http_response_body}
        ]

  @doc """
  Fetches content from the given URL using the configured adapter chain.

  The adapter chain is determined by:
  1. Explicit `:strategy` option (if provided)
  2. Per-source configuration (if `:source` provided)
  3. Default strategy (`:direct` then `:zyte`)

  ## Options

  - `:headers` - List of request headers (default: adapter default)
  - `:timeout` - Connection timeout in milliseconds (default: `30_000`)
  - `:recv_timeout` - Receive timeout in milliseconds (default: `30_000`)
  - `:follow_redirects` - Whether to follow redirects (default: `true`)
  - `:max_redirects` - Maximum number of redirects to follow (default: `5`)
  - `:source` - Source identifier for configuration lookup (optional)
  - `:strategy` - Override strategy (`:direct`, `:proxy`, `:fallback`, `:auto`)
  - `:mode` - Zyte mode: `:browser_html` (default) or `:http_response_body`

  ## Returns

  - `{:ok, body, metadata}` - Success with body and metadata
  - `{:error, reason}` - Failure with error reason

  ## Examples

      # Simple fetch
      {:ok, body, _meta} = Client.fetch("https://example.com")

      # With custom headers
      {:ok, body, _meta} = Client.fetch("https://api.example.com",
        headers: [{"Authorization", "Bearer token"}]
      )

      # Source-specific (uses configured adapter chain)
      {:ok, body, meta} = Client.fetch(url, source: :bandsintown)
      # meta.adapter will show which adapter succeeded

      # Force fallback strategy
      {:ok, body, meta} = Client.fetch(url, strategy: :fallback)
  """
  @spec fetch(url(), fetch_opts()) ::
          {:ok, String.t(), map()} | {:error, term()}
  def fetch(url, opts \\ []) do
    source = Keyword.get(opts, :source, :default)
    strategy = Keyword.get(opts, :strategy, :auto)

    adapter_chain = get_adapter_chain(strategy, source)
    adapter_names = Enum.map(adapter_chain, & &1.name())

    # Emit telemetry start event
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:eventasaurus, :http, :request, :start],
      %{system_time: System.system_time()},
      %{url: truncate_url(url), source: source, strategy: strategy, adapter_chain: adapter_names}
    )

    log_request_start(url, source, strategy, adapter_chain)

    result = execute_with_fallback(url, opts, adapter_chain, [], source)

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, body, metadata} ->
        # Emit telemetry stop event
        :telemetry.execute(
          [:eventasaurus, :http, :request, :stop],
          %{duration: duration},
          %{
            url: truncate_url(url),
            source: source,
            adapter: metadata.adapter,
            status_code: metadata.status_code,
            attempts: Map.get(metadata, :attempts, 1),
            blocked_by: Map.get(metadata, :blocked_by, [])
          }
        )

        log_request_success(url, metadata)
        {:ok, body, metadata}

      {:error, reason} ->
        # Emit telemetry exception event
        :telemetry.execute(
          [:eventasaurus, :http, :request, :exception],
          %{duration: duration},
          %{url: truncate_url(url), source: source, error: reason}
        )

        log_request_failure(url, reason)
        {:error, reason}
    end
  end

  @doc """
  Fetches content and returns only the body, discarding metadata.

  Useful when you don't need response headers or timing information.

  ## Examples

      {:ok, html} = Client.fetch!(url)
      {:ok, html} = Client.fetch!(url, source: :bandsintown)
  """
  @spec fetch!(url(), fetch_opts()) :: {:ok, String.t()} | {:error, term()}
  def fetch!(url, opts \\ []) do
    case fetch(url, opts) do
      {:ok, body, _metadata} -> {:ok, body}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Returns the list of available adapters.

  Only includes adapters that are properly configured and available.

  ## Examples

      iex> Client.available_adapters()
      [EventasaurusDiscovery.Http.Adapters.Direct, EventasaurusDiscovery.Http.Adapters.Zyte]
  """
  @spec available_adapters() :: [module()]
  def available_adapters do
    Config.available_adapters()
  end

  @doc """
  Returns the adapter chain that would be used for a given source and strategy.

  Useful for debugging and understanding what adapters will be tried.

  ## Examples

      iex> Client.get_adapter_chain_for(:bandsintown)
      [EventasaurusDiscovery.Http.Adapters.Zyte]

      iex> Client.get_adapter_chain_for(:default, :fallback)
      [EventasaurusDiscovery.Http.Adapters.Direct, EventasaurusDiscovery.Http.Adapters.Zyte]
  """
  @spec get_adapter_chain_for(atom(), atom()) :: [module()]
  def get_adapter_chain_for(source, strategy \\ :auto) do
    get_adapter_chain(strategy, source)
  end

  # Private functions

  defp get_adapter_chain(:auto, source) do
    Config.get_adapter_chain(source)
  end

  defp get_adapter_chain(strategy, source) do
    Config.get_adapter_chain_for_strategy(strategy, source)
  end

  # Execute request with fallback chain
  defp execute_with_fallback(_url, _opts, [], blocked_by, _source) do
    # All adapters exhausted
    Logger.warning("All adapters exhausted or blocked",
      blocked_by: Enum.map(blocked_by, & &1.adapter)
    )

    {:error, {:all_adapters_failed, blocked_by}}
  end

  defp execute_with_fallback(url, opts, [adapter | rest], blocked_by, source) do
    Logger.debug("Trying adapter: #{adapter.name()}", adapter: adapter.name())

    case adapter.fetch(url, opts) do
      {:ok, body, metadata} ->
        # Check if response is blocked
        status_code = Map.get(metadata, :status_code, 200)
        headers = Map.get(metadata, :headers, [])

        case BlockingDetector.detect(status_code, headers, body) do
          :ok ->
            # Success! Return with enhanced metadata
            enhanced_metadata =
              metadata
              |> Map.put(:attempts, length(blocked_by) + 1)
              |> Map.put(:blocked_by, Enum.map(blocked_by, & &1.adapter))

            {:ok, body, enhanced_metadata}

          {:blocked, blocking_type} ->
            Logger.info(
              "Adapter #{adapter.name()} blocked by #{blocking_type}, trying next adapter",
              adapter: adapter.name(),
              blocking_type: blocking_type,
              url: truncate_url(url)
            )

            # Emit telemetry blocked event
            :telemetry.execute(
              [:eventasaurus, :http, :blocked],
              %{system_time: System.system_time()},
              %{
                url: truncate_url(url),
                source: source,
                adapter: adapter.name(),
                blocking_type: blocking_type,
                status_code: status_code
              }
            )

            block_info = %{
              adapter: adapter.name(),
              blocking_type: blocking_type,
              status_code: status_code
            }

            # Try next adapter
            execute_with_fallback(url, opts, rest, [block_info | blocked_by], source)

          {:blocked, :rate_limit, retry_after} ->
            Logger.info(
              "Adapter #{adapter.name()} rate limited, retry after #{retry_after}s",
              adapter: adapter.name(),
              retry_after: retry_after,
              url: truncate_url(url)
            )

            # Emit telemetry blocked event
            :telemetry.execute(
              [:eventasaurus, :http, :blocked],
              %{system_time: System.system_time()},
              %{
                url: truncate_url(url),
                source: source,
                adapter: adapter.name(),
                blocking_type: :rate_limit,
                status_code: status_code,
                retry_after: retry_after
              }
            )

            block_info = %{
              adapter: adapter.name(),
              blocking_type: :rate_limit,
              retry_after: retry_after,
              status_code: status_code
            }

            # Try next adapter
            execute_with_fallback(url, opts, rest, [block_info | blocked_by], source)
        end

      {:error, :not_configured} ->
        # Adapter not configured, skip to next
        Logger.debug("Adapter #{adapter.name()} not configured, skipping",
          adapter: adapter.name()
        )

        execute_with_fallback(url, opts, rest, blocked_by, source)

      {:error, reason} ->
        # Network or other error - try next adapter if available
        if rest == [] do
          # Last adapter failed, return error
          {:error, reason}
        else
          Logger.debug(
            "Adapter #{adapter.name()} failed: #{inspect(reason)}, trying next adapter",
            adapter: adapter.name(),
            error: inspect(reason)
          )

          error_info = %{
            adapter: adapter.name(),
            error: reason
          }

          execute_with_fallback(url, opts, rest, [error_info | blocked_by], source)
        end
    end
  end

  # Logging helpers

  defp log_request_start(url, source, strategy, adapter_chain) do
    adapter_names = Enum.map(adapter_chain, & &1.name())

    Logger.debug("Http.Client starting request",
      url: truncate_url(url),
      source: source,
      strategy: strategy,
      adapter_chain: adapter_names
    )
  end

  defp log_request_success(url, metadata) do
    Logger.debug("Http.Client request succeeded",
      url: truncate_url(url),
      adapter: metadata.adapter,
      duration_ms: metadata.duration_ms,
      status_code: metadata.status_code,
      attempts: Map.get(metadata, :attempts, 1)
    )
  end

  defp log_request_failure(url, reason) do
    Logger.warning("Http.Client request failed",
      url: truncate_url(url),
      error: inspect(reason)
    )
  end

  defp truncate_url(url) when byte_size(url) > 100 do
    String.slice(url, 0, 100) <> "..."
  end

  defp truncate_url(url), do: url

  # Legacy support - list all adapters
  @doc false
  def all_adapters do
    [Direct, Zyte]
  end
end
