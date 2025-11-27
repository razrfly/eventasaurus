# Phase 5: ShowtimeProcessJob Metrics Accuracy Issue

**Status:** 🔴 Critical - Dashboard shows 100% success but actual failure rate is ~30-40%
**Date Created:** 2025-11-27
**Related:** [GitHub Issue #2427 - Movie Not Found Bug](https://github.com/razrfly/eventasaurus/issues/2427)

---

## Executive Summary

ShowtimeProcessJob pipeline stage shows **100% pipeline health** on the monitoring dashboard, but is actually **cancelling 30-40% of jobs** due to "movie not found" errors. The dashboard metrics are misleading because cancelled jobs are being counted as "healthy" when they represent actual processing failures.

**Impact:** Stakeholders cannot accurately assess pipeline performance or identify data quality issues.

---

## What We've Accomplished (Phases 1-4)

### ✅ Phase 1: Telemetry Foundation (Nov 23)
- Implemented ObanTelemetry handler for job lifecycle tracking
- Created `job_execution_summaries` table for historical job data
- Integrated Sentry for error alerting

### ✅ Phase 2: ShowtimeProcessJob Monitoring (Nov 26)
- Fixed telemetry tracking for ShowtimeProcessJob cancellations
- Updated `cancellation_reason?/1` to detect `{:cancel, :movie_not_matched}` pattern
- Changed logging from ERROR to INFO for intentional cancellations
- **Result:** ShowtimeProcessJob executions now properly tracked in `job_execution_summaries`

### ✅ Phase 3: Movie Matching Improvements (Nov 26)
- Lowered TMDB confidence threshold from 60% to 50%
- Enhanced match type categorization (standard, now_playing_fallback, low_confidence_accepted)
- Improved logging for match analysis
- **Result:** Increased movie match rate from 42% to 70%+

### ✅ Phase 4: Metrics Categorization Fix (Nov 26)
- Separated "cancelled" from "failed" in all 10 metrics functions
- Updated dashboard with new metrics: Pipeline Health, Match Rate, Error Rate
- Changed UI from 4 cards to 5 cards with detailed breakdowns
- **Result:** ShowtimeProcessJob now visible in pipeline (was missing before)

**Current Dashboard State:**
```
Pipeline Stages: 4
- SyncJob (100.0%, 2 runs)
- CinemaDateJob (100.0%, 44 runs)
- MovieDetailJob (97.4%, 77 runs)
- ShowtimeProcessJob (100.0%, 451 runs) ← INCORRECT
```

---

## The Problem

### Current Metrics Show

```
ShowtimeProcessJob:
- Pipeline Health: 100.0%
- Match Rate: 0.0%
- Total Runs: 451
- State Distribution: 451 cancelled
```

### Reality Check: Oban Data

**Example Cancelled Job:**
```elixir
Job ID: 7685
Worker: EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob
State: cancelled
Cancelled Reason: {:cancel, :movie_not_matched}

Meta:
%{
  "external_id" => "cinema_city_showtime_1090_7381d2r_1114191",
  "processed_at" => "2025-11-27T09:17:58.098970Z",
  "status" => "success"  ← WRONG: Should be "failed"
}

Error:
** (Oban.PerformError) {:cancel, :movie_not_matched}
```

**Oban State Summary:**
```sql
SELECT state, COUNT(*)
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob'
GROUP BY state;

-- Results (historical):
cancelled: 1,063 (42%)  ← These are FAILURES
completed: 1,337 (53%)
discarded: 126 (5%)
```

### Root Cause Analysis

#### 1. **Conceptual Error in Phase 4**

Phase 4 defined Pipeline Health as:
```elixir
pipeline_health = (completed + cancelled) / total * 100
```

**Assumption:** Cancelled = intentional skip = healthy
**Reality:** For ShowtimeProcessJob, cancelled = processing failure

#### 2. **Two Types of Cancellations**

| Job Type | Cancellation Meaning | Should Count As |
|----------|---------------------|-----------------|
| **MovieDetailJob** | Movie not matched in TMDB | ✅ Healthy (intentional skip) |
| **ShowtimeProcessJob** | Movie not found in database | ❌ Failed (processing failure) |

**Why the difference?**
- MovieDetailJob: External data source limitation (TMDB doesn't have the movie)
- ShowtimeProcessJob: Internal pipeline failure (movie SHOULD be in our database but isn't)

#### 3. **Code Issue in ShowtimeProcessJob**

Lines 71-76:
```elixir
{:ok, :skipped} ->
  # Movie was not matched in TMDB - record as skipped cancellation
  MetricsTracker.record_success(job, external_id)  ← WRONG
  {:cancel, :movie_not_matched}
```

**Problem:** Calls `record_success` before returning `{:cancel, reason}`, so:
- Job meta shows: `"status" => "success"`
- Oban state shows: `state = "cancelled"`
- Creates data inconsistency

---

## Proposed Solution: 3-Phase Approach

### Phase 5.1: Calculate Baseline Failure Rate

**Objective:** Establish ground truth from Oban data to validate our metrics

**Tasks:**
1. Query Oban for ShowtimeProcessJob historical data
   ```sql
   -- Calculate actual success rate
   SELECT
     COUNT(*) FILTER (WHERE state = 'completed') as completed,
     COUNT(*) FILTER (WHERE state = 'cancelled') as cancelled,
     COUNT(*) FILTER (WHERE state = 'discarded') as discarded,
     COUNT(*) as total,
     ROUND(COUNT(*) FILTER (WHERE state = 'completed')::numeric / COUNT(*)::numeric * 100, 2) as true_success_rate
   FROM oban_jobs
   WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob';
   ```

2. Query `job_execution_summaries` for telemetry data
   ```sql
   -- Verify telemetry matches Oban
   SELECT
     state,
     COUNT(*),
     ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 2) as percentage
   FROM job_execution_summaries
   WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob'
   GROUP BY state
   ORDER BY state;
   ```

3. Compare results and document discrepancies
4. Calculate expected metrics:
   - **Expected Success Rate:** ~53-60% (based on historical data)
   - **Expected Failure Rate:** ~40-47% (cancelled + discarded)

**Deliverable:** Baseline report with expected vs. actual metrics

**Estimated Time:** 1 hour

---

### Phase 5.2: Fix Metrics to Reflect True Pipeline Health

**Objective:** Update metrics system to distinguish cancellation types and show accurate pipeline health

#### Sub-Task 5.2.1: Store Cancellation Reason in Telemetry

**File:** `lib/eventasaurus_app/monitoring/oban_telemetry.ex`

**Changes Needed:**

1. Update `record_job_summary/5` to capture cancellation reason:
   ```elixir
   defp record_job_summary(job, state, duration_ms, error_message, metadata) do
     db_state = case state do
       :success -> "completed"
       :failure -> "retryable"
       :discard -> "discarded"
       :cancelled -> "cancelled"
       other -> to_string(other)
     end

     # Extract cancellation reason if state is cancelled
     cancel_reason = if state == :cancelled do
       extract_cancel_reason(metadata.reason)
     else
       nil
     end

     results = %{
       # ... existing fields ...
       "cancel_reason" => cancel_reason  # NEW
     }

     # ... rest of function ...
   end
   ```

2. Add migration to ensure `results` JSONB field can store `cancel_reason`
   - Note: JSONB already supports arbitrary keys, no schema change needed
   - Just update queries to use it

**Estimated Time:** 2 hours

#### Sub-Task 5.2.2: Update Metrics Queries

**File:** `lib/eventasaurus_discovery/job_execution_summaries.ex`

**Functions to Update:**

1. **`get_source_pipeline_metrics/2`** (lines 594-662)

   **Current Logic:**
   ```elixir
   pipeline_health = (completed + cancelled) / total * 100
   ```

   **New Logic:**
   ```elixir
   # Count cancellations by type
   healthy_cancellations = count(s.id) |>
     filter(s.state == "cancelled" and
            fragment("?->>'cancel_reason' != ?", s.results, "movie not matched"))

   failed_cancellations = count(s.id) |>
     filter(s.state == "cancelled" and
            fragment("?->>'cancel_reason' = ?", s.results, "movie not matched"))

   # Pipeline Health: completed + healthy_cancellations / total
   pipeline_health = (completed + healthy_cancellations) / total * 100

   # Processing Failure Rate: failed_cancellations + discarded / total
   failure_rate = (failed_cancellations + discarded) / total * 100
   ```

2. **Add new metric: `processing_failure_rate`**

   For each job type, track:
   - `completed`: Successfully processed
   - `cancelled_expected`: Intentional skips (healthy)
   - `cancelled_failed`: Processing failures (unhealthy)
   - `discarded`: Hard failures

3. **Update affected functions:**
   - `get_worker_metrics/1`
   - `get_system_metrics/1`
   - `get_scraper_metrics/1`
   - `get_top_workers/2`
   - `get_worker_metrics_for_period/2`
   - `get_source_pipeline_metrics/2`
   - `compare_scrapers/1`

**Estimated Time:** 4 hours

#### Sub-Task 5.2.3: Fix ShowtimeProcessJob MetricsTracker Calls

**File:** `lib/eventasaurus_discovery/sources/cinema_city/jobs/showtime_process_job.ex`

**Current Code (lines 71-76):**
```elixir
{:ok, :skipped} ->
  # Movie was not matched in TMDB - record as skipped cancellation
  # Using {:cancel, reason} instead of deprecated {:discard, reason}
  MetricsTracker.record_success(job, external_id)  ← REMOVE THIS
  {:cancel, :movie_not_matched}
```

**Fixed Code:**
```elixir
{:ok, :skipped} ->
  # Movie was not matched in TMDB - this is a processing failure
  # Don't call MetricsTracker - let telemetry handler record it
  # Telemetry will correctly mark this as "cancelled" with reason
  {:cancel, :movie_not_matched}
```

**Rationale:**
- Telemetry handler already records cancelled jobs correctly
- Calling `record_success` creates inconsistent data (meta says "success", Oban says "cancelled")
- Let telemetry be the single source of truth

**Estimated Time:** 1 hour

#### Sub-Task 5.2.4: Update Dashboard UI

**File:** `lib/eventasaurus_web/live/admin/source_pipeline_monitor_live.ex`

**Changes:**

1. Add new metric display for "Processing Failures"
2. Update pipeline stage cards to show failure breakdown:
   ```html
   <div class="text-sm text-gray-600 space-y-1">
     <div><%= stage.total_runs %> runs</div>
     <div><%= format_duration(stage.avg_duration_ms) %> avg</div>
     <div class="text-xs">Success: <%= Float.round(stage.pipeline_health, 1) %>%</div>
     <div class="text-xs text-red-600">Failed: <%= Float.round(stage.failure_rate, 1) %>%</div> <!-- NEW -->
   </div>
   ```

3. Update status badge colors to reflect true health:
   ```elixir
   defp status_badge(health_percentage, failure_rate) do
     cond do
       failure_rate > 10 -> red_badge()
       failure_rate > 5 -> yellow_badge()
       health_percentage >= 95 -> green_badge()
       true -> blue_badge()
     end
   end
   ```

**Estimated Time:** 2 hours

#### Sub-Task 5.2.5: Validation & Testing

1. **Restart Phoenix server** to clear any cached data
2. **Trigger Cinema City sync** to generate fresh job data
3. **Verify dashboard metrics:**
   - ShowtimeProcessJob should show ~53-60% success rate
   - Cancelled jobs should be categorized correctly
   - Overall pipeline health should reflect true state

4. **Cross-reference with Oban data:**
   ```bash
   mix monitor.baseline cinema_city --hours=24 --save
   ```

5. **Check job_execution_summaries:**
   ```sql
   SELECT
     results->>'cancel_reason' as reason,
     COUNT(*)
   FROM job_execution_summaries
   WHERE worker LIKE '%ShowtimeProcessJob%'
     AND state = 'cancelled'
   GROUP BY results->>'cancel_reason';
   ```

**Expected Results:**
- Dashboard shows accurate failure rates
- Telemetry data matches Oban state
- Cancelled jobs properly categorized by reason

**Estimated Time:** 2 hours

**Total Phase 5.2 Time:** ~11 hours

---

### Phase 5.3: Fix Root Cause (Movie Not Found Bug)

**Objective:** Eliminate the underlying "movie not found" errors

**Related Issue:** [GitHub #2427 - Cinema City Movie Not Found](https://github.com/razrfly/eventasaurus/issues/2427)

**Root Cause:**
ShowtimeProcessJob can't find movies in the database because:
1. MovieDetailJob failed to create the movie
2. MovieDetailJob was cancelled (low TMDB confidence)
3. Timing issue: ShowtimeProcessJob runs before MovieDetailJob completes
4. Data inconsistency: Movie exists in Cinema City API but not in our database

**Proposed Solutions:**

#### Option A: Improve Movie Matching (Recommended)
- Further lower TMDB confidence threshold (50% → 45%)
- Add fallback to original title matching
- Implement fuzzy matching for Polish → English title translation
- **Expected Impact:** Reduce cancellation rate to 5-10%

#### Option B: Retry Logic
- If movie not found, retry ShowtimeProcessJob after delay
- Add exponential backoff (5s → 30s → 2m)
- Max 3 retries before permanent cancellation
- **Expected Impact:** Reduce cancellation rate to 15-20%

#### Option C: Dependency Management
- Make ShowtimeProcessJob depend on MovieDetailJob completion
- Use Oban's `[:depends_on]` feature
- Ensure movies are created before processing showtimes
- **Expected Impact:** Eliminate timing-related failures (~5%)

**Recommended Approach:** Combination of A + C

**Estimated Time:** 8 hours (including testing)

**Deliverable:**
- Reduced ShowtimeProcessJob cancellation rate to <10%
- Updated dashboard showing improved pipeline health
- Documentation of changes

---

## Success Criteria

### Phase 5.1 Success
- ✅ Baseline report created with Oban vs. telemetry comparison
- ✅ Expected failure rate documented (~40-47%)
- ✅ Discrepancies identified and explained

### Phase 5.2 Success
- ✅ Dashboard shows accurate ShowtimeProcessJob success rate (53-60%)
- ✅ Cancelled jobs categorized by reason (intentional vs. failure)
- ✅ Telemetry data includes `cancel_reason` field
- ✅ Metrics queries distinguish cancellation types
- ✅ ShowtimeProcessJob no longer calls `record_success` before cancelling
- ✅ Pipeline health reflects true state (not 100%)

### Phase 5.3 Success
- ✅ ShowtimeProcessJob cancellation rate reduced to <10%
- ✅ Dashboard shows >90% pipeline health for ShowtimeProcessJob
- ✅ GitHub Issue #2427 closed
- ✅ Production monitoring confirms sustained improvement

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Metrics queries break existing dashboards | Medium | High | Test all dashboard pages before deployment |
| Performance degradation from JSONB queries | Low | Medium | Add index on `results->>'cancel_reason'` if needed |
| Movie matching changes increase false positives | Medium | Medium | Monitor match quality, implement rollback threshold |
| Oban dependency chains cause job delays | Low | Medium | Monitor job queue latency, adjust timeouts |

---

## Testing Plan

### Unit Tests

1. **Telemetry Handler Tests**
   ```elixir
   test "records cancellation reason for movie_not_matched" do
     # Trigger [:oban, :job, :exception] event with {:cancel, :movie_not_matched}
     # Assert job_execution_summary.results["cancel_reason"] == "movie not matched"
   end
   ```

2. **Metrics Query Tests**
   ```elixir
   test "distinguishes cancellation types in pipeline health" do
     # Create test data: completed, cancelled (expected), cancelled (failed), discarded
     # Assert pipeline_health only counts completed + cancelled (expected)
     # Assert failure_rate includes cancelled (failed) + discarded
   end
   ```

3. **ShowtimeProcessJob Tests**
   ```elixir
   test "does not call record_success before cancelling" do
     # Mock movie lookup to return {:error, :not_found}
     # Perform job
     # Assert job meta does NOT contain "status" => "success"
   end
   ```

### Integration Tests

1. **End-to-End Pipeline Test**
   - Trigger full Cinema City sync
   - Verify all 4 pipeline stages execute
   - Assert metrics match Oban state
   - Validate dashboard displays correct percentages

2. **Dashboard Rendering Test**
   - Load `/admin/job-executions/sources/cinema_city`
   - Assert ShowtimeProcessJob card shows accurate metrics
   - Assert pipeline flow displays 4 stages with correct health percentages
   - Take screenshot for regression testing

### Manual Testing

1. **Baseline Comparison**
   ```bash
   # Before changes
   mix monitor.baseline cinema_city --save baseline_before.json

   # After changes
   mix monitor.baseline cinema_city --save baseline_after.json

   # Compare
   mix monitor.compare --before baseline_before.json --after baseline_after.json
   ```

2. **Dashboard Visual Verification**
   - Load dashboard, verify ShowtimeProcessJob shows ~53-60% success
   - Check that cancelled jobs are not counted as "healthy"
   - Verify color coding reflects true pipeline state

3. **Data Consistency Check**
   ```sql
   -- Verify telemetry matches Oban state
   SELECT
     o.state as oban_state,
     j.state as telemetry_state,
     j.results->>'cancel_reason' as reason,
     COUNT(*)
   FROM oban_jobs o
   LEFT JOIN job_execution_summaries j ON o.id = j.job_id
   WHERE o.worker LIKE '%ShowtimeProcessJob%'
   GROUP BY o.state, j.state, j.results->>'cancel_reason';
   ```

---

## Rollback Plan

### If Phase 5.2 Causes Issues

1. **Revert Metrics Queries**
   ```bash
   git revert <commit-hash-for-metrics-changes>
   mix compile
   ```

2. **Restore Original Pipeline Health Formula**
   ```elixir
   # Rollback to Phase 4 definition
   pipeline_health = (completed + cancelled) / total * 100
   ```

3. **Remove cancel_reason field from queries**
   - Dashboard will show old metrics
   - System remains functional, just with inaccurate metrics

### If Phase 5.3 Causes Issues

1. **Revert TMDB Threshold Changes**
   ```bash
   git revert <commit-hash-for-matching-changes>
   ```

2. **Disable Dependency Chains**
   ```elixir
   # Remove [:depends_on] from ShowtimeProcessJob
   ```

3. **Monitor for false positive rate**
   - If >5% of "matched" movies are incorrect, rollback immediately

---

## Documentation Updates Needed

1. **Update `PHASE4_COMPLETION_SUMMARY.md`**
   - Add note about ShowtimeProcessJob metrics issue
   - Reference Phase 5 for resolution

2. **Create `PHASE5_COMPLETION_SUMMARY.md`**
   - Document metrics accuracy improvements
   - Include before/after screenshots
   - Provide cancellation reason mapping guide

3. **Update `docs/scraper-monitoring-guide.md`**
   - Explain cancellation types and how to interpret them
   - Add troubleshooting section for metrics discrepancies
   - Document best practices for handling cancellations

4. **Update Job Documentation**
   - `ShowtimeProcessJob` module doc: Explain cancellation behavior
   - `MetricsTracker` module doc: When to call vs. rely on telemetry

---

## Timeline Estimate

| Phase | Tasks | Estimated Time | Dependencies |
|-------|-------|---------------|--------------|
| **5.1** | Baseline calculation & analysis | 1 hour | None |
| **5.2.1** | Store cancellation reason | 2 hours | 5.1 complete |
| **5.2.2** | Update metrics queries | 4 hours | 5.2.1 complete |
| **5.2.3** | Fix ShowtimeProcessJob | 1 hour | 5.2.1 complete |
| **5.2.4** | Update dashboard UI | 2 hours | 5.2.2 complete |
| **5.2.5** | Validation & testing | 2 hours | 5.2.1-5.2.4 complete |
| **5.3** | Fix root cause (movie not found) | 8 hours | 5.2 complete |
| **Total** | | **20 hours** | (~3 days) |

---

## Open Questions

1. **Should we distinguish other cancellation types?**
   - Current focus: `movie_not_matched`
   - Future: Other cancellation reasons in different jobs?

2. **What's the acceptable failure threshold?**
   - Proposal: Pipeline Health < 85% triggers alert
   - Need stakeholder input on acceptable ranges

3. **Should we implement automatic rollback?**
   - If failure rate suddenly spikes >50%, auto-revert recent changes?
   - Requires monitoring infrastructure

4. **Do we need historical metric recalculation?**
   - Current: Only affects new data going forward
   - Option: Backfill historical data with corrected metrics
   - Trade-off: Complexity vs. historical accuracy

---

## References

- **Phase 4 Completion:** `PHASE4_COMPLETION_SUMMARY.md`
- **Phase 2 & 3 Audit:** `PHASE2_AND_PHASE3_AUDIT.md`
- **Monitoring Guide:** `docs/scraper-monitoring-guide.md`
- **GitHub Issue #2427:** Movie Not Found Root Cause
- **Oban Documentation:** [Job Cancellation](https://hexdocs.pm/oban/Oban.Worker.html#module-cancelling-jobs)
- **MetricsTracker:** `lib/eventasaurus_discovery/metrics/metrics_tracker.ex`
- **ObanTelemetry:** `lib/eventasaurus_app/monitoring/oban_telemetry.ex`

---

## Approval Required

This issue requires approval from:
- [ ] Technical Lead: Review technical approach
- [ ] Product Owner: Confirm acceptable failure thresholds
- [ ] DevOps: Review rollback plan and monitoring strategy

---

_Issue created by: Claude Code_
_Last updated: 2025-11-27_
