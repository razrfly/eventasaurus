# Issue: Recent Job History Display is Misleading

**Date**: 2025-10-20
**Severity**: Medium - UX/Data Interpretation Issue
**Component**: Source Detail Page - Recent Job History Section

---

## Problem Statement

The "Recent Job History (Last 10)" section on the source detail page is currently misleading because it appears to show a comprehensive list of recent jobs, but it actually only shows **failures from our error tracking table**, not the complete Oban job history.

### Current Behavior

Looking at Sortiraparis as an example:
```
Recent Job History (Last 10)
Time                      Status      Duration  Errors
Oct 20, 2025 12:17 AM    ❌ Failed    5s       :missing_venue
Oct 20, 2025 12:17 AM    ❌ Failed    11s      None
Oct 20, 2025 12:16 AM    ❌ Failed    5s       None
Oct 20, 2025 12:16 AM    ❌ Failed    10s      None
Oct 20, 2025 12:16 AM    ❌ Failed    5s       None
Oct 20, 2025 12:16 AM    ❌ Failed    5s       None
Oct 20, 2025 12:16 AM    ❌ Failed    6s       None
Oct 20, 2025 12:16 AM    ❌ Failed    11s      None
Oct 20, 2025 12:15 AM    ❌ Failed    11s      None
Oct 20, 2025 12:15 AM    ❌ Failed    5s       None
```

### Issues Identified

1. **Misleading Title**: "Recent Job History (Last 10)" implies a complete history of all jobs (successes + failures)
2. **All Failures**: The list shows ONLY failures, making it appear like the source is completely broken
3. **Confusing Error Column**: Many entries show "None" in the Errors column despite being marked as failed
4. **No Success Context**: Users can't see the success rate or pattern of failures vs. successes over time
5. **Duplicate Data Sources**: We have:
   - **Oban job history** (complete job execution records)
   - **Error tracking table** (specifically tracks failures for analysis)

---

## Current Implementation Analysis

### Data Source
The current implementation queries our **error tracking table**, which is designed to:
- Track failures specifically for debugging and analysis
- Store detailed error information (error reasons, metadata, context)
- NOT include successful job executions

### Location
- File: `/lib/eventasaurus_web/live/admin/discovery_stats_live/source_detail.ex`
- Function: `DiscoveryStatsCollector.get_run_history(source_slug, 10)`
- Lines: ~231-284 in the render function

### Success Rate Context
The page DOES show overall success metrics:
- **Success Rate Card**: Shows "76% Success (168/222 runs)" for last 30 days
- This indicates there ARE successful runs, but they're not visible in the history table

---

## Solution Options

### Option 1: Show Complete Oban Job History (Recommended)

**Approach**: Query Oban's job history for the last 10 jobs (success + failure)

**Pros**:
- Accurate representation of actual job execution history
- Shows the pattern of successes and failures over time
- Users can see if failures are isolated or systemic
- No misleading "all failures" view

**Cons**:
- Oban job history may be pruned/deleted based on retention settings
- Requires querying Oban tables directly
- May not have detailed error metadata (would need to join with error table)

**Implementation**:
```elixir
# Query Oban jobs table
defp get_complete_job_history(source_slug, limit) do
  from(j in Oban.Job,
    where: j.worker == "EventasaurusDiscovery.Workers.SourceDetailScraper",
    where: fragment("?->>'source_slug' = ?", j.args, ^source_slug),
    order_by: [desc: j.completed_at],
    limit: ^limit,
    select: %{
      completed_at: j.completed_at,
      state: j.state,  # "completed" or "discarded"
      duration_seconds: fragment("EXTRACT(EPOCH FROM (? - ?))", j.completed_at, j.scheduled_at),
      errors: j.errors  # Oban's error field
    }
  )
  |> Repo.all()
  |> enrich_with_error_tracking()  # Join with our error table for detailed info
end
```

### Option 2: Rename to "Recent Failures" (Quick Fix)

**Approach**: Keep current implementation but change title and messaging

**Pros**:
- No code changes needed
- Clear and honest about what's being shown
- Quick fix

**Cons**:
- Doesn't provide complete job history context
- Still limited value for users

**Implementation**:
```elixir
# Change title from:
"Recent Job History (Last 10)"
# To:
"Recent Failures (Last 10)"
# With subtitle:
"Showing detailed failure logs for debugging. See success rate above for overall health."
```

### Option 3: Hybrid View - Success/Failure Timeline (Best UX)

**Approach**: Show last 20 jobs with visual timeline, expand failures for details

**Pros**:
- Best of both worlds: context + details
- Visual pattern recognition (users can see failure clusters)
- Success entries are lightweight (just timestamp + duration)
- Failure entries expandable for detailed error info

**Cons**:
- More complex UI
- Requires both Oban + error table queries

**Implementation**:
```
Recent Job History (Last 20)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Oct 20, 2025 12:20 AM  ✅ Success    8s
Oct 20, 2025 12:17 AM  ❌ Failed     5s    [Expand for details ▼]
Oct 20, 2025 12:17 AM  ❌ Failed    11s    [Expand for details ▼]
Oct 20, 2025 12:16 AM  ✅ Success    7s
Oct 20, 2025 12:16 AM  ❌ Failed     5s    [Expand for details ▼]
Oct 20, 2025 12:14 AM  ✅ Success    9s
Oct 20, 2025 12:12 AM  ✅ Success    8s
...

[Expanded Failure]
Oct 20, 2025 12:17 AM  ❌ Failed     5s
Error: :missing_venue
Context: Event "Concert à Paris" at unknown location
Attempted: venue_matcher.ex:45
Retry: Will retry in 5 minutes
```

### Option 4: Tabbed View (Most Comprehensive)

**Approach**: Two tabs: "All Jobs" and "Failures Only"

**Pros**:
- Users can switch between views based on their needs
- Debugging: "Failures Only" with full details
- Monitoring: "All Jobs" for pattern recognition

**Cons**:
- Most complex implementation
- May be overkill for the use case

**Implementation**:
```
Recent Job History
[All Jobs] [Failures Only]

# All Jobs Tab (default)
Time                      Status      Duration
Oct 20, 2025 12:20 AM    ✅ Success    8s
Oct 20, 2025 12:17 AM    ❌ Failed     5s
Oct 20, 2025 12:17 AM    ❌ Failed    11s
Oct 20, 2025 12:16 AM    ✅ Success    7s
...

# Failures Only Tab
Time                      Status      Duration  Error Details
Oct 20, 2025 12:17 AM    ❌ Failed     5s       :missing_venue (Event "...")
Oct 20, 2025 12:17 AM    ❌ Failed    11s       :network_timeout (...)
...
```

---

## Error Column Issues

### Problem
Many failures show "None" in the Errors column, which is confusing:
- Why did it fail if there's no error?
- Is "None" the error reason or does it mean no error was recorded?

### Root Cause Analysis
Need to investigate:
1. **Are these Oban-level failures?** (job discarded but our error tracking didn't capture it)
2. **Are these expected failures?** (e.g., "no events found" which we mark as failed but not an error)
3. **Is error tracking incomplete?** (not all failure paths are being logged)

### Potential Solutions
1. **Distinguish between failure types**:
   - "No events found" → ⚠️ Warning (not an error)
   - "Network timeout" → ❌ Error
   - "Invalid credentials" → 🔴 Critical Error

2. **Better error messages**:
   - Instead of "None" → "No events found"
   - Instead of `:missing_venue` → "Missing venue: Could not match venue for event 'X'"

3. **Add error categorization**:
   ```
   Error Categories:
   - Network Issues (timeouts, connection refused)
   - Data Quality (missing venues, invalid formats)
   - Source Changes (scraper needs update)
   - Rate Limiting (too many requests)
   - No Data (no events available)
   ```

---

## Recommended Implementation Plan

### Phase 1: Quick Win (1-2 hours)
1. **Rename section**: "Recent Job History (Last 10)" → "Recent Failures (Last 10)"
2. **Add context**: Subtitle explaining this shows failures only
3. **Improve error messages**: Replace "None" with meaningful descriptions

### Phase 2: Complete History (4-6 hours)
1. **Query Oban jobs table**: Get last 20 jobs (success + failure)
2. **Join with error table**: Enrich failures with detailed error info
3. **Update UI**: Show success/failure pattern
4. **Make failures expandable**: Show error details on click

### Phase 3: Enhanced UX (2-3 hours)
1. **Add visual timeline**: Color-coded job execution history
2. **Group by time period**: "Last Hour", "Last 6 Hours", "Last 24 Hours"
3. **Add filtering**: Filter by status, error type, time range

---

## Impact Assessment

### User Impact
- **Current**: Users think the source is completely broken (10/10 failures shown)
- **With Fix**: Users see accurate picture (e.g., 168 successes, 54 failures in last 10 jobs)

### Decision-Making Impact
- **Current**: May abandon a source that appears to be failing constantly
- **With Fix**: Can make informed decisions about source health and prioritization

### Debugging Impact
- **Current**: Hard to see patterns (all failures, no context)
- **With Fix**: Can identify clusters of failures, correlate with time/events

---

## Data Sources Available

### 1. Oban Jobs Table
- **Table**: `oban_jobs`
- **Contains**: All job execution records (success + failure)
- **Retention**: Based on Oban pruning configuration
- **Fields**: `worker`, `args`, `state`, `completed_at`, `scheduled_at`, `errors`

### 2. Error Tracking Table
- **Table**: `discovery_source_errors` (or similar)
- **Contains**: Detailed failure metadata
- **Retention**: Permanent (for analysis)
- **Fields**: `source_slug`, `error_type`, `error_message`, `context`, `metadata`

### 3. Stats Aggregation
- **Already computed**: Success rate, run count, last run time
- **Location**: Displayed in cards at top of page

---

## Questions to Answer

1. **What's the primary use case for this section?**
   - Debugging failures? → Show failures only with full details
   - Monitoring health? → Show all jobs with success/failure pattern
   - Both? → Hybrid or tabbed view

2. **How important is historical context?**
   - If very important → Query Oban for complete history
   - If not → Keep error-tracking table, but rename section

3. **How long should we retain this data?**
   - Affects whether we rely on Oban (pruned) or error table (permanent)

4. **Should we differentiate failure types?**
   - Critical errors vs. expected "no data" results
   - Affects how we categorize and display errors

---

## Related Code Locations

### Current Implementation
- **LiveView**: `/lib/eventasaurus_web/live/admin/discovery_stats_live/source_detail.ex`
  - Line 181: `run_history = DiscoveryStatsCollector.get_run_history(source_slug, 10)`
  - Lines 231-284: Run history table rendering

### Data Collection
- **Stats Collector**: `/lib/eventasaurus_discovery/admin/discovery_stats_collector.ex`
  - Function: `get_run_history/2`
  - Currently queries error tracking table

### Oban Integration
- **Oban Jobs**: Would need to query `Oban.Job` table directly
- **Worker**: `EventasaurusDiscovery.Workers.SourceDetailScraper`

---

## Recommendation

**Implement Option 3 (Hybrid View)** with the following priorities:

### Immediate (Phase 1)
- Rename to "Recent Failures (Last 10)"
- Add context subtitle
- Fix "None" error messages

### Short-term (Phase 2)
- Query Oban for complete job history (last 20 jobs)
- Show success/failure timeline
- Make failures expandable for details

### Long-term (Phase 3)
- Add visual timeline/chart
- Add filtering and grouping
- Consider categorizing error types

This approach provides:
- ✅ Accurate representation of job execution
- ✅ Pattern recognition (failure clusters)
- ✅ Detailed error info when needed
- ✅ Balanced between simplicity and completeness
- ✅ Aligns with existing success rate metrics
