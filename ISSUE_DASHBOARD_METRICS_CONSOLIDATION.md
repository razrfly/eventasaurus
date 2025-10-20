# Dashboard Metrics Consolidation Issue

## Overview

The discovery dashboard has inconsistent data across different pages because it uses two incompatible query patterns:

1. **OLD PATTERN (Job State)**: Queries `job.state` (completed/discarded) - Used by Stats page
2. **NEW PATTERN (Metadata)**: Queries `meta->>'status'` (success/failed) - Used by Imports page

The Stats page was built before MetricsTracker was implemented and uses job state queries. The Imports page uses the new metadata queries. This causes contradictory data across pages.

## Problems Identified

### Problem 1: Stats Page Shows 0% Success Rates

**Location**: `/admin/discovery/stats`

**Current Behavior**:
- All sources show 0% success rate
- Status shows "⚪ No Data"
- Health score shows 0%

**What User Sees**:
```
Source          | Success Rate | Status
----------------|--------------|--------
bandsintown     | 0%          | ⚪ No Data
karnet          | 0%          | ⚪ No Data
sortiraparis    | 0%          | ⚪ No Data
```

**Root Cause**:
- **File**: `lib/eventasaurus_web/live/admin/discovery_stats_live.ex`
- **Line 67**: Calls `DiscoveryStatsCollector.get_all_source_stats(first_city, source_names)`
- **Line 91-92**: Uses `SourceHealthCalculator.success_rate_percentage(stats)` based on job state

`get_all_source_stats` queries job STATE (completed/discarded) instead of metadata:
```elixir
# discovery_stats_collector.ex line 116
def get_all_source_stats(city_id, source_names) do
  # Queries job.state NOT meta->>'status'
  where: j.state in ["completed", "discarded"]
  # Returns empty stats because old jobs don't have tracked metadata
end
```

**Why It's Wrong**:
- Job state (completed/discarded) doesn't reflect success/failure
- MetricsTracker records success/failure in `meta->>'status'`
- Old jobs (pre-MetricsTracker) have job state but no metadata
- After cleanup, we only have jobs WITH metadata, so state-based queries show nothing

---

### Problem 2: Stats Page Shows "Never" for Last Run

**Location**: `/admin/discovery/stats`

**Current Behavior**:
- All sources show "Never" for last run time
- Even sources that ran recently show "Never"

**Root Cause**:
- **File**: `lib/eventasaurus_web/live/admin/discovery_stats_live.ex`
- **Line 67**: `get_all_source_stats` returns `last_run_at: nil`

The function queries job state instead of metadata, so it doesn't find jobs with metadata and returns nil for last_run_at.

---

### Problem 3: Source Detail Pages Show "No run history available"

**Location**: `/admin/discovery/stats/source/:source_name`

**Current Behavior**:
```
Run History (Last 10)
Time    | Status | Duration | Errors
No run history available
```

Shows "0 runs" even though detail jobs have run.

**Root Cause**:
- **File**: `lib/eventasaurus_discovery/admin/discovery_stats_collector.ex`
- **Line 558-588**: `get_run_history/2` function

The function queries the SYNC WORKER instead of DETAIL WORKER:
```elixir
# Line 560-564
case SourceRegistry.get_worker_name(source_slug) do
  {:ok, worker_name} ->
    # This returns "Karnet.Jobs.SyncJob" for example
    query = from(j in "oban_jobs",
      where: j.worker == ^worker_name,  # WRONG - querying sync job
```

**Why It's Wrong**:
- MetricsTracker records metadata in DETAIL jobs:
  - Karnet: `IndexPageJob` and `EventDetailJob`
  - Speed Quizzing: `DetailJob`
  - Geeks Who Drink: `VenueDetailJob`
- SyncJobs are just coordinators that schedule detail jobs
- The metadata is at the detail job level, not sync job level
- Querying sync jobs returns empty results

**Solution**: Query detail worker instead of sync worker.

---

### Problem 4: Imports Page "Top Errors" Shows "No failures"

**Location**: `/admin/imports`

**Current Behavior**:
```
Source       | Processed | Succeeded | Failed | Success Rate | Top Errors
-------------|-----------|-----------|--------|--------------|------------
sortiraparis | 1138      | 1109      | 29     | 97.5%        | No failures
```

Shows "No failures" even when Failed > 0.

**Root Cause**:
- **File**: `lib/eventasaurus_web/live/admin/discovery_dashboard_live.html.heex`
- **Line 651-653**: Template checks if `stats.failure_breakdown` is empty

```elixir
<%= if Enum.empty?(stats.failure_breakdown) do %>
  <span class="text-gray-400 text-xs">No failures</span>
<% end %>
```

- **File**: `lib/eventasaurus_discovery/admin/discovery_stats_collector.ex`
- **Line 805**: Calls `failure_summary = get_failure_breakdown(source_name)`

**The Problem**: `get_failure_breakdown/1` function DOES NOT EXIST!

The function is called but never implemented, so it crashes or returns empty, causing the failure breakdown to always be empty.

**Solution**: Implement `get_failure_breakdown/1` to query `meta->>'error_category'` and aggregate counts.

---

### Problem 5: Imports Page Shows CORRECT Data (Reference)

**Location**: `/admin/imports`

**Current Behavior** (CORRECT):
```
Source       | Processed | Succeeded | Failed | Success Rate
-------------|-----------|-----------|--------|-------------
karnet       | 1655      | 1655      | 0      | 100.0%
bandsintown  | 1138      | 1109      | 29     | 97.5%
sortiraparis | 1138      | 867       | 271    | 76.2%
```

**Why This Works**:
- **File**: `lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex`
- **Line 465**: Calls `DiscoveryStatsCollector.get_detailed_source_statistics(min_events: 1)`
- This function internally uses `get_event_level_stats/3` which queries metadata:

```elixir
# discovery_stats_collector.ex line 770-808
defp get_event_level_stats(detail_worker, city_id, source_name) do
  from(j in "oban_jobs",
    where: j.worker == ^detail_worker,  # Queries DETAIL worker
    where: j.state in ["completed", "discarded"],
    select: %{
      processed: count(j.id),
      succeeded: fragment("COUNT(*) FILTER (WHERE meta->>'status' = 'success')"),  # METADATA
      failed: fragment("COUNT(*) FILTER (WHERE meta->>'status' = 'failed')")       # METADATA
    }
  )
end
```

This is the CORRECT approach - it queries metadata status from detail jobs.

---

## Architectural Analysis

### Two Query Patterns

| Pattern | What It Queries | Where Used | Accuracy |
|---------|----------------|------------|----------|
| **Job State** | `job.state` (completed/discarded) | Stats page (`get_all_source_stats`) | ❌ Incorrect - doesn't reflect success/failure |
| **Metadata** | `meta->>'status'` (success/failed) | Imports page (`get_detailed_source_statistics`) | ✅ Correct - reflects actual event processing outcomes |

### Function Comparison

#### OLD PATTERN: `get_all_source_stats/2` (Lines 116-195)
```elixir
def get_all_source_stats(city_id, source_names) do
  # Queries SYNC worker
  {:ok, worker_name} = SourceRegistry.get_worker_name(source_name)

  from(j in "oban_jobs",
    where: j.worker == ^worker_name,           # Sync job (wrong)
    where: j.state in ["completed", "discarded"], # Job state (wrong)
    # Does NOT query meta->>'status'
  )
end
```

**Problems**:
- Queries sync worker (coordinator) instead of detail worker
- Queries job state instead of metadata
- Returns 0 because jobs with metadata have different workers

#### NEW PATTERN: `get_detailed_source_statistics/1` (Lines 851-875)
```elixir
def get_detailed_source_statistics(opts \\ []) do
  sources
  |> Enum.map(fn source_name ->
    stats = get_detailed_source_stats(city_id, source_name)
    # Returns events_processed, events_succeeded, events_failed
    # from get_event_level_stats which queries meta->>'status'
  end)
end
```

**Why This Works**:
- Calls `get_event_level_stats/3` which queries detail worker
- Queries `meta->>'status'` for success/failure
- Returns accurate metadata-based statistics

---

## Phased Refactoring Plan

### Phase 1: Implement Missing Function

**Goal**: Fix "Top Errors" display on Imports page

**Task 1.1**: Implement `get_failure_breakdown/1`
- **File**: `lib/eventasaurus_discovery/admin/discovery_stats_collector.ex`
- **Location**: Add after line 908 (after `get_event_level_stats`)

```elixir
defp get_failure_breakdown(source_name) do
  case SourceRegistry.get_worker_name(source_name) do
    {:ok, worker} ->
      detail_worker = determine_detail_worker(worker)

      query =
        from(j in "oban_jobs",
          where: j.worker == ^detail_worker,
          where: j.state in ["completed", "discarded"],
          where: fragment("meta->>'status' = 'failed'"),
          group_by: fragment("meta->>'error_category'"),
          select: {
            fragment("meta->>'error_category'"),
            count(j.id)
          }
        )

      Repo.all(query) |> Enum.into(%{})

    {:error, _} ->
      %{}
  end
end
```

**Expected Result**:
- Imports page shows error breakdown: "validation_error: 42, network_error: 15"

---

### Phase 2: Create Metadata-Based Stats Function

**Goal**: Provide consistent metadata-based query function for all pages

**Task 2.1**: Create `get_metadata_based_source_stats/2`
- **File**: `lib/eventasaurus_discovery/admin/discovery_stats_collector.ex`
- **Location**: Add after `get_all_source_stats`

```elixir
@doc """
Metadata-based source statistics.

RECOMMENDED: Use this instead of get_all_source_stats.
Queries meta->>'status' for accurate success/failure tracking.
"""
def get_metadata_based_source_stats(city_id, source_names) do
  source_names
  |> Enum.map(fn source_name ->
    stats = get_detailed_source_stats(city_id, source_name)
    {source_name, stats}
  end)
  |> Enum.into(%{})
end
```

**Task 2.2**: Mark `get_all_source_stats` as deprecated
- Add deprecation warning to function documentation
- Add comment: "DEPRECATED: Use get_metadata_based_source_stats instead"

---

### Phase 3: Fix Stats Page

**Goal**: Stats page shows correct success rates and health scores

**Task 3.1**: Update Stats page to use metadata queries
- **File**: `lib/eventasaurus_web/live/admin/discovery_stats_live.ex`
- **Line 65-70**: Replace `get_all_source_stats` call

```elixir
# OLD (line 67):
source_stats =
  if first_city do
    DiscoveryStatsCollector.get_all_source_stats(first_city, source_names)
  else
    %{}
  end

# NEW:
source_stats =
  if first_city do
    DiscoveryStatsCollector.get_metadata_based_source_stats(first_city, source_names)
  else
    %{}
  end
```

**Task 3.2**: Verify health calculation uses metadata
- Ensure `SourceHealthCalculator.calculate_health_score/1` works with metadata stats
- Verify it uses `events_succeeded` and `events_failed` fields

**Expected Result**:
- Stats page shows correct success rates (100%, 97.5%, 76.2%)
- Status shows proper health indicators (🟢 Healthy, 🟡 Warning, 🔴 Critical)
- Last run shows actual timestamps

---

### Phase 4: Fix Run History

**Goal**: Source detail pages show run history from detail jobs

**Task 4.1**: Update `get_run_history/2` to query detail worker
- **File**: `lib/eventasaurus_discovery/admin/discovery_stats_collector.ex`
- **Line 558-588**: Update query to use detail worker

```elixir
def get_run_history(source_slug, limit \\ 10) do
  case SourceRegistry.get_worker_name(source_slug) do
    {:error, :not_found} ->
      []

    {:ok, sync_worker} ->
      # NEW: Get detail worker instead of sync worker
      detail_worker = determine_detail_worker(sync_worker)

      query =
        from(j in "oban_jobs",
          where: j.worker == ^detail_worker,  # Changed from sync_worker
          where: j.state in ["completed", "discarded"],
          where: fragment("meta->>'status' IS NOT NULL"),  # Ensure has metadata
          order_by: [
            desc:
              fragment(
                "COALESCE(?, ?)",
                j.completed_at,
                j.discarded_at
              )
          ],
          limit: ^limit,
          select: %{
            completed_at:
              fragment(
                "COALESCE(?, ?)",
                j.completed_at,
                j.discarded_at
              ),
            attempted_at: j.attempted_at,
            state: fragment("meta->>'status'"),  # Get from metadata
            errors: fragment("meta->>'error_message'"),  # Get from metadata
            duration_seconds:
              fragment(
                "EXTRACT(EPOCH FROM (? - ?))",
                j.completed_at,
                j.attempted_at
              )
          }
        )

      Repo.all(query)
  end
end
```

**Expected Result**:
- Source detail pages show last 10 runs with metadata status
- Run history displays success/failure from metadata
- Error messages from metadata displayed

---

### Phase 5: Testing & Documentation

**Goal**: Verify consistency across all pages and document approach

**Task 5.1**: Verification Checklist
- [ ] Stats page success rates match Imports page
- [ ] Stats page health scores reflect metadata
- [ ] Source detail pages show run history
- [ ] Imports page shows error breakdown
- [ ] All pages show consistent last run times

**Task 5.2**: Manual Testing
```bash
# 1. Visit Stats page
open http://localhost:4000/admin/discovery/stats
# Verify: Success rates > 0%, proper health indicators

# 2. Visit Imports page
open http://localhost:4000/admin/imports
# Verify: Same success rates, error breakdown shows

# 3. Visit Source detail page
open http://localhost:4000/admin/discovery/stats/source/karnet
# Verify: Run history shows last 10 runs with metadata
```

**Task 5.3**: Documentation
- Update `discovery_stats_collector.ex` module documentation
- Add comment explaining metadata-based queries vs job state queries
- Document the query pattern standard for future development

```elixir
@moduledoc """
Discovery statistics collector.

## Query Patterns

This module uses METADATA-BASED queries for accurate statistics:
- Queries meta->>'status' (success/failed) NOT job.state
- Queries DETAIL workers (DetailJob, VenueDetailJob) NOT sync workers
- Provides accurate event-level success/failure tracking

Legacy functions using job state are deprecated.
"""
```

---

## Code Reuse Strategy

### Shared Query Functions

All pages should use these metadata-based functions:

1. **`get_detailed_source_statistics/1`** - For aggregate stats across all sources
   - Used by: Imports page ✅
   - Should use: Stats page (Phase 3)

2. **`get_detailed_source_stats/2`** - For single source stats
   - Used by: Source detail pages ✅
   - Internally calls `get_event_level_stats/3`

3. **`get_event_level_stats/3`** - Core metadata query function
   - Queries: `meta->>'status'` for success/failure
   - Queries: Detail worker, not sync worker
   - Returns: processed, succeeded, failed counts

4. **`get_failure_breakdown/1`** - NEW function for error categories
   - Queries: `meta->>'error_category'`
   - Groups by: error category
   - Returns: Map of category => count

### Query Pattern Standard

**DO**:
- ✅ Query detail workers (DetailJob, VenueDetailJob, IndexPageJob)
- ✅ Query `meta->>'status'` for success/failure
- ✅ Query `meta->>'error_category'` for error breakdown
- ✅ Use `get_detailed_source_statistics` for consistency

**DON'T**:
- ❌ Query sync workers (SyncJob)
- ❌ Query job.state (completed/discarded) for success rates
- ❌ Use `get_all_source_stats` (deprecated)

---

## Summary

### Root Cause
The Stats page uses OLD query patterns (job state from sync workers) while the Imports page uses NEW query patterns (metadata from detail workers). This creates contradictory data across pages.

### Solution
Consolidate all pages to use metadata-based queries consistently:
1. Implement missing `get_failure_breakdown` function
2. Create `get_metadata_based_source_stats` function
3. Update Stats page to use metadata queries
4. Fix run history to query detail workers
5. Verify consistency across all pages

### Benefits
- ✅ Consistent data across all dashboard pages
- ✅ Accurate success/failure tracking from metadata
- ✅ Error breakdown showing actual error categories
- ✅ Run history showing detail job metadata
- ✅ Clear query pattern standard for future development

---

## Files Modified

1. `lib/eventasaurus_discovery/admin/discovery_stats_collector.ex`
   - Implement `get_failure_breakdown/1`
   - Add `get_metadata_based_source_stats/2`
   - Update `get_run_history/2` to query detail workers
   - Mark `get_all_source_stats/2` as deprecated

2. `lib/eventasaurus_web/live/admin/discovery_stats_live.ex`
   - Update line 67 to use `get_metadata_based_source_stats`
   - Verify health calculation uses metadata

3. Documentation
   - Update module documentation with query pattern standards
   - Add comments explaining metadata vs job state queries
