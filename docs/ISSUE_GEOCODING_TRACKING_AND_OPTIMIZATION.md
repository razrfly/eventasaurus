# Geocoding Tracking Dashboard & OpenStreetMap Failures

**Severity:** 🔴 **CRITICAL** - Multiple issues requiring immediate attention
**Status:** PROPOSED - Requires implementation
**Created:** 2025-10-11
**Related Issues:**
- ISSUE_FORWARD_GEOCODING_SOLUTION.md (implemented)
- ISSUE_QUESTION_ONE_FAKE_CITIES.md (root cause)

---

## Problem Summary

### Issue 1: OpenStreetMap API Failures (CRITICAL)

**Current State**: QuestionOne scraper failing with 21 retryable + 4 discarded jobs (19% failure rate)

**Root Causes**:
1. **JSON Decode Errors**: OpenStreetMap returning HTML (`<`) instead of JSON
   - Error: `Jason.DecodeError) unexpected byte at position 0: 0x3C ("<")`
   - OSM is returning error pages (likely rate limit violations or malformed requests)
   - The `geocoder` library is NOT handling these errors gracefully
2. **GenServer Timeouts**: 5-second timeout insufficient when OSM is slow/overloaded
   - Error: `(EXIT) time out` in `GenServer.call(#PID, {:geocode, ...}, 5000)`
   - Multiple concurrent requests queueing up in poolboy
3. **Google Fallback Not Wired Up**: `geocoder` library's Google provider doesn't use our existing Google Maps API key
   - We HAVE a Google Maps API key (been using it for 6 months in VenueProcessor)
   - But the NEW `geocoder` library we just added doesn't know about it
   - Need to configure `geocoder`'s Google provider to use existing key

**Impact**:
- 25 out of 130 QuestionOne jobs failing (19% failure rate)
- Jobs being discarded after 3 attempts
- Data not being ingested properly
- System reliability compromised

### Issue 2: Lack of Geocoding Cost Tracking

**Current State**: No visibility into geocoding costs or usage patterns

**Problem**:
- Google Places API costs money ($5 per 1,000 requests after $200 free credit)
- No way to know which geocoding method is being used
- Can't optimize cost vs. reliability trade-offs
- Can't track if OpenStreetMap failures are pushing us to expensive Google API

**Need**: Dashboard showing:
- % of requests using each geocoding method
- Success/failure rates by method
- Cost estimates for paid services
- Trends over time

---

## Current Geocoding Architecture

### Method 1: Forward Geocoding (QuestionOne) - NEW
**File**: `lib/eventasaurus_discovery/helpers/address_geocoder.ex`

**Flow**:
```
Address String → OpenStreetMaps (free, 1 req/sec) → Google Maps fallback (paid)
```

**Status**: ❌ **FAILING** - OSM returning HTML errors, Google fallback not configured

**Used By**:
- QuestionOne scraper (UK pub quiz venues)

### Method 2: Reverse Geocoding (GPS → City)
**Library**: `:geocoding` (offline)

**Flow**:
```
GPS Coordinates → Offline City Database → City Name
```

**Status**: ✅ Working reliably

**Used By**:
- Bandsintown transformer
- Cinema City transformer
- Geeks Who Drink transformer

### Method 3: Google Places API Lookup (VenueProcessor)
**File**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:464-499`

**Flow**:
```
Venue Name + Address → Google Places TextSearch → Place Details → GPS + Verified Name
```

**Status**: ✅ Working (but costs money)

**Used By**:
- VenueProcessor when `latitude`/`longitude` are nil
- VenueProcessor when updating existing venues without coordinates
- All scrapers indirectly via VenueProcessor

### Method 4: Manual Parsing (DEPRECATED)
**Status**: 🗑️ Removed - was creating fake cities

---

## Error Analysis

### OpenStreetMap Errors (from Oban job logs)

**Error Type 1: JSON Decode Error**
```
Jason.DecodeError) unexpected byte at position 0: 0x3C ("<")
```

**Root Cause**: OSM API returning HTML error pages instead of JSON
- Possible rate limit violation (1 req/sec limit)
- Possible service degradation
- Invalid request format

**Affected Addresses**:
- "16 Saint Peter's Street, St Albans England AL1 3NA, United Kingdom"
- "102 Camden Road, England NW1 9EA, United Kingdom"
- "Orestan Lane, Effingham England KT24 5SW, United Kingdom"
- "27 High Street, Histon England CB24 9JD, United Kingdom"
- "87 Noel Road, England N1 8HD, United Kingdom"

**Error Type 2: GenServer Timeout**
```
(EXIT) exited in: GenServer.call(#PID, {:geocode, [store: true, address: "..."]}, 5000)
** (EXIT) time out
```

**Root Cause**: 5-second timeout insufficient for geocoding requests
- Likely caused by queueing in poolboy worker pool
- Multiple concurrent requests waiting
- OSM API slow to respond

---

## Proposed Solutions

### Phase 1: Fix OpenStreetMap Failures (IMMEDIATE)

#### 1.1 Wire Up Existing Google Maps API Key to Geocoder Library

**Problem**: The NEW `geocoder` library doesn't know about our existing Google Maps API key

**Reality Check**:
- ✅ We HAVE been using Google Maps API for 6+ months
- ✅ Key is already in environment as `GOOGLE_MAPS_API_KEY`
- ✅ VenueProcessor uses it successfully via our own GooglePlaces client
- ❌ NEW `geocoder` library needs to be configured to use same key

**Solution**: Tell `geocoder`'s Google provider to use our existing key

**Files**:
- `config/config.exs` or `config/runtime.exs` - Add geocoder Google provider config

**Implementation**:
```elixir
# config/runtime.exs (add after existing geocoder config)
config :geocoder, Geocoder.Providers.GoogleMaps,
  api_key: System.get_env("GOOGLE_MAPS_API_KEY")  # Same key we've been using
```

#### 1.2 Add Retry Logic with Exponential Backoff

**Problem**: Single OSM failure immediately tries Google (expensive)

**Solution**: Retry OSM 2-3 times with backoff before falling back to Google

**Implementation**:
```elixir
defp try_openstreetmaps_with_retry(address, attempts \\ 3) do
  case try_openstreetmaps(address) do
    {:ok, result} -> {:ok, result}
    {:error, reason} when attempts > 1 ->
      backoff_ms = (4 - attempts) * 1000  # 1s, 2s
      Process.sleep(backoff_ms)
      try_openstreetmaps_with_retry(address, attempts - 1)
    {:error, reason} -> {:error, reason}
  end
end
```

#### 1.3 Increase GenServer Timeout

**Problem**: 5-second timeout too short for geocoding operations

**Solution**: Increase timeout to 15-30 seconds for geocoding calls

**Implementation**:
```elixir
# Current: GenServer.call(pid, {:geocode, opts}, 5000)
# Change to: GenServer.call(pid, {:geocode, opts}, 15000)
```

**Note**: This is controlled by the `geocoder` library, may need configuration

#### 1.4 Add Better Error Handling for OSM HTML Responses

**Problem**: OSM returning HTML error pages, causing JSON decode crashes in `geocoder` library

**Root Cause**: `geocoder` library's OSM provider tries to decode HTML as JSON when API returns errors

**Solution**: Catch these errors gracefully and immediately fallback to Google

**Implementation**:
```elixir
defp try_openstreetmaps(address) do
  case Geocoder.call(address) do
    {:ok, coordinates} -> extract_location_data(coordinates, "OpenStreetMaps")
    {:error, reason} -> {:error, :osm_failed}
  end
rescue
  Jason.DecodeError ->
    Logger.warning("⚠️ OSM returned HTML instead of JSON for: #{address} (likely rate limited)")
    {:error, :osm_rate_limited}
  error ->
    Logger.error("❌ OSM unexpected error for #{address}: #{inspect(error)}")
    {:error, :osm_failed}
end
```

**Why This Happens**:
- OSM Nominatim has 1 req/sec rate limit
- When exceeded, returns HTTP 429 with HTML error page
- `geocoder` library doesn't handle this, crashes on JSON decode
- We need to catch and fallback to Google

### Phase 2: Implement Geocoding Tracking Dashboard

#### 2.1 Create GeocodingStats Schema

**Purpose**: Track all geocoding operations for cost analysis and optimization

**Schema**:
```elixir
defmodule EventasaurusDiscovery.Tracking.GeocodingStats do
  use Ecto.Schema
  import Ecto.Changeset

  schema "geocoding_stats" do
    field :method, :string          # "forward_osm", "forward_google", "reverse_offline", "google_places", "cached"
    field :source, :string           # "question_one", "bandsintown", "venue_processor", etc.
    field :success, :boolean
    field :response_time_ms, :integer
    field :cost_estimate, :decimal   # Estimated cost in USD
    field :error_reason, :string
    field :address, :text            # For debugging (anonymize if needed)
    field :result_city, :string      # What city was resolved
    field :metadata, :map            # Additional tracking data

    timestamps()
  end

  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:method, :source, :success, :response_time_ms, :cost_estimate, :error_reason, :address, :result_city, :metadata])
    |> validate_required([:method, :source, :success])
  end
end
```

**Migration**:
```elixir
create table(:geocoding_stats) do
  add :method, :string, null: false
  add :source, :string, null: false
  add :success, :boolean, null: false
  add :response_time_ms, :integer
  add :cost_estimate, :decimal, precision: 10, scale: 6
  add :error_reason, :string
  add :address, :text
  add :result_city, :string
  add :metadata, :map

  timestamps()
end

create index(:geocoding_stats, [:method])
create index(:geocoding_stats, [:source])
create index(:geocoding_stats, [:inserted_at])
create index(:geocoding_stats, [:success])
```

#### 2.2 Instrument All Geocoding Methods

**AddressGeocoder (Forward Geocoding)**:
```elixir
defp try_openstreetmaps(address) do
  start_time = System.monotonic_time(:millisecond)

  result = case Geocoder.call(address) do
    {:ok, coordinates} ->
      extract_location_data(coordinates, "OpenStreetMaps")
    {:error, reason} ->
      {:error, :osm_failed}
  end

  response_time = System.monotonic_time(:millisecond) - start_time

  # Track stats
  track_geocoding_stat(%{
    method: "forward_osm",
    source: "question_one",  # Pass this in from caller
    success: match?({:ok, _}, result),
    response_time_ms: response_time,
    cost_estimate: 0.0,  # Free
    address: address,
    result_city: case result do
      {:ok, {city, _, _}} -> city
      _ -> nil
    end,
    error_reason: case result do
      {:error, reason} -> to_string(reason)
      _ -> nil
    end
  })

  result
end
```

**VenueProcessor (Google Places)**:
```elixir
defp lookup_venue_from_google_places(data, city) do
  start_time = System.monotonic_time(:millisecond)

  # ... existing lookup logic ...

  response_time = System.monotonic_time(:millisecond) - start_time

  track_geocoding_stat(%{
    method: "google_places",
    source: "venue_processor",
    success: not is_nil(venue_data),
    response_time_ms: response_time,
    cost_estimate: 0.005,  # $5 per 1,000 requests
    address: "#{data.name}, #{city.name}",
    result_city: city.name,
    metadata: %{place_id: venue_data.place_id}
  })

  # ... return result ...
end
```

**Reverse Geocoding (Offline)**:
```elixir
defp resolve_location_from_coordinates(lat, lng) do
  start_time = System.monotonic_time(:millisecond)

  result = CityResolver.resolve_city_from_coordinates(lat, lng)

  response_time = System.monotonic_time(:millisecond) - start_time

  track_geocoding_stat(%{
    method: "reverse_offline",
    source: get_source_from_caller(),  # bandsintown, geeks_who_drink, etc.
    success: match?({:ok, _}, result),
    response_time_ms: response_time,
    cost_estimate: 0.0,  # Free
    metadata: %{lat: lat, lng: lng}
  })

  result
end
```

#### 2.3 Create Dashboard Queries

**Daily Summary**:
```elixir
def daily_geocoding_summary(date \\ Date.utc_today()) do
  from(gs in GeocodingStats,
    where: fragment("DATE(?)", gs.inserted_at) == ^date,
    group_by: [gs.method, gs.success],
    select: %{
      method: gs.method,
      success: gs.success,
      count: count(gs.id),
      total_cost: sum(gs.cost_estimate),
      avg_response_time: avg(gs.response_time_ms)
    }
  )
  |> Repo.all()
end
```

**Cost Projection**:
```elixir
def monthly_cost_projection do
  # Get current month's costs
  current_month_start = Date.beginning_of_month(Date.utc_today())
  days_elapsed = Date.diff(Date.utc_today(), current_month_start) + 1

  from(gs in GeocodingStats,
    where: gs.inserted_at >= ^current_month_start,
    select: %{
      total_cost: sum(gs.cost_estimate),
      total_requests: count(gs.id)
    }
  )
  |> Repo.one()
  |> case do
    %{total_cost: cost, total_requests: requests} ->
      days_in_month = Date.days_in_month(Date.utc_today())
      projected_cost = (cost / days_elapsed) * days_in_month

      %{
        current_cost: cost,
        projected_monthly_cost: projected_cost,
        requests_per_day: requests / days_elapsed,
        projected_monthly_requests: (requests / days_elapsed) * days_in_month
      }
  end
end
```

**Method Distribution**:
```elixir
def geocoding_method_distribution(days_back \\ 30) do
  cutoff = DateTime.utc_now() |> DateTime.add(-days_back, :day)

  from(gs in GeocodingStats,
    where: gs.inserted_at >= ^cutoff,
    group_by: gs.method,
    select: %{
      method: gs.method,
      count: count(gs.id),
      success_rate: fragment("CAST(SUM(CASE WHEN ? THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100", gs.success),
      total_cost: sum(gs.cost_estimate)
    }
  )
  |> Repo.all()
end
```

#### 2.4 Add Dashboard UI Component

**Location**: LiveView component in Oban Dashboard or separate admin page

**Features**:
- Real-time success/failure rates by method
- Cost tracking and projections
- Response time distributions
- Error rate alerts (>10% failure = warning)
- Method distribution pie chart
- Daily/weekly/monthly trends

**Example Visualization**:
```
┌─────────────────────────────────────────────────┐
│ Geocoding Dashboard - Last 7 Days              │
├─────────────────────────────────────────────────┤
│ Method Distribution:                            │
│   Forward OSM:        45% (1,234 req) - FREE   │
│   Reverse Offline:    30% (  820 req) - FREE   │
│   Google Places:      25% (  685 req) - $3.43  │
│   Forward Google:      0% (    0 req) - $0.00  │
├─────────────────────────────────────────────────┤
│ Success Rates:                                  │
│   Forward OSM:        81% ⚠️ (19% failure)      │
│   Reverse Offline:   100% ✅                    │
│   Google Places:     100% ✅                    │
├─────────────────────────────────────────────────┤
│ Cost Analysis:                                  │
│   Week Total:    $3.43                         │
│   Month Proj:   $14.76 (well under $200 free)  │
│   Avg per Day:   $0.49                         │
└─────────────────────────────────────────────────┘
```

### Phase 3: Optimization Strategies

#### 3.1 Cache Forward Geocoding Results

**Problem**: Same addresses being geocoded repeatedly

**Solution**: Add database cache for forward geocoding (similar to ISSUE_FORWARD_GEOCODING_SOLUTION.md proposal)

**Schema**:
```elixir
create table(:cached_geocoding) do
  add :address, :text, null: false
  add :city_name, :string, null: false
  add :country_name, :string, null: false
  add :latitude, :float
  add :longitude, :float
  add :method_used, :string  # Track which method resolved it
  add :last_verified, :utc_datetime

  timestamps()
end

create unique_index(:cached_geocoding, [:address])
```

**Cache Check**:
```elixir
def geocode_address(address) do
  # Check cache first
  case get_cached_geocoding(address) do
    {:ok, result} ->
      track_geocoding_stat(%{method: "cached", source: "cache", success: true, cost_estimate: 0.0})
      {:ok, result}

    :miss ->
      # Try OSM, then Google, then cache result
      result = try_openstreetmaps(address)
      cache_geocoding_result(address, result)
      result
  end
end
```

#### 3.2 Batch Geocoding Operations

**Problem**: Individual requests hitting rate limits

**Solution**: Batch multiple addresses and process with rate limiting

**Implementation**:
```elixir
defmodule EventasaurusDiscovery.Helpers.GeocodingBatcher do
  use GenServer

  # Collect addresses for 500ms, then batch geocode
  @batch_window_ms 500
  @osm_rate_limit_ms 1000  # 1 req/sec

  # ... batch processing logic ...
end
```

#### 3.3 Prefer Free Methods Over Paid

**Current Order**:
1. Forward OSM (free, but failing)
2. Google Maps fallback (paid)

**Better Order**:
1. Cache check (free, instant)
2. Forward OSM with retry (free, 1-5s)
3. Reverse geocoding if we have approximate coordinates (free, instant)
4. Google Places API (paid, reliable, 200-500ms)

---

## Success Criteria

### Phase 1: Fix OSM Failures ✅
- [ ] OpenStreetMap failure rate <5% (currently 19%)
- [ ] Google Maps fallback working when configured
- [ ] Zero "JSON decode error" failures
- [ ] Zero timeout failures
- [ ] All 25 failed jobs successfully reprocessed

### Phase 2: Tracking Dashboard ✅
- [ ] GeocodingStats table created and populated
- [ ] All 4 geocoding methods instrumented
- [ ] Dashboard showing method distribution
- [ ] Cost tracking and projections visible
- [ ] Success/failure rates per method

### Phase 3: Cost Optimization ✅
- [ ] Geocoding cache implemented and hit rate >60%
- [ ] Monthly Google Places cost <$50 (currently ~$15-20 projected)
- [ ] Forward OSM success rate >90%
- [ ] Zero unnecessary Google API calls

---

## Implementation Plan

### Week 1: Emergency Fixes (Phase 1)
**Priority**: CRITICAL - Fix production failures

**Tasks**:
1. Add Google Maps API key configuration
2. Implement OSM retry logic with backoff
3. Add rescue blocks for JSON decode errors
4. Increase GenServer timeout or configure poolboy properly
5. Test with all 25 failed addresses
6. Deploy and monitor success rates

**Estimated Time**: 4-6 hours

### Week 2: Tracking Infrastructure (Phase 2)
**Priority**: HIGH - Visibility for optimization

**Tasks**:
1. Create GeocodingStats schema and migration
2. Instrument AddressGeocoder
3. Instrument VenueProcessor Google Places calls
4. Instrument reverse geocoding in transformers
5. Create dashboard queries
6. Build LiveView dashboard component
7. Deploy and start collecting data

**Estimated Time**: 2-3 days

### Week 3: Optimization (Phase 3)
**Priority**: MEDIUM - Cost reduction

**Tasks**:
1. Create cached_geocoding table
2. Implement cache check in AddressGeocoder
3. Analyze dashboard data to identify optimization opportunities
4. Consider batch processing if rate limits still an issue
5. Monitor cost savings and cache hit rates

**Estimated Time**: 2-3 days

---

## Monitoring & Alerts

### Critical Alerts
- **OSM Failure Rate >10%**: Check rate limits and API status
- **Google Places Cost >$100/month**: Investigate cache misses and unnecessary calls
- **Geocoding Timeout Rate >5%**: Check poolboy configuration and GenServer settings

### Weekly Review Metrics
- Total geocoding requests by method
- Success rates by method
- Cost per request by method
- Cache hit rates
- Average response times

---

## Alternative Approaches Considered

### 1. Self-Hosted Nominatim
**Pros**:
- No rate limits
- Full control
- Zero API costs

**Cons**:
- Requires ~100GB database
- Server infrastructure costs
- Maintenance overhead
- Initial setup complexity

**Decision**: Start with hosted OSM + Google fallback, consider self-hosting if we scale significantly (>10K requests/month)

### 2. Pre-populate Geocoding Cache
**Pros**:
- Instant lookups
- Zero API calls
- Predictable costs

**Cons**:
- Requires knowing all addresses upfront
- Stale data for new venues
- High initial setup cost

**Decision**: Use lazy caching (cache on first lookup) instead of pre-population

### 3. Remove OSM, Use Only Google
**Pros**:
- More reliable (100% success rate)
- Simpler code
- Better data quality

**Cons**:
- Significantly higher costs ($5 per 1,000 vs. free)
- Projected ~$75/month vs. current ~$15/month
- Unnecessary when OSM works fine 90%+ of the time

**Decision**: Fix OSM reliability, keep as primary free option

---

## Related Documentation

- **ISSUE_FORWARD_GEOCODING_SOLUTION.md** - Original forward geocoding implementation
- **ISSUE_QUESTION_ONE_FAKE_CITIES.md** - Root cause that led to this solution
- **SCRAPER_MANIFESTO.md** - Update with geocoding tracking best practices

---

## Cost Analysis

### Current Estimated Costs (projected)
- Google Places API: ~$15-20/month (685 requests/week × 4 weeks)
- OpenStreetMaps: $0/month (free)
- Reverse Geocoding: $0/month (offline)

**Total**: ~$15-20/month

### If OSM Continues Failing (worst case)
- All 1,234 OSM requests → Google: +$6.17/month
- **New Total**: ~$21-26/month

### If Cache Implemented (60% hit rate)
- 60% of requests from cache: $0
- 40% of requests from API
- **New Total**: ~$8-12/month

**Savings**: ~40-50% cost reduction

---

## Conclusion

**Immediate Action Required**: Fix OpenStreetMap failures causing 19% job failure rate

**Long-term Goal**: Build comprehensive tracking dashboard to optimize geocoding costs and reliability

**Expected Outcome**: <5% failure rate, <$20/month costs, full visibility into geocoding operations
