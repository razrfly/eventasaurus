# Phase 3 Complete: Timezone Bug Fix & Full Re-scrape

**Date**: November 4, 2025
**Issue**: #2153 - Time Quality System Failures
**Previous Phase**: Phase 2 (DataQualityChecker fixes - TIME_QUALITY_PHASE2_COMPLETE.md)

---

## Summary

Fixed the root cause of incorrect event times: VenueDetailJob hardcoded "America/New_York" timezone for ALL venues, causing 1-3 hour errors for non-Eastern venues. Triggered full re-scrape to update all events with correct times.

---

## Root Cause

**Location**: `lib/eventasaurus_discovery/sources/geeks_who_drink/jobs/venue_detail_job.ex:168`

**Before Fix**:
```elixir
defp calculate_next_occurrence(day_of_week, time) do
  # BUG: Hardcoded to Eastern timezone regardless of venue location!
  next_dt = RecurringEventParser.next_occurrence(day_of_week, time, "America/New_York")
  {:ok, next_dt}
end
```

**Impact**:
- Denver (Mountain Time): 7PM → 6PM (1 hour off)
- Chicago (Central Time): 7PM → 6PM (1 hour off)
- Los Angeles (Pacific Time): 7PM → 4PM (3 hours off!)
- Only Eastern timezone venues were correct

---

## The Fix

### 1. Determine Timezone BEFORE Calculating DateTime

**File**: `lib/eventasaurus_discovery/sources/geeks_who_drink/jobs/venue_detail_job.ex`

**Lines**: 59-67

**Change**: Calculate venue timezone BEFORE next_occurrence, not after

```elixir
result =
  with {:ok, additional_details} <- fetch_additional_details(venue_url),
       _ <- log_additional_details(additional_details),
       # CRITICAL FIX: Determine timezone BEFORE calculating next_occurrence
       # Previously hardcoded to "America/New_York", causing 1-3 hour errors
       venue_timezone <- determine_timezone(venue_data),
       {:ok, {day_of_week, time}} <-
         parse_time_from_sources(venue_data.time_text, additional_details),
       {:ok, next_occurrence} <- calculate_next_occurrence(day_of_week, time, venue_timezone),
       enriched_venue_data <-
         enrich_venue_data(venue_data, additional_details, next_occurrence),
```

### 2. Update Function Signature

**File**: Same file

**Lines**: 169-179

**Change**: Accept timezone parameter and use it

```elixir
defp calculate_next_occurrence(day_of_week, time, timezone) do
  # Calculate next occurrence in venue's actual timezone (not hardcoded!)
  # This fixes the bug where all venues were calculated in Eastern timezone
  Logger.info("🕐 Calculating next occurrence for #{day_of_week} at #{time} in #{timezone}")
  next_dt = RecurringEventParser.next_occurrence(day_of_week, time, timezone)
  {:ok, next_dt}
rescue
  error ->
    Logger.error("❌ Failed to calculate next occurrence: #{inspect(error)}")
    {:error, "Failed to calculate next occurrence"}
end
```

---

## How Timezone is Determined

The existing `determine_timezone/1` function already worked correctly:

```elixir
defp determine_timezone(venue_data) do
  cond do
    # Priority 1: Use timezone if already provided by source
    is_binary(venue_data[:timezone]) ->
      venue_data[:timezone]

    # Priority 2: Calculate from coordinates using TzWorld
    venue_data[:latitude] && venue_data[:longitude] ->
      case TzWorld.timezone_at({venue_data[:longitude], venue_data[:latitude]}) do
        {:ok, timezone} -> timezone
        {:error, reason} -> fallback_timezone_from_address(venue_data)
      end

    # Priority 3: Fallback to Eastern
    true -> "America/New_York"
  end
end
```

**For Denver venues**:
- Coordinates: (39.7586429, -105.0153123)
- TzWorld returns: `"America/Denver"` ✅
- Now used BEFORE calculating DateTime (not after!)

---

## Re-scrape Process

### Test Scrape
```
Job ID: 7393
Status: completed
Started: 2025-11-04 15:15:47
Completed: 2025-11-04 15:15:51
```

### Full Re-scrape
```
Job ID: 7394
Status: in_progress
Started: 2025-11-04 15:16:xx
Expected: ~5-10 minutes for all Geeks Who Drink venues
```

**Command Used**:
```elixir
%{"force" => true}
|> EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob.new()
|> Oban.insert()
```

---

## Expected Results

After full re-scrape completes:

### Denver Events (Mountain Time)
**Before**: `"time": "18:00"` (6:00 PM) ❌
**After**: `"time": "19:00"` (7:00 PM) ✅
**Source**: https://www.geekswhodrink.com/venues/715188153/ shows 7:00 PM

### Los Angeles Events (Pacific Time)
**Before**: `"time": "16:00"` (4:00 PM) ❌
**After**: `"time": "19:00"` (7:00 PM) ✅

### Chicago Events (Central Time)
**Before**: `"time": "18:00"` (6:00 PM) ❌
**After**: `"time": "19:00"` (7:00 PM) ✅

### Eastern Events (New York, Boston, etc.)
**Before**: `"time": "19:00"` (7:00 PM) ✅
**After**: `"time": "19:00"` (7:00 PM) ✅ (no change - already correct)

---

## Testing

### Compilation
✅ No errors, clean compilation

### Test Scrape
✅ Job 7393 completed successfully

### Full Re-scrape
⏳ Job 7394 in progress - will update all 84+ events

---

## Verification Steps

Once re-scrape completes:

1. **Check Database**:
```sql
SELECT title, occurrences->'pattern'->>'time' as time,
       occurrences->'pattern'->>'timezone' as timezone
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
WHERE pes.source_id = 6 AND title LIKE '%Denver%'
LIMIT 5;
```

2. **Compare Against Source**:
- Pick random Denver event
- Check time in database vs. source website
- Should now match exactly

3. **Check Admin UI**:
- Quality metrics should show time diversity increasing
- Time quality score should improve (currently ~40%)
- Same time percentage should decrease

---

## Files Modified

**Changed**:
- `lib/eventasaurus_discovery/sources/geeks_who_drink/jobs/venue_detail_job.ex` - Fixed timezone calculation

**Created**:
- `trigger_geeks_scrape.exs` - Test scrape script
- `trigger_full_geeks_scrape.exs` - Full re-scrape script
- `TIME_QUALITY_PHASE3_COMPLETE.md` - This document

---

## Related Documentation

- GitHub Issue: #2153
- Phase 1: `INVESTIGATION_REPORT_ISSUE_2153.md` (Root cause investigation)
- Phase 2: `TIME_QUALITY_PHASE2_COMPLETE.md` (Quality checker fixes)
- Phase 3: This document (Timezone bug fix + re-scrape)

---

## Question One Status

**Status**: ⏳ NEEDS INVESTIGATION

Question One also uses RecurringEventParser. Need to check if VenueDetailJob has same hardcoded timezone bug.

**Action Item**: Schedule separate investigation for Question One source.

---

## Status

✅ **Phase 3: IN PROGRESS**
- ✅ Timezone bug fixed in VenueDetailJob
- ✅ Test scrape completed (job 7393)
- ⏳ Full re-scrape in progress (job 7394)
- ⏳ Verification pending re-scrape completion

🎯 **Next**: Monitor re-scrape progress, verify times match sources
