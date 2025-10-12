# Build Modular Multi-Provider Geocoding System

**Status**: 🟡 Design Phase
**Priority**: P1 - High (Blocks reliable venue creation)
**Estimated Effort**: 3-4 weeks
**Root Cause**: Current system is tightly coupled to 2 providers with no flexibility

---

## Executive Summary

Our current geocoding system is hard-coded to use OpenStreetMap → Google Places with no ability to:
- Add new providers without code changes
- Configure provider priority at runtime
- Track and manage quota usage across providers
- Implement different fallback strategies
- Enable/disable providers dynamically

**Critical Requirement**: Latitude and longitude are **ABSOLUTE REQUIREMENTS**. A venue without coordinates is useless. The system must try ALL available providers before failing.

---

## Current Problems

### 1. Tightly Coupled Architecture
```elixir
# Current implementation is hard-coded
def geocode_address_with_metadata(address) do
  case try_openstreetmaps_with_retry(address) do
    {:ok, data} -> {:ok, data}
    {:error, _} ->
      # Google fallback DISABLED - now just fails
      {:error, :geocoding_failed, metadata}
  end
end
```

**Problems:**
- Only 2 providers supported
- Fallback logic hard-coded in function
- No way to add providers without modifying core code
- Google Places currently disabled, leaving only OSM
- Single point of failure (OSM rate limiting = 60% job failure)

### 2. No Quota Management
- Can't track usage against provider limits
- No automatic switching when quotas exhausted
- Can't utilize free tiers optimally
- Risk of unexpected costs

### 3. No Runtime Configuration
- Can't enable/disable providers without deployment
- Can't change priority order without code changes
- Can't adjust strategy based on usage patterns
- No A/B testing of different provider combinations

### 4. No Health Monitoring
- Failing providers are tried on every request
- No circuit breaker pattern
- Wastes time on down/rate-limited services
- No automatic recovery detection

---

## Available Geocoding Providers

### Free/Open Source (No API Key Required)

#### 1. OpenStreetMap Nominatim ✅ *Currently Used*
- **Cost**: Free
- **Rate Limit**: 1 request/second (strict)
- **Quality Score**: 7/10
- **Coverage**: Global
- **Pros**: Free, no API key, good coverage
- **Cons**: Strict rate limit, moderate quality, requires User-Agent
- **Best For**: Low-volume or as first-try fallback

#### 2. Photon (OSM-based)
- **Cost**: Free (public instance or self-hosted)
- **Rate Limit**: Flexible (no strict limit on public instance)
- **Quality Score**: 7/10
- **Coverage**: Global
- **Pros**: Fast, OSM data, generous rate limits
- **Cons**: Public instance reliability varies
- **Best For**: High-volume free option

### Freemium (Generous Free Tiers)

#### 3. Mapbox Geocoding API ⭐ *Recommended Primary*
- **Cost**: 100,000 requests/month free, then $0.0050/request
- **Rate Limit**: 600 requests/minute
- **Quality Score**: 9/10
- **Coverage**: Global, excellent quality
- **Pros**: Generous free tier, high quality, fast
- **Cons**: Requires API key, paid after quota
- **Best For**: Primary provider with quality data

#### 4. HERE Geocoding API ⭐ *Recommended Secondary*
- **Cost**: 250,000 requests/month free
- **Rate Limit**: Generous (varies by tier)
- **Quality Score**: 9/10
- **Coverage**: Global, excellent quality
- **Pros**: Very generous free tier, high quality
- **Cons**: Requires API key, complex pricing after quota
- **Best For**: Secondary high-quality option

#### 5. Geoapify Geocoding API
- **Cost**: 3,000 requests/day free (~90,000/month)
- **Rate Limit**: Burst-friendly (based on tier)
- **Quality Score**: 8/10
- **Coverage**: Global
- **Pros**: Good free tier, flexible rate limits
- **Cons**: Smaller quota than Mapbox/HERE
- **Best For**: Tertiary option or specific use cases

#### 6. LocationIQ (OSM-based)
- **Cost**: 5,000 requests/day free (~150,000/month)
- **Rate Limit**: 2 requests/second (free tier)
- **Quality Score**: 7/10
- **Coverage**: Global (OSM data)
- **Pros**: Good free tier, OSM-based
- **Cons**: Lower quality than commercial providers
- **Best For**: High-volume fallback option

### Paid Options (Keep as Last Resort)

#### 7. Google Places API 🚫 *Currently Disabled*
- **Cost**: $0.037 per request (SKU: Place Details)
- **Rate Limit**: 100 requests/second
- **Quality Score**: 10/10
- **Coverage**: Best-in-class
- **Pros**: Highest quality, comprehensive data
- **Cons**: Expensive, no free tier
- **Best For**: Last resort only (high cost)

#### 8. Google Maps Geocoding API
- **Cost**: $0.005 per request
- **Rate Limit**: 100 requests/second
- **Quality Score**: 9/10
- **Coverage**: Excellent
- **Pros**: Cheaper than Places, good quality
- **Cons**: Still paid, no free tier
- **Best For**: Alternative to Places if needed

---

## Recommended Provider Strategy

### Strategy: Hybrid (Quality + Cost Optimization)

**Phase 1: Free High-Quality (Try First)**
1. Mapbox (9/10 quality, 100K/month free) - *Primary*
2. HERE (9/10 quality, 250K/month free) - *Secondary*

**Phase 2: Free Moderate-Quality**
3. Geoapify (8/10 quality, 90K/month free)
4. LocationIQ (7/10 quality, 150K/month free)
5. Photon (7/10 quality, unlimited free)
6. OpenStreetMap Nominatim (7/10 quality, rate-limited)

**Phase 3: Paid (Last Resort)**
7. Google Maps Geocoding ($0.005/request) - *Disabled by default*
8. Google Places ($0.037/request) - *Disabled by default*

**Expected Outcome**: With 6 free providers, we should achieve 98%+ success rate without any paid API calls.

---

## Proposed Architecture

### 1. Provider Behavior (Contract)

```elixir
defmodule EventasaurusDiscovery.Geocoding.Provider do
  @moduledoc """
  Behavior that all geocoding providers must implement.
  """

  @type geocode_result :: %{
    latitude: float(),
    longitude: float(),
    city: String.t(),
    country: String.t()
  }

  @callback name() :: String.t()
  @callback geocode(address :: String.t()) ::
    {:ok, geocode_result()} | {:error, reason :: atom()}
  @callback rate_limit() :: {requests :: integer(), per :: :second | :minute | :hour | :day}
  @callback cost_per_request() :: float()
  @callback quality_score() :: 1..10
  @callback requires_api_key?() :: boolean()
end
```

### 2. Provider Implementations

```elixir
# Example: Mapbox provider
defmodule EventasaurusDiscovery.Geocoding.Providers.Mapbox do
  @behaviour EventasaurusDiscovery.Geocoding.Provider

  def name(), do: "mapbox"

  def geocode(address) do
    api_key = get_api_key()
    url = "https://api.mapbox.com/geocoding/v5/mapbox.places/#{URI.encode(address)}.json"

    case HTTPoison.get(url, [], params: [access_token: api_key]) do
      {:ok, %{status_code: 200, body: body}} ->
        parse_response(body)
      {:ok, %{status_code: 429}} ->
        {:error, :rate_limited}
      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def rate_limit(), do: {600, :minute}
  def cost_per_request(), do: 0.0  # Free tier
  def quality_score(), do: 9
  def requires_api_key?(), do: true

  defp parse_response(body) do
    # Parse Mapbox response format
    # Extract coordinates, city, country
  end

  defp get_api_key() do
    System.get_env("MAPBOX_API_KEY") ||
      raise "MAPBOX_API_KEY not configured"
  end
end
```

### 3. Provider Registry

```elixir
defmodule EventasaurusDiscovery.Geocoding.Registry do
  @moduledoc """
  Manages provider configuration and availability.
  Loads from config/runtime.exs.
  """

  use GenServer

  @type provider_config :: %{
    module: module(),
    enabled: boolean(),
    priority: integer(),
    max_requests_per_month: integer() | nil,
    api_key_configured: boolean(),
    quality_score: 1..10,
    cost_per_request: float()
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list_enabled_providers() do
    GenServer.call(__MODULE__, :list_enabled)
  end

  def get_provider_config(provider_name) do
    GenServer.call(__MODULE__, {:get_config, provider_name})
  end

  def enable_provider(provider_name) do
    GenServer.call(__MODULE__, {:enable, provider_name})
  end

  def disable_provider(provider_name) do
    GenServer.call(__MODULE__, {:disable, provider_name})
  end

  # Load configuration from Application config
  def init(_) do
    config = Application.get_env(:eventasaurus_discovery, :geocoding, [])
    providers = load_provider_configs(config)
    {:ok, %{providers: providers}}
  end
end
```

### 4. Strategy Behavior

```elixir
defmodule EventasaurusDiscovery.Geocoding.Strategy do
  @moduledoc """
  Behavior for provider selection strategies.
  """

  @callback order_providers(providers :: [provider_config()]) :: [provider_config()]
end
```

**Strategy Implementations:**

```elixir
# Quality-First: Sort by quality score
defmodule EventasaurusDiscovery.Geocoding.Strategies.QualityFirst do
  @behaviour EventasaurusDiscovery.Geocoding.Strategy

  def order_providers(providers) do
    Enum.sort_by(providers, & &1.quality_score, :desc)
  end
end

# Cost-First: Sort by cost (free first)
defmodule EventasaurusDiscovery.Geocoding.Strategies.CostFirst do
  @behaviour EventasaurusDiscovery.Geocoding.Strategy

  def order_providers(providers) do
    Enum.sort_by(providers, & &1.cost_per_request, :asc)
  end
end

# Hybrid: Free high-quality → Free moderate → Paid
defmodule EventasaurusDiscovery.Geocoding.Strategies.Hybrid do
  @behaviour EventasaurusDiscovery.Geocoding.Strategy

  def order_providers(providers) do
    providers
    |> Enum.group_by(fn p ->
      cond do
        p.cost_per_request == 0.0 and p.quality_score >= 9 -> :free_high
        p.cost_per_request == 0.0 -> :free_moderate
        true -> :paid
      end
    end)
    |> then(fn grouped ->
      (sort_by_quality(grouped[:free_high] || []) ++
       sort_by_quality(grouped[:free_moderate] || []) ++
       sort_by_cost(grouped[:paid] || []))
    end)
  end

  defp sort_by_quality(providers), do: Enum.sort_by(providers, & &1.quality_score, :desc)
  defp sort_by_cost(providers), do: Enum.sort_by(providers, & &1.cost_per_request, :asc)
end

# Quota-Aware: Consider remaining quota
defmodule EventasaurusDiscovery.Geocoding.Strategies.QuotaAware do
  alias EventasaurusDiscovery.Geocoding.UsageTracker

  def order_providers(providers) do
    providers
    |> Enum.map(fn provider ->
      remaining = UsageTracker.quota_remaining?(provider.module)
      {provider, remaining}
    end)
    |> Enum.sort_by(fn {provider, remaining} ->
      # Sort by: has quota remaining, then quality, then cost
      {!remaining, -provider.quality_score, provider.cost_per_request}
    end)
    |> Enum.map(fn {provider, _} -> provider end)
  end
end
```

### 5. Usage Tracker

```elixir
defmodule EventasaurusDiscovery.Geocoding.UsageTracker do
  @moduledoc """
  Tracks provider usage and quota management.
  Stores in database for persistence across restarts.
  """

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def record_request(provider_name, success?, cost) do
    GenServer.cast(__MODULE__, {:record, provider_name, success?, cost})
  end

  def get_current_usage(provider_name) do
    GenServer.call(__MODULE__, {:get_usage, provider_name})
  end

  def quota_remaining?(provider_name) do
    GenServer.call(__MODULE__, {:quota_remaining, provider_name})
  end

  # Reset expired periods (called by periodic job)
  def reset_expired_periods() do
    GenServer.cast(__MODULE__, :reset_expired)
  end
end
```

**Database Schema:**

```elixir
defmodule EventasaurusApp.Repo.Migrations.CreateGeocodingUsage do
  use Ecto.Migration

  def change do
    create table(:geocoding_usage) do
      add :provider, :string, null: false
      add :period_start, :utc_datetime, null: false
      add :period_end, :utc_datetime, null: false
      add :period_type, :string, null: false  # "daily", "monthly"
      add :request_count, :integer, default: 0
      add :success_count, :integer, default: 0
      add :failure_count, :integer, default: 0
      add :total_cost, :decimal, precision: 10, scale: 4, default: 0.0

      timestamps()
    end

    create index(:geocoding_usage, [:provider, :period_start])
    create unique_index(:geocoding_usage, [:provider, :period_start, :period_type])
  end
end
```

### 6. Circuit Breaker

```elixir
defmodule EventasaurusDiscovery.Geocoding.CircuitBreaker do
  @moduledoc """
  Implements circuit breaker pattern for provider health monitoring.
  Prevents wasting time on consistently failing providers.
  """

  use GenServer

  @failure_threshold 5
  @timeout_ms 60_000  # 1 minute
  @half_open_max_requests 1

  # States: :closed (working), :open (failing), :half_open (testing)

  def call(provider_name, fun) do
    case get_state(provider_name) do
      :closed ->
        # Normal operation
        case fun.() do
          {:ok, _} = result ->
            record_success(provider_name)
            result
          {:error, _} = error ->
            record_failure(provider_name)
            error
        end

      :open ->
        # Provider is failing, skip immediately
        {:error, :circuit_open}

      :half_open ->
        # Testing recovery, allow limited requests
        case fun.() do
          {:ok, _} = result ->
            close_circuit(provider_name)
            result
          {:error, _} = error ->
            open_circuit(provider_name)
            error
        end
    end
  end

  defp get_state(provider_name) do
    GenServer.call(__MODULE__, {:get_state, provider_name})
  end

  defp record_failure(provider_name) do
    GenServer.cast(__MODULE__, {:record_failure, provider_name})
  end

  defp record_success(provider_name) do
    GenServer.cast(__MODULE__, {:record_success, provider_name})
  end
end
```

### 7. Rate Limiters (Per-Provider)

```elixir
# lib/eventasaurus_discovery/geocoding/rate_limiters/mapbox.ex
defmodule EventasaurusDiscovery.Geocoding.RateLimiters.Mapbox do
  use Hammer, backend: :ets

  def check() do
    # 600 requests per minute
    hit("mapbox_geocoding", :timer.minutes(1), 600)
  end
end

# lib/eventasaurus_discovery/geocoding/rate_limiters/open_street_map.ex
defmodule EventasaurusDiscovery.Geocoding.RateLimiters.OpenStreetMap do
  use Hammer, backend: :ets

  def check() do
    # 1 request per second
    hit("osm_geocoding", :timer.seconds(1), 1)
  end
end

# Similar for each provider...
```

### 8. Orchestrator (Main Coordinator)

```elixir
defmodule EventasaurusDiscovery.Geocoding.Orchestrator do
  @moduledoc """
  Main coordinator for geocoding requests.
  Handles provider selection, fallback logic, rate limiting, and circuit breaking.
  """

  alias EventasaurusDiscovery.Geocoding.{
    Registry,
    UsageTracker,
    CircuitBreaker,
    MetadataBuilder
  }

  require Logger

  def geocode(address) do
    strategy = get_strategy()
    providers = Registry.list_enabled_providers()
    ordered_providers = strategy.order_providers(providers)

    geocode_with_fallback(address, ordered_providers, [])
  end

  defp geocode_with_fallback(_address, [], attempts) do
    # All providers failed - return error with full attempt history
    Logger.error("❌ All #{length(attempts)} geocoding providers failed")

    metadata = %{
      providers_attempted: Enum.reverse(attempts),
      total_attempts: length(attempts),
      strategy_used: get_strategy_name(),
      geocoding_failed: true,
      geocoded_at: DateTime.utc_now()
    }

    {:error, :all_providers_failed, metadata}
  end

  defp geocode_with_fallback(address, [provider | rest], attempts) do
    Logger.debug("Trying provider: #{provider.module.name()}")

    # Check rate limit
    rate_limiter = get_rate_limiter(provider.module)

    case rate_limiter.check() do
      {:deny, retry_after_ms} ->
        Logger.info("⏱️ #{provider.module.name()} rate limited, skipping")
        attempt = build_attempt(provider, :rate_limited, nil)
        geocode_with_fallback(address, rest, [attempt | attempts])

      {:allow, _count} ->
        # Check circuit breaker
        result = CircuitBreaker.call(provider.module.name(), fn ->
          provider.module.geocode(address)
        end)

        case result do
          {:ok, %{latitude: lat, longitude: lng} = data} when is_float(lat) and is_float(lng) ->
            # Success!
            Logger.info("✅ Geocoded via #{provider.module.name()}: #{lat}, #{lng}")

            # Record usage
            UsageTracker.record_request(provider.module.name(), true, provider.cost_per_request)

            # Build metadata
            attempt = build_attempt(provider, :success, provider.cost_per_request)
            all_attempts = Enum.reverse([attempt | attempts])

            metadata = %{
              providers_attempted: all_attempts,
              successful_provider: provider.module.name(),
              total_cost: Enum.sum(Enum.map(all_attempts, & &1.cost)),
              total_attempts: length(all_attempts),
              strategy_used: get_strategy_name(),
              geocoded_at: DateTime.utc_now()
            }

            {:ok, Map.put(data, :geocoding_metadata, metadata)}

          {:error, reason} ->
            Logger.warning("⚠️ #{provider.module.name()} failed: #{reason}")

            # Record failure
            UsageTracker.record_request(provider.module.name(), false, 0.0)

            # Try next provider
            attempt = build_attempt(provider, reason, 0.0)
            geocode_with_fallback(address, rest, [attempt | attempts])
        end
    end
  end

  defp build_attempt(provider, result, cost) do
    %{
      name: provider.module.name(),
      attempted_at: DateTime.utc_now(),
      result: result,
      cost: cost || 0.0
    }
  end

  defp get_strategy() do
    strategy_name = Application.get_env(:eventasaurus_discovery, :geocoding)
      |> Keyword.get(:strategy, :hybrid)

    case strategy_name do
      :quality_first -> EventasaurusDiscovery.Geocoding.Strategies.QualityFirst
      :cost_first -> EventasaurusDiscovery.Geocoding.Strategies.CostFirst
      :quota_aware -> EventasaurusDiscovery.Geocoding.Strategies.QuotaAware
      :hybrid -> EventasaurusDiscovery.Geocoding.Strategies.Hybrid
      _ -> EventasaurusDiscovery.Geocoding.Strategies.Hybrid
    end
  end

  defp get_strategy_name() do
    Application.get_env(:eventasaurus_discovery, :geocoding)
      |> Keyword.get(:strategy, :hybrid)
      |> to_string()
  end

  defp get_rate_limiter(provider_module) do
    # Map provider module to rate limiter module
    # e.g., Providers.Mapbox -> RateLimiters.Mapbox
    rate_limiter_name = provider_module
      |> Module.split()
      |> List.replace_at(-2, "RateLimiters")
      |> Module.concat()

    rate_limiter_name
  end
end
```

### 9. Update AddressGeocoder (Migration Layer)

```elixir
defmodule EventasaurusDiscovery.Helpers.AddressGeocoder do
  @moduledoc """
  Forward geocoding: convert addresses to coordinates.

  Now uses modular Orchestrator for multi-provider support.
  Old functions maintained for backward compatibility.
  """

  alias EventasaurusDiscovery.Geocoding.Orchestrator

  @doc """
  Geocode an address using the new multi-provider system.

  Tries all enabled providers in configured order until success.
  Returns error only if ALL providers fail.

  Coordinates are REQUIRED - if no provider can geocode, returns error.
  """
  def geocode_address_with_metadata(address) when is_binary(address) do
    case Orchestrator.geocode(address) do
      {:ok, %{latitude: lat, longitude: lng, city: city, country: country, geocoding_metadata: metadata}} ->
        {:ok, %{
          city: city,
          country: country,
          latitude: lat,
          longitude: lng,
          geocoding_metadata: metadata
        }}

      {:error, :all_providers_failed, metadata} ->
        Logger.error("❌ All geocoding providers failed for: #{address}")
        {:error, :all_providers_failed, metadata}
    end
  end

  def geocode_address_with_metadata(_), do: {:error, :invalid_address, %{}}

  # Old function for backward compatibility
  def geocode_address(address) do
    case geocode_address_with_metadata(address) do
      {:ok, %{city: city, country: country, latitude: lat, longitude: lng}} ->
        {:ok, {city, country, {lat, lng}}}
      {:error, _, _} ->
        {:error, :geocoding_failed}
    end
  end
end
```

---

## Configuration

### Runtime Configuration (config/runtime.exs)

```elixir
config :eventasaurus_discovery, :geocoding,
  # Strategy: :quality_first | :cost_first | :quota_aware | :hybrid
  strategy: :hybrid,

  # Provider configurations
  providers: [
    # Primary: Mapbox (100K/month free, high quality)
    %{
      module: EventasaurusDiscovery.Geocoding.Providers.Mapbox,
      enabled: true,
      priority: 1,
      max_requests_per_month: 100_000,
      rate_limit: {600, :minute},
      cost_per_request: 0.0,
      quality_score: 9,
      api_key: {:system, "MAPBOX_API_KEY"}
    },

    # Secondary: HERE (250K/month free, high quality)
    %{
      module: EventasaurusDiscovery.Geocoding.Providers.Here,
      enabled: true,
      priority: 2,
      max_requests_per_month: 250_000,
      rate_limit: {100, :second},
      cost_per_request: 0.0,
      quality_score: 9,
      api_key: {:system, "HERE_API_KEY"}
    },

    # Tertiary: Geoapify (90K/month free)
    %{
      module: EventasaurusDiscovery.Geocoding.Providers.Geoapify,
      enabled: true,
      priority: 3,
      max_requests_per_month: 90_000,
      rate_limit: {5, :second},
      cost_per_request: 0.0,
      quality_score: 8,
      api_key: {:system, "GEOAPIFY_API_KEY"}
    },

    # Fallback: LocationIQ (150K/month free, OSM-based)
    %{
      module: EventasaurusDiscovery.Geocoding.Providers.LocationIQ,
      enabled: true,
      priority: 4,
      max_requests_per_month: 150_000,
      rate_limit: {2, :second},
      cost_per_request: 0.0,
      quality_score: 7,
      api_key: {:system, "LOCATIONIQ_API_KEY"}
    },

    # Fallback: Photon (unlimited free)
    %{
      module: EventasaurusDiscovery.Geocoding.Providers.Photon,
      enabled: true,
      priority: 5,
      max_requests_per_month: nil,
      rate_limit: {10, :second},
      cost_per_request: 0.0,
      quality_score: 7,
      api_key: nil
    },

    # Fallback: OpenStreetMap Nominatim
    %{
      module: EventasaurusDiscovery.Geocoding.Providers.OpenStreetMap,
      enabled: true,
      priority: 6,
      max_requests_per_month: nil,
      rate_limit: {1, :second},
      cost_per_request: 0.0,
      quality_score: 7,
      api_key: nil
    },

    # Last Resort: Google Maps Geocoding (DISABLED by default)
    %{
      module: EventasaurusDiscovery.Geocoding.Providers.GoogleMaps,
      enabled: false,  # Currently disabled
      priority: 97,
      max_requests_per_month: nil,
      rate_limit: {100, :second},
      cost_per_request: 0.005,
      quality_score: 9,
      api_key: {:system, "GOOGLE_MAPS_API_KEY"}
    },

    # Last Resort: Google Places (DISABLED by default)
    %{
      module: EventasaurusDiscovery.Geocoding.Providers.GooglePlaces,
      enabled: false,  # Currently disabled
      priority: 99,
      max_requests_per_month: nil,
      rate_limit: {100, :second},
      cost_per_request: 0.037,
      quality_score: 10,
      api_key: {:system, "GOOGLE_PLACES_API_KEY"}
    }
  ]
```

---

## Implementation Plan

### Phase 1: Foundation (Week 1)

**Goal**: Build core architecture without breaking existing system

- [ ] Create Provider behavior definition
- [ ] Implement Mapbox provider (primary)
- [ ] Implement OpenStreetMap provider (migrate existing)
- [ ] Build Registry module with config loading
- [ ] Create basic Orchestrator (no strategies yet)
- [ ] Add database migration for usage tracking
- [ ] Set up Hammer rate limiters for Mapbox + OSM
- [ ] Write unit tests for providers

**Deliverable**: Working system with 2 providers (Mapbox + OSM)

### Phase 2: Strategies & Additional Providers (Week 2)

**Goal**: Add fallback strategies and more providers

- [ ] Implement HERE provider
- [ ] Implement Geoapify provider
- [ ] Implement LocationIQ provider
- [ ] Implement Photon provider
- [ ] Create Strategy behavior
- [ ] Implement all strategy modules (Quality, Cost, Quota, Hybrid)
- [ ] Build CircuitBreaker module
- [ ] Build UsageTracker with quota management
- [ ] Add rate limiters for all providers
- [ ] Write strategy unit tests
- [ ] Write integration tests for orchestrator

**Deliverable**: Full multi-provider system with all strategies

### Phase 3: Migration & Enhanced Features (Week 3)

**Goal**: Replace old system and add monitoring

- [ ] Update AddressGeocoder to use Orchestrator
- [ ] Migrate Google providers (keep disabled)
- [ ] Enhanced metadata tracking (multi-provider attempts)
- [ ] Add Oban periodic job for usage reset
- [ ] Build admin dashboard for provider management
- [ ] Add quota warning alerts (80%, 90%, 100%)
- [ ] Comprehensive integration tests
- [ ] Load testing with multiple providers
- [ ] Documentation for adding new providers

**Deliverable**: Production-ready system with monitoring

### Phase 4: Production Deployment & Optimization (Week 4)

**Goal**: Deploy and optimize based on real usage

- [ ] Deploy to staging environment
- [ ] Run test scraper with real data
- [ ] Monitor success rates per provider
- [ ] Optimize provider order based on data
- [ ] Monitor costs and quota usage
- [ ] Adjust strategy if needed
- [ ] Deploy to production
- [ ] 7-day monitoring period
- [ ] Document actual success rates and costs
- [ ] Final optimization based on production data

**Deliverable**: Optimized production system with 95%+ success rate

---

## Success Criteria

### Functional Requirements
✅ Support 6+ geocoding providers with easy addition of new providers
✅ Configurable fallback strategies (Quality, Cost, Quota, Hybrid)
✅ Runtime enable/disable of providers without deployment
✅ Quota tracking and automatic provider rotation
✅ Rate limiting per provider (coordinated, not blocking)
✅ Circuit breaker for failing providers
✅ Coordinates remain ABSOLUTE REQUIREMENT (no optional fields)
✅ Try ALL enabled providers before failing

### Performance Requirements
✅ 95%+ geocoding success rate with 6 free providers
✅ <5% paid API usage (Google should rarely be used)
✅ Average response time <2 seconds per geocode
✅ Zero job discards due to missing coordinates

### Operational Requirements
✅ Comprehensive metadata tracking (all attempts logged)
✅ Cost tracking per provider
✅ Usage monitoring and quota alerts
✅ Easy to add new providers (implement behavior, add to config)
✅ Admin dashboard for provider management

---

## Files to Create

### New Modules
1. `lib/eventasaurus_discovery/geocoding/provider.ex` - Behavior definition
2. `lib/eventasaurus_discovery/geocoding/orchestrator.ex` - Main coordinator
3. `lib/eventasaurus_discovery/geocoding/registry.ex` - Provider registry
4. `lib/eventasaurus_discovery/geocoding/usage_tracker.ex` - Quota tracking
5. `lib/eventasaurus_discovery/geocoding/circuit_breaker.ex` - Health monitoring
6. `lib/eventasaurus_discovery/geocoding/strategy.ex` - Strategy behavior

### Provider Implementations
7. `lib/eventasaurus_discovery/geocoding/providers/mapbox.ex`
8. `lib/eventasaurus_discovery/geocoding/providers/here.ex`
9. `lib/eventasaurus_discovery/geocoding/providers/geoapify.ex`
10. `lib/eventasaurus_discovery/geocoding/providers/location_iq.ex`
11. `lib/eventasaurus_discovery/geocoding/providers/photon.ex`
12. `lib/eventasaurus_discovery/geocoding/providers/open_street_map.ex` (migrate)
13. `lib/eventasaurus_discovery/geocoding/providers/google_maps.ex` (migrate)
14. `lib/eventasaurus_discovery/geocoding/providers/google_places.ex` (migrate)

### Rate Limiters
15-22. `lib/eventasaurus_discovery/geocoding/rate_limiters/*.ex` (one per provider)

### Strategies
23. `lib/eventasaurus_discovery/geocoding/strategies/quality_first.ex`
24. `lib/eventasaurus_discovery/geocoding/strategies/cost_first.ex`
25. `lib/eventasaurus_discovery/geocoding/strategies/quota_aware.ex`
26. `lib/eventasaurus_discovery/geocoding/strategies/hybrid.ex`

### Database
27. `priv/repo/migrations/XXXXXX_create_geocoding_usage.exs`

### Tests
28-35. `test/eventasaurus_discovery/geocoding/**/*_test.exs`

### Configuration
36. Update `config/runtime.exs` with provider configuration

### Modifications
37. Update `lib/eventasaurus_discovery/helpers/address_geocoder.ex` to use Orchestrator
38. Update `lib/eventasaurus_discovery/application.ex` to start new supervisors

---

## Risk Assessment

### High Risk
- **Breaking existing jobs**: Mitigated by keeping AddressGeocoder API unchanged
- **Provider API changes**: Mitigated by abstraction layer and tests
- **Cost explosion**: Mitigated by quota tracking and Google disabled by default

### Medium Risk
- **Complex migration**: Mitigated by phased rollout (build alongside, then replace)
- **Performance impact**: Mitigated by efficient rate limiting and circuit breakers
- **Configuration complexity**: Mitigated by good defaults and documentation

### Low Risk
- **Provider reliability**: Mitigated by 6+ providers with fallback
- **Rate limit violations**: Mitigated by proper Hammer implementation per provider

---

## Related Issues

- #1658 - Original geocoding cost reduction (led to current problems)
- #1661 - Incorrect architectural analysis (closed)
- #1663 - Attempted optional coordinates (rejected, closed)
- `docs/ISSUE_FIX_OSM_RATE_LIMITING.md` - Rate limiting fix (prerequisite)

---

## Next Steps

1. **Review and approve this design**
2. **Set up API keys** for Mapbox, HERE, Geoapify, LocationIQ
3. **Implement Phase 1** (Foundation - Week 1)
4. **Test with real data** before expanding to more providers
5. **Monitor and optimize** based on actual usage patterns

---

**Priority**: P1 - High
**Estimated Timeline**: 3-4 weeks
**Expected Outcome**: 95%+ success rate, <5% paid API usage, $0-2/month costs
