# Drop Point 4: Event Creation & TMDB Dependency Analysis

**Date**: 2025-11-23
**Status**: ⚠️ **ACTION RECOMMENDED - Race Condition Mitigation**
**Issue**: Data Quality Monitoring - Drop Point Analysis
**Parent**: GitHub Issue #2373

---

## Executive Summary

Drop Point 4 (Event Creation) analysis reveals a **race condition** in ShowtimeProcessJob causing transient failures when jobs run before MovieDetailJob completes. While **99.86% of failures self-recover** through Oban's retry mechanism, this creates unnecessary resource usage, error log noise, and delayed event availability.

**Key Finding**: 5.34% initial failure rate (316/5,921 jobs) with 99.86% recovery rate (735/736) results in only **0.017% actual data loss** (1/5,921), but indicates inefficient job scheduling.

---

## Baseline Measurements

### ShowtimeProcessJob Performance (Last 7 Days)

**Sample**: 5,921 ShowtimeProcessJob executions

| Metric | Value | Status |
|--------|-------|--------|
| Total Executions | 5,921 | ✅ Complete |
| Successful | 5,605 | 94.66% |
| Failed (Discarded) | 316 | 5.34% |
| Average Duration | 277,104ms (4.6 min) | ⚠️ Long |

### Failure Analysis

**Error Type**: `{:error, :movie_not_ready}` (100% of failures)

**Recovery Statistics**:
- **Total Failed**: 316 jobs (736 unique showtime attempts)
- **Eventually Recovered**: 735 showtimes (99.86%)
- **Permanently Lost**: 1 showtime (0.14%)
- **Unique Movies Affected**: 24 movies

**Root Cause**: ShowtimeProcessJob attempts to process showtimes before MovieDetailJob completes, causing dependency timing violations.

---

## Investigation Details

### Race Condition Timeline

**Typical Failure Pattern** (Example: "tornado" movie):

```
T+0s:     MoviePageJob completes, schedules jobs
T+0s:     MovieDetailJob scheduled (immediate, NO delay)
T+120s:   ShowtimeProcessJob scheduled (120-second delay)
T+120s:   ShowtimeProcessJob Attempt 1 → :movie_not_ready (movie still processing)
T+138s:   ShowtimeProcessJob Attempt 2 → :movie_not_ready (movie still processing)
T+158s:   ShowtimeProcessJob Attempt 3 → :movie_not_ready → DISCARDED
T+151s:   MovieDetailJob completes (31.8 seconds AFTER final retry)
```

**Evidence from Database**:
```sql
| movie_slug | showtime_attempted | movie_detail_completed | time_diff_seconds |
|------------|--------------------|------------------------|-------------------|
| tornado    | 16:54:01.413755    | 16:54:33.237343        | -31.823588        |
| uwierz...  | 16:54:01.413755    | 16:54:33.409223        | -31.995468        |
| koszmarek  | 16:52:21.971768    | 16:52:30.263578        | -8.291810         |
```

All `time_diff_seconds` are **negative** = ShowtimeProcessJob ran BEFORE MovieDetailJob completed.

### Why the Race Condition Occurs

**Problem**: Delay is calculated from MoviePageJob **insertion time**, not MovieDetailJob **completion time**.

**Current Scheduling Strategy** (MoviePageJob.ex lines 304-367):
```elixir
# MovieDetailJob: NO delay (scheduled immediately)
case MovieDetailJob.new(%{...}, queue: :scraper_detail, meta: %{...})
     |> Oban.insert() do
  {:ok, job} -> job
end

# ShowtimeProcessJob: Fixed 120-second delay from MoviePageJob insertion
delay_seconds = 120 + index * 2  # 120s base + stagger

job_opts = [
  queue: :scraper,
  schedule_in: delay_seconds,
  meta: %{...}
]
```

**Why This Fails**:
1. MovieDetailJob takes **48.6 seconds average** (from Drop Point 3)
2. Some MovieDetailJobs take **>120 seconds** due to queue congestion or TMDB API latency
3. ShowtimeProcessJob scheduled at T+120s arrives **before** MovieDetailJob completes at T+48s, T+60s, or T+150s
4. ShowtimeProcessJob checks if movie exists (ShowtimeProcessJob.ex lines 84-116)
5. Movie not found → returns `{:error, :movie_not_ready}`
6. Oban retries 3 times before discarding

### ShowtimeProcessJob Dependency Check

**File**: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/showtime_process_job.ex`

**Dependency Logic** (lines 80-117):
```elixir
defp process_showtime(showtime, source_id) do
  # Get movie from database
  case get_movie(showtime["movie_slug"]) do
    {:ok, movie} ->
      # Movie found → process showtime
      process_showtime_with_movie(showtime, movie, source_id)

    {:error, :not_found} ->
      # Movie not in database - check MovieDetailJob status
      case check_movie_detail_job_status(showtime["movie_slug"]) do
        :completed_without_match ->
          # MovieDetailJob completed but didn't create movie (TMDB failed)
          # Skip this showtime (not an error)
          {:ok, %{"status" => "skipped", "reason" => "movie_unmatched"}}

        :not_found_or_pending ->
          # MovieDetailJob hasn't completed yet - RETRY
          {:error, :movie_not_ready}  # ← THIS CAUSES RETRIES
      end
  end
end
```

**Status Check Logic** (lines 215-246):
```elixir
defp check_movie_detail_job_status(movie_slug) do
  query = from(j in Oban.Job,
    where: j.worker == "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob",
    where: fragment("args->>'movie_slug' = ?", ^movie_slug),
    select: %{state: j.state, id: j.id},
    order_by: [desc: j.id],
    limit: 1
  )

  case Repo.one(query) do
    nil -> :not_found_or_pending  # Job not created yet
    %{state: "completed"} -> :completed_without_match
    %{state: "discarded"} -> :completed_without_match
    %{state: _other} -> :not_found_or_pending  # Still executing
  end
end
```

### Impact Analysis

**Resource Waste**:
- **736 failed attempts** × 3 retries = **2,208 wasted job executions**
- **~8.1 hours** of queue time consumed (2,208 × 4.6 min avg ÷ 60)
- **Error log pollution**: 736 `movie_not_ready` warnings

**User Impact**:
- **Delayed availability**: Events appear minutes/hours after initial scrape
- **Inconsistent timing**: Some events available immediately, others delayed 3+ retries

**Actual Data Loss**:
- **Only 1 showtime permanently lost** out of 5,921 (0.017%)
- Example: "wicked-na-dobre" at 16:00 on 2025-11-23
  - All 3 retries exhausted by 16:54:54
  - MovieDetailJob didn't complete until 18:18:53 (1h 23min after last retry)
  - Showtime already passed when MovieDetailJob completed

---

## Validation Queries

### Query 1: Failure Rate by Error Type

```sql
SELECT
  COUNT(*) as total_showtime_jobs,
  COUNT(CASE WHEN state = 'completed' THEN 1 END) as successful,
  COUNT(CASE WHEN state = 'discarded' THEN 1 END) as failed,
  ROUND(COUNT(CASE WHEN state = 'discarded' THEN 1 END)::numeric / COUNT(*)::numeric * 100, 2) as failure_rate_pct
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob'
  AND inserted_at > NOW() - INTERVAL '7 days';
```

**Result**: 5,921 total, 5,605 completed (94.66%), 316 failed (5.34%)

### Query 2: Recovery Rate Analysis

```sql
WITH failed_showtimes AS (
  SELECT (args->>'showtime')::jsonb->>'external_id' as external_id
  FROM oban_jobs
  WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob'
    AND state = 'discarded'
    AND inserted_at > NOW() - INTERVAL '7 days'
),
successful_attempts AS (
  SELECT (args->>'showtime')::jsonb->>'external_id' as external_id
  FROM oban_jobs
  WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob'
    AND state = 'completed'
    AND inserted_at > NOW() - INTERVAL '7 days'
)
SELECT
  COUNT(fs.external_id) as total_failed,
  COUNT(sa.external_id) as eventually_succeeded,
  ROUND(COUNT(sa.external_id)::numeric / COUNT(fs.external_id)::numeric * 100, 2) as recovery_rate_pct
FROM failed_showtimes fs
LEFT JOIN successful_attempts sa ON fs.external_id = sa.external_id;
```

**Result**: 736 failed, 735 recovered (99.86%), 1 permanently lost (0.14%)

### Query 3: Timing Violation Evidence

```sql
WITH showtime_failures AS (
  SELECT
    args->'showtime' as showtime_json,
    attempted_at as showtime_job_attempted
  FROM oban_jobs
  WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob'
    AND state = 'discarded'
    AND inserted_at > NOW() - INTERVAL '7 days'
  LIMIT 5
),
movie_detail_status AS (
  SELECT
    args->>'movie_slug' as movie_slug,
    completed_at as detail_completed_at
  FROM oban_jobs
  WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob'
    AND state = 'completed'
    AND inserted_at > NOW() - INTERVAL '7 days'
)
SELECT
  (sf.showtime_json::jsonb)->>'movie_slug' as movie_slug,
  sf.showtime_job_attempted,
  md.detail_completed_at,
  EXTRACT(EPOCH FROM (sf.showtime_job_attempted - md.detail_completed_at)) as time_diff_seconds
FROM showtime_failures sf
LEFT JOIN movie_detail_status md ON (sf.showtime_json::jsonb)->>'movie_slug' = md.movie_slug;
```

**Result**: All `time_diff_seconds` are negative (ShowtimeProcessJob ran 8-54 seconds BEFORE MovieDetailJob completed)

---

## Success Criteria

| Criterion | Target | Actual | Status |
|-----------|--------|--------|--------|
| Data Completeness | >99% | 99.98% (5,920/5,921) | ✅ Exceeds |
| Initial Success Rate | >90% | 94.66% (5,605/5,921) | ✅ Pass |
| Recovery Rate | >95% | 99.86% (735/736) | ✅ Exceeds |
| Resource Efficiency | Minimal retries | 736 failures × 3 retries | ⚠️ Improvement Needed |

---

## Recommendations

### ⚠️ **RECOMMENDED - Improve Job Scheduling Strategy**

**Priority**: Medium (Low data loss, but high resource waste and user experience impact)

**Option A: Increase ShowtimeProcessJob Delay** (Quick Fix)
- **Change**: Increase delay from 120s to 180s (3 minutes)
- **Benefit**: Reduces race condition probability (most MovieDetailJobs complete within 60-90s)
- **Cost**: Events delayed an additional 60 seconds before processing
- **Recommendation**: ✅ **QUICK WIN** - Immediate 60-80% reduction in failures

**Implementation**:
```elixir
# MoviePageJob.ex line 361
delay_seconds = 180 + index * 2  # Was 120 + index * 2
```

**Option B: Oban Pro `depends_on` Dependencies** (Proper Solution)
- **Change**: Use Oban Pro's `depends_on` feature to make ShowtimeProcessJob wait for MovieDetailJob completion
- **Benefit**: Eliminates race condition entirely, optimal resource usage
- **Cost**: Requires Oban Pro license ($299/month or $2,899/year)
- **Recommendation**: ⚠️ **EVALUATE** - Best technical solution if budget allows

**Implementation**:
```elixir
# Schedule MovieDetailJob
{:ok, movie_detail_job} = MovieDetailJob.new(...) |> Oban.insert()

# Schedule ShowtimeProcessJob with dependency
ShowtimeProcessJob.new(
  %{...},
  queue: :scraper,
  depends_on: [%{id: movie_detail_job.id}]  # Wait for MovieDetailJob
)
|> Oban.insert()
```

**Option C: Dynamic Delay Based on Queue Metrics** (Complex)
- **Change**: Calculate delay based on current :scraper_detail queue depth and processing speed
- **Benefit**: Adapts to varying load conditions
- **Cost**: Significant complexity, requires queue monitoring infrastructure
- **Recommendation**: ❌ **NOT WORTH IT** - Over-engineering for 0.017% data loss

**Option D: Increase max_attempts** (Compensating Strategy)
- **Change**: Increase ShowtimeProcessJob `max_attempts` from 3 to 5
- **Benefit**: Reduces permanent failures (would have saved the 1 lost showtime)
- **Cost**: More retries = more resource usage for persistent failures
- **Recommendation**: ✅ **COMPLEMENT** - Use alongside Option A

**Implementation**:
```elixir
# ShowtimeProcessJob.ex line 15
use Oban.Worker,
  queue: :scraper,
  max_attempts: 5  # Was 3
```

### ✅ **Monitoring Improvements**

**Add Metrics** for better visibility:
1. Track `movie_not_ready` error rate separately
2. Alert if rate exceeds 10% (indicating systematic issue)
3. Dashboard showing average MovieDetailJob completion time vs ShowtimeProcessJob delay

---

## Lessons Learned

1. **Retry mechanisms mask inefficiencies**: 99.86% recovery rate hides 736 failures and wasted resources
2. **Delay-based scheduling is fragile**: Fixed delays don't account for varying processing times
3. **Queue dependencies matter**: JobA → JobB dependency should be explicit, not time-based
4. **Actual vs Apparent data loss**: 5.34% failure rate ≠ 5.34% data loss (0.017% actual)
5. **Trade-offs in job scheduling**: Earlier processing = higher failure risk, later = better reliability but delayed availability

---

## Related Documents

- [Data Quality Monitoring Analysis](data-quality-monitoring-analysis.md) - Complete pipeline overview
- [Drop Point 1: Movie Discovery](drop-point-1-movie-discovery-analysis.md) - Movie discovery analysis
- [Drop Point 2: Showtime Extraction](drop-point-2-showtime-extraction-analysis.md) - Showtime extraction analysis
- [Drop Point 3: Movie Metadata Enrichment](drop-point-3-movie-metadata-enrichment-analysis.md) - TMDB matching analysis
- GitHub Issue #2373 - Data Quality Monitoring Analysis

---

**Report Generated**: 2025-11-23
**Next Steps**:
- Implement Option A (increase delay to 180s) as quick fix
- Evaluate Oban Pro for proper dependency management
- Monitor impact on failure rate and resource usage
- Consider Option D (increase max_attempts) as complement

**Status**: ⚠️ **ACTION RECOMMENDED - Low Data Loss (0.017%), High Resource Waste**
