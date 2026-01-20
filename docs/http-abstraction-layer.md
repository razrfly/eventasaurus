# HTTP Abstraction Layer

A modular HTTP client system with automatic blocking detection and fallback support.

## Overview

The HTTP abstraction layer provides a unified interface for making HTTP requests across all scrapers. It handles:

- **Multiple adapters**: Direct HTTP, Zyte proxy, Crawlbase proxy, and extensible for future adapters
- **Automatic fallback**: If one adapter is blocked, automatically try the next
- **Blocking detection**: Cloudflare, CAPTCHA, rate limits, and access denied detection
- **Per-source configuration**: Configure different strategies for different scrapers
- **Telemetry integration**: Full request lifecycle monitoring

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Http.Client                             │
│  (Unified entry point with strategy selection and fallback)     │
└────────────────────────────┬────────────────────────────────────┘
                             │
          ┌──────────────────┴──────────────────┐
          │                                     │
          ▼                                     ▼
┌─────────────────────┐              ┌─────────────────────┐
│   Http.Config       │              │ Http.BlockingDetector│
│ (Per-source config) │              │ (Cloudflare/CAPTCHA) │
└─────────┬───────────┘              └─────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                            Adapter Chain                                   │
│  ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌───────────────┐   │
│  │  Direct   │ →  │   Zyte    │ →  │ Crawlbase │ →  │ Future Adapters│   │
│  │ (HTTPoison)│    │ (Proxy)   │    │  (Proxy)  │    │                │   │
│  └───────────┘    └───────────┘    └───────────┘    └───────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Basic Usage

```elixir
alias EventasaurusDiscovery.Http.Client

# Simple fetch (uses default adapter chain)
{:ok, body, metadata} = Client.fetch("https://example.com")

# With options
{:ok, body, metadata} = Client.fetch("https://example.com",
  timeout: 10_000,
  headers: [{"Authorization", "Bearer token"}]
)
```

### Source-Specific Configuration

```elixir
# Uses pre-configured strategy for the source
{:ok, body, metadata} = Client.fetch(url, source: :bandsintown)

# Force specific strategy
{:ok, body, metadata} = Client.fetch(url, source: :bandsintown, strategy: :proxy)
```

## Configuration

### Per-Source Strategies

Configure strategies in `config/runtime.exs`:

```elixir
config :eventasaurus_discovery, :http_strategies, %{
  # Default: try direct first, fallback to Zyte on blocking
  default: [:direct, :zyte],

  # Always use Crawlbase (known Cloudflare blocking, cheaper than Zyte)
  bandsintown: [:crawlbase],

  # Direct only (API works without proxy)
  cinema_city: [:direct],

  # Try direct, fallback on failure
  karnet: [:direct, :zyte],

  # More sources...
  kino_krakow: [:direct, :zyte],
  sortiraparis: [:direct, :zyte],
  waw4free: [:direct, :zyte],
  week_pl: [:direct, :zyte]
}
```

**Available adapters:**
- `:direct` - Plain HTTPoison (fast, no cost, may be blocked)
- `:zyte` - Zyte browser rendering proxy (bypasses blocking, has cost)
- `:crawlbase` - Crawlbase API proxy (alternative to Zyte, has cost)

### API Keys

**Zyte** - Set the API key in your environment:

```bash
export ZYTE_API_KEY="your-api-key-here"
```

**Crawlbase** - Two API keys available for different rendering modes:

```bash
# For static HTML requests (1 credit per request)
export CRAWLBASE_API_KEY="your-normal-token-here"

# For JavaScript-rendered requests (2 credits per request)
export CRAWLBASE_JS_API_KEY="your-js-token-here"
```

The Crawlbase adapter requires at least one key. Use the JS token for sites that require
JavaScript rendering (e.g., Cloudflare-protected sites like Bandsintown).

## Strategies

| Strategy | Description | Use Case |
|----------|-------------|----------|
| `:direct` | Direct HTTP only | APIs without blocking |
| `:proxy` | Proxy adapters only | Known blocked sites |
| `:fallback` | Direct first, then proxies | Unknown blocking status |
| `:auto` | Use per-source config | Default behavior |

## Adapters

### Direct Adapter

Plain HTTPoison requests with standard headers.

```elixir
# Uses Direct adapter
{:ok, body, metadata} = Client.fetch(url, strategy: :direct)

# metadata.adapter == "direct"
```

**Features**:
- Always available
- No external costs
- Fast for unblocked sites

### Zyte Adapter

Browser rendering proxy that bypasses Cloudflare and other protections.

```elixir
# Uses Zyte with browser rendering (default mode)
{:ok, body, metadata} = Client.fetch(url,
  source: :bandsintown,
  mode: :browser_html
)

# Uses Zyte with simple HTTP (faster for JSON APIs)
{:ok, body, metadata} = Client.fetch(url,
  source: :bandsintown,
  mode: :http_response_body
)
```

**Modes**:
- `:browser_html` - Full browser rendering with JavaScript execution (default)
- `:http_response_body` - Simple HTTP request through Zyte proxy

**Features**:
- Bypasses Cloudflare challenges
- Full JavaScript execution
- Automatic browser fingerprinting
- Per-request cost (check Zyte pricing)

### Crawlbase Adapter

Crawlbase API proxy for web scraping with anti-bot bypass. A cost-effective alternative to Zyte.

```elixir
# Uses Crawlbase with JavaScript rendering (default mode)
{:ok, body, metadata} = Client.fetch(url,
  source: :bandsintown,
  mode: :javascript
)

# Uses Crawlbase with static HTML (faster, cheaper)
{:ok, body, metadata} = Client.fetch(url,
  source: :some_source,
  mode: :normal
)

# With page wait for dynamic content
{:ok, body, metadata} = Client.fetch(url,
  source: :bandsintown,
  mode: :javascript,
  page_wait: 3000,
  ajax_wait: true
)
```

**Modes**:
- `:javascript` - Browser rendering with JavaScript execution (default, 2 credits/request)
- `:normal` - Static HTML without JavaScript (1 credit/request)

**Options**:
- `page_wait` - Milliseconds to wait after page load (default: 2000)
- `ajax_wait` - Wait for AJAX requests to complete (default: true)
- `timeout` - Connection timeout in ms (default: 60000)
- `recv_timeout` - Receive timeout in ms (default: 60000)

**Features**:
- Bypasses Cloudflare challenges
- Automatic CAPTCHA solving (included in API)
- JavaScript execution with page wait
- Lower cost than Zyte for most use cases
- Per-request pricing (check Crawlbase pricing)

**Error Handling**:
```elixir
case Crawlbase.fetch(url, mode: :javascript) do
  {:ok, body, metadata} ->
    # metadata.mode == :javascript
    process_body(body)

  {:error, :not_configured} ->
    # CRAWLBASE_JS_API_KEY not set
    Logger.error("Crawlbase JS token not configured")

  {:error, {:crawlbase_error, status, message}} ->
    # Crawlbase API error
    Logger.error("Crawlbase error (#{status}): #{message}")

  {:error, {:rate_limit, retry_after}} ->
    # Rate limited, retry after N seconds
    Process.sleep(retry_after * 1000)
    retry_request()

  {:error, {:timeout, :connect}} ->
    # Connection timeout
    {:error, :timeout}

  {:error, {:network_error, reason}} ->
    # Network failure
    {:error, reason}
end
```

## Blocking Detection

The `BlockingDetector` module identifies various blocking patterns:

| Type | Detection Method |
|------|------------------|
| Cloudflare | `cf-ray` header, challenge page patterns, 403/503 status |
| Rate Limit | 429 status, `Retry-After` header |
| CAPTCHA | reCAPTCHA/hCaptcha scripts and patterns |
| Access Denied | Generic 403 without Cloudflare indicators |

### Using BlockingDetector Directly

```elixir
alias EventasaurusDiscovery.Http.BlockingDetector

# Check if response is blocked
case BlockingDetector.detect(status_code, headers, body) do
  :ok ->
    # Not blocked, proceed with body
    {:ok, body}

  {:blocked, :cloudflare} ->
    # Cloudflare challenge detected
    {:error, :cloudflare_blocked}

  {:blocked, :captcha} ->
    # CAPTCHA required
    {:error, :captcha_required}

  {:blocked, :rate_limit, retry_after} ->
    # Rate limited, wait and retry
    Process.sleep(retry_after * 1000)
    retry_request()
end

# Get detailed blocking info
details = BlockingDetector.details(status_code, headers, body)
# %{
#   blocked: true,
#   type: :cloudflare,
#   status_code: 403,
#   indicators: [:status_403, :cf_headers, :cf_challenge_page],
#   retry_after: nil
# }
```

## Response Format

### Success

```elixir
{:ok, body, metadata}

# metadata structure:
%{
  status_code: 200,
  headers: [{"Content-Type", "text/html"}, ...],
  adapter: "direct" | "zyte" | "crawlbase",
  duration_ms: 150,
  attempts: 1,
  blocked_by: []  # List of adapters that were blocked
}
```

### Fallback Success

When the first adapter is blocked but fallback succeeds:

```elixir
{:ok, body, metadata}

# metadata shows fallback occurred:
%{
  adapter: "zyte",      # Adapter that succeeded
  attempts: 2,          # Number of adapters tried
  blocked_by: ["direct"] # Adapters that were blocked
}
```

### Errors

```elixir
# All adapters failed
{:error, {:all_adapters_failed, blocked_by}}
# blocked_by is a list of %{adapter: "...", blocking_type: ..., status_code: ...}

# HTTP error (non-blocking)
{:error, {:http_error, 404, body, metadata}}
{:error, {:http_error, 500, body, metadata}}

# Network errors
{:error, {:timeout, :connect}}
{:error, {:timeout, :recv}}
{:error, {:network_error, reason}}

# Adapter not configured
{:error, :not_configured}
```

## Telemetry Events

The HTTP client emits telemetry events for monitoring:

### Events

| Event | When | Measurements | Metadata |
|-------|------|--------------|----------|
| `[:eventasaurus, :http, :request, :start]` | Request begins | `system_time` | url, source, strategy, adapter_chain |
| `[:eventasaurus, :http, :request, :stop]` | Request succeeds | `duration` | url, adapter, status_code, attempts, blocked_by |
| `[:eventasaurus, :http, :request, :exception]` | Request fails | `duration` | url, source, error |
| `[:eventasaurus, :http, :blocked]` | Adapter blocked | `system_time` | url, adapter, blocking_type, status_code |

### Listening to Events

```elixir
:telemetry.attach(
  "my-handler",
  [:eventasaurus, :http, :request, :stop],
  fn _event, measurements, metadata, _config ->
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("HTTP request to #{metadata.url} completed in #{duration_ms}ms via #{metadata.adapter}")
  end,
  nil
)
```

## Adding a New Adapter

1. Create the adapter module implementing the `Adapter` behaviour:

```elixir
defmodule EventasaurusDiscovery.Http.Adapters.MyAdapter do
  @behaviour EventasaurusDiscovery.Http.Adapter

  @impl true
  def name, do: "my-adapter"

  @impl true
  def available? do
    # Check if adapter is configured/available
    api_key = System.get_env("MY_ADAPTER_API_KEY")
    api_key != nil and api_key != ""
  end

  @impl true
  def fetch(url, opts \\ []) do
    if not available?() do
      {:error, :not_configured}
    else
      # Implementation
      start_time = System.monotonic_time(:millisecond)

      case make_request(url, opts) do
        {:ok, body, status, headers} ->
          duration_ms = System.monotonic_time(:millisecond) - start_time
          metadata = %{
            status_code: status,
            headers: headers,
            adapter: name(),
            duration_ms: duration_ms
          }
          {:ok, body, metadata}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
```

2. Register in `Http.Config`:

```elixir
# lib/eventasaurus_discovery/http/config.ex
def all_adapters do
  [Direct, Zyte, MyAdapter]
end

def adapter_name_to_module(name) do
  %{
    :direct => Direct,
    :zyte => Zyte,
    :my_adapter => MyAdapter
  }[name]
end
```

3. Add to source strategies:

```elixir
config :eventasaurus_discovery, :http_strategies, %{
  some_source: [:direct, :my_adapter, :zyte]
}
```

## Migrating Existing Scrapers

To migrate a scraper to use the HTTP abstraction layer:

### Before

```elixir
defmodule MySource.Client do
  def fetch_page(url) do
    case HTTPoison.get(url, headers(), timeout: 30_000) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### After

```elixir
defmodule MySource.Client do
  alias EventasaurusDiscovery.Http.Client, as: HttpClient

  def fetch_page(url) do
    case HttpClient.fetch(url, source: :my_source, timeout: 30_000) do
      {:ok, body, _metadata} ->
        {:ok, body}
      {:error, {:http_error, status, _body, _meta}} ->
        {:error, {:http_error, status}}
      {:error, {:all_adapters_failed, _blocked_by}} ->
        {:error, :all_adapters_blocked}
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### Key Changes

1. Replace `HTTPoison.get/3` with `HttpClient.fetch/2`
2. Add `source: :my_source` option for strategy lookup
3. Update error handling for new error types
4. Configure strategy in `runtime.exs`

## Best Practices

### Choose the Right Mode

```elixir
# For HTML pages that need JavaScript rendering
HttpClient.fetch(url, source: :my_source, mode: :browser_html)

# For JSON APIs (faster, cheaper)
HttpClient.fetch(url, source: :my_source, mode: :http_response_body)
```

### Handle All Error Cases

```elixir
case HttpClient.fetch(url, source: :my_source) do
  {:ok, body, metadata} ->
    Logger.info("Success via #{metadata.adapter}")
    process_body(body)

  {:error, {:all_adapters_failed, blocked_by}} ->
    Logger.error("All adapters blocked: #{inspect(blocked_by)}")
    {:error, :blocked}

  {:error, {:http_error, status, _body, _meta}} when status in 400..499 ->
    Logger.warning("Client error: #{status}")
    {:error, {:client_error, status}}

  {:error, {:http_error, status, _body, _meta}} when status >= 500 ->
    Logger.error("Server error: #{status}")
    {:error, {:server_error, status}}

  {:error, {:timeout, _}} ->
    Logger.warning("Request timed out")
    {:error, :timeout}

  {:error, reason} ->
    Logger.error("Unexpected error: #{inspect(reason)}")
    {:error, reason}
end
```

### Monitor Blocking Patterns

Use telemetry to track which sites are blocking and which adapters succeed:

```elixir
# Track blocked adapters
:telemetry.attach(
  "blocking-monitor",
  [:eventasaurus, :http, :blocked],
  fn _event, _measurements, metadata, _config ->
    Metrics.increment(
      "http.blocked",
      tags: [source: metadata.source, adapter: metadata.adapter, type: metadata.blocking_type]
    )
  end,
  nil
)
```

## Troubleshooting

### "All adapters failed"

1. Check if proxy API keys are configured (Zyte or Crawlbase)
2. Verify the site isn't rate limiting you
3. Check proxy dashboard for usage/errors (Zyte or Crawlbase)
4. Try increasing timeout
5. Consider switching proxy providers if one is blocked

### "Not configured" error

The adapter requires configuration that isn't set:

```bash
# Check if Zyte API key is set
echo $ZYTE_API_KEY

# Check if Crawlbase API keys are set
echo $CRAWLBASE_API_KEY
echo $CRAWLBASE_JS_API_KEY
```

### Crawlbase-specific errors

**`{:error, {:crawlbase_error, status, message}}`**

1. Check Crawlbase dashboard for account status and credits
2. Verify the correct token is being used (Normal vs JS)
3. Status 520-530 often indicates the target site is blocking Crawlbase

**Mode-specific "not configured"**

Crawlbase requires different tokens for different modes:
- `:javascript` mode requires `CRAWLBASE_JS_API_KEY`
- `:normal` mode requires `CRAWLBASE_API_KEY`

```elixir
# Check which modes are available
Crawlbase.available_for_mode?(:javascript)  # => true/false
Crawlbase.available_for_mode?(:normal)      # => true/false
```

### Slow requests

1. Use `:http_response_body` mode for JSON APIs
2. Adjust timeouts appropriately
3. Check if direct requests work (might not need proxy)

### Unexpected blocking

1. Check `BlockingDetector.details/3` for detailed info
2. Verify blocking detection patterns match the site
3. May need to add new blocking patterns

## Files

| File | Purpose |
|------|---------|
| `lib/eventasaurus_discovery/http/adapter.ex` | Adapter behaviour definition |
| `lib/eventasaurus_discovery/http/adapters/direct.ex` | Direct HTTP adapter |
| `lib/eventasaurus_discovery/http/adapters/zyte.ex` | Zyte proxy adapter |
| `lib/eventasaurus_discovery/http/adapters/crawlbase.ex` | Crawlbase API proxy adapter |
| `lib/eventasaurus_discovery/http/blocking_detector.ex` | Blocking detection logic |
| `lib/eventasaurus_discovery/http/config.ex` | Per-source configuration |
| `lib/eventasaurus_discovery/http/client.ex` | Main entry point |
| `lib/eventasaurus_discovery/http/telemetry.ex` | Telemetry event handlers |

## Tests

```bash
# Run all HTTP tests
mix test test/eventasaurus_discovery/http/

# Run specific test file
mix test test/eventasaurus_discovery/http/client_test.exs

# Run with external tests (requires network)
mix test --include external test/eventasaurus_discovery/http/
```
