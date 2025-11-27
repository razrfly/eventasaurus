# Phase 5.1: ShowtimeProcessJob Baseline Report

**Date:** 2025-11-27
**Status:** ✅ Complete
**Related:** [GitHub Issue #2438](https://github.com/razrfly/eventasaurus/issues/2438)

---

## Executive Summary

Established ground truth metrics for ShowtimeProcessJob performance by analyzing Oban historical data (3,829 jobs over 2 days).

**Key Findings:**
- **True Success Rate:** 37.92% (not 100% as shown on dashboard)
- **True Failure Rate:** 62.08% (2,377 failed jobs)
- **Telemetry Coverage:** Only 12.5% of jobs tracked (479 of 3,829)
- **Data Inconsistency:** ALL 2,251 cancelled jobs incorrectly marked as "success" in job meta

---

## Data Sources

### Oban Jobs Table (Source of Truth)
**Table:** `oban_jobs`
**Worker:** `EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob`
**Time Range:** 2025-11-26 15:24:15 to 2025-11-27 09:17:58 (approximately 18 hours)
**Total Jobs:** 3,829

### Telemetry Table (Dashboard Data)
**Table:** `job_execution_summaries`
**Worker:** `EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob`
**Time Range:** 2025-11-27 09:16:42 to 2025-11-27 09:17:58 (approximately 1 minute 16 seconds)
**Total Jobs:** 479

---

## Baseline Metrics: Oban Data (Ground Truth)

### Overall Distribution

```sql
SELECT
  state,
  COUNT(*) as count,
  ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 2) as percentage
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob'
GROUP BY state
ORDER BY count DESC;
```

**Results:**

| State | Count | Percentage |
|-------|-------|------------|
| **cancelled** | 2,251 | 58.79% |
| **completed** | 1,452 | 37.92% |
| **discarded** | 126 | 3.29% |
| **TOTAL** | **3,829** | **100.00%** |

### Success vs. Failure Breakdown

```sql
SELECT
  COUNT(*) FILTER (WHERE state = 'completed') as completed,
  COUNT(*) FILTER (WHERE state = 'cancelled') as cancelled,
  COUNT(*) FILTER (WHERE state = 'discarded') as discarded,
  COUNT(*) as total,
  ROUND(COUNT(*) FILTER (WHERE state = 'completed')::numeric / COUNT(*)::numeric * 100, 2) as true_success_rate,
  ROUND((COUNT(*) FILTER (WHERE state = 'cancelled') + COUNT(*) FILTER (WHERE state = 'discarded'))::numeric / COUNT(*)::numeric * 100, 2) as true_failure_rate
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob';
```

**Results:**

| Metric | Value | Interpretation |
|--------|-------|----------------|
| **Completed** | 1,452 | Successfully processed showtimes |
| **Cancelled** | 2,251 | Movie not found in database (FAILURE) |
| **Discarded** | 126 | Hard failures after max retries |
| **Total** | 3,829 | All ShowtimeProcessJob executions |
| **True Success Rate** | **37.92%** | ✅ Baseline for dashboard |
| **True Failure Rate** | **62.08%** | ❌ Processing failures (not 0%!) |

---

## Telemetry Data Analysis

### Telemetry State Distribution

```sql
SELECT
  state,
  COUNT(*),
  ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 2) as percentage
FROM job_execution_summaries
WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob'
GROUP BY state
ORDER BY state;
```

**Results:**

| State | Count | Percentage |
|-------|-------|------------|
| **cancelled** | 479 | 100.00% |
| **completed** | 0 | 0.00% |
| **discarded** | 0 | 0.00% |

### Telemetry Coverage Analysis

**Time Window Comparison:**

| Data Source | Time Range | Duration | Jobs Tracked |
|-------------|-----------|----------|--------------|
| **Oban (Full History)** | 2025-11-26 15:24:15 → 2025-11-27 09:17:58 | ~18 hours | 3,829 |
| **Telemetry (Recent)** | 2025-11-27 09:16:42 → 2025-11-27 09:17:58 | ~1 min 16 sec | 479 |

**Coverage Percentage:** 479 / 3,829 = **12.5%**

**Why Telemetry is Incomplete:**
- Telemetry tracking only started after Phoenix server restart at ~09:16:42
- Historical jobs from Nov 26 and earlier today (00:00 - 09:16) are not tracked in telemetry
- Only captures jobs that executed AFTER telemetry handlers were attached

### Same Time Window Comparison

To verify telemetry accuracy, compared Oban vs. telemetry for the SAME time window:

```sql
-- Oban (same time window as telemetry)
SELECT COUNT(*) FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob'
  AND attempted_at >= '2025-11-27 09:16:42'
  AND attempted_at <= '2025-11-27 09:17:58';
-- Result: 478 jobs

-- Telemetry
SELECT COUNT(*) FROM job_execution_summaries
WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob';
-- Result: 479 jobs
```

**Match Rate:** 479 / 478 = **100.2%** (essentially identical, difference of 1 is within margin for race conditions)

**Conclusion:** Telemetry tracking IS working correctly for recent jobs, but lacks historical data.

---

## Data Inconsistency: Job Meta "status" Field

### Meta Status Field Analysis

```sql
SELECT
  state,
  meta->>'status' as meta_status,
  COUNT(*) as count
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob'
GROUP BY state, meta->>'status'
ORDER BY state, count DESC;
```

**Results:**

| State | Meta Status | Count | Interpretation |
|-------|-------------|-------|----------------|
| **completed** | "success" | 1,452 | ✅ Correct - meta matches state |
| **cancelled** | "success" | 2,251 | ❌ WRONG - meta says success but job failed |
| **discarded** | null | 126 | ✅ Correct - no meta for hard failures |

**Root Cause:** ShowtimeProcessJob calls `MetricsTracker.record_success(job, external_id)` before returning `{:cancel, :movie_not_matched}`, which creates this inconsistency:
- Job meta field: `"status" => "success"`
- Oban state: `state = "cancelled"`
- Error field: `"** (Oban.PerformError) {:cancel, :movie_not_matched}"`

**Code Location:** `lib/eventasaurus_discovery/sources/cinema_city/jobs/showtime_process_job.ex` lines 71-76

---

## Cancellation Reason Analysis

### Sample Cancelled Job

```elixir
Job ID: 7685
Worker: EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob
State: cancelled
Attempted At: 2025-11-27T09:17:58.087459Z

Meta:
%{
  "external_id" => "cinema_city_showtime_1090_7381d2r_1114191",
  "processed_at" => "2025-11-27T09:17:58.098970Z",
  "status" => "success"  # ← INCORRECT
}

Errors:
[
  {
    "at": "2025-11-27T09:17:58.100939Z",
    "error": "** (Oban.PerformError) EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob failed with {:cancel, :movie_not_matched}",
    "attempt": 1
  }
]
```

### Cancellation Reason Verification

**Query:**
```sql
SELECT
  LEFT(errors::text, 200) as error_sample,
  COUNT(*) as count
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob'
  AND state = 'cancelled'
GROUP BY LEFT(errors::text, 200)
ORDER BY count DESC
LIMIT 1;
```

**Result:** All 2,251 cancelled jobs have the same error pattern:
```
"** (Oban.PerformError) EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob failed with {:cancel, :movie_not_matched}"
```

**Conclusion:** 100% of cancelled jobs are due to "movie_not_matched" error.

---

## Comparison: Dashboard vs. Reality

### Current Dashboard Metrics (INCORRECT)

| Metric | Dashboard Shows | Interpretation |
|--------|----------------|----------------|
| **Pipeline Health** | 100.0% | ✅ All jobs healthy |
| **Match Rate** | 0.0% | ⚠️ No matches (contradicts 100% health) |
| **Total Runs** | 451 | ℹ️ Only recent telemetry data |
| **State Distribution** | 451 cancelled | ℹ️ Only shows recent cancelled jobs |

**Why Dashboard is Wrong:**
1. **Limited Data:** Dashboard only shows 451 jobs (recent telemetry), not all 3,829 historical jobs
2. **Formula Error:** Pipeline Health = `(completed + cancelled) / total` treats ALL cancelled as healthy
3. **Missing Context:** Doesn't distinguish "movie_not_matched" cancellations (failures) from intentional skips

### Expected Dashboard Metrics (CORRECT)

Based on Oban ground truth (3,829 jobs):

| Metric | Expected Value | Formula | Interpretation |
|--------|---------------|---------|----------------|
| **True Success Rate** | **37.92%** | `completed / total` | Jobs that successfully processed showtimes |
| **Cancelled (Failures)** | **58.79%** | `cancelled / total` | Jobs that failed due to movie not found |
| **Hard Failures** | **3.29%** | `discarded / total` | Jobs that exceeded max retries |
| **True Failure Rate** | **62.08%** | `(cancelled + discarded) / total` | All processing failures |
| **Pipeline Health** | **37.92%** | Should match success rate for this job type | Percentage of jobs without failures |

---

## Expected Metrics for Dashboard Fix

### After Phase 5.2 Implementation

Once we fix the metrics system to distinguish cancellation types:

**ShowtimeProcessJob Metrics:**

| Metric | Value | Formula | Meaning |
|--------|-------|---------|---------|
| **Pipeline Health** | **37.92%** | `completed / total` | Jobs without processing failures |
| **Processing Failure Rate** | **58.79%** | `cancelled / total` | Jobs that failed (movie not found) |
| **Hard Failure Rate** | **3.29%** | `discarded / total` | Jobs that exceeded retries |
| **Total Failure Rate** | **62.08%** | `(cancelled + discarded) / total` | All failures combined |
| **Total Jobs** | 3,829 | All historical jobs | Comprehensive view |

**Dashboard Display:**
```
ShowtimeProcessJob: 37.92% pipeline health ❌ (was 100.0%)
- 3,829 runs (1,452 completed, 2,251 failed, 126 discarded)
- Processing Failure Rate: 58.79%
- Average Duration: [calculate from Oban]
```

---

## Discrepancies Identified

### 1. Telemetry Coverage Gap

**Issue:** Telemetry only tracks 12.5% of jobs (479 of 3,829)

**Root Cause:** Phoenix server restart reset telemetry handlers, losing historical tracking

**Impact:**
- Dashboard shows incomplete picture
- Metrics don't reflect true pipeline performance
- Stakeholders can't trust monitoring data

**Fix:** Telemetry is working correctly going forward; historical data will accumulate over time

### 2. Job Meta Inconsistency

**Issue:** Cancelled jobs have `meta->>'status' = 'success'` but `state = 'cancelled'`

**Root Cause:** ShowtimeProcessJob calls `MetricsTracker.record_success()` before cancelling

**Impact:**
- Inconsistent data in Oban jobs table
- Confusing when debugging job failures
- Could mislead other systems that read job meta

**Fix:** Remove `MetricsTracker.record_success()` call in Phase 5.2.3

### 3. Metrics Formula Error

**Issue:** Phase 4 formula treats ALL cancelled jobs as "healthy"

**Root Cause:** Assumed all cancellations are intentional skips (valid for MovieDetailJob, invalid for ShowtimeProcessJob)

**Impact:**
- Dashboard shows 100% success when reality is 37.92%
- Stakeholders can't identify pipeline problems
- No visibility into 58.79% failure rate

**Fix:** Update metrics queries in Phase 5.2.2 to use cancellation reason for categorization

---

## Baseline Establishment

### Ground Truth Metrics (From Oban)

**Time Period:** 2025-11-26 15:24:15 to 2025-11-27 09:17:58 (approximately 18 hours)

| Metric | Value | Source |
|--------|-------|--------|
| **Total Jobs** | 3,829 | Oban `oban_jobs` table |
| **Completed (Success)** | 1,452 (37.92%) | `state = 'completed'` |
| **Cancelled (Failure)** | 2,251 (58.79%) | `state = 'cancelled'` with `{:cancel, :movie_not_matched}` |
| **Discarded (Hard Failure)** | 126 (3.29%) | `state = 'discarded'` |
| **True Success Rate** | 37.92% | Baseline for dashboard |
| **True Failure Rate** | 62.08% | Combined cancelled + discarded |
| **Days Covered** | 2 | Nov 26-27, 2025 |

**This is our baseline for validating Phase 5.2 fixes.**

---

## Validation Criteria

### After Phase 5.2 Implementation

**Dashboard should show:**
1. ✅ Total runs: ~3,829+ (includes all historical jobs)
2. ✅ Pipeline Health: ~37.92% (matches Oban baseline)
3. ✅ Processing Failure Rate: ~58.79% (movie_not_matched cancellations)
4. ✅ Hard Failure Rate: ~3.29% (discarded jobs)
5. ✅ State breakdown visible: completed, cancelled (failed), cancelled (expected), discarded

**Telemetry should capture:**
1. ✅ `cancel_reason` field in `results` JSONB
2. ✅ Correct state for all job types
3. ✅ No more `"status" => "success"` for cancelled jobs

**Metrics queries should:**
1. ✅ Distinguish cancellation types by reason
2. ✅ Count `cancelled (movie_not_matched)` as failures
3. ✅ Count `cancelled (other reasons)` as expected (if any exist)
4. ✅ Calculate pipeline health = `completed / total` for ShowtimeProcessJob

---

## Next Steps: Phase 5.2 Implementation

Now that we have established the baseline (37.92% success, 62.08% failure), we can proceed with Phase 5.2 to fix the metrics system.

**Phase 5.2 Sub-Tasks:**
1. **5.2.1:** Store cancellation reason in telemetry (2 hours)
2. **5.2.2:** Update metrics queries to use cancellation reason (4 hours)
3. **5.2.3:** Fix ShowtimeProcessJob to stop calling `record_success` (1 hour)
4. **5.2.4:** Update dashboard UI to show failure breakdown (2 hours)
5. **5.2.5:** Validation & testing against this baseline (2 hours)

**Success Criteria:** Dashboard metrics match this baseline report (37.92% ± 5% as new jobs execute)

---

## References

- **GitHub Issue:** [#2438 - ShowtimeProcessJob Metrics Accuracy](https://github.com/razrfly/eventasaurus/issues/2438)
- **Related Issue:** [#2427 - Cinema City Movie Not Found](https://github.com/razrfly/eventasaurus/issues/2427)
- **Phase 4 Summary:** `PHASE4_COMPLETION_SUMMARY.md`
- **ShowtimeProcessJob:** `lib/eventasaurus_discovery/sources/cinema_city/jobs/showtime_process_job.ex`
- **MetricsTracker:** `lib/eventasaurus_discovery/metrics/metrics_tracker.ex`
- **Oban Documentation:** [Job States](https://hexdocs.pm/oban/Oban.Job.html#t:state/0)

---

_Baseline report completed: 2025-11-27_
_Phase 5.1 Duration: ~1 hour_
_Status: ✅ Ready for Phase 5.2_
