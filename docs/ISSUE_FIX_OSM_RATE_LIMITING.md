# Fix Broken OpenStreetMap Rate Limiting Implementation

**Status**: 🔴 Critical
**Root Cause**: `Process.sleep()` doesn't work for parallel workers
**Impact**: OSM returning rate limit errors, causing 60% job failure rate

## Problem

Our rate limiting implementation is fundamentally broken. We use `Process.sleep(1000)` which does NOT provide global rate limiting across parallel workers.

### Current Broken Code

```elixir
# lib/eventasaurus_discovery/helpers/address_geocoder.ex:197-202
defp try_openstreetmaps(address) do
  Process.sleep(1000)  # ❌ BROKEN - each worker sleeps independently!

  case Geocoder.call(address) do
    {:ok, coordinates} -> extract_location_data(coordinates, "OpenStreetMaps")
    {:error, reason} -> {:error, :osm_failed}
  end
end
```

### What Actually Happens

With 3 parallel Oban workers:

```
t=0ms:    Worker 1 starts sleep(1000)
t=0ms:    Worker 2 starts sleep(1000)
t=0ms:    Worker 3 starts sleep(1000)
          ↓ (all sleeping in parallel)
t=1000ms: Worker 1 wakes up → calls OSM
t=1000ms: Worker 2 wakes up → calls OSM  ← Same millisecond!
t=1000ms: Worker 3 wakes up → calls OSM  ← Same millisecond!
```

**Result**: All 3 workers hit OSM simultaneously, violating the 1 req/sec rate limit.

**OSM Response**: Returns HTML rate limit page instead of JSON

**Our Code**: Gets Jason.DecodeError, returns `{:error, :osm_rate_limited}`

**Job Outcome**: Retries eventually exhaust, geocoding fails, job discarded

## Evidence

```sql
-- Jobs after our "fix" (post 9:56am)
SELECT state, COUNT(*) FROM oban_jobs
WHERE scheduled_at > '2025-10-12 09:56:00';

discarded | 87   -- 60% failure rate ❌
completed | 58   -- Only 40% succeed
```

## The Solution: Proper Global Rate Limiting with Hammer

We already have Hammer configured in the project. We just need to use it correctly.

### Step 1: Create Rate Limiter Module

```elixir
# lib/eventasaurus_discovery/rate_limiter/osm.ex
defmodule EventasaurusDiscovery.RateLimiter.OSM do
  @moduledoc """
  Global rate limiter for OpenStreetMap Nominatim API.

  Enforces strict 1 request per second across ALL workers using ETS-backed Hammer.
  This ensures compliance with OSM's usage policy.
  """
  use Hammer, backend: :ets
end
```

### Step 2: Add to Supervision Tree

```elixir
# lib/eventasaurus_discovery/application.ex
def start(_type, _args) do
  children = [
    # ... existing children ...
    {EventasaurusDiscovery.RateLimiter.OSM, clean_period: :timer.minutes(10)}
  ]

  opts = [strategy: :one_for_one, name: EventasaurusDiscovery.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Step 3: Update AddressGeocoder

```elixir
# lib/eventasaurus_discovery/helpers/address_geocoder.ex
alias EventasaurusDiscovery.RateLimiter.OSM

defp try_openstreetmaps(address) do
  # CRITICAL: Check global rate limit BEFORE making request
  # Returns {:allow, count} or {:deny, retry_after_ms}
  case OSM.hit("osm_geocoding", :timer.seconds(1), 1) do
    {:allow, _count} ->
      # Within rate limit - proceed with request
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
          Logger.warning("⚠️ OSM returned HTML for: #{address} (rate limited despite check)")
          {:error, :osm_rate_limited}

        error ->
          Logger.error("❌ OSM error for #{address}: #{inspect(error)}")
          {:error, :osm_failed}
      catch
        :exit, {:timeout, _} ->
          Logger.warning("⏱️ OSM timeout for: #{address}")
          {:error, :osm_timeout}

        :exit, reason ->
          Logger.error("❌ OSM exited: #{inspect(reason)}")
          {:error, :osm_crashed}
      end

    {:deny, retry_after_ms} ->
      # Rate limit exceeded - return retryable error
      # Oban will retry this job with exponential backoff
      Logger.info("⏱️ OSM rate limit reached, job will retry in #{retry_after_ms}ms")
      {:error, :osm_rate_limited}
  end
end
```

### Step 4: Simplify Retry Logic

Remove the manual retry logic since Oban handles retries:

```elixir
# Remove or simplify this function
defp try_openstreetmaps_with_retry(address, _attempts_left \\ 3) do
  # Just call once - let Oban handle retries with exponential backoff
  try_openstreetmaps(address)
end
```

## How This Works

### Scenario: Multiple Workers Try to Geocode

```
t=0ms:
  Worker 1: OSM.hit(...) → {:allow, 1} ✅
           → Makes OSM request

  Worker 2: OSM.hit(...) → {:deny, 1000} ❌
           → Returns {:error, :osm_rate_limited}
           → Oban retries later

  Worker 3: OSM.hit(...) → {:deny, 1000} ❌
           → Returns {:error, :osm_rate_limited}
           → Oban retries later

t=1000ms:
  Worker 2: (retrying) OSM.hit(...) → {:allow, 1} ✅
           → Makes OSM request

t=2000ms:
  Worker 3: (retrying) OSM.hit(...) → {:allow, 1} ✅
           → Makes OSM request
```

**Result**: True 1 req/sec rate limiting, all jobs eventually succeed

## Why Hammer Instead of Process.sleep?

| Feature | Process.sleep | Hammer |
|---------|--------------|--------|
| **Scope** | Per-worker (local) | Global (all workers) |
| **Shared State** | None | ETS-backed |
| **Works with Parallel Workers** | ❌ No | ✅ Yes |
| **Provides Retry Time** | No | Yes (retry_after_ms) |
| **Token Bucket Algorithm** | No | Yes |
| **Production Ready** | No | Yes |

## Expected Behavior After Fix

### If OSM Successfully Geocodes
```
Worker calls OSM → Gets coordinates → Venue created with lat/lng ✅
```

### If OSM Can't Find Address
```
Worker calls OSM → Returns error → Falls back to Google Maps API
→ Venue created with Google coordinates (costs $0.037) ⚠️
```

### If Rate Limited
```
Worker denied by Hammer → Job returns retryable error
→ Oban retries after backoff → Eventually succeeds ✅
```

## Testing & Validation

After deploying the fix:

1. **Monitor Rate Limiting**:
```elixir
# Check Hammer is working
EventasaurusDiscovery.RateLimiter.OSM.hit("test", :timer.seconds(1), 1)
# First call: {:allow, 1}
# Second call: {:deny, ~1000}
```

2. **Run Question One Scraper**:
```bash
# Trigger scraper and watch logs
mix run -e "EventasaurusDiscovery.Sources.QuestionOne.trigger_scrape()"
```

3. **Check Success Rate**:
```sql
-- Venues created in last hour
SELECT COUNT(*) as total FROM venues
WHERE inserted_at > NOW() - INTERVAL '1 hour';

-- Check if OSM is working
SELECT
  metadata->'geocoding'->>'provider' as provider,
  COUNT(*) as count
FROM venues
WHERE inserted_at > NOW() - INTERVAL '1 hour'
GROUP BY provider;

-- Expected: Most should be 'openstreetmap'
```

4. **Monitor Job Success Rate**:
```sql
-- Should be 90%+ success rate
SELECT state, COUNT(*) FROM oban_jobs
WHERE inserted_at > NOW() - INTERVAL '1 hour'
AND worker LIKE '%VenueDetail%'
GROUP BY state;
```

## Success Criteria

✅ Only 1 OSM request per second (enforced globally)
✅ Jobs succeed or retry (no permanent discards due to rate limiting)
✅ OSM used for 90%+ of geocoding (Google only for OSM failures)
✅ API costs remain low (<10% Google usage)

## Implementation Checklist

- [ ] Create `lib/eventasaurus_discovery/rate_limiter/osm.ex`
- [ ] Add OSM rate limiter to supervision tree in `application.ex`
- [ ] Update `address_geocoder.ex` to use `OSM.hit(...)` instead of `Process.sleep`
- [ ] Simplify/remove manual retry logic
- [ ] Test Hammer rate limiter works correctly
- [ ] Deploy and monitor
- [ ] Run scraper and verify success rate
- [ ] Document actual OSM success rate

## Files to Change

1. `lib/eventasaurus_discovery/rate_limiter/osm.ex` - **New file**
2. `lib/eventasaurus_discovery/application.ex` - Add supervisor child
3. `lib/eventasaurus_discovery/helpers/address_geocoder.ex` - Replace Process.sleep with Hammer

## Timeline

- **Implementation**: 1 hour
- **Testing**: 30 minutes
- **Validation**: 30 minutes (run scraper, check results)
- **Total**: ~2 hours

---

**Priority**: P0 - Critical
**Related**: #1658, #1661 (closed), #1663 (closed)
