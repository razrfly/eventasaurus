# Phase 4: Time Extraction Fix - Solution Summary

**Date**: November 4, 2025
**Status**: ✅ EXTRACTION FIXED | ⏳ DATABASE UPDATE PENDING

---

## Problem Identified

Phase 3 only fixed **timezone calculation** but missed **time extraction bug**:
- VenueDetailsExtractor was failing to extract times from HTML
- Falling back to hardcoded "20:00" when extraction failed
- Result: 100% of events showing 8PM regardless of actual time

---

## Solution Implemented

### File: `lib/eventasaurus_discovery/sources/geeks_who_drink/extractors/venue_details_extractor.ex`

**Changes (Lines 265-323)**:

1. **Added Two-Strategy Time Extraction**:
   - **Strategy 1** (NEW): Parse `data-time` attribute from `.time-moment-date` selector
   - **Strategy 2** (EXISTING): Parse visible text in "7:00 pm" format

2. **Removed Hardcoded Fallbacks**:
   - No more `"20:00"` fallback
   - Return `nil` on extraction failure
   - Added logging for failures

3. **ISO 8601 DateTime Parsing with UTC-to-Local Conversion**:
   ```elixir
   case DateTime.from_iso8601(data_time) do
     {:ok, dt, _offset} ->
       # Convert UTC time to local time using best-effort heuristics
       # Full timezone detection happens later via TzWorld in VenueDetailJob
       convert_utc_to_local_time(dt)
     _ ->
       Logger.warning("⚠️ Failed to parse data-time: #{time_str}")
       nil
   end
   ```

   The `convert_utc_to_local_time/1` function applies heuristics to convert UTC times to likely local times for US venues (most trivia happens 6-9 PM local, which is 00:00-04:00 UTC across US timezones).

---

## Verification

### Test Script: `test_time_extraction_fix.exs`

**Rosso Pomodoro Pizza Venue Test**:
- **Source URL**: https://www.geekswhodrink.com/venues/2936708819/
- **Source Shows**: 6:00 PM (Thursdays at 6:00 pm)
- **HTML Data**: `<span class="time-moment-date" data-time="2025-11-06T18:00:00+00:00"></span>`
- **Extracted Time**: ✅ **18:00** (correct!)
- **Previous Extraction**: ❌ null → fallback to "20:00"

**Test Result**: 🎉 **SUCCESS! Time extraction is now correct!**

---

## Current Database State

**Quality Report** (mix quality.check geeks-who-drink):
- Total Events: 418
- Overall Score: 88% (Good)
- **Issue**: ⚠️ Suspicious time pattern: 100.0% of events at 20:00
- **Reason**: Events were scraped BEFORE the fix was deployed

---

## Next Steps to Complete Fix

### Option 1: Trigger Full Re-scrape (RECOMMENDED)

Wait for next scheduled IndexJob run OR manually trigger:

```bash
mix run -e "alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.IndexJob; %{\"source_id\" => 6, \"force\" => true} |> IndexJob.new() |> Oban.insert!()"
```

**Note**: IndexJob may skip venues if they're considered "fresh" (updated within 7 days). Force mode should override this, but needs investigation why it's not working.

### Option 2: Manual Database Update (QUICK TEST)

Directly update one event to prove fix works:

```sql
-- Example: Update Rosso event with correct time
UPDATE public_events pe
SET occurrences = jsonb_set(
  occurrences,
  '{pattern,time}',
  '"18:00"'
)
WHERE slug = 'geeks-who-drink-trivia-at-rosso-rosso-pomodoro-pizza-251107';
```

### Option 3: Delete & Re-create Events

Delete all Geeks Who Drink events and let next scrape recreate them with correct times.

---

## Investigation Needed

### Why IndexJob Isn't Scheduling Detail Jobs

**Observations**:
1. IndexJob completes successfully (no errors)
2. But schedules 0 VenueDetailJobs
3. Even with `force: true` parameter

**Possible Causes**:
1. EventFreshnessChecker filtering out all venues
2. API returning empty venue list
3. Force parameter not being properly handled
4. Venues being filtered by another mechanism

**Files to Check**:
- `lib/eventasaurus_discovery/sources/geeks_who_drink/jobs/index_job.ex` (lines 181-227)
- `lib/eventasaurus_discovery/services/event_freshness_checker.ex`

---

## Code Changes Summary

**Files Modified**:
1. ✅ `lib/eventasaurus_discovery/sources/geeks_who_drink/extractors/venue_details_extractor.ex`
   - Added data-time attribute parsing
   - Removed hardcoded fallbacks
   - Added comprehensive logging

**Files Created**:
1. ✅ `test_time_extraction_fix.exs` - Verification script
2. ✅ `trigger_geeks_index_phase4.exs` - Re-scrape trigger script
3. ✅ `ISSUE_2153_PHASE3_FAILURE_ANALYSIS.md` - Problem analysis
4. ✅ `PHASE_4_SOLUTION_SUMMARY.md` - This file

---

## Success Criteria

- [x] Time extraction works correctly (verified with test script)
- [ ] Database events updated with correct times
- [ ] Quality check shows time diversity > 0%
- [ ] Manual verification: sample events match source websites

---

## Expected Quality Report After Fix

```
Quality Report: geeks-who-drink
============================================================
Overall Score: 92%+ 🟢 Excellent

Dimensions:
  Time Quality: 90%+ ✅
  Time diversity: 40%+ (multiple different times)

No suspicious time patterns detected
```

---

## Rollout Plan

1. **Immediate**: Code is deployed and compiled ✅
2. **Test**: Extraction verified with test script ✅
3. **Update**: Trigger re-scrape of all venues (PENDING)
4. **Verify**: Run quality check to confirm fix (PENDING)
5. **Monitor**: Check sample events match sources (PENDING)
