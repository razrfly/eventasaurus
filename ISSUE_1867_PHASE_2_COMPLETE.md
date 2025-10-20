# Issue #1867 - Phase 2 Implementation Complete

**Date**: 2025-10-20
**Issue**: https://github.com/razrfly/eventasaurus/issues/1867
**Status**: ✅ Phase 2 Complete

---

## Summary

Phase 2 has been successfully implemented to provide complete job history (both successes AND failures) instead of just failures. This addresses the core misleading nature of the original "Recent Job History" section.

---

## Changes Made

### 1. New Data Collection Function

**File**: `/lib/eventasaurus_discovery/admin/discovery_stats_collector.ex` (lines 724-812)

Created `get_complete_run_history/2` function:

```elixir
def get_complete_run_history(source_slug, limit \\ 20)
    when is_binary(source_slug) and is_integer(limit) do
  # Queries ALL Oban jobs (completed AND discarded)
  # No longer filters by meta->>'status' IS NOT NULL
  # Returns last 20 jobs instead of 10
  # Uses COALESCE to map metadata status OR job state
end
```

**Key improvements**:
- ✅ Removed `meta->>'status' IS NOT NULL` filter to include ALL jobs
- ✅ Default limit changed from 10 to 20 jobs
- ✅ Uses `COALESCE(meta->>'status', CASE WHEN state = 'completed' THEN 'completed' ELSE 'failed' END)`
- ✅ Gracefully handles jobs with or without metadata status

### 2. Deprecated Old Function

**File**: `/lib/eventasaurus_discovery/admin/discovery_stats_collector.ex` (lines 646-682)

Marked `get_run_history/2` as DEPRECATED with clear migration guidance.

### 3. Updated LiveView

**File**: `/lib/eventasaurus_web/live/admin/discovery_stats_live/source_detail.ex` (line 181)

```elixir
# Before:
run_history = DiscoveryStatsCollector.get_run_history(source_slug, 10)

# After:
run_history = DiscoveryStatsCollector.get_complete_run_history(source_slug, 20)
```

### 4. UI Updates

**File**: `/lib/eventasaurus_web/live/admin/discovery_stats_live/source_detail.ex` (lines 762-826)

**Title**: "Recent Job History (Last 20)"
**Subtitle**: "Complete job execution history showing both successes and failures for accurate context."

**Visual improvements**:
- Success rows have light green background (`bg-green-50`)
- Failed rows remain white (default)
- Status badges: ✅ Success (green) or ❌ Failed (red)

**Details column messages**:
- **Success**: "Job completed successfully" (gray text)
- **Failure with error**: Shows red error message
- **Failure without error**: "Failed with warnings" (orange text)

---

## User Experience Improvement

### Before Phase 2:
```
Recent Failures (Last 10)
----------------------------
[Shows 10 failures, but phase 1 added context]

User sees: "All failures, but success rate card shows 76%"
Reality: Phase 1 improved labeling but didn't show complete history
```

### After Phase 2:
```
Recent Job History (Last 20)
Complete job execution history showing both successes and failures for accurate context.
----------------------------
Oct 20, 2025 12:20 AM  ✅ Success    8s   Job completed successfully
Oct 20, 2025 12:17 AM  ❌ Failed     5s   :missing_venue
Oct 20, 2025 12:17 AM  ❌ Failed    11s   Failed with warnings
Oct 20, 2025 12:16 AM  ✅ Success    7s   Job completed successfully
Oct 20, 2025 12:16 AM  ❌ Failed     5s   Failed with warnings
Oct 20, 2025 12:14 AM  ✅ Success    9s   Job completed successfully
...

User sees: Complete pattern of successes and failures
Reality: 76% success rate is visually apparent in the history
```

---

## Technical Details

### Query Comparison

**OLD Query** (get_run_history):
```sql
SELECT ... FROM oban_jobs
WHERE worker = 'EventDetailJob'
  AND state IN ('completed', 'discarded')
  AND meta->>'status' IS NOT NULL  -- ❌ ONLY jobs with metadata status (failures)
ORDER BY COALESCE(completed_at, discarded_at) DESC
LIMIT 10
```

**NEW Query** (get_complete_run_history):
```sql
SELECT
  COALESCE(completed_at, discarded_at) as completed_at,
  attempted_at,
  COALESCE(
    meta->>'status',
    CASE WHEN state = 'completed' THEN 'completed' ELSE 'failed' END
  ) as state,
  meta->>'error_message' as errors,
  args,
  meta
FROM oban_jobs
WHERE worker = 'EventDetailJob'
  AND state IN ('completed', 'discarded')  -- ✅ ALL completed/discarded jobs
ORDER BY COALESCE(completed_at, discarded_at) DESC
LIMIT 20
```

### Data Enrichment

Both queries use `enrich_job_history/1` to:
- Format timestamps
- Calculate duration (completed_at - attempted_at)
- Extract error messages
- Handle metadata variations

---

## Validation

### Server Status
✅ Application compiled successfully
✅ No runtime errors
✅ LiveView loads correctly
✅ All queries executing correctly

### Log Evidence
```
[debug] QUERY OK source="oban_jobs" db=4.6ms
SELECT ... FROM "oban_jobs" ...
WHERE (o0."worker" = 'EventDetailJob')
  AND (o0."state" IN ('completed','discarded'))  -- ✅ No metadata filter
ORDER BY COALESCE(...) DESC
LIMIT 20  -- ✅ Increased from 10
[90m↳ EventasaurusDiscovery.Admin.DiscoveryStatsCollector.get_complete_run_history/2
```

### Warnings (Pre-existing)
- Unused function warnings in `data_quality_checker.ex` (not related to this change)
- Stripity Stripe deprecation warning (not related to this change)

---

## Impact Assessment

### Problem Solved
✅ **Complete History**: Users now see both successes AND failures
✅ **Accurate Context**: Visual pattern matches success rate percentage
✅ **No Misleading Data**: Section title and content are aligned
✅ **Better UX**: Green highlighting makes successes immediately visible

### Example: Sortiraparis Source
- **Success Rate**: 76% (168/222 runs)
- **Before**: Showed 10 failures, appeared completely broken
- **After**: Shows mix of successes and failures matching 76% success rate

---

## Next Steps

Phase 2 is complete and ready for use. Optional Phase 3 enhancements could include:

### Phase 3: Enhanced UX (Optional)
- Visual timeline with color-coded job execution history
- Group by time period ("Last Hour", "Last 6 Hours", "Last 24 Hours")
- Add filtering (by status, error type, time range)
- Expandable failure details (collapse by default, expand for full error context)
- Estimated time: 2-3 hours

**Recommendation**: Deploy Phase 2 and gather user feedback before implementing Phase 3. The current implementation provides accurate, complete context that addresses the core issue.

---

## Related Work

- Issue #1864: Translation completeness metrics (completed - Phases 1-3)
- Issue #1867 Phase 1: Section renaming and context (completed)
- Issue #1867 Phase 2: Complete job history (completed ✅)
- Issue #1867 Phase 3: Enhanced UX (optional, not started)

---

## Conclusion

Phase 2 successfully addresses the misleading job history display by showing complete execution history. Users can now:
- ✅ See the actual pattern of successes and failures
- ✅ Verify that success rate matches visual job history
- ✅ Identify clusters of failures vs isolated failures
- ✅ Make informed decisions about source health

**Impact**: Eliminates the misleading "all failures" view and provides accurate context for source health assessment.
