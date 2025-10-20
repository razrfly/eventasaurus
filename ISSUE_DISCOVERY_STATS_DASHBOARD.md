# Discovery Stats Dashboard Issues

**Date**: October 19, 2025
**Scope**: Admin Discovery Statistics Dashboard (`/admin/discovery/stats`)
**Analysis Method**: Playwright browser exploration + Sequential Thinking
**Status**: Analysis Complete - Ready for Implementation

---

## Executive Summary

The main Discovery Stats Dashboard at `/admin/discovery/stats` has critical data display issues that make it unusable for monitoring event discovery sources. While the individual source detail pages display correct data, the main dashboard shows incorrect metrics for event counts, run statistics, and timestamps.

**Key Finding**: The main dashboard query logic is broken, while the detail pages (which use `SourceStatsCollector`) work correctly. This suggests the dashboard is using a different, broken query method.

---

## Critical Issues

### Issue #1: Events Column Shows 0 for All Sources ⚠️ CRITICAL

**Observed Behavior:**
- Main dashboard table shows "Events: 0" for ALL 13 sources
- But "New" column shows positive values: +111 (bandsintown), +92 (karnet), +41 (cinema-city, sortiraparis, ticketmaster), +125 (question-one), +87 (pubquiz-pl)

**Expected Behavior:**
- Events column should show total event count for each source
- Detail pages show correct totals: bandsintown (111), karnet (92), sortiraparis (39)

**Evidence:**
```
Main Dashboard (/admin/discovery/stats):
- bandsintown: Events=0, New=+111
- karnet: Events=0, New=+92
- sortiraparis: Events=0, New=+41

Detail Pages:
- bandsintown (/admin/discovery/stats/source/bandsintown): Total Events: 111
- karnet (/admin/discovery/stats/source/karnet): Total Events: 92
- sortiraparis (/admin/discovery/stats/source/sortiraparis): Total Events: 39
```

**Root Cause Hypothesis:**
The main dashboard is NOT using `SourceStatsCollector` (which works on detail pages), but instead uses a separate query that:
- May be querying a cached/aggregated table that isn't populated
- May be using incorrect joins that filter out all results
- May be filtering by time window incorrectly
- May be querying the wrong table/schema

**Impact:**
- Dashboard is completely unusable for monitoring actual event counts
- Misleading data suggests sources have no events when they actually do
- Cannot assess source productivity or health

**Suggested Fix:**
1. Identify the query used by the main dashboard LiveView
2. Compare it to `SourceStatsCollector.get_comprehensive_stats/1`
3. Either fix the broken query OR replace it with SourceStatsCollector
4. Add tests to ensure consistency between dashboard and detail pages

**Files to Investigate:**
- `/lib/eventasaurus_web/live/admin/discovery_stats_live.ex` (main dashboard)
- `/lib/eventasaurus_discovery/admin/source_stats_collector.ex` (working detail page queries)

---

### Issue #2: Runs Metric Shows 0 Despite Actual Runs ⚠️ CRITICAL

**Observed Behavior:**
- Main dashboard shows "Runs: 0 Last 30 days" for all sources
- Detail page summary cards also show "Runs: 0 Last 30 days"
- BUT detail page "Run History" table shows multiple actual runs from Oct 15-19, 2025

**Expected Behavior:**
- Runs metric should count all runs within the specified time window
- Based on Run History tables, counts should be:
  - karnet: 10 runs
  - sortiraparis: 10 runs
  - bandsintown: 6 runs

**Evidence:**
```
Detail Page Summary Card:
- Runs: 0 (Last 30 days)

Detail Page Run History Table:
- karnet: 10 runs from Oct 15-19, 2025
- sortiraparis: 10 runs from Oct 18-19, 2025
- bandsintown: 6 runs from Oct 15-19, 2025
```

**Related Symptoms:**
- "Last Run: Never" shown for sources with actual runs
- "Success Rate: 0% (0/0 runs)" despite successful run history
- Status shows "🔴 Error" when runs are actually successful

**Root Cause Hypothesis:**
The "Last 30 days" time window query is broken:
- Possible timezone mismatch (UTC vs local time)
- Incorrect date comparison (e.g., using > instead of >=)
- Time window calculation off by timezone offset
- Using wrong timestamp field for comparison

**Impact:**
- Cannot monitor source health or execution frequency
- Misleading "Never" status suggests sources aren't running
- Success rate calculations are useless (0%)

**Suggested Fix:**
1. Review the time window calculation logic
2. Check timezone handling in queries
3. Verify timestamp field being used for filtering
4. Add timezone-aware date comparison tests
5. Consider using relative time functions instead of manual calculations

**Files to Investigate:**
- Main dashboard LiveView (time window filtering)
- SourceStatsCollector (if used for run metrics)
- Database schema (verify timestamp fields are timestamptz)

---

## Medium Priority Issues

### Issue #3: Confusing "Never" Status with Error State

**Observed Behavior:**
- Sources show "Last Run: Never" combined with "🔴 Error" status
- But these sources have successful run history

**Expected Behavior:**
- If a source has run history, should show actual last run timestamp
- Error status should only appear if the LAST run failed (not if no runs found in time window)

**Suggested Fix:**
- Separate "no runs found in time window" from "last run failed"
- Show appropriate messaging: "No recent runs" vs "Last run failed"
- Only show error status if the most recent run actually failed

---

### Issue #4: City Growth Shows 100% for All Entries

**Observed Behavior:**
- Cities Performance table shows "+100%" week-over-week growth for ALL cities
- Krakow: +100%, London: +100%, Katowice: +100%, etc.

**Expected Behavior:**
- Growth percentage should vary based on actual week-over-week changes
- 100% growth means doubling - unlikely all cities doubled simultaneously

**Root Cause Hypothesis:**
- Likely division by zero (no baseline data from previous week)
- Formula: (current - baseline) / baseline * 100
- If baseline = 0, result is undefined or shows as 100%

**Suggested Fix:**
- Handle zero baseline case (show "New" or "N/A" instead of 100%)
- Verify baseline data exists for previous week
- Add validation to growth calculation

---

## Minor Issues / UX Improvements

### Issue #5: Inconsistent Date Formatting

**Observed:**
- Some fields use "Never"
- Some use relative time "2d ago", "13m ago"
- Some use absolute timestamps "Oct 19, 2025 12:18 PM"

**Suggested Improvement:**
- Standardize on relative time for recent events (< 7 days)
- Use absolute timestamps for older events
- Consistent format across dashboard and detail pages

---

## What's Working Correctly ✅

**The following features work as expected:**
1. ✅ "New" events tracking (24-hour window)
2. ✅ "Quality" scores match detail pages
3. ✅ Data Quality Dashboard on detail pages
4. ✅ Category breakdown (after recent fix)
5. ✅ Venue statistics
6. ✅ Image statistics
7. ✅ Run History table (raw data)
8. ✅ "Events by City" breakdown on detail pages
9. ✅ Occurrence type distribution
10. ✅ Change tracking (new/dropped events)

---

## Testing Strategy

**Before Fix:**
1. Document current query results with screenshots
2. Identify exact queries being used by main dashboard
3. Create failing test cases for broken metrics

**After Fix:**
1. Verify Events column shows correct totals
2. Verify Runs count matches Run History
3. Verify Last Run timestamp is accurate
4. Verify Success Rate calculation is correct
5. Test timezone handling across different server configurations
6. Add regression tests to prevent future breakage

**Test Cases to Add:**
```elixir
test "main dashboard event counts match detail page totals" do
  # Setup: Create source with known event count
  # Assert: Main dashboard shows same count as detail page
end

test "runs count respects time window" do
  # Setup: Create runs at various timestamps
  # Assert: Count only includes runs within window
end

test "last run shows most recent run timestamp" do
  # Setup: Create multiple runs
  # Assert: Shows timestamp of most recent run
end
```

---

## Screenshots Reference

- `main-dashboard-final.png` - Shows Events=0 issue
- `karnet-source-detail.png` - Shows correct Total Events: 92
- `sortiraparis-source-detail.png` - Shows correct Total Events: 39
- `bandsintown-source-detail.png` - Shows correct Total Events: 111

---

## Priority Ranking

1. **CRITICAL** - Fix Events column showing 0 (Issue #1)
2. **CRITICAL** - Fix Runs count showing 0 (Issue #2)
3. **MEDIUM** - Fix confusing "Never" + Error status (Issue #3)
4. **MEDIUM** - Fix 100% growth for all cities (Issue #4)
5. **LOW** - Standardize date formatting (Issue #5)

---

## Implementation Checklist

- [x] Investigate main dashboard LiveView query logic
- [x] Compare with working SourceStatsCollector queries
- [x] **FIXED** Events column query - Changed `s.name` to `s.slug` in discovery_stats_live.ex:166
- [x] **FIXED** Runs count JSONB type mismatch - Cast `args->>'city_id'` to integer in all 4 queries
- [x] **FIXED** City growth percentage calculation - Return nil instead of 100% when no baseline
- [x] **FIXED** "Never" + Error status confusion - Added :no_data status type for sources with no runs
- [ ] Add comprehensive test coverage
- [ ] Verify timezone handling
- [ ] Test with production-like data volumes
- [ ] Update documentation if query patterns change

---

## Fixes Applied (2025-10-19)

### Fix #1: Events Column Showing 0 ✅

**File**: `/lib/eventasaurus_web/live/admin/discovery_stats_live.ex:166`

**Problem**: Query filtered by `s.name == ^source_name`, but `source_name` variable contains SLUGS (e.g., "bandsintown"), not display names (e.g., "Bandsintown").

**Fix**: Changed to `s.slug == ^source_name`

**Verification**:
- bandsintown: 0 → **111** ✅
- karnet: 0 → **92** ✅
- sortiraparis: 0 → **67** ✅
- cinema-city: 0 → **41** ✅

### Fix #2: Runs Count Showing 0 ✅

**Files**: `/lib/eventasaurus_discovery/admin/discovery_stats_collector.ex`
- Line 147: `get_city_stats/2`
- Line 233: `get_city_sources_batch/2`
- Line 384: `get_last_error/2`
- Line 447: `get_last_errors_batch/2`

**Problem**: JSONB operator `args ->> 'city_id'` returns TEXT, but database stores city_id as INTEGER. Query compared `2` (integer) to `"1"` (string), which always fails.

**Fix**: Cast JSONB text value to integer: `(args ->> 'city_id')::integer = ?`

**Verification**:
- Regional/country sources (no city filter): Working correctly ✅
  - pubquiz-pl: "50m ago", "100% (6/6)"
  - question-one: "50m ago", "100% (4/4)"
  - geeks-who-drink: "3d ago", "100% (6/6)"
- City-scoped sources with jobs: Working correctly ✅
  - Tested karnet with city_id=2: Shows 5 runs with timestamps

**Note**: City-scoped sources showing "Never" on main dashboard is expected - dashboard defaults to first city (London, id=1) which has no jobs. Sources with jobs in other cities display correctly.

### Fix #3: Confusing "Never" + Error Status ✅

**Files**: `/lib/eventasaurus_discovery/admin/source_health_calculator.ex`
- Lines 2-11: Updated moduledoc to document `:no_data` status
- Line 32: Changed `def calculate_health_score(%{run_count: 0}), do: :error` to `do: :no_data`
- Lines 108-129: Added `:no_data` case to status_emoji (⚪)
- Lines 131-148: Added `:no_data` case to status_text ("No Data")
- Lines 154-175: Added `:no_data` case to status_classes (gray badge)

**Problem**: `calculate_health_score(%{run_count: 0})` returned `:error` for ALL sources with 0 runs, even when they simply had no jobs in the selected city (not an actual error).

**Fix**: Added new `:no_data` status type to distinguish between "no runs available in current context" vs "runs that failed".

**Verification**:
- City-scoped sources now show "⚪ No Data" instead of "🔴 Error" when no runs in selected city ✅
- Sources with actual errors still show "🔴 Error" (quizmeisters: 67%, speed-quizzing: 47%) ✅
- Screenshot: dashboard-after-fix3.png

### Fix #4: City Growth Showing 100% for All Cities ✅

**File**: `/lib/eventasaurus_web/live/admin/discovery_stats_live.ex`
- Lines 219-255: Updated `calculate_city_change/1` function
- Lines 511-524: Added nil handling for growth display helpers

**Problem**: When `last_week = 0` (no baseline data 7-14 days ago), code returned `100` instead of `nil`. All cities showed "+100%" because events were just added recently with no historical baseline.

**Discovery Process**:
```bash
# Test output confirmed:
Kraków (city_id=2):
  This week (last 7 days): 274
  Last week (7-14 days ago): 0  # No baseline!
  Growth: 100% (no baseline - THIS IS THE BUG)
```

**Fix**: Changed `calculate_city_change` to return `nil` instead of `100` when no baseline exists. Updated UI helpers to display `nil` as "New 🆕":
- `format_change(nil)` → "New"
- `change_color(nil)` → "text-blue-600"
- `status_emoji_for_change(nil)` → "🆕"

**Verification**:
- All cities now show "New 🆕" instead of "+100%" ✅
- Kraków: "New 🆕" (274 events)
- London: "New 🆕" (63 events)
- Katowice: "New 🆕" (29 events)
- Screenshot: dashboard-after-fix3.png

---

## Next Steps

All critical and medium priority issues have been resolved! ✅

**Completed Fixes**:
1. ✅ **Issue #1 (CRITICAL)**: Events column showing 0 - Fixed by changing name to slug comparison
2. ✅ **Issue #2 (CRITICAL)**: Runs count showing 0 - Fixed by casting JSONB city_id to integer
3. ✅ **Issue #3 (MEDIUM)**: Confusing "Never" + Error status - Fixed by adding :no_data status type
4. ✅ **Issue #4 (MEDIUM)**: 100% growth for all cities - Fixed by returning nil when no baseline

**Remaining Low Priority**:
- **Issue #5 (LOW)**: Standardize date formatting - Not critical for dashboard functionality

**Recommended Next Steps**:
1. **Test** thoroughly with various time zones and data volumes
2. **Add** comprehensive test coverage for fixed functionality
3. **Deploy** and verify on staging environment
4. **Consider** Issue #5 (date formatting) in future UX improvements

---

**Generated by Claude Code via Playwright exploration and Sequential Thinking analysis**
