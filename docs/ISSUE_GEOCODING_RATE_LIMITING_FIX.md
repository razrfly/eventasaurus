# Fix Broken Rate Limiting for OpenStreetMap Geocoding

**Status**: 🔴 Critical - 60% Job Failure Rate
**Root Cause**: Process.sleep() doesn't provide global rate limiting
**Impact**: OSM returning HTML errors instead of JSON, causing geocoding failures

## Problem Summary

Our implementation to prevent Google API costs (#1658) uses `Process.sleep(1000)` for rate limiting, but this **does not work with parallel workers**. All 3 Oban workers sleep simultaneously, wake up simultaneously, and hit OSM simultaneously - violating the 1 req/sec limit.

## The Broken Implementation

```elixir
# lib/eventasaurus_discovery/helpers/address_geocoder.ex:197-202
defp try_openstreetmaps(address) do
  Process.sleep(1000)  # ❌ BROKEN - doesn't work across workers!

  case Geocoder.call(address) do
    {:ok, coordinates} -> extract_location_data(coordinates, "OpenStreetMaps")
    {:error, reason} -> {:error, :osm_failed}
  end
end
```

### Why This Fails

With 3 parallel Oban workers (concurrency: 3):

```
t=0ms:    Worker 1 starts Process.sleep(1000)
t=0ms:    Worker 2 starts Process.sleep(1000)
t=0ms:    Worker 3 starts Process.sleep(1000)
          ↓
t=1000ms: Worker 1 wakes up, calls OSM API
t=1000ms: Worker 2 wakes up, calls OSM API  ← Same millisecond!
t=1000ms: Worker 3 wakes up, calls OSM API  ← Same millisecond!
          ↓
Result:   All 3 hit OSM simultaneously → rate limit violation
```

**OSM Response**: Returns HTML rate limit page instead of JSON
**Our Code**: Jason.DecodeError → {:error, :osm_rate_limited}
**Job Result**: Fails with retryable error

### Evidence from Database

```sql
-- Jobs after our changes (post 9:56am on 2025-10-12)
SELECT state, COUNT(*) FROM oban_jobs
WHERE scheduled_at > '2025-10-12 09:56:00'
AND worker LIKE '%VenueDetail%';

-- Results:
discarded | 87   -- 60% failure rate ❌
completed | 58   -- 40% success rate
```

**Error Pattern** (all 87 discarded jobs):
```
GPS coordinate validation failed: GPS coordinates required but unavailable
for venue 'X' in Y. Geocoding failed or returned no results.
```

## Why Jobs Are Being Discarded

The failure chain:

1. **Rate Limiting Fails** → Multiple workers hit OSM simultaneously
2. **OSM Returns HTML** → Jason.DecodeError
3. **Geocoding Fails** → Returns `{:error, :osm_rate_limited}`
4. **Retry Logic** → Oban retries, but hits rate limit again
5. **Eventually Returns Nil** → `{:ok, enriched}` with `latitude: nil, longitude: nil`
6. **VenueProcessor Rejects** → Database requires coordinates
7. **Error Contains "GPS"** → Processor marks job for discard
8. **Oban Discards** → Permanent failure, venue never created

The real issue is twofold:
- **Immediate**: Broken rate limiting causes OSM failures
- **Downstream**: VenueProcessor requires coordinates (can't handle nil)

## The Correct Solution

### Part 1: Implement Global Rate Limiting with Hammer

**Create Rate Limiter Module**:

```elixir
# lib/eventasaurus_discovery/rate_limiter/osm.ex
defmodule EventasaurusDiscovery.RateLimiter.OSM do
  @moduledoc """
  Global rate limiter for OpenStreetMap Nominatim API.

  Enforces 1 request per second across all workers using ETS-backed Hammer.
  """
  use Hammer, backend: :ets
end
```

**Add to Supervision Tree**:

```elixir
# lib/eventasaurus_discovery/application.ex
def start(_type, _args) do
  children = [
    # ... existing children
    {EventasaurusDiscovery.RateLimiter.OSM, clean_period: :timer.minutes(10)}
  ]

  opts = [strategy: :one_for_one, name: EventasaurusDiscovery.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**Update AddressGeocoder**:

```elixir
# lib/eventasaurus_discovery/helpers/address_geocoder.ex
alias EventasaurusDiscovery.RateLimiter.OSM

defp try_openstreetmaps(address) do
  # Check global rate limit BEFORE making request
  case OSM.hit("osm_geocoding", :timer.seconds(1), 1) do
    {:allow, _count} ->
      # Within rate limit - make request
      Logger.debug("Geocoding with OpenStreetMaps: #{address}")

      try do
        case Geocoder.call(address) do
          {:ok, coordinates} ->
            extract_location_data(coordinates, "OpenStreetMaps")
          {:error, reason} ->
            Logger.debug("OpenStreetMaps failed: #{inspect(reason)}")
            {:error, :osm_failed}
        end
      rescue
        Jason.DecodeError ->
          Logger.warning("⚠️ OSM returned HTML for: #{address}")
          {:error, :osm_rate_limited}
        error ->
          Logger.error("❌ OSM error for #{address}: #{inspect(error)}")
          {:error, :osm_failed}
      catch
        :exit, {:timeout, _} ->
          Logger.warning("⏱️ OSM timeout for: #{address}")
          {:error, :osm_timeout}
      end

    {:deny, retry_after_ms} ->
      # Rate limit exceeded - return retryable error
      Logger.info("⏱️ OSM rate limit reached, Oban will retry. Retry after: #{retry_after_ms}ms")
      {:error, :osm_rate_limited}
  end
end
```

**Remove Retry Logic**:

The existing `try_openstreetmaps_with_retry` function should be simplified to just call `try_openstreetmaps` once, since Oban handles retries with exponential backoff.

```elixir
# Remove this function or simplify to single call
defp try_openstreetmaps_with_retry(address, attempts_left \\ 3) do
  # Just call once, let Oban handle retries
  try_openstreetmaps(address)
end
```

### Part 2: Make Coordinates Optional (Testing Mode)

To measure OSM success rate, we need to allow venues without coordinates:

```elixir
# lib/eventasaurus_discovery/scraping/processors/venue_processor.ex

# Around line 671-673, update error handling:
defp create_venue_from_data(data, city, source_scraper) do
  case VenueStore.create_venue(data, city, source_scraper) do
    {:ok, venue} ->
      {:ok, venue}

    {:error, changeset} ->
      errors = format_changeset_errors(changeset)

      # TEMPORARY: Allow venues without coordinates for OSM testing
      # Check if it's ONLY a coordinate error
      if has_only_coordinate_errors?(changeset) do
        Logger.warning(
          "⚠️ Creating venue '#{data.name}' without coordinates for OSM testing. " <>
          "Geocoding failed or unavailable."
        )

        # Try creating venue with explicit nil coordinates
        data_with_nil_coords = Map.merge(data, %{latitude: nil, longitude: nil})

        case VenueStore.create_venue(data_with_nil_coords, city, source_scraper) do
          {:ok, venue} -> {:ok, venue}
          {:error, _} ->
            {:error, "Failed to create venue: #{errors}"}
        end
      else
        {:error, "Failed to create venue: #{errors}"}
      end
  end
end

# Add helper to check if ONLY coordinates are missing
defp has_only_coordinate_errors?(changeset) do
  errors = changeset.errors
  coord_errors = Keyword.take(errors, [:latitude, :longitude])

  # True if we have coordinate errors and no other errors
  length(coord_errors) > 0 and length(errors) == length(coord_errors)
end
```

**And update the Venue schema**:

```elixir
# lib/eventasaurus_app/venues/venue.ex

# Make latitude/longitude optional temporarily
def changeset(venue, attrs) do
  venue
  |> cast(attrs, [..., :latitude, :longitude, ...])
  # Comment out coordinate validation for testing
  # |> validate_required([..., :latitude, :longitude, ...])
  |> validate_required([..., <other fields>, ...])  # Remove lat/lng
  # ... rest of validations
end
```

## Expected Behavior After Fix

### Scenario 1: OSM Succeeds
```
Worker 1: Check rate limit → {:allow, 1} → Call OSM → Success → Coordinates extracted
Worker 2: Check rate limit → {:deny, 1000} → Return error → Oban retries later
Worker 3: Check rate limit → {:deny, 1000} → Return error → Oban retries later

Result: Worker 1 creates venue with coordinates ✅
        Workers 2 & 3 retry after backoff ✅
```

### Scenario 2: OSM Can't Find Address
```
Worker 1: Check rate limit → {:allow, 1} → Call OSM → {:error, :not_found}
         → Return nil coordinates → Venue created without coords ✅

Result: Venue created, marked for manual geocoding later
```

### Scenario 3: OSM Timeout
```
Worker 1: Check rate limit → {:allow, 1} → Call OSM → Timeout after 5s
         → Return {:error, :osm_timeout} → Oban retries ✅

Result: Job retried, may succeed on next attempt
```

## Success Metrics

After implementing the fix, measure:

```sql
-- Total venues processed
SELECT COUNT(*) as total FROM venues
WHERE inserted_at > NOW() - INTERVAL '1 hour';

-- Venues with coordinates (OSM success)
SELECT COUNT(*) as with_coords FROM venues
WHERE inserted_at > NOW() - INTERVAL '1 hour'
AND latitude IS NOT NULL
AND longitude IS NOT NULL;

-- Venues without coordinates (OSM failure)
SELECT COUNT(*) as without_coords FROM venues
WHERE inserted_at > NOW() - INTERVAL '1 hour'
AND (latitude IS NULL OR longitude IS NULL);

-- Calculate success rate
SELECT
  COUNT(*) FILTER (WHERE latitude IS NOT NULL) * 100.0 / COUNT(*) as success_rate
FROM venues
WHERE inserted_at > NOW() - INTERVAL '1 hour';
```

**Target**: >90% success rate with OSM-only geocoding

## Testing Plan

1. **Deploy Fix**:
   - Create OSM rate limiter module
   - Add to supervision tree
   - Update AddressGeocoder to use Hammer
   - Make coordinates optional in Venue schema

2. **Run Scraper**:
   - Trigger Question One scraper
   - Monitor logs for rate limit behavior
   - Watch for OSM success vs. failure patterns

3. **Measure Results**:
   - Count venues with coordinates vs. without
   - Calculate OSM success rate
   - Review failed addresses (manual spot check)

4. **Decision**:
   - If >90% success: Keep coordinates optional, OSM is working well
   - If 80-90% success: Evaluate if acceptable or need Google fallback for edge cases
   - If <80% success: Need to re-enable Google fallback or improve OSM queries

## Implementation Checklist

- [ ] Create `lib/eventasaurus_discovery/rate_limiter/osm.ex`
- [ ] Add OSM rate limiter to supervision tree
- [ ] Update `AddressGeocoder.try_openstreetmaps/1` to use Hammer
- [ ] Simplify or remove `try_openstreetmaps_with_retry/2`
- [ ] Make coordinates optional in Venue schema
- [ ] Update VenueProcessor error handling for nil coordinates
- [ ] Add logging to track OSM success vs. failure rates
- [ ] Deploy to staging/production
- [ ] Run test scraper
- [ ] Measure success rate
- [ ] Document findings

## Files to Change

1. `lib/eventasaurus_discovery/rate_limiter/osm.ex` - New file
2. `lib/eventasaurus_discovery/application.ex` - Add to supervision tree
3. `lib/eventasaurus_discovery/helpers/address_geocoder.ex` - Use Hammer
4. `lib/eventasaurus_app/venues/venue.ex` - Make coords optional
5. `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex` - Handle nil coords

## Why Hammer Instead of Process.sleep?

| Feature | Process.sleep | Hammer |
|---------|--------------|--------|
| **Scope** | Per-worker (local) | Global (all workers) |
| **Coordination** | None | ETS-backed shared state |
| **Effectiveness** | ❌ Fails with parallel workers | ✅ Works across all workers |
| **Retry After** | Unknown | Returns exact retry time |
| **Token Bucket** | No | Yes (proper rate limiting) |
| **Production Ready** | No | Yes |

## Expected Timeline

- **Implementation**: 1-2 hours
- **Testing**: 30 minutes (one scraper run)
- **Analysis**: 15 minutes (query database, calculate rates)
- **Total**: ~3 hours

## Related Issues

- #1658 - Original geocoding cost reduction implementation
- #1661 - Closed (incorrect analysis)

---

**Priority**: P0 - Critical
**Estimated Effort**: 3 hours
**Success Criteria**: >90% OSM geocoding success rate
