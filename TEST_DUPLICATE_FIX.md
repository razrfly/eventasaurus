# Testing Advisory Lock Duplicate Prevention

## Overview

This document describes how to test the PostgreSQL advisory lock implementation that prevents duplicate venue creation during concurrent scraping.

## Root Cause

**TOCTOU Race Condition**: When multiple Oban workers process the same venue simultaneously, they can all check for duplicates BEFORE any of them commits, resulting in duplicate insertions.

**Evidence**: Database timestamps showed duplicate venues created 1 second apart or in the same second, proving concurrent worker race conditions.

## Solution Implemented

PostgreSQL advisory locks (`pg_advisory_xact_lock`) serialize venue insertions at the same location:

1. Round coordinates to 3 decimals (~50m grid)
2. Generate lock key: `:erlang.phash2({lat_rounded, lng_rounded, city_id})`
3. Acquire advisory lock in transaction
4. Perform duplicate check (protected by lock)
5. Insert if no duplicate, or return existing venue
6. Lock automatically released when transaction completes

**Location**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:702-800`

## Test Procedure

### 1. Clear Development Database

```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "DELETE FROM venues;"
```

### 2. Run UK Scrapers

These scrapers previously caused 1.2% duplicate rate:

```bash
mix run -e "EventasaurusDiscovery.Sources.QuestionOne.run_scraper()"
mix run -e "EventasaurusDiscovery.Sources.Inquizition.run_scraper()"
mix run -e "EventasaurusDiscovery.Sources.GeekyQuiz.run_scraper()"
```

### 3. Check for Duplicates

```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "
WITH duplicate_groups AS (
  SELECT
    name,
    ROUND(latitude::numeric, 6) as lat,
    ROUND(longitude::numeric, 6) as lng,
    COUNT(*) as duplicate_count,
    array_agg(id ORDER BY id) as venue_ids,
    array_agg(inserted_at ORDER BY id) as insertion_times
  FROM venues
  GROUP BY name, ROUND(latitude::numeric, 6), ROUND(longitude::numeric, 6)
  HAVING COUNT(*) > 1
)
SELECT
  COUNT(*) as duplicate_groups,
  SUM(duplicate_count) as total_duplicate_venues,
  (SELECT COUNT(*) FROM venues) as total_venues,
  ROUND(100.0 * SUM(duplicate_count) / (SELECT COUNT(*) FROM venues), 2) as duplicate_percentage
FROM duplicate_groups;
"
```

**Expected Result**: `duplicate_groups = 0`, `duplicate_percentage = 0.00%`

### 4. Verify Advisory Lock Logs

Check application logs for lock acquisition messages:

```bash
tail -f /tmp/scraper_test.log | grep "🔒"
```

**Expected Output**:
```
🔒 Acquired advisory lock 123456 for venue 'Hope and Anchor' at (51.460, -0.127)
🏛️ ✅ Found existing venue in locked transaction: 'Hope and Anchor' (ID: 248)
🔓 Releasing lock 123456 after successful insert
```

### 5. Inspect Previously Problematic Venues

Query specific venues that were duplicated in previous tests:

```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "
SELECT id, name,
       ROUND(latitude::numeric, 7) as lat,
       ROUND(longitude::numeric, 7) as lng,
       provider_ids::text,
       geocoding_performance->>'source_scraper' as scraper,
       geocoding_performance->>'provider' as geo_provider,
       inserted_at
FROM venues
WHERE name LIKE '%Hope and Anchor%'
   OR name LIKE '%Islington Town%'
ORDER BY name, inserted_at;
"
```

**Expected Result**: Each venue should appear ONCE only.

## Previous Test Results (Before Fix)

**Baseline (with race conditions)**:
- Total venues: 346
- Duplicate groups: 2
- Total duplicates: 4 venues
- Duplicate rate: 1.2%

**Specific duplicates**:
1. **Hope and Anchor, Brixton**
   - IDs: 248 (09:54:08), 249 (09:54:09) - 1 second apart
   - GPS: 51.4595646, -0.1266272 (EXACT same coordinates)
   - Different geocoding providers (geoapify vs photon)

2. **Islington Town House**
   - IDs: 20, 22 (09:54:24) - same second
   - GPS: 51.5429153, -0.1030338 vs 51.5430000, -0.1030000 (10m apart)
   - Both had `provider="provided"` (coordinates from scraper)

## Success Criteria

✅ **Zero duplicates**: `duplicate_percentage = 0.00%`
✅ **Lock logging**: Advisory lock messages in logs
✅ **Performance**: No significant slowdown in scraping
✅ **All code paths**: Works for geocoded AND provided coordinates

## Troubleshooting

### If duplicates still appear:

1. Check lock key generation:
   ```elixir
   lock_key = :erlang.phash2({lat_rounded, lng_rounded, city_id})
   ```

2. Verify transaction wrapping:
   ```elixir
   Repo.transaction(fn ->
     Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])
     # ... duplicate check and insert ...
   end)
   ```

3. Confirm duplicate detection runs inside lock:
   ```elixir
   existing_venue = find_existing_venue(%{
     latitude: latitude,
     longitude: longitude,
     name: final_name,
     city_id: city.id
   })
   ```

### If performance degrades:

- Check for lock contention: `SELECT * FROM pg_locks WHERE locktype = 'advisory';`
- Review lock key distribution: ensure rounding doesn't create hot spots
- Consider increasing coordinate precision if too many venues lock on same key

## Reference

- **GitHub Issue**: #2110
- **Previous Attempts**: Branch `fix/duplicate-venues-attempt-1-app-level-checks`
- **Implementation**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:702-800`
