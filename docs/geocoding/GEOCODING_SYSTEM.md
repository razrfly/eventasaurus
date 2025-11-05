# Geocoding System Documentation

**Last Updated**: October 2025
**Status**: Production-ready multi-provider system

## Overview

Eventasaurus uses a **multi-provider geocoding orchestrator** that automatically handles address geocoding with intelligent fallback across 8 providers. The system prioritizes free-tier providers and only uses paid services when explicitly enabled.

**Key Features**:
- ✅ 6 free providers with generous rate limits (primary)
- ✅ 2 paid providers disabled by default (fallback)
- ✅ Automatic failover when providers are rate-limited or unavailable
- ✅ Built-in rate limiting to respect provider quotas
- ✅ Database-driven configuration via admin dashboard
- ✅ Comprehensive metadata tracking for debugging and cost analysis
- ✅ Real-time performance monitoring and metrics

**Important**: Google Places API and Google Maps API are **disabled by default**. The system uses free providers first and can handle production workloads without paid services.

---

## Architecture

### System Components

```
Address String
    ↓
AddressGeocoder.geocode_address_with_metadata/1
    ↓
Orchestrator.geocode/1
    ↓
ProviderConfig.list_active_providers/0 (reads from database)
    ↓
Try each provider in priority order:
    → RateLimiter.check_rate_limit/1 (checks BEFORE calling)
    → Provider.geocode/1 (Mapbox, HERE, Geoapify, etc.)
    → Parse and standardize response
    → Return with metadata OR try next provider
    ↓
{:ok, result} OR {:error, :all_failed, metadata}
```

### Multi-Provider Fallback

The Orchestrator tries providers in database-configured priority order. If a provider:
- Returns `:rate_limited` → Wait and retry same provider
- Returns `:no_results` → Try next provider immediately
- Returns any other error → Try next provider immediately
- Succeeds → Return result with metadata

All providers attempted are tracked in the metadata for debugging and cost analysis.

---

## Provider Details

### Free Providers (Primary)

All free providers are **enabled by default** with priority 1 (randomized for load distribution):

| Provider | Free Tier | Rate Limit | Quality | Coverage | API Key Required |
|----------|-----------|------------|---------|----------|-----------------|
| **Mapbox** | 100K/month | 10 req/sec | 9/10 | Global, excellent | Yes (`MAPBOX_ACCESS_TOKEN`) |
| **HERE** | 250K/month | 10 req/sec | 9/10 | Global, excellent | Yes (`HERE_API_KEY`) |
| **Geoapify** | 90K/month | 5 req/sec | 8/10 | Global, good | Yes (`GEOAPIFY_API_KEY`) |
| **LocationIQ** | 150K/month | 5 req/sec | 8/10 | Global, OSM-based | Yes (`LOCATIONIQ_API_KEY`) |
| **OpenStreetMap** | Community | 1 req/sec | 7/10 | Global, free | No (public API) |
| **Photon** | Unlimited | 10 req/sec | 7/10 | Global, OSM-based | No (public API) |

### Paid Providers (Disabled by Default)

These providers are **disabled by default** and must be explicitly enabled via admin dashboard:

| Provider | Cost Per Call | Rate Limit | Quality | Notes |
|----------|--------------|------------|---------|-------|
| **Google Maps** | $0.005 | 50 req/sec | 10/10 | Highest quality, requires billing |
| **Google Places** | $0.034 | 50 req/sec | 10/10 | Most expensive, legacy fallback |

**Priority**: Set to 99 (last resort) even when enabled.

---

## Using the Geocoding System

### In Scrapers (VenueProcessor)

The geocoding system is automatically used by `VenueProcessor` when processing venues. **You don't need to call it directly in most cases.**

However, if you need to geocode an address directly (e.g., for testing or custom processing):

```elixir
# In your scraper or test code
alias EventasaurusDiscovery.Helpers.AddressGeocoder

# Geocode with full metadata
case AddressGeocoder.geocode_address_with_metadata("123 Main St, Paris, France") do
  {:ok, result} ->
    # Success! Result contains:
    # - latitude: Float (e.g., 48.8566)
    # - longitude: Float (e.g., 2.3522)
    # - city: String (e.g., "Paris")
    # - country: String (e.g., "France")
    # - geocoding_metadata: Map (see Metadata section)

    IO.puts("✅ Geocoded via #{result.geocoding_metadata.provider}")
    IO.puts("📍 Location: #{result.latitude}, #{result.longitude}")

  {:error, reason, metadata} ->
    # All providers failed
    IO.puts("❌ Geocoding failed: #{reason}")
    IO.puts("Attempted providers: #{inspect(metadata.attempted_providers)}")
end
```

### In VenueProcessor (Automatic)

The `VenueProcessor` automatically geocodes venue addresses. See `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex` lines 500-531:

```elixir
defp geocode_venue_address(data, city) do
  full_address = build_full_address(data, city)
  Logger.info("🔍 Geocoding venue address: #{full_address}")

  case AddressGeocoder.geocode_address_with_metadata(full_address) do
    {:ok, %{latitude: lat, longitude: lng, geocoding_metadata: metadata}} ->
      Logger.info("🗺️ ✅ Successfully geocoded via #{metadata.provider}: #{lat}, #{lng}")
      {lat, lng, metadata}

    {:error, reason, metadata} ->
      Logger.error("🗺️ ❌ Failed to geocode: #{reason}. Attempted: #{inspect(metadata.attempted_providers)}")
      {nil, nil, metadata}
  end
end
```

---

## Metadata Tracking

Every geocoding attempt returns comprehensive metadata for debugging and cost analysis:

```elixir
%{
  provider: "mapbox",                    # Provider that succeeded
  attempted_providers: ["mapbox"],        # All providers tried (in order)
  attempts: 1,                            # Number of providers attempted
  geocoded_at: ~U[2025-10-17 10:30:00Z], # Timestamp
  place_id: "place.123456",              # Provider-specific place ID (optional)
  raw_response: %{...}                   # Full API response (for debugging)
}
```

**When all providers fail**:

```elixir
{:error, :all_failed, %{
  attempted_providers: ["mapbox", "here", "geoapify", "locationiq", "openstreetmap", "photon"],
  attempts: 6,
  geocoded_at: ~U[2025-10-17 10:30:00Z],
  all_failed: true
}}
```

This metadata is stored with each venue and can be queried for:
- Cost analysis (which providers are being used most)
- Success rate monitoring (which providers fail most often)
- Performance optimization (which providers are fastest)
- Debugging failed geocoding attempts

---

## Error Handling in Scrapers

When implementing a new scraper, handle geocoding failures gracefully:

```elixir
# In your scraper's venue processing
case AddressGeocoder.geocode_address_with_metadata(full_address) do
  {:ok, result} ->
    # Success - use coordinates
    process_venue_with_coordinates(venue_data, result)

  {:error, :all_failed, metadata} ->
    # All providers failed - venue still valid, just without coordinates
    Logger.warning("⚠️ Geocoding failed after #{metadata.attempts} attempts")
    Logger.warning("Attempted providers: #{inspect(metadata.attempted_providers)}")

    # Continue processing - venue will be created without GPS coordinates
    # VenueProcessor handles this case automatically
    process_venue_without_coordinates(venue_data)

  {:error, reason, metadata} ->
    # Other error (should rarely happen)
    Logger.error("❌ Unexpected geocoding error: #{inspect(reason)}")
    process_venue_without_coordinates(venue_data)
end
```

**Best Practices**:
1. ✅ Always use `geocode_address_with_metadata/1` for full metadata
2. ✅ Log attempted providers and reasons for debugging
3. ✅ Continue processing even if geocoding fails (venues are still valuable)
4. ✅ Include full address strings (street, city, country) for best results
5. ❌ Don't implement your own geocoding - use the orchestrator
6. ❌ Don't directly call individual providers (Mapbox, HERE, etc.)

---

## Venue Name Validation

**Critical Design Pattern**: All scrapers MUST trigger geocoding to enable venue name validation, regardless of whether they provide coordinates.

### Why We Always Geocode

The geocoding system serves **two purposes**:
1. **Get coordinates** (latitude/longitude for mapping)
2. **Validate venue names** (prevent bad names from entering the database)

Even if a scraper provides coordinates, we MUST geocode to get a trusted venue name from the geocoding provider for validation.

### The Validation Process

When VenueProcessor creates a venue, it:

1. **Geocodes the address** (even if coordinates are provided)
2. **Extracts the geocoded venue name** from the provider's response
3. **Compares scraped name vs geocoded name** using similarity scoring
4. **Chooses the best name**:
   - High similarity (≥70%): Use scraped name (validated as correct)
   - Moderate similarity (30-70%): Prefer geocoded name, log warning
   - Low similarity (<30%): Use geocoded name, reject scraped name

**Validation module**: `lib/eventasaurus_discovery/validation/venue_name_validator.ex`

### Why This Matters

Scrapers can extract bad venue names from HTML that include:
- Event-specific information: `"Barchetta (Starts on November 3!)"`
- UI elements: `"Click here for details"`
- Image captions: `"View on map"`
- Promotional text: `"50% off tickets!"`

The geocoding provider (Mapbox, HERE, etc.) gives us the **authoritative venue name** from their business database, which we can trust.

### Scraper Requirements

**All scrapers MUST**:
- Extract venue name from the source
- Provide address for geocoding
- Let VenueProcessor handle geocoding (don't skip it)

**What NOT to do**:
```elixir
# ❌ BAD - Providing coordinates AND address bypasses validation
%{
  name: scraped_name,  # May be bad
  address: "123 Main St",
  latitude: 40.7128,   # ❌ Causes geocoding to be skipped
  longitude: -74.0060  # ❌ No validation happens
}
```

**Correct pattern**:
```elixir
# ✅ GOOD - Let VenueProcessor geocode for validation
%{
  name: scraped_name,        # Will be validated
  address: "123 Main St",    # Used for geocoding
  latitude: nil,             # ✅ Triggers geocoding
  longitude: nil             # ✅ Enables validation
}

# ✅ ALSO GOOD - Provide coordinates, but still geocode for validation
# (Future implementation: VenueProcessor will geocode even when coords exist)
```

### Current Status (As of Issue #2165)

**Working correctly**:
- Question One scraper ✅ (provides address only → geocoding happens → validation works)

**Validation bypassed** (needs fix):
- Geeks Who Drink ❌ (provides name + address + coordinates → skips geocoding)
- Inquizition ❌ (provides name + address + coordinates → skips geocoding)
- Speed Quizzing ❌ (provides name + address + coordinates → skips geocoding)

**The fix**: Remove the optimization in VenueProcessor that skips geocoding when coordinates are provided. Always geocode to ensure venue name validation happens.

### Design Philosophy

**"Geocode everything for validation, even when we have coordinates."**

The marginal API cost of geocoding is worth the data quality improvement from catching bad venue names before they enter the database. Geocoding providers have generous free tiers (100K-250K requests/month) that easily support this pattern.

---

## Rate Limiting

The system checks rate limits **before** calling providers to avoid wasted API calls and bans.

### How Rate Limiting Works

1. **Before calling provider**: `RateLimiter.check_rate_limit/1` checks current usage
2. **If limit reached**: Returns `{:error, :rate_limited, retry_after_ms}`
3. **Orchestrator waits**: `Process.sleep(retry_after_ms)` before retrying same provider
4. **Retry**: After wait period, tries same provider again

### Rate Limit Configuration

Rate limits are stored in the database (`geocoding_providers.metadata` JSONB field):

```elixir
metadata: %{
  "rate_limits" => %{
    "per_second" => 10,   # Max requests per second
    "per_minute" => 600,  # Max requests per minute
    "per_hour" => 36000   # Max requests per hour
  },
  "timeout_ms" => 5000    # Request timeout
}
```

**Default Rate Limits** (conservative, respect provider terms):

- Mapbox: 10/sec, 600/min, 36K/hour
- HERE: 10/sec, 600/min, 36K/hour
- Geoapify: 5/sec, 300/min, 18K/hour
- LocationIQ: 5/sec, 300/min, 18K/hour
- OpenStreetMap: 1/sec, 60/min, 3600/hour (strictly enforced by OSM)
- Photon: 10/sec, 600/min, 36K/hour (no official limit, conservative)

---

## Admin Dashboard

### Provider Configuration UI

**URL**: `/admin/geocoding/providers`

Features:
- 🎯 Drag-and-drop provider reordering (change priority)
- 🟢/🔴 Toggle providers on/off
- 📊 View current configuration and status
- 🔄 Real-time updates (no code deployment needed)

### Performance Metrics Dashboard

**URL**: `/admin/geocoding`

Features:
- 📈 Overall success rate across all providers
- 📊 Provider hit rates (which providers succeed most)
- 🔍 Fallback depth analysis (how many providers tried per request)
- ❌ Failed geocoding venues (last 10 failures)
- 💰 Cost reporting (manual generation via button)
- 📋 Performance by scraper source

**Accessing the Dashboard**:

```bash
# Start Phoenix server
mix phx.server

# Navigate to admin dashboard
open http://localhost:4000/admin/geocoding

# Or view provider configuration
open http://localhost:4000/admin/geocoding/providers
```

---

## Cost Management

### Free Tier Monitoring

The system tracks provider usage automatically. Monitor in admin dashboard to ensure you stay within free tiers:

| Provider | Free Tier Limit | Monthly Cost if Exceeded |
|----------|----------------|-------------------------|
| Mapbox | 100,000 requests | $0.50/1K after limit |
| HERE | 250,000 requests | Contact sales |
| Geoapify | 90,000 requests | $1.00/1K after limit |
| LocationIQ | 150,000 requests | $1.00/1K after limit |
| OpenStreetMap | No limit | Free forever (community) |
| Photon | No limit | Free forever (community) |

### Cost Optimization Strategies

1. **Use free providers first** (default configuration)
2. **Monitor usage in admin dashboard** weekly
3. **Disable high-cost providers** (Google APIs disabled by default)
4. **Cache geocoding results** (handled automatically by VenueProcessor)
5. **Use full addresses** to maximize first-attempt success

### Generating Cost Reports

```bash
# Via admin dashboard UI
Click "Generate Report" button at /admin/geocoding

# Via IEx console
iex> EventasaurusDiscovery.Workers.GeocodingCostReportWorker.generate_report()
{:ok, %{
  total_requests: 45_231,
  by_provider: %{
    "mapbox" => %{count: 15_432, cost: 0.0},
    "here" => %{count: 18_921, cost: 0.0},
    ...
  },
  total_cost: 0.0  # $0 when using only free providers
}}
```

---

## Adding New Providers

### 1. Create Provider Module

```elixir
# lib/eventasaurus_discovery/geocoding/providers/my_provider.ex
defmodule EventasaurusDiscovery.Geocoding.Providers.MyProvider do
  @moduledoc """
  MyProvider Geocoding API.

  **Free Tier**: 50K requests/month
  **Rate Limit**: 5 requests/second
  **Quality**: 8/10
  **Coverage**: European focus

  ## Configuration

  Requires `MY_PROVIDER_API_KEY` environment variable.
  Sign up at: https://myprovider.com/
  """

  @behaviour EventasaurusDiscovery.Geocoding.Provider

  require Logger

  @impl true
  def name, do: "my_provider"

  @impl true
  def geocode(address) when is_binary(address) do
    api_key = System.get_env("MY_PROVIDER_API_KEY")

    if is_nil(api_key) do
      Logger.error("❌ MY_PROVIDER_API_KEY not configured")
      {:error, :api_key_missing}
    else
      # Make API request, parse response
      # Return {:ok, %{latitude:, longitude:, city:, country:}}
      # Or {:error, reason}
    end
  end

  def geocode(_), do: {:error, :invalid_address}
end
```

### 2. Add to Database

```bash
# Via IEx console
iex> alias EventasaurusApp.Repo
iex> alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider

iex> %GeocodingProvider{}
...> |> GeocodingProvider.changeset(%{
...>   name: "my_provider",
...>   priority: 7,  # After existing free providers
...>   is_active: true,
...>   metadata: %{
...>     rate_limits: %{
...>       per_second: 5,
...>       per_minute: 300,
...>       per_hour: 18000
...>     },
...>     timeout_ms: 5000
...>   }
...> })
...> |> Repo.insert()
```

### 3. Configure API Key

```bash
# Add to .env
MY_PROVIDER_API_KEY=your_api_key_here

# Or export directly
export MY_PROVIDER_API_KEY=your_api_key_here
```

### 4. Test Provider

```elixir
# Test directly
iex> EventasaurusDiscovery.Geocoding.Providers.MyProvider.geocode("123 Main St, Paris")
{:ok, %{latitude: 48.8566, longitude: 2.3522, city: "Paris", country: "France"}}

# Test via orchestrator
iex> EventasaurusDiscovery.Geocoding.Orchestrator.geocode("123 Main St, Paris")
{:ok, %{..., geocoding_metadata: %{provider: "my_provider", ...}}}
```

---

## Testing Geocoding

### Unit Tests

```elixir
# Test individual provider
test "geocodes Paris address" do
  result = MyProvider.geocode("Eiffel Tower, Paris, France")

  assert {:ok, %{latitude: lat, longitude: lng, city: city}} = result
  assert_in_delta lat, 48.8584, 0.01
  assert_in_delta lng, 2.2945, 0.01
  assert city == "Paris"
end
```

### Integration Tests

```elixir
# Test orchestrator fallback
test "tries multiple providers when first fails" do
  # Mock first provider to fail
  expect(MockProvider1, :geocode, fn _ -> {:error, :no_results} end)
  expect(MockProvider2, :geocode, fn _ -> {:ok, %{...}} end)

  {:ok, result} = Orchestrator.geocode("Address")

  assert result.geocoding_metadata.provider == "mock_provider_2"
  assert result.geocoding_metadata.attempts == 2
end
```

### Manual Testing

```bash
# Create test script (see test_geocoding.exs in project root)
mix run test_geocoding.exs

# Or via IEx
iex -S mix
iex> alias EventasaurusDiscovery.Helpers.AddressGeocoder
iex> AddressGeocoder.geocode_address_with_metadata("123 Main St, London, UK")
```

---

## Troubleshooting

### Provider Always Fails

**Symptom**: One provider consistently returns errors

**Check**:
1. API key configured? `echo $PROVIDER_API_KEY`
2. API key valid? Check provider dashboard
3. Rate limits hit? Check `/admin/geocoding` dashboard
4. Provider down? Check provider status page

### All Providers Fail

**Symptom**: Every geocoding request returns `:all_failed`

**Check**:
1. Are any providers enabled? Check `/admin/geocoding/providers`
2. Network connectivity? `curl https://api.mapbox.com`
3. Database configuration? Check `geocoding_providers` table
4. Address format valid? Try with known-good address

### Slow Geocoding

**Symptom**: Geocoding takes >5 seconds per request

**Possible Causes**:
1. Rate limiting (providers waiting between requests)
2. Multiple provider failures (cascading through all 6 providers)
3. Network latency to provider APIs
4. Provider API slowness

**Solutions**:
- Check `/admin/geocoding` for fallback depth metrics
- Optimize provider priority order based on success rates
- Disable slow/failing providers temporarily

### High Costs

**Symptom**: Unexpected charges from geocoding providers

**Check**:
1. Are paid providers enabled? (Should be disabled by default)
2. Free tier limits exceeded? Check usage in admin dashboard
3. Generate cost report: `/admin/geocoding` → "Generate Report"

**Prevention**:
- Keep Google providers disabled unless explicitly needed
- Monitor usage weekly via admin dashboard
- Set alerts when approaching free tier limits

---

## Related Documentation

- [Scraper Specification](../scrapers/SCRAPER_SPECIFICATION.md) - How geocoding integrates with scrapers
- [VenueProcessor Source](../../lib/eventasaurus_discovery/scraping/processors/venue_processor.ex) - Automatic geocoding implementation
- [Geocoding Admin MVP](../GEOCODING_ADMIN_MVP.md) - Admin dashboard implementation details
- [AddressGeocoder Source](../../lib/eventasaurus_discovery/helpers/address_geocoder.ex) - High-level geocoding interface

---

## FAQ

### Q: Do I need a Google Places API key?

**A: No.** Google Places is disabled by default and only used as a last resort when explicitly enabled. The 6 free providers handle production workloads.

### Q: Which provider is used first?

**A: All free providers have priority 1 by default**, meaning they're randomized for load distribution. Check `/admin/geocoding/providers` for current order.

### Q: Can I change provider priority without code deployment?

**A: Yes!** Use the admin dashboard at `/admin/geocoding/providers` to drag-and-drop reorder providers. Changes take effect immediately.

### Q: What happens if all providers fail?

**A: The venue is still created**, just without GPS coordinates. Venues can be geocoded later via a background job or manual intervention.

### Q: How do I test geocoding in development?

**A: Use the test script**: `mix run test_geocoding.exs` or call `AddressGeocoder.geocode_address_with_metadata/1` directly in IEx.

### Q: Can I use only OpenStreetMap and Photon (no API keys)?

**A: Yes!** Disable the other providers in `/admin/geocoding/providers`. OSM and Photon require no API keys and are completely free.

---

**Last Updated**: October 2025
**Maintained By**: Eventasaurus Core Team
**Questions?**: Check the [admin dashboard](/admin/geocoding) or review the source code.
