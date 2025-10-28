# 🐛 Critical Regression: Venue Image Geocoding Functionality Broken

## Summary

The venue image enrichment geocoding feature (reverse geocoding to obtain Google provider IDs) was accidentally disabled in commit `8bc263fd` ("fixes for organ" - Oct 26, 2025). This regression prevents venues without Google Places provider IDs from successfully fetching images from Google Places API.

## Impact

**Severity:** High - Core feature completely non-functional

**Affected Functionality:**
- Venues missing `provider_ids.google_places` cannot fetch Google images
- BackfillOrchestratorJob's documented `geocode: true` parameter is ignored
- Reverse geocoding feature implemented in commit `537e5d9a` (Oct 23) is broken

**User Impact:**
- Many venues cannot get images from Google Places (one of our primary image sources)
- Backfill jobs silently fail to geocode venues that need it
- Manual intervention required to add provider IDs for affected venues

## Root Cause Analysis

### The Bug

In `lib/eventasaurus_discovery/venue_images/backfill_orchestrator_job.ex`, the `spawn_enrichment_jobs/3` function was modified to ignore the options parameter:

**Before (Working - commit a8f5d1ac, Oct 25):**
```elixir
defp spawn_enrichment_jobs(venues, providers, opts) do
  geocode = Keyword.get(opts, :geocode, false)
  force = Keyword.get(opts, :force, false)

  jobs =
    Enum.map(venues, fn venue ->
      EventasaurusDiscovery.VenueImages.EnrichmentJob.new(%{
        venue_id: venue.id,
        providers: providers,
        geocode: geocode,  # ✅ Passed to job
        force: force
      })
    end)
  # ...
end
```

**After (Broken - commit 8bc263fd, Oct 26):**
```elixir
defp spawn_enrichment_jobs(venues, providers, _opts) do  # ❌ opts parameter ignored!
  jobs =
    Enum.map(venues, fn venue ->
      EventasaurusDiscovery.VenueImages.EnrichmentJob.new(%{
        venue_id: venue.id,
        providers: providers,
        force: true  # ❌ Hardcoded, geocode parameter completely removed
      })
    end)
  # ...
end
```

### Timeline of Changes

1. **Oct 23 (537e5d9a - "google changes")** ✅
   - Implemented reverse geocoding feature in EnrichmentJob
   - Added `geocode` parameter to BackfillOrchestratorJob
   - Feature working as designed

2. **Oct 25 (a8f5d1ac - "fixes for rrrrabbit")** ✅
   - No changes to geocoding functionality
   - Still working

3. **Oct 26 (8bc263fd - "fixes for organ")** ❌ **REGRESSION INTRODUCED**
   - Changed `opts` to `_opts` (explicitly ignored parameter)
   - Removed extraction of `geocode` and `force` from options
   - Hardcoded `force: true`
   - Completely removed passing `geocode` to EnrichmentJob

### Developer Intent vs. Actual Result

**Intended Change:**
The commit comment suggests the developer wanted to always use `force: true` because the SQL query already filters for staleness:

```elixir
# IMPORTANT: We pass force: true because find_venues_without_images SQL query
# already filtered for staleness using last_checked_at + cooldown period.
```

**Unintended Consequence:**
While hardcoding `force: true` may have been intentional, the developer also removed the `geocode` parameter, which is completely unrelated to staleness logic. This appears to be an accidental deletion.

## Technical Details

### How Geocoding Should Work

1. BackfillOrchestratorJob is called with `geocode: true`:
```elixir
BackfillOrchestratorJob.enqueue(
  city_id: 5,
  provider: "google_places",
  limit: 10,
  geocode: true  # Request reverse geocoding
)
```

2. The orchestrator spawns EnrichmentJobs with the geocode parameter
3. EnrichmentJob checks if venue needs geocoding via `needs_geocoding?/2`
4. If needed, calls `reverse_geocode_venue/2` which:
   - Uses Geocoding.Orchestrator to get provider IDs from address
   - Updates venue with the obtained provider IDs
   - Proceeds to fetch images using the new provider IDs

### Current Behavior (Broken)

1. BackfillOrchestratorJob receives `geocode: true`
2. The parameter is **ignored** (underscore prefix in `_opts`)
3. EnrichmentJob is created **without** the geocode parameter
4. Venues without provider IDs fail to fetch images
5. No error is raised - it silently fails

## Evidence

### Git History Analysis

```bash
# Original working implementation (Oct 23)
$ git show 537e5d9a:lib/eventasaurus_discovery/venue_images/backfill_orchestrator_job.ex | grep -A 12 "defp spawn_enrichment_jobs"
defp spawn_enrichment_jobs(venues, providers, opts) do
  geocode = Keyword.get(opts, :geocode, false)
  force = Keyword.get(opts, :force, false)
  # ... passes both parameters to EnrichmentJob

# Broken implementation (Oct 26 - current)
$ git show 8bc263fd:lib/eventasaurus_discovery/venue_images/backfill_orchestrator_job.ex | grep -A 12 "defp spawn_enrichment_jobs"
defp spawn_enrichment_jobs(venues, providers, _opts) do  # ❌ Parameter ignored
  # ... only passes force: true (hardcoded)
```

### Module Documentation vs. Reality

The module documentation promises geocoding support:

**From backfill_orchestrator_job.ex:22-23:**
```elixir
# Backfill with geocoding fallback for venues missing provider IDs
BackfillOrchestratorJob.enqueue(city_id: 5, provider: "google_places", limit: 10, geocode: true)
```

But this parameter is completely ignored in the current implementation.

## Affected Code Paths

### Files Involved

1. **lib/eventasaurus_discovery/venue_images/backfill_orchestrator_job.ex**
   - Line 136: Passes `geocode: geocode` to spawn_enrichment_jobs
   - Line 157: `spawn_enrichment_jobs/3` ignores the opts parameter
   - Lines 168-172: Creates EnrichmentJob without geocode parameter

2. **lib/eventasaurus_discovery/venue_images/enrichment_job.ex**
   - Lines 103-104: Reads `geocode` parameter from job args (never receives it)
   - Lines 296-322: `needs_geocoding?/2` function (never called due to missing parameter)
   - Lines 324-366: `reverse_geocode_venue/2` function (never called)

## Reproduction Steps

1. Find a venue without Google Places provider ID:
```elixir
venue = Repo.get_by(Venue, id: some_venue_id)
venue.provider_ids["google_places"]  # => nil
```

2. Attempt backfill with geocoding:
```elixir
BackfillOrchestratorJob.enqueue(
  city_id: venue.city_id,
  provider: "google_places",
  limit: 1,
  geocode: true
)
```

3. Observe failure:
- Job completes without errors
- No images are fetched from Google Places
- Venue's provider_ids are not updated
- Error: `INVALID_REQUEST` or similar from Google Places API

## Expected Behavior

1. BackfillOrchestratorJob should pass `geocode: true` to EnrichmentJob
2. EnrichmentJob should detect missing Google Places provider ID
3. EnrichmentJob should call reverse_geocode_venue to get the ID
4. Venue's provider_ids should be updated with Google Places ID
5. Images should be successfully fetched using the new provider ID

## Solution

### The Fix

Restore the parameter extraction in `spawn_enrichment_jobs/3`:

```elixir
defp spawn_enrichment_jobs(venues, providers, opts) do  # ✅ Use opts, not _opts
  # Extract geocode parameter (force can remain hardcoded if that was intentional)
  geocode = Keyword.get(opts, :geocode, false)

  jobs =
    Enum.map(venues, fn venue ->
      EventasaurusDiscovery.VenueImages.EnrichmentJob.new(%{
        venue_id: venue.id,
        providers: providers,
        geocode: geocode,  # ✅ Pass geocode to job
        force: true  # Keep hardcoded if intentional
      })
    end)

  # ... rest of function
end
```

### Design Decision: Force Parameter

The commit intentionally hardcoded `force: true` with the reasoning that the SQL query already filters for staleness. If this was the intended behavior, we should:

**Option A:** Keep force hardcoded, only restore geocode
```elixir
geocode = Keyword.get(opts, :geocode, false)
# force is always true - SQL handles staleness
```

**Option B:** Restore both parameters for maximum flexibility
```elixir
geocode = Keyword.get(opts, :geocode, false)
force = Keyword.get(opts, :force, true)  # Default to true
```

**Recommendation:** Option A is sufficient. The force parameter being hardcoded appears intentional based on the commit message, but the geocode parameter removal was clearly accidental.

## Testing Requirements

### Unit Tests Needed

1. Test that BackfillOrchestratorJob passes geocode parameter to EnrichmentJob
2. Test that EnrichmentJob receives and respects the geocode parameter
3. Test that venues without provider IDs trigger reverse geocoding when geocode=true

### Integration Tests Needed

1. End-to-end test of backfill with geocoding for venue without provider ID
2. Verify provider_ids are updated after successful geocoding
3. Verify images are fetched after geocoding completes

### Manual Testing

After fix is deployed:
1. Find venues in database with no Google Places provider ID
2. Run backfill with `geocode: true`
3. Verify provider IDs are added
4. Verify images are successfully fetched

## Related Issues

- #1978 - Original PR implementing geocoding feature (Oct 23)
- #2020 - PR where regression may have been introduced (Oct 25-26)
- This relates to venues discovered via Foursquare/HERE that need Google IDs

## Priority Justification

**High Priority** because:
1. Core feature completely broken (not degraded)
2. Affects significant percentage of venues (those without Google provider IDs)
3. Google Places is a primary image source
4. Silent failure - no errors raised, difficult to detect
5. Simple fix with low risk
6. Already causing production issues

## Next Steps

1. Apply the fix to restore geocode parameter passing
2. Add test coverage to prevent regression
3. Backfill affected venues that failed due to this bug
4. Consider adding telemetry to detect when geocoding should trigger but doesn't
5. Update commit messages/PR descriptions to be more descriptive about breaking changes

---

**Discovered:** 2025-10-28
**Regression Introduced:** 2025-10-26 (commit 8bc263fd)
**Commits Analyzed:** 537e5d9a → a8f5d1ac → 8bc263fd
**Analysis Method:** Git history audit with sequential analysis
