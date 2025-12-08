defmodule EventasaurusDiscovery.Http.Adapter do
  @moduledoc """
  Behaviour definition for HTTP adapters.

  Adapters implement different strategies for fetching HTTP content:
  - Direct: Plain HTTPoison requests (default)
  - Zyte: Browser rendering proxy for Cloudflare-protected sites
  - Future: Playwright, ScrapingBee, Bright Data, etc.

  ## Implementing an Adapter

      defmodule MyApp.Http.Adapters.MyAdapter do
        @behaviour EventasaurusDiscovery.Http.Adapter

        @impl true
        def fetch(url, opts) do
          # Implementation
          {:ok, body}
        end

        @impl true
        def name, do: "my-adapter"

        @impl true
        def available?, do: true
      end

  ## Response Types

  Adapters should return:
  - `{:ok, body}` - Successful response with body content
  - `{:ok, body, metadata}` - Success with additional metadata (headers, status, etc.)
  - `{:error, reason}` - Failure with error reason

  Common error reasons:
  - `{:http_error, status_code}` - HTTP error status
  - `{:blocked, :cloudflare | :captcha | :rate_limit}` - Request was blocked
  - `{:timeout, :connect | :recv}` - Connection or receive timeout
  - `{:network_error, reason}` - Network-level failure
  """

  @type url :: String.t()
  @type body :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type metadata :: %{
          optional(:status_code) => integer(),
          optional(:headers) => headers(),
          optional(:adapter) => String.t(),
          optional(:duration_ms) => non_neg_integer()
        }

  @type fetch_opts :: [
          {:headers, headers()}
          | {:timeout, non_neg_integer()}
          | {:recv_timeout, non_neg_integer()}
          | {:follow_redirects, boolean()}
          | {:max_redirects, non_neg_integer()}
          | {:source, atom()}
        ]

  @type success :: {:ok, body()} | {:ok, body(), metadata()}
  @type error :: {:error, term()}
  @type fetch_result :: success() | error()

  @doc """
  Fetches content from the given URL.

  ## Options

  - `:headers` - List of request headers (default: `[]`)
  - `:timeout` - Connection timeout in milliseconds (default: `30_000`)
  - `:recv_timeout` - Receive timeout in milliseconds (default: `30_000`)
  - `:follow_redirects` - Whether to follow redirects (default: `true`)
  - `:max_redirects` - Maximum number of redirects to follow (default: `5`)
  - `:source` - Source identifier for logging/metrics (optional)

  ## Returns

  - `{:ok, body}` - Success with response body
  - `{:ok, body, metadata}` - Success with body and metadata
  - `{:error, reason}` - Failure with error reason
  """
  @callback fetch(url(), fetch_opts()) :: fetch_result()

  @doc """
  Returns the human-readable name of this adapter.

  Used for logging and metrics tracking.

  ## Examples

      iex> Direct.name()
      "direct"

      iex> Zyte.name()
      "zyte"
  """
  @callback name() :: String.t()

  @doc """
  Returns whether this adapter is available for use.

  Adapters may be unavailable due to:
  - Missing API keys or configuration
  - Service unavailability
  - Feature flags

  The Http.Client uses this to filter out unavailable adapters
  from the fallback chain.

  ## Examples

      # Direct adapter is always available
      iex> Direct.available?()
      true

      # Zyte requires an API key
      iex> Zyte.available?()
      false  # when ZYTE_API_KEY is not set
  """
  @callback available?() :: boolean()

  @doc """
  Optional callback for adapter-specific initialization.

  Called when the adapter is first used. Useful for:
  - Validating configuration
  - Establishing connections
  - Warming caches

  Default implementation does nothing.
  """
  @callback init() :: :ok | {:error, term()}

  @optional_callbacks [init: 0]
end
