# Issue: Venue Image Operations Page Not Working

**URL**: `http://localhost:4000/admin/geocoding/operations/:city_slug` (e.g., `/admin/geocoding/operations/krakow`)

**Status**: 🔴 **BROKEN** - Page loads blank, shows no data

**Severity**: High - Critical admin visibility lost

**Date Discovered**: 2025-10-24

---

## Problem Statement

The venue image operations page at `/admin/geocoding/operations/:city_slug` is completely blank and shows no data, even though:

1. ✅ We have 36 total Oban jobs in the database (11 BackfillOrchestratorJob, 25 EnrichmentJob)
2. ✅ We have successful image uploads (2 venues with images in venue_images JSONB field)
3. ✅ We have failed jobs with detailed error information (7 discarded EnrichmentJob)
4. ✅ The route is correctly configured in router.ex
5. ✅ The LiveView file exists and compiles

**User Need**: A unified admin dashboard to monitor ALL venue image enrichment operations (successes, partial failures, and complete failures) with granular retry capabilities.

---

## Root Cause Analysis

### Primary Issue: Wrong Worker Name in Query

**File**: `lib/eventasaurus_web/live/admin/geocoding_operations_live.ex:94`

```elixir
# CURRENT (BROKEN) - queries for non-existent worker
where: j.worker == "EventasaurusDiscovery.VenueImages.BackfillJob"
```

**Database Reality**:
```sql
-- Actual workers in oban_jobs table:
SELECT worker, COUNT(*) FROM oban_jobs WHERE worker LIKE '%Venue%' GROUP BY worker;

EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob   | 11 jobs
EventasaurusDiscovery.VenueImages.EnrichmentJob             | 25 jobs
EventasaurusDiscovery.VenueImages.BackfillJob               | 0 jobs  ❌ DOESN'T EXIST
```

**Result**: Query returns 0 rows → page shows empty table → blank screen

### Secondary Issues

1. **Misleading Page Name**: Called "Geocoding Operations" but actually shows venue image enrichment data
2. **Split Visibility**: Two separate pages exist:
   - `/admin/geocoding/operations/:city_slug` (broken, shows city-wide backfills)
   - `/admin/venue-images/operations` (new, shows individual venue enrichments)
3. **No Partial Failure Detection**: Neither page shows venues with mixed success/failure (e.g., 3/5 images uploaded successfully)
4. **No Granular Retry**: Can only retry all failed uploads, not individual venues or specific failed images

---

## Database Investigation Results

### Available Data Sources

#### 1. Oban Jobs (Primary Source)

**BackfillOrchestratorJob** (City-Wide Operations):
```json
{
  "worker": "EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob",
  "args": {
    "city_id": 5,
    "limit": 1,
    "geocode": true,
    "providers": ["google_places"]
  },
  "meta": {
    "total_venues": 10,
    "enriched": 8,
    "skipped": 1,
    "failed": 1,
    "by_provider": { "google_places": 8 },
    "total_cost_usd": 0.0
  }
}
```

**EnrichmentJob** (Individual Venue Operations):
```json
{
  "worker": "EventasaurusDiscovery.VenueImages.EnrichmentJob",
  "args": {
    "venue_id": 9,
    "geocode": true,
    "providers": ["google_places"]
  },
  "meta": {
    "status": "no_images",
    "summary": "Failed - google_places encountered errors",
    "providers": {
      "google_places": {
        "status": "failed",
        "reason": "\"API error: REQUEST_DENIED\""
      }
    },
    "images_discovered": 0,
    "images_uploaded": 0,
    "images_failed": 0,
    "failed_images": [],
    "imagekit_urls": [],
    "total_cost_usd": 0.0,
    "execution_time_ms": 3185
  },
  "errors": [
    {
      "at": "2025-10-24T17:11:34.115801Z",
      "error": "** (Oban.PerformError) ... REQUEST_DENIED ...",
      "attempt": 3
    }
  ]
}
```

#### 2. Venue Images (Partial Failure Source)

**venues.venue_images JSONB** (Per-Image Status):
```json
[
  {
    "url": "https://ik.imagekit.io/wombie/venues/noce-krk/gp-848af5.jpg",
    "provider": "google_places",
    "provider_url": "https://maps.googleapis.com/maps/api/place/photo?...",
    "upload_status": "uploaded",
    "quality_score": 1.0,
    "fetched_at": "2025-10-24T11:34:26.592309Z",
    "imagekit_path": "/venues/noce-krk/gp-848af5.jpg"
  },
  {
    "provider": "google_places",
    "provider_url": "https://maps.googleapis.com/maps/api/place/photo?...",
    "upload_status": "failed",
    "error_details": {
      "error_type": "rate_limited",
      "status_code": 429,
      "message": "Too many requests"
    },
    "fetched_at": "2025-10-24T11:34:26.592315Z"
  }
]
```

**Key Fields**:
- `upload_status`: `"uploaded"`, `"failed"`, `"permanently_failed"`
- `error_details`: Error type, status code, message (present only on failures)
- `provider_url`: Original URL for retry without calling provider API again
- `quality_score`: Image quality rating (0.0-1.0)

### Current Data State

```sql
-- Job Distribution
BackfillOrchestratorJob: 11 jobs (all completed)
EnrichmentJob:           25 jobs (18 completed, 7 discarded/failed)

-- Venues with Images
Total venues with venue_images: 2
  - Globus Music Club (id: 10): 1 image
  - Noce KRK (id: 14): 6 images

-- Failed EnrichmentJobs
7 discarded jobs with REQUEST_DENIED errors (Google API key issue)
```

---

## User Requirements

### Primary Need: Unified Operations Dashboard

**What the user wants**:
> "I want ONE page that shows me ALL image enrichment activity - whether it was a city-wide backfill or a single venue retry. I need to see what succeeded, what partially failed, and what completely failed. And I need to be able to retry failed operations at a granular level."

### Specific Requirements

1. **Unified View**: Show BOTH BackfillOrchestratorJob AND EnrichmentJob in one table
2. **Partial Failure Detection**: Highlight venues with mixed success/failure (e.g., 3/5 images uploaded)
3. **Success/Failure Visibility**: Clear visual indicators for complete success, partial failure, complete failure
4. **Granular Retry Controls**:
   - Retry all failed uploads for a city (batch)
   - Retry all failed uploads for a specific venue (individual)
   - Retry specific failed images for a venue (granular)
5. **Real-Time Updates**: Auto-refresh to show retry progress
6. **Provider Filtering**: Filter operations by provider (Google Places, Foursquare, etc.)
7. **Error Details**: Expandable rows showing detailed error information per failed image
8. **Image Gallery**: Visual preview of successfully uploaded images

### Navigation & Naming

**Current Problem**:
- Page is called "Geocoding Operations" but shows image data
- URL path `/geocoding/operations` is misleading

**Proposed Fix**:
- Rename to "Venue Image Enrichment Operations"
- Consider URL: `/admin/venue-images/operations` (or keep city-specific URLs)

---

## Technical Solution Plan

### Option 1: Fix Existing Page (Quickest)

**Changes Needed**:
1. Update worker query to include both workers:
   ```elixir
   where: j.worker in [
     "EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob",
     "EventasaurusDiscovery.VenueImages.EnrichmentJob"
   ]
   ```

2. Update enrich_operation/1 to handle both job types
3. Add city_id extraction for EnrichmentJob (from venue lookup)
4. Update page title and breadcrumbs

**Pros**:
- ✅ Minimal code changes
- ✅ Preserves existing URL structure
- ✅ Fixes blank page immediately

**Cons**:
- ❌ Still has misleading "geocoding" name
- ❌ Mixed job types may have different metadata structures
- ❌ Doesn't address partial failure visibility

### Option 2: Consolidate Into venue_image_operations_live.ex (Better)

**Changes Needed**:
1. Expand `/admin/venue-images/operations` to support optional city filtering:
   - `/admin/venue-images/operations` → all operations
   - `/admin/venue-images/operations?city=krakow` → city-specific

2. Query both BackfillOrchestratorJob and EnrichmentJob

3. Add partial failure detection:
   ```elixir
   defp detect_partial_failures(job) do
     venue_id = extract_venue_id(job)
     venue = Repo.get(Venue, venue_id)

     failed_count = count_images_by_status(venue, ["failed", "permanently_failed"])
     uploaded_count = count_images_by_status(venue, ["uploaded"])

     cond do
       failed_count > 0 and uploaded_count > 0 -> :partial_failure
       failed_count > 0 -> :complete_failure
       uploaded_count > 0 -> :success
       true -> :no_images
     end
   end
   ```

4. Add granular retry handlers:
   ```elixir
   # Retry all failed for a venue
   def handle_event("retry_venue", %{"venue_id" => id}, socket)

   # Retry specific failed images
   def handle_event("retry_images", %{"venue_id" => id, "image_indexes" => indexes}, socket)
   ```

5. Add expandable rows showing per-image status with retry buttons

**Pros**:
- ✅ Unified page with correct naming
- ✅ Supports partial failure detection
- ✅ Granular retry controls
- ✅ Better user experience

**Cons**:
- ❌ More code changes required
- ❌ Need to migrate existing `/geocoding/operations` links

### Option 3: New Unified Dashboard (Best Long-Term)

**Create**: `/admin/venue-images/enrichment-history`

**Features**:
1. Tabbed interface:
   - **All Operations** (default)
   - **City Backfills** (BackfillOrchestratorJob)
   - **Individual Venues** (EnrichmentJob)
   - **Partial Failures** (venues with mixed status)
   - **Failed Only** (discarded jobs + venues with all failed images)

2. Advanced filtering:
   - By provider (Google Places, Foursquare, etc.)
   - By status (success, partial, failed)
   - By date range
   - By city

3. Bulk actions:
   - Retry all transient failures
   - Retry selected venues
   - Export results to CSV

4. Real-time updates via Phoenix PubSub

**Pros**:
- ✅ Best user experience
- ✅ Scalable for future features
- ✅ Clear separation of concerns

**Cons**:
- ❌ Most development effort
- ❌ Requires careful design

---

## Questions to Answer Before Implementation

1. **Do we need to preserve the city-specific URL pattern** (`/operations/:city_slug`)?
   - If yes → Fix existing page (Option 1)
   - If no → Consolidate or create new (Option 2/3)

2. **What level of retry granularity is needed**?
   - City-level only → Simple fix
   - Venue-level → Medium complexity
   - Per-image level → High complexity

3. **Should we show historical data or just recent operations**?
   - Recent only (last 50 jobs) → Current approach is fine
   - Full history → Need pagination

4. **Do we need to keep existing data**?
   - Yes → All solutions preserve data
   - No → Could clean up old jobs

5. **Is the Google API key issue blocking testing**?
   - Yes → Fix API key first (already identified in previous session)
   - No → Can test with existing successful jobs

---

## Recommended Approach

**Recommendation**: **Option 2 - Consolidate Into venue_image_operations_live.ex**

**Rationale**:
1. Fixes the broken page with correct worker names
2. Provides unified view the user is asking for
3. Enables partial failure detection and granular retry
4. Reasonable development effort
5. Better naming and URL structure

**Implementation Steps**:

### Step 1: Fix Worker Query (Immediate)
- Update `geocoding_operations_live.ex` line 94 to use correct worker names
- Test that page shows data

### Step 2: Add Partial Failure Detection
- Create helper function to detect mixed success/failure in venue_images
- Add visual indicators (badges, icons) for partial failures

### Step 3: Add Granular Retry
- Implement venue-level retry handler
- Implement per-image retry handler
- Add retry buttons to UI

### Step 4: Consolidate Pages
- Merge functionality into single page
- Update navigation and breadcrumbs
- Deprecate old geocoding operations page

### Step 5: Test & Validate
- Test with real data (both BackfillOrchestratorJob and EnrichmentJob)
- Verify retry functionality works
- Ensure partial failures are correctly detected

---

## Data Migration Needs

**Answer**: ✅ **NO migration needed**

All necessary data already exists in the database:
- Oban jobs with detailed metadata ✅
- venue_images JSONB with per-image status ✅
- Error details for failed operations ✅
- Provider URLs for retry without API calls ✅

---

## Deployment Checklist

- [ ] Fix worker name in query (immediate fix)
- [ ] Test page loads with data
- [ ] Implement partial failure detection
- [ ] Add venue-level retry functionality
- [ ] Add per-image retry functionality
- [ ] Update page title and breadcrumbs
- [ ] Update navigation links
- [ ] Test with real failed uploads
- [ ] Document new retry workflow
- [ ] Update admin guide

---

## Related Issues & Documentation

- **Google API Key Issue**: Fixed API key permissions for Places API (previous session)
- **Phase 3 Implementation**: `.github/PHASE3_IMPLEMENTATION_SUMMARY.md`
- **Admin Button**: `.github/ADMIN_BUTTON_IMPLEMENTATION.md`
- **Venue Image Operations Page**: `.github/VENUE_IMAGE_OPERATIONS_PAGE.md`

---

## Next Steps

1. **Decide on approach** (Option 1, 2, or 3)
2. **Fix worker name immediately** (one-line change to unblock)
3. **Implement chosen solution** following steps above
4. **Test with real data** including partial failures
5. **Deploy and monitor** retry functionality

---

**Created**: 2025-10-24
**Last Updated**: 2025-10-24
**Status**: 🔴 Awaiting Decision on Approach
