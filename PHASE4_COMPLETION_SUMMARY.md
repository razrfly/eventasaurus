# Phase 4 Completion: Metrics Categorization Fix

**Status:** ✅ Complete
**Date:** 2025-11-26

---

## What We Fixed

### Problem
The monitoring dashboard was misleading because "cancelled" jobs (intentional skips when movies aren't matched) were grouped with "discarded" jobs (real failures) in ALL metrics queries throughout `job_execution_summaries.ex`.

**Original Bug Pattern** (found in 10 functions):
```elixir
failed: count(s.id) |> filter(s.state in ["discarded", "cancelled"])
```

This made:
- Cinema City pipeline show 42% "success rate" when it had ~100% pipeline health
- No visibility into actual match rate vs error rate
- "Error trends" include intentional skips as errors

### Goal
Comprehensively fix all metrics categorization to:
1. **Separate "cancelled" (intentional skips) from "failed" (real errors)** in ALL queries
2. **Add new metrics**: Pipeline Health, Match Rate, Error Rate
3. **Update dashboard** to display new metrics properly

---

## Changes Made

### Updated Functions in `lib/eventasaurus_discovery/job_execution_summaries.ex`

#### Functions Modified in Initial Implementation (Lines 64-530):

1. **`get_worker_metrics/1`** (lines 64-120)
   - Added `cancelled` field
   - Changed `failed` to only `"discarded"`
   - Added `pipeline_health` and `match_rate` calculations

2. **`get_system_metrics/1`** (lines 173-226)
   - Added `cancelled` field
   - Changed `failed` to only `"discarded"`
   - Added `pipeline_health`, `match_rate`, and `error_rate` calculations

3. **`get_execution_timeline/1`** (lines 228-273)
   - Added `cancelled` field to hourly/daily buckets
   - Changed `failed` to only `"discarded"`
   - Timeline now tracks cancelled separately

4. **`get_scraper_metrics/1`** (lines 462-530)
   - Added `cancelled` field
   - Changed `failed` to only `"discarded"`
   - Added `pipeline_health` and `match_rate` calculations

#### Additional Functions Fixed (Discovered During Verification):

5. **`get_top_workers/2`** (lines 278-319)
   - Added `cancelled` field
   - Changed `failed` to only `"discarded"`
   - Replaced `success_rate` with `pipeline_health` and `match_rate`

6. **`get_worker_metrics_for_period/2`** (lines 351-405)
   - Added `cancelled` field
   - Changed `failed` to only `"discarded"`
   - Replaced `success_rate` with `pipeline_health` and `match_rate`
   - Updated empty result map to include new fields

7. **`get_worker_timeline_data/2`** (lines 421-448)
   - Added `cancelled` field to daily buckets
   - Changed `failed` to only `"discarded"`
   - Timeline data now includes cancelled count

8. **`get_source_pipeline_metrics/2`** (lines 594-662)
   - Added `cancelled` field
   - Changed `failed` to only `"discarded"`
   - Replaced `success_rate` with `pipeline_health` and `match_rate`
   - Provides per-source pipeline metrics with match rates

9. **`get_error_trends/2`** (lines 1011-1042)
   - Added `cancelled` field
   - Changed `failed` to only `"discarded"`
   - **CRITICAL**: Error rate now correctly excludes intentional skips
   - Comment added: "Error Rate: only count real errors (discarded), not cancelled"

10. **`compare_scrapers/1`** (lines 1093-1139)
    - Added `cancelled` field
    - Changed `failed` to only `"discarded"`
    - Replaced `success_rate` with `pipeline_health` and `match_rate`
    - Scraper comparison now shows accurate pipeline health

### Updated Dashboard in `lib/eventasaurus_web/live/admin/job_execution_monitor_live.ex`

#### System Metrics Summary Cards (lines 503-591)

**Changed from 4 cards to 5 cards:**

**Card 1: Total Jobs** (unchanged)
- Shows total job count

**Card 2: Pipeline Health** (NEW - replaced "Success Rate")
```elixir
<dt>Pipeline Health</dt>
<dd><%= format_percentage(@system_metrics.pipeline_health) %></dd>
<div class="text-xs">
  <%= format_number(@system_metrics.completed) %> completed,
  <%= format_number(@system_metrics.cancelled) %> skipped
</div>
```
- Formula: `(completed + cancelled) / total`
- Shows jobs without real errors
- Expected: ~100% for Cinema City

**Card 3: Match Rate** (NEW)
```elixir
<dt>Match Rate</dt>
<dd><%= format_percentage(@system_metrics.match_rate) %></dd>
<div class="text-xs">Data processing success</div>
```
- Formula: `completed / (completed + cancelled)`
- Shows data processing success rate
- Expected: 42% → 70%+ (after Phase 3)

**Card 4: Error Rate** (NEW)
```elixir
<dt>Error Rate</dt>
<dd><%= format_percentage(@system_metrics.error_rate) %></dd>
<div class="text-xs">
  <%= format_number(@system_metrics.failed + @system_metrics.retryable) %> real errors
</div>
```
- Formula: `(retryable + failed) / total`
- Shows actual error rate
- Expected: ~0% for healthy pipelines

**Card 5: Avg Duration** (moved here, condensed)
- Shows average job duration
- Also displays unique worker count

#### Per-Scraper Metrics Table (lines 679-775)

**Added 3 new columns:**

1. **Pipeline Health Column**
```elixir
<th>Pipeline Health</th>
<td>
  <span class={badge_class_for_pipeline_health(scraper.pipeline_health)}>
    <%= format_percentage(scraper.pipeline_health) %>
  </span>
</td>
```
- Badge colors: >=95% blue, >=85% yellow, else red
- Shows jobs without real errors per scraper

2. **Match Rate Column**
```elixir
<th>Match Rate</th>
<td>
  <span class={badge_class_for_match_rate(scraper.match_rate)}>
    <%= format_percentage(scraper.match_rate) %>
  </span>
</td>
```
- Badge colors: >=70% green, >=50% yellow, else red
- Shows data processing success per scraper

3. **Skipped Column**
```elixir
<th>Skipped</th>
<td class="text-gray-500">
  <%= format_number(scraper.cancelled) %>
</td>
```
- Shows count of cancelled jobs (intentional skips)

---

## New Metrics Explained

### 1. Pipeline Health = `(completed + cancelled) / total`

**What it measures:** Percentage of jobs that completed without real errors

**Why it matters:** Shows overall pipeline reliability - jobs either completed successfully OR were intentionally skipped (movie not matched)

**Expected values:**
- Cinema City: ~100% (pipeline working correctly)
- Jobs fail only on network errors, API failures, or bugs

**Example:**
- 738 completed + 536 cancelled = 1274 healthy jobs
- 0 real errors
- Pipeline Health: 1274/1274 = **100%** ✅

### 2. Match Rate = `completed / (completed + cancelled)`

**What it measures:** Percentage of movies successfully matched to TMDB

**Why it matters:** Measures data processing success rate - how many movies we can match vs. how many we skip

**Expected values:**
- Cinema City: 42% (current) → 70%+ (after Phase 3 takes effect)
- Directly related to TMDB confidence threshold

**Example:**
- 738 completed
- 536 cancelled (movies not matched)
- Match Rate: 738/(738+536) = **58%** (would be 70%+ with Phase 3)

### 3. Error Rate = `(retryable + failed) / total`

**What it measures:** Percentage of jobs with real errors

**Why it matters:** Shows actual error rate excluding intentional skips

**Expected values:**
- Healthy pipelines: ~0%
- Unhealthy pipelines: >5%

**Example:**
- 1274 total jobs
- 0 real errors
- Error Rate: 0/1274 = **0%** ✅

---

## Expected Results After Phase 4

### Before Phase 4 (Misleading):
| Metric | Value | Interpretation |
|--------|-------|----------------|
| Success Rate | 42% | ❌ Looks broken |
| Failed Jobs | 536 | ❌ Includes intentional skips |
| Error Visibility | None | ❌ Can't distinguish errors from skips |

### After Phase 4 (Accurate):
| Metric | Value | Interpretation |
|--------|-------|----------------|
| Pipeline Health | ~100% | ✅ Pipeline working correctly |
| Match Rate | 42% → 70%+ | ✅ Clear data processing metric |
| Error Rate | ~0% | ✅ No real errors |
| Skipped | 536 | ✅ Clearly labeled as intentional |

---

## Integration with Previous Phases

| Phase | What It Fixed | Metrics Impact |
|-------|---------------|----------------|
| **Phase 2** | Fixed telemetry tracking of cancelled jobs | Jobs now recorded with `state: "cancelled"` |
| **Phase 3** | Lowered TMDB confidence threshold 60% → 50% | Match Rate should improve from 42% to 70%+ |
| **Phase 4** | Fixed metrics categorization | Dashboard now shows accurate metrics |

**Combined Effect:**
- Phase 2: Enabled tracking cancelled jobs
- Phase 3: Will improve match rate
- Phase 4: Makes improvements visible in dashboard

---

## Verification Steps

### 1. Check Dashboard Metrics

Visit `/admin/job-executions` and verify:

**System Metrics Cards:**
- ✅ 5 cards visible (Total, Pipeline Health, Match Rate, Error Rate, Avg Duration)
- ✅ Pipeline Health shows ~100%
- ✅ Match Rate shows 42% (will improve with Phase 3)
- ✅ Error Rate shows ~0%

**Per-Scraper Table:**
- ✅ New columns: Pipeline Health, Match Rate, Skipped
- ✅ Cinema City shows 100% pipeline health
- ✅ Skipped count matches cancelled jobs (536)

### 2. Verify Query Results

```elixir
# Start IEx
iex -S mix

# Check system metrics
alias EventasaurusDiscovery.JobExecutionSummaries
metrics = JobExecutionSummaries.get_system_metrics(24)

# Expected:
%{
  total_jobs: 1274,
  completed: 738,
  cancelled: 536,
  failed: 0,
  retryable: 0,
  pipeline_health: 100.0,  # NEW
  match_rate: 57.9,        # NEW
  error_rate: 0.0          # NEW
}

# Check scraper metrics
scraper_metrics = JobExecutionSummaries.get_scraper_metrics(24)
cinema_city = Enum.find(scraper_metrics, & &1.scraper_name == "cinema_city")

# Expected:
%{
  scraper_name: "cinema_city",
  total_executions: 1274,
  completed: 738,
  cancelled: 536,
  failed: 0,
  pipeline_health: 100.0,  # NEW
  match_rate: 57.9,        # NEW
  ...
}
```

### 3. Verify Error Trends

```elixir
# Check error trends (should exclude cancelled jobs)
error_trends = JobExecutionSummaries.get_error_trends(24)

# Each bucket should show:
%{
  time_bucket: ~U[...],
  total: 100,
  completed: 58,
  cancelled: 42,
  failed: 0,
  error_rate: 0.0  # Correctly 0% (doesn't count cancelled)
}
```

### 4. Compare All Functions

Verify all 10 functions now separate cancelled from failed:
- ✅ `get_worker_metrics/1`
- ✅ `get_system_metrics/1`
- ✅ `get_execution_timeline/1`
- ✅ `get_scraper_metrics/1`
- ✅ `get_top_workers/2`
- ✅ `get_worker_metrics_for_period/2`
- ✅ `get_worker_timeline_data/2`
- ✅ `get_source_pipeline_metrics/2`
- ✅ `get_error_trends/2`
- ✅ `compare_scrapers/1`

---

## Benefits

### ✅ Accurate Dashboard Metrics
- **Pipeline Health**: Shows actual pipeline reliability (~100%)
- **Match Rate**: Shows data processing success (42% → 70%+)
- **Error Rate**: Shows real errors only (~0%)

### ✅ Better Visibility
- **Clear Separation**: Cancelled vs. failed jobs are distinct
- **Context-Rich**: Each metric has clear meaning and context
- **Actionable**: Can identify real errors vs. data matching issues

### ✅ Improved Monitoring
- **Error Trends**: No longer polluted with intentional skips
- **Worker Comparison**: Accurate comparison across scrapers
- **Performance Tracking**: Can measure true performance improvements

### ✅ Aligned with Phase 3
- **Match Rate Metric**: Will show Phase 3 improvements (42% → 70%+)
- **Clear Success Criteria**: Can measure effectiveness of threshold changes
- **Data-Driven Decisions**: Can tune confidence thresholds based on match rate

---

## Technical Notes

### Why 10 Functions?

**Initially found 4 functions** using the dashboard:
- `get_worker_metrics/1`
- `get_system_metrics/1`
- `get_execution_timeline/1`
- `get_scraper_metrics/1`

**Discovered 6 more functions** during grep search:
- `get_top_workers/2` - Used by top workers widget
- `get_worker_metrics_for_period/2` - Used for worker analysis over time
- `get_worker_timeline_data/2` - Used for worker timeline charts
- `get_source_pipeline_metrics/2` - Used for source-specific pipeline metrics
- `get_error_trends/2` - **CRITICAL**: Error trends were including cancelled jobs
- `compare_scrapers/1` - Used for scraper comparison dashboard

### Pattern Consistency

All functions now follow this pattern:

**Query:**
```elixir
select: %{
  completed: count(s.id) |> filter(s.state == "completed"),
  cancelled: count(s.id) |> filter(s.state == "cancelled"),  # NEW
  failed: count(s.id) |> filter(s.state == "discarded")      # CHANGED
}
```

**Metrics Calculation:**
```elixir
# Pipeline Health: (completed + cancelled) / total
pipeline_health = Float.round((result.completed + result.cancelled) / result.total * 100, 2)

# Match Rate: completed / (completed + cancelled)
match_rate =
  if result.completed + result.cancelled > 0 do
    Float.round(result.completed / (result.completed + result.cancelled) * 100, 2)
  else
    0.0
  end

# Error Rate: (retryable + failed) / total (where failed = discarded only)
error_rate = Float.round((result.retryable + result.failed) / result.total * 100, 2)
```

### Compilation Status

**Compilation:** ✅ Success
**Warnings:** 4 pre-existing unrelated warnings
**Errors:** None

---

## Summary

✅ **Problem:** Dashboard grouped cancelled (intentional skips) with failed (real errors)
✅ **Fix:** Updated ALL 10 functions in `job_execution_summaries.ex` to separate cancelled from failed
✅ **Result:** Dashboard now shows accurate pipeline health, match rate, and error rate
✅ **Benefit:** Clear visibility into pipeline performance and data processing success

**Status:** Ready for testing with next Cinema City sync run.

**Integration:** Works seamlessly with Phase 2 (telemetry) and Phase 3 (matching improvements).

---

## Next Steps

### Immediate (Post-Deployment)
1. **Visit Dashboard** - Check `/admin/job-executions` for new metrics
2. **Verify Metrics** - Confirm Pipeline Health ~100%, Match Rate 42%, Error Rate ~0%
3. **Test Queries** - Run verification queries in IEx to validate results

### Short-Term (1-2 Weeks)
1. **Monitor Phase 3 Impact** - Watch match rate improve from 42% to 70%+
2. **Analyze Error Trends** - Verify error trends exclude cancelled jobs
3. **Compare Scrapers** - Use accurate metrics for scraper comparison

### Long-Term (Future Phases)
1. **Phase 5:** Add visualization charts for pipeline health, match rate trends
2. **Phase 6:** Implement alerting for low pipeline health or high error rates
3. **Phase 7:** Create comprehensive monitoring dashboard with Phase 4 metrics

---

_This document covers all changes made in Phase 4 (metrics categorization fix) for the Cinema City scraper monitoring system._
