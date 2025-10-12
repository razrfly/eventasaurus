# Geocoding Implementation Audit - Post-Mortem Analysis

**Issue Date**: 2025-10-12
**Severity**: CRITICAL
**Status**: Implementation Failed - System Down

## Executive Summary

Our geocoding cost-reduction implementation (#1658) successfully prevented API costs but created a catastrophic failure: **100% of venue scraping jobs are now being discarded**. Zero venues have been created since the changes were deployed.

### Critical Metrics

| Metric | Before Changes | After Changes | Delta |
|--------|---------------|---------------|-------|
| Venues Created | 125 | 0 | -100% |
| Google API Calls | 125 (100%) | 0 (0%) | -$4.63 |
| Job Success Rate | ~46% | 0% | -46% |
| Jobs Discarded | 67 | 87 | +30% |

## What We Attempted

### Phase 1: Rate Limiting
**Objective**: Prevent parallel workers from violating OSM's 1 req/sec limit

**Implementation**:
```elixir
# lib/eventasaurus_discovery/helpers/address_geocoder.ex:202
Process.sleep(1000)  # Enforce 1 req/sec globally
```

**Result**: ✅ Successfully prevents parallel requests

### Phase 2: Disable Google Fallback
**Objective**: Prevent cost explosion by failing gracefully without Google API

**Implementation**:
```elixir
# lib/eventasaurus_discovery/helpers/address_geocoder.ex:117-130
{:error, reason} ->
  Logger.warning("⚠️ Geocoding FAILED for: #{address} (reason: #{reason}).
    Venue will be stored without coordinates. Expected failure rate: <10%.")

  metadata = MetadataBuilder.build_openstreetmap_metadata(address)
    |> MetadataBuilder.mark_failed(reason)

  {:error, :geocoding_failed, metadata}
```

**Result**: ✅ Google API calls prevented, but...

### Phase 3: User-Agent Header
**Objective**: Comply with OSM Nominatim usage policy

**Implementation**:
```elixir
# config/runtime.exs:42-48
config :geocoder, Geocoder.Providers.OpenStreetMaps,
  headers: [
    {"User-Agent", "Eventasaurus/1.0 (https://eventasaurus.com; support@eventasaurus.com)"}
  ]
```

**Result**: ✅ Policy compliance achieved

### Phase 4: Dashboard Query Fix
**Objective**: Make dashboard queries consistent with date filtering

**Implementation**: Added date filtering to `costs_by_provider/1` and `costs_by_scraper/1`

**Result**: ✅ Queries now consistent (but showing no new data)

## What Actually Happened

### The Failure Chain

1. **Scraper runs** → Question One venue detail jobs queued
2. **Geocoding called** → OSM returns data or fails
3. **OSM failures** → Return `{:ok, enriched}` with `latitude: nil, longitude: nil`
4. **VenueProcessor validation** → **REJECTS nil coordinates** (database constraint)
5. **Processor checks error** → Sees "GPS coordinates" keyword
6. **Job marked for discard** → Returns `{:discard, "GPS coordinate validation failed..."}`
7. **VenueDetailJob with clause** → Doesn't match `{:discard, ...}` → **WithClauseError**
8. **Oban** → Discards job permanently

### Database Evidence

```sql
-- Jobs after our changes (post 9:56am)
SELECT state, COUNT(*) FROM oban_jobs
WHERE scheduled_at > '2025-10-12 09:56:00';

executing | 3      -- Still running
discarded | 87     -- Failed permanently (60% of total)
completed | 58     -- Index/discovery jobs only
```

```sql
-- Venues created after our changes
SELECT COUNT(*) FROM venues WHERE inserted_at > '2025-10-12 09:56:00';
-- Result: 0
```

### Error Messages

All 87 discarded jobs show the same pattern:

```
** (WithClauseError) no with clause matching:
  {:discard, "GPS coordinate validation failed: GPS coordinates required
   but unavailable for venue 'Dog's Head, Bishops Stortford' in East Hertfordshire.
   Geocoding failed or returned no results."}
    (eventasaurus 0.1.0) lib/eventasaurus_discovery/sources/question_one/jobs/venue_detail_job.ex:44
```

## Root Cause Analysis

### Primary Issue: Architectural Mismatch

We created a fundamental incompatibility between system layers:

```
Geocoding Layer:    "Failures are acceptable, return nil coordinates"
                              ↓
Persistence Layer:  "Coordinates are REQUIRED, reject nil values"
                              ↓
Result:             All venues rejected, 100% failure rate
```

### Code Location of Conflict

**VenueProcessor** (lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:671-673):

```elixir
if has_coordinate_errors?(changeset) do
  {:error,
   "GPS coordinates required but unavailable for venue '#{name}' in #{city.name}.
    Geocoding failed or returned no results."}
end
```

**Processor** (lib/eventasaurus_discovery/sources/processor.ex:114-122):

```elixir
# Checks for GPS-related keywords in error messages
if String.contains?(String.downcase(reason), "gps coordinates") or
     String.contains?(String.downcase(reason), "latitude") or
     String.contains?(String.downcase(reason), "longitude") do
  {:error, {:discard, reason}}  # Mark job for permanent discard
end
```

**VenueDetailJob** (lib/eventasaurus_discovery/sources/question_one/jobs/venue_detail_job.ex:44):

```elixir
with {:ok, body} <- Client.fetch_venue_page(venue_url),
     {:ok, document} <- parse_document(body),
     {:ok, venue_data} <- VenueExtractor.extract_venue_data(...),
     {:ok, enriched} <- enrich_with_geocoding(venue_data),  # Returns {:ok, ...} with nil coords
     {:ok, transformed} <- transform_and_validate(enriched),
     {:ok, results} <- process_event(transformed, source_id) do  # Fails with {:discard, ...}
  # Success never reached
```

The `with` clause expects `{:ok, ...}` or `{:error, ...}` but receives `{:discard, ...}`, causing **WithClauseError**.

## Why This Wasn't Caught

### 1. Incomplete Testing
- Did not test full scraper workflow end-to-end
- Only verified geocoding module changes in isolation
- Assumed VenueDetailJob's error handling (lines 85-94) would work
- Didn't verify VenueProcessor's coordinate requirements

### 2. Hidden Dependencies
- Database schema requires coordinates (not obvious from code)
- VenueProcessor validation not documented in geocoding docs
- Processor's GPS keyword matching was unknown
- `{:discard, ...}` return format not in VenueDetailJob's pattern matching

### 3. Assumption Errors
- **Assumed**: "Expected failure rate <10%" meant system could handle failures
- **Reality**: ANY failures cause job discard due to coordinate requirement
- **Assumed**: VenueDetailJob's nil coordinate handling would suffice
- **Reality**: Downstream validation rejects nil coordinates entirely

## Impact Assessment

### Immediate Impact
- ✅ **Cost Savings**: $0.00 (prevented $4.63+ in API costs)
- ❌ **System Availability**: 0% (no venues being created)
- ❌ **Data Quality**: Stale (dashboard showing October 12 data only)
- ❌ **Job Queue**: 87 permanently discarded jobs (cannot be retried)

### Business Impact
- Zero new events being added to platform
- Users seeing outdated event information
- Scraper infrastructure non-functional
- Potential data loss (87 venues not captured)

## Lessons Learned

### What Went Right
1. **Cost Prevention**: Successfully prevented Google API costs
2. **Rate Limiting**: Properly enforced 1 req/sec OSM compliance
3. **Clear Logging**: Error messages are detailed and traceable
4. **Metadata Tracking**: Geocoding metadata properly preserved

### What Went Wrong
1. **No Integration Testing**: Changes tested in isolation, not end-to-end
2. **Incomplete Analysis**: Didn't trace full data flow to database
3. **Assumption-Driven**: Expected <10% failures, got 100%
4. **Missed Dependencies**: Didn't discover coordinate requirement

### Process Improvements Needed
1. **Mandatory Integration Tests**: Test full scraper workflow before deployment
2. **Database Schema Review**: Check constraints before data layer changes
3. **Error Path Testing**: Verify error handling through all layers
4. **Rollback Strategy**: Have immediate rollback plan for critical systems

## Proposed Solutions

### Option 1: Make Coordinates Optional (Recommended)
**Complexity**: Medium
**Risk**: Low
**Timeline**: 2-4 hours

**Changes Required**:
1. **Database Migration**: Make `latitude`/`longitude` nullable in `venues` table
2. **VenueProcessor**: Remove coordinate requirement validation
3. **EventProcessor**: Handle venues without coordinates (e.g., don't show on map)
4. **Frontend**: Gracefully display venues without GPS coordinates

**Pros**:
- Maintains free OSM geocoding
- Allows venue creation even when geocoding fails
- Aligns with original "fail gracefully" design intent
- Tracks failures via metadata for later batch processing

**Cons**:
- Some venues won't appear on map
- Requires frontend changes to handle missing coordinates
- May impact search/filtering features dependent on location

### Option 2: Re-enable Google Fallback (Not Recommended)
**Complexity**: Low
**Risk**: High (cost explosion)
**Timeline**: 30 minutes

**Changes Required**:
1. Uncomment Google fallback code in `AddressGeocoder.geocode_address_with_metadata/1`
2. Re-enable `GOOGLE_MAPS_API_KEY` in environment

**Pros**:
- Immediate fix, system functional again
- Existing architecture unchanged

**Cons**:
- Returns to original problem ($4.63+ per 125 venues)
- Rate limiting still causes 60% Google usage (not <10%)
- Does NOT solve underlying OSM reliability issues
- Defeats entire purpose of this project

### Option 3: Default Coordinates + Batch Processing
**Complexity**: High
**Risk**: Medium
**Timeline**: 4-6 hours

**Changes Required**:
1. Use default coordinates (e.g., Krakow city center: 50.0619, 19.9369)
2. Mark venues as `needs_geocoding: true` in metadata
3. Create batch geocoding script with proper rate limiting
4. Schedule periodic geocoding updates

**Pros**:
- Venues immediately visible (approximate location)
- Can retry geocoding later with better success rate
- Separates concerns: scraping vs. geocoding

**Cons**:
- Users see approximate locations initially
- Additional maintenance (batch script, monitoring)
- More complex system architecture

### Option 4: Separate Failed Venue Table
**Complexity**: High
**Risk**: Low
**Timeline**: 6-8 hours

**Changes Required**:
1. Create `failed_venues` table for geocoding failures
2. Store venues without coordinates separately
3. Manual review/batch geocoding workflow
4. Periodic retry with improved strategies

**Pros**:
- Clean separation of concerns
- Allows manual intervention for difficult cases
- Maintains data quality standards

**Cons**:
- Significantly more complex
- Requires manual review workflow
- Delays venue availability

## Recommended Action Plan

### Immediate (Next 1 Hour)
1. **Rollback**: Revert to Google Places API for Question One scraper only
2. **Enable Monitoring**: Set up alerts for API cost spikes
3. **Document Rollback**: Update issue #1658 with rollback status

### Short-term (Next 1-2 Days)
1. **Implement Option 1**: Make coordinates optional
2. **Write Integration Tests**: Full scraper workflow tests
3. **Test with OSM**: Verify 90%+ success rate with optional coordinates
4. **Deploy**: Gradual rollout with monitoring

### Long-term (Next 1-2 Weeks)
1. **Batch Geocoding Script**: For retrying failed venues
2. **Monitor OSM Success Rate**: Collect data on actual failure rates
3. **Optimize Rate Limiting**: Test if we can handle >1 req/sec
4. **Dashboard Enhancements**: Show venues with/without coordinates separately

## Files Requiring Changes

### For Option 1 (Recommended)
1. `priv/repo/migrations/XXXXXX_make_venue_coordinates_optional.exs` - Database migration
2. `lib/eventasaurus_app/venues/venue.ex` - Remove coordinate validation
3. `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex` - Allow nil coordinates
4. `lib/eventasaurus_discovery/sources/processor.ex` - Remove GPS error discard logic
5. `lib/eventasaurus_web/live/event_map_live.ex` - Handle venues without coordinates

### For Immediate Rollback
1. `lib/eventasaurus_discovery/helpers/address_geocoder.ex` - Uncomment Google fallback

## Success Criteria

### Phase 1 (Rollback)
- ✅ Venue scraping jobs succeeding (>80% success rate)
- ✅ New venues appearing in database
- ⚠️ Google API costs monitored (alert if >$10/day)

### Phase 2 (Optional Coordinates)
- ✅ Venue scraping jobs succeeding with OSM-only (>80% success rate)
- ✅ Venues created even when geocoding fails
- ✅ Zero Google API costs (OSM-only)
- ✅ <10% venues without coordinates
- ✅ Dashboard showing venues with/without coords

### Phase 3 (Long-term)
- ✅ Batch geocoding script operational
- ✅ Failed venues retried successfully (>50% recovery rate)
- ✅ OSM success rate >90%
- ✅ Total API costs <$5/month

## Conclusion

Our geocoding cost-reduction implementation achieved its primary goal (preventing Google API costs) but created a critical system failure by not accounting for downstream coordinate requirements. The system is currently non-functional for venue creation.

**Immediate action required**: Rollback to restore functionality
**Long-term solution**: Make coordinates optional to align layers
**Root cause**: Insufficient integration testing and incomplete dependency analysis

This serves as a critical lesson in the importance of end-to-end testing for infrastructure changes, especially those affecting core data pipelines.

---

**Created**: 2025-10-12
**Related Issues**: #1658
**Priority**: P0 (System Down)
**Assignee**: Infrastructure Team
