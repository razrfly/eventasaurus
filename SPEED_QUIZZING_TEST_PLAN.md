# Speed Quizzing Scraper - Test Plan

**Status**: ✅ Implementation Complete - Ready for Testing
**Date**: 2025-10-16
**Issue**: #1769

---

## 🎯 Implementation Summary

The Speed Quizzing scraper has been successfully implemented following the two-stage architecture:

1. **Phase 1-2**: Index Scraping (SyncJob → IndexJob) - ✅ Complete
2. **Phase 3**: Performer Cleaning (PerformerCleaner) - ✅ Complete
3. **Phase 4**: Venue Data Extraction (VenueExtractor) - ✅ Complete
4. **Phase 5**: Data Transformation & Processing (DetailJob + Transformer) - ✅ Complete

**All phases compile cleanly with no warnings.**

---

## 📋 Testing Checklist

### 1. Admin Dashboard Verification

**URL**: http://localhost:4000/admin/discovery

**Steps**:
1. Start the Phoenix server: `mix phx.server`
2. Navigate to the Discovery Dashboard
3. ✅ Verify "Speed Quizzing" appears in the source dropdown
4. ✅ Verify it shows "International (UK, US, UAE)" coverage
5. ✅ Verify no city selection is required (regional scope)

**Expected Result**: Speed Quizzing should be visible and selectable without city requirement.

---

### 2. Database Verification

**Steps**:
```bash
# Check source record exists
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT id, slug, name, is_active, priority, metadata->'scope' as scope FROM sources WHERE slug = 'speed-quizzing';"
```

**Expected Result**:
```
 id |      slug      |      name      | is_active | priority | scope
----+----------------+----------------+-----------+----------+----------
 13 | speed-quizzing | Speed Quizzing | t         |       35 | regional
```

---

### 3. Manual Import Test (Small Scale)

**Test with limit to avoid overwhelming the system on first run.**

**Steps**:
1. Go to Discovery Dashboard: http://localhost:4000/admin/discovery
2. Select "Speed Quizzing" from source dropdown
3. Set limit to **10** (small test batch)
4. Click "Start Import"
5. Monitor the import progress indicator
6. Check Oban dashboard for job execution

**Expected Workflow**:
```
SyncJob (fetch index)
  → Extract JSON with ~500+ events
  → IndexJob (process with EventFreshnessChecker)
  → Filter to fresh events (80-90% reduction expected on first run)
  → Enqueue DetailJobs (10 detail jobs for limit=10)
  → DetailJob #1: Fetch detail page → VenueExtractor → PerformerCleaner → Transformer → Processor
  → DetailJob #2-10: Same workflow
```

**Success Criteria**:
- ✅ SyncJob completes successfully
- ✅ IndexJob filters and enqueues DetailJobs
- ✅ ~10 DetailJobs execute (may be less if EventFreshnessChecker filters some)
- ✅ Events appear in PublicEvents table
- ✅ Venues appear in Venues table
- ✅ Performers appear in Performers table (if performer data extracted)
- ✅ No error logs in terminal

**Verification Queries**:
```bash
# Check events created
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT COUNT(*) FROM public_events pe
   JOIN public_event_sources pes ON pe.id = pes.event_id
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'speed-quizzing';"

# Check venues created
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT COUNT(*) FROM venues v
   JOIN public_events pe ON v.id = pe.venue_id
   JOIN public_event_sources pes ON pe.id = pes.event_id
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'speed-quizzing';"

# Check performers created
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT COUNT(DISTINCT p.id) FROM performers p
   JOIN public_event_performers pep ON p.id = pep.performer_id
   JOIN public_events pe ON pep.event_id = pe.id
   JOIN public_event_sources pes ON pe.id = pes.event_id
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'speed-quizzing';"

# View sample events
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT pe.title, pe.starts_at, pe.external_id, v.name as venue, v.city, v.country
   FROM public_events pe
   JOIN venues v ON pe.venue_id = v.id
   JOIN public_event_sources pes ON pe.id = pes.event_id
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'speed-quizzing'
   LIMIT 5;"
```

---

### 4. Oban Dashboard Monitoring

**URL**: http://localhost:4000/oban

**Steps**:
1. Navigate to Oban dashboard during import
2. Monitor queue: `scraper_index` (SyncJob, IndexJob)
3. Monitor queue: `scraper_detail` (DetailJobs)
4. Check for failed jobs in "Completed" or "Retrying" tabs

**Expected Behavior**:
- SyncJob appears in `scraper_index` queue
- IndexJob appears after SyncJob completes
- DetailJobs appear in `scraper_detail` queue in batch
- All jobs complete with state "completed"
- No jobs in "retrying" or "cancelled" state

**Common Issues to Check**:
- ❌ HTTP timeout errors → Increase timeout in config.ex
- ❌ JSON parsing errors → Check index page format hasn't changed
- ❌ Missing performer data → Check VenueExtractor selectors
- ❌ GPS parsing errors → Check coordinate format

---

### 5. Data Quality Verification

**After successful import, verify data quality:**

**5.1 Event Data Structure**
```bash
# Check event fields are populated correctly
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT
    pe.external_id,
    pe.title,
    pe.starts_at,
    pe.is_free,
    pe.min_price,
    pe.currency,
    pe.recurrence_rule,
    pe.metadata
   FROM public_events pe
   JOIN public_event_sources pes ON pe.id = pes.event_id
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'speed-quizzing'
   LIMIT 3;"
```

**Expected Fields**:
- ✅ `external_id`: `speed-quizzing-{event_id}`
- ✅ `title`: "SpeedQuizzing at {Venue Name}"
- ✅ `starts_at`: Valid DateTime in UTC
- ✅ `is_free`: false (Speed Quizzing charges fees)
- ✅ `min_price`: Float value (e.g., 2.0)
- ✅ `currency`: "GBP", "USD", "AED", or "AUD"
- ✅ `recurrence_rule`: JSON with weekly pattern
- ✅ `metadata`: Contains source info

**5.2 Venue Data Structure**
```bash
# Check venue fields
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT
    v.name,
    v.address,
    v.city,
    v.country,
    v.latitude,
    v.longitude,
    v.postcode
   FROM venues v
   JOIN public_events pe ON v.id = pe.venue_id
   JOIN public_event_sources pes ON pe.id = pes.event_id
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'speed-quizzing'
   LIMIT 3;"
```

**Expected Fields**:
- ✅ `name`: Venue name
- ✅ `address`: Full address
- ✅ `city`: Resolved from GPS or address
- ✅ `country`: "United Kingdom", "United States", "United Arab Emirates", etc.
- ✅ `latitude`: Float coordinate
- ✅ `longitude`: Float coordinate
- ✅ `postcode`: UK/US format

**5.3 Performer Data Structure**
```bash
# Check performer fields (if extracted)
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT DISTINCT
    p.name,
    p.image_url,
    p.metadata
   FROM performers p
   JOIN public_event_performers pep ON p.id = pep.performer_id
   JOIN public_events pe ON pep.event_id = pe.id
   JOIN public_event_sources pes ON pe.id = pes.event_id
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'speed-quizzing'
   LIMIT 3;"
```

**Expected Fields**:
- ✅ `name`: Clean name (no "★234" prefixes)
- ✅ `image_url`: Profile image URL or null
- ✅ `metadata`: Contains source info

**5.4 Recurrence Rule Validation**
```bash
# Check recurrence_rule format
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT
    pe.title,
    pe.recurrence_rule->>'frequency' as frequency,
    pe.recurrence_rule->>'days_of_week' as days,
    pe.recurrence_rule->>'time' as time,
    pe.recurrence_rule->>'timezone' as timezone
   FROM public_events pe
   JOIN public_event_sources pes ON pe.id = pes.event_id
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'speed-quizzing'
   AND pe.recurrence_rule IS NOT NULL
   LIMIT 3;"
```

**Expected Recurrence Rule**:
```json
{
  "frequency": "weekly",
  "days_of_week": ["tuesday"],
  "time": "19:00",
  "timezone": "Europe/London"
}
```

---

### 6. EventFreshnessChecker Validation

**Test freshness filtering on second run:**

**Steps**:
1. Complete first import with limit=10
2. Wait ~1 minute
3. Run second import with same limit=10
4. Check logs for freshness filtering

**Expected Behavior**:
```
📋 Enqueueing X detail jobs
(Y events skipped - recently updated)
```

**Where**:
- `X + Y = 10` (or fewer if index has fewer events)
- `Y ≈ 8-9` (80-90% reduction on second run within 7 days)

**Verification**:
- ✅ Second run should process significantly fewer DetailJobs
- ✅ `last_seen_at` timestamp should be updated on existing events
- ✅ No duplicate events created (check by `external_id`)

---

### 7. Full-Scale Import Test

**After successful small-scale test, test full import:**

**Steps**:
1. Select "Speed Quizzing" from source dropdown
2. **Leave limit empty** (will fetch ALL events)
3. Click "Start Import"
4. Monitor Oban dashboard for ~30-60 minutes

**Expected**:
- ✅ SyncJob fetches ~500+ events from index
- ✅ EventFreshnessChecker filters already-processed events
- ✅ DetailJobs process remaining events
- ✅ Total events in database: ~500+ (Speed Quizzing's global inventory)
- ✅ Multiple countries represented (UK, US, UAE)
- ✅ Multiple currencies (GBP, USD, AED, AUD)

**Performance Expectations**:
- IndexJob: ~5-10 seconds (fetch + parse JSON)
- EventFreshnessChecker: ~2-5 seconds (database query)
- DetailJob batch: ~5-10 minutes for 100 events (rate limited)
- Full import: ~30-60 minutes for 500 events

---

## 🐛 Troubleshooting Guide

### Issue: "Events JSON not found in page"

**Cause**: Index page HTML structure changed, or regex not matching JSON array format

**Note**: Fixed in commit - regex was changed from non-greedy `(.+?)` to greedy `(\[.+\])` to properly capture long JSON arrays (500+ events)

**Solution**:
1. Check `https://www.speedquizzing.com/find/` in browser
2. View source, search for `var events = JSON.parse(`
3. Verify pattern: `var events = JSON.parse('[...]');`
4. Update `SyncJob.extract_json_string/1` if pattern changed

---

### Issue: "Failed to parse HTML"

**Cause**: Floki parsing error

**Solution**:
1. Check DetailJob logs for event_id
2. Visit `https://www.speedquizzing.com/events/{event_id}/` manually
3. Verify page exists and loads correctly
4. Check VenueExtractor selectors still match HTML structure

---

### Issue: "Could not calculate starts_at"

**Cause**: Time parsing failure

**Solution**:
1. Check `venue_data.start_time` and `venue_data.day_of_week` values
2. Verify RecurringEventParser handles Speed Quizzing's time formats
3. Common formats: "8pm", "7.30pm", "7:30 PM"
4. Check logs for specific parsing error

---

### Issue: "Geocoding failed"

**Cause**: CityResolver couldn't resolve GPS to city

**Solution**:
1. This is expected for some venues - check logs
2. Transformer falls back to conservative address parsing
3. Verify fallback extracted city correctly from address
4. If city is nil, check address parsing logic in Transformer

---

### Issue: No performers extracted

**Cause**: Performer data not available or selectors changed

**Solution**:
1. Check detail page manually for host/performer info
2. Speed Quizzing performers are optional (not all events have them)
3. Verify VenueExtractor.extract_performer/1 selectors
4. Check PerformerCleaner for star prefix removal

---

### Issue: Duplicate events created

**Cause**: External ID collision or deduplication failure

**Solution**:
1. Check `external_id` format: `speed-quizzing-{event_id}`
2. Verify EventProcessor deduplication logic
3. Check if `event_id` from index is stable across runs
4. Run query: `SELECT external_id, COUNT(*) FROM public_events GROUP BY external_id HAVING COUNT(*) > 1`

---

## 📊 Success Metrics

After full-scale import, verify these metrics:

✅ **Events Created**: ~500+ total events
✅ **Venues Created**: ~300-400 unique venues
✅ **Performers Created**: ~50-100 unique performers
✅ **Countries**: 3+ (UK, US, UAE minimum)
✅ **Recurrence Rules**: 100% of events have weekly recurrence
✅ **GPS Coordinates**: 100% of venues have lat/lng
✅ **Cities Resolved**: 90%+ venues have city name
✅ **Freshness Filtering**: 80-90% reduction on second run

---

## 🚀 Ready for Testing

**Implementation Status**: ✅ **COMPLETE**

**Next Steps**:
1. **YOU ARE HERE** → Start with Section 3: Manual Import Test (limit=10)
2. Monitor Section 4: Oban Dashboard
3. Verify Section 5: Data Quality
4. Test Section 6: EventFreshnessChecker
5. Complete Section 7: Full-Scale Import (if small test successful)

**Source Dashboard Location**:
- http://localhost:4000/admin/discovery
- Select "Speed Quizzing" from dropdown
- It's under the "Regional" category (no city selection needed)

**Source Database Record**:
- ID: 13
- Slug: `speed-quizzing`
- Priority: 35 (regional specialist)
- Scope: `regional` (multi-country coverage)

---

## 📝 Implementation Notes

### Architecture Pattern
Speed Quizzing follows the **two-stage scraping pattern**:
1. **Index Stage**: Fetch embedded JSON from `/find/` page
2. **Detail Stage**: Fetch individual event pages for full data

### Key Features Implemented
- ✅ EventFreshnessChecker integration (7-day window)
- ✅ RecurringEventParser for weekly events
- ✅ CityResolver for GPS → city resolution
- ✅ Multi-timezone support (UK, US, UAE, Australia)
- ✅ Multi-currency support (GBP, USD, AED, AUD)
- ✅ PerformerCleaner for removing star prefixes ("★234")
- ✅ Processor.process_source_data/3 (unified processing)
- ✅ Stable external_id for deduplication

### Reference Implementation
Based on trivia_advisor Speed Quizzing scraper, adapted for Eventasaurus architecture following Quizmeisters patterns.

---

**Last Updated**: 2025-10-16
**Status**: ✅ Ready for Testing
