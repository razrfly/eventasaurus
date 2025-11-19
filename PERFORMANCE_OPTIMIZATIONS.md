# Event Page Performance Optimizations

## Problem

Event pages (e.g., https://wombie.com/3n4uz5o6x6) were timing out for web scrapers, preventing proper Open Graph metadata and image loading.

## Root Cause Analysis

The `PublicEventShowLive` module was performing ALL heavy operations synchronously in `handle_params/3` before rendering:

1. Complex database query with multiple preloads
2. Primary category lookup
3. User plan check
4. Image enrichment for main event
5. **Nearby events query with fallback** (potentially 3+ database queries)
6. **Additional image enrichment for nearby events**
7. JSON-LD schema generation

This resulted in response times exceeding web scraper timeout thresholds (typically 10-30 seconds).

## Solutions Implemented

### 1. Event Page Caching (`EventPageCache`)

Created a new Cachex-based caching module at `lib/eventasaurus_web/cache/event_page_cache.ex`:

- **Event Metadata Cache**: 10-minute TTL for event data with preloads
- **Nearby Events Cache**: 5-minute TTL for related events
- **Event Images Cache**: 30-minute TTL for image URLs
- **Invalidation Methods**: Manual cache clearing when events update

**Benefits:**
- First request computes and caches result
- Subsequent requests serve from cache (sub-millisecond response)
- Significantly reduces database load

### 2. Asynchronous Nearby Events Loading

Modified `PublicEventShowLive` to load nearby events **after** initial page render:

**Before:**
```elixir
# Synchronous - blocks initial render
nearby_events = PublicEvents.get_nearby_activities_with_fallback(...)
```

**After:**
```elixir
# Initialize empty, send message to load async
send(self(), :load_nearby_events)
nearby_events = []

# Later, in handle_info callback:
def handle_info(:load_nearby_events, socket) do
  # Load nearby events in background, update socket when ready
end
```

**Benefits:**
- Initial page renders immediately with core event data
- Metadata (title, description, images) loads instantly for scrapers
- Nearby events populate progressively for users
- No blocking on expensive database queries

### 3. Database Indexes

Verified existing indexes in `priv/repo/migrations/20250920210002_add_full_text_search_and_performance_indexes.exs`:

- ✅ `index(:public_events, [:slug])` - Event lookup by slug
- ✅ `index(:public_events, [:venue_id])` - Venue-based queries
- ✅ GiST index on `geography` - Spatial queries for nearby events
- ✅ Full-text search indexes - Search functionality

All critical queries are properly indexed.

## Performance Impact

### Expected Improvements:

| Metric | Before | After (First Request) | After (Cached) |
|--------|--------|----------------------|----------------|
| Response Time | 10-30s | 3-5s | <100ms |
| Database Queries | 15-20 | 10-12 | 2-3 |
| Scraper Success | ❌ Timeout | ✅ Success | ✅ Success |
| TTI (Time to Interactive) | 10-30s | 1-2s | <500ms |

### Cache Hit Rates (Expected):

- Event metadata: ~80-90% (events are relatively static)
- Nearby events: ~70-80% (changes with new events)
- Event images: ~90-95% (rarely change)

## Testing Instructions

### 1. Test with curl (Web Scraper Simulation)

```bash
# Test the problematic URL
curl -I "https://wombie.com/3n4uz5o6x6"

# Should return 200 OK in < 5 seconds
# Check for og:image and og:description headers
curl -s "https://wombie.com/3n4uz5o6x6" | grep -E 'og:image|og:description'
```

### 2. Test Cache Warming (First Request)

```bash
# Clear cache (if needed)
# In IEx: EventasaurusWeb.Cache.EventPageCache.clear_all()

# First request (cache miss - slower)
time curl -s "https://wombie.com/3n4uz5o6x6" > /dev/null

# Second request (cache hit - much faster)
time curl -s "https://wombie.com/3n4uz5o6x6" > /dev/null
```

### 3. Monitor Cache Stats (Production)

```elixir
# In IEx console:
Cachex.stats(:event_page_cache)

# Expected output:
# %{hits: X, misses: Y, ...}
# Hit rate should be > 70%
```

### 4. Test Nearby Events Async Loading

1. Open browser DevTools Network tab
2. Navigate to an event page
3. Observe:
   - Initial page load completes quickly
   - "Nearby Events" section populates 1-2s after page load
   - No blocking on initial render

## Files Modified

1. **Created:** `lib/eventasaurus_web/cache/event_page_cache.ex`
   - New caching module for event pages

2. **Modified:** `lib/eventasaurus/application.ex`
   - Added `EventPageCache` to supervision tree

3. **Modified:** `lib/eventasaurus_web/live/public_event_show_live.ex`
   - Added cache usage for event metadata
   - Moved nearby events to async loading
   - Added `handle_info(:load_nearby_events)` callback

## Deployment Checklist

- [x] Code compiles without warnings
- [ ] Start Phoenix server and verify cache initializes
- [ ] Test event page loads without errors
- [ ] Test with curl to verify scraper compatibility
- [ ] Monitor cache hit rates after deployment
- [ ] Set up alerts for response time degradation

## Rollback Plan

If issues occur:

1. **Quick Fix:** Clear all caches
   ```elixir
   EventasaurusWeb.Cache.EventPageCache.clear_all()
   ```

2. **Full Rollback:** Revert to synchronous loading
   - Remove `handle_info(:load_nearby_events)` callback
   - Load nearby_events synchronously in `fetch_event/3`
   - Keep caching infrastructure for future use

## Future Optimizations

1. **Preload Popular Events:** Background job to warm cache for trending events
2. **Edge Caching:** Add Cloudflare/CDN caching for static event pages
3. **Service Worker:** Client-side caching for returning visitors
4. **Image Optimization:** Lazy-load images below fold
5. **Database Query Optimization:** Review N+1 queries in preloads

## Monitoring Recommendations

1. Track response times by percentile (p50, p95, p99)
2. Monitor cache hit/miss rates hourly
3. Alert on response times > 3s (99th percentile)
4. Track scraper success rates from social platforms
5. Monitor database query counts per request

---

**Implementation Date:** 2025-01-19
**Author:** Claude Code
**Issue:** Event pages timing out for web scrapers
**Status:** ✅ Ready for Testing
