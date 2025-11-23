# Phase 3: Kino Krakow Performance Analysis - Thundering Herd Problem

**Date**: 2025-11-23
**Status**: IN PROGRESS - Jitter fix implemented, testing pending
**Issue**: #2371 - Improve Cinema City and Kino Krakow scrapers

---

## Executive Summary

Phase 3 revealed a **critical discovery**: the parallel day fetching optimization was already implemented in `MoviePageJob.ex` (lines 161-200), but it created a severe **thundering herd problem** that made performance **3-6x WORSE** than the sequential baseline.

### Key Findings

✅ **Parallel optimization already exists** - Uses `Task.async_stream` with `max_concurrency: 7`
❌ **Thundering herd problem** - Multiple concurrent jobs overwhelm the server
✅ **Jitter fix implemented** - Added randomized delays to prevent simultaneous requests
⏳ **Testing pending** - New baseline collection needed to validate fix

---

## Performance Comparison

### Phase 2 Baseline (Sequential Processing, Old Code)
- **Sample Size**: 17 executions over 30 days
- **P50**: 30,520ms (30.5 seconds)
- **P95**: 31,178ms (31.2 seconds)
- **Average**: 18,571ms (18.6 seconds)
- **Success Rate**: 100%
- **Status**: ❌ **10.4x above 3,000ms SLO target**

### Recent Run (Parallel Processing WITHOUT Jitter)
- **Sample Size**: 101 executions (17:11-17:15 UTC)
- **P50**: 106,986ms (107 seconds) - **3.5x WORSE** ❌
- **P95**: 197,777ms (198 seconds) - **6.3x WORSE** ❌
- **Average**: 108,511ms (109 seconds) - **5.8x WORSE** ❌
- **Min**: 6,051ms (6 seconds) - Shows optimization CAN work ✅
- **Max**: 228,015ms (228 seconds) - Severe degradation ❌
- **Success Rate**: 100%
- **Status**: ❌ **66x above 3,000ms SLO target** (regression!)

### Performance Distribution Analysis

**Fast Jobs** (Jobs 4677-4682, first batch):
- Duration: 6-16 seconds
- Pattern: Optimization working as expected
- Proves parallel fetching CAN reduce time from 30s to 6-16s

**Moderate Jobs** (Jobs 4683-4701, middle batch):
- Duration: 17-53 seconds
- Pattern: Server starting to slow down under load

**Slow Jobs** (Jobs 4730-4777, later batches):
- Duration: 117-228 seconds
- Pattern: Severe thundering herd - server overwhelmed
- Consistent 117-228 second range across all jobs

---

## Root Cause Analysis

### The Thundering Herd Problem

**What Happened**:
1. SyncJob schedules ~101 MoviePageJobs simultaneously
2. Oban processes ~10-15 MoviePageJobs concurrently (based on queue config)
3. Each MoviePageJob spawns 7 parallel tasks (one per day)
4. Total concurrent HTTP requests: **10-15 jobs × 7 tasks = 70-105 simultaneous requests**
5. All tasks call `rate_limit_delay()` at the same time
6. They all wait exactly 2 seconds together
7. They all hit `kino.krakow.pl` simultaneously (thundering herd)
8. Server gets overwhelmed and throttles/rate limits the IP
9. Later batches experience severe slowdown (117-228 seconds)

**Evidence from Database Analysis**:

```sql
-- All jobs started at exactly 17:11:03 or 17:11:04
SELECT inserted_at, COUNT(*)
FROM oban_jobs
WHERE worker = 'KinoKrakow.Jobs.MoviePageJob'
GROUP BY inserted_at;

-- Results show:
-- 17:11:03: 10 jobs (6-48s duration)
-- 17:11:04: 91 jobs (117-228s duration)
```

### Why The Optimization Made Things Worse

**Sequential Processing** (old code):
- One movie at a time, 7 days sequentially
- Max: 1 HTTP request at a time
- Server handles load easily
- Duration: 30 seconds per movie (consistent)

**Parallel Processing WITHOUT Jitter** (current code):
- 10-15 movies concurrently, each with 7 parallel day tasks
- Max: 70-105 simultaneous HTTP requests
- Server overwhelmed, starts throttling
- Duration: 6s (first jobs) → 228s (later jobs) (degradation)

---

## The Fix: Rate Limiting with Jitter

### Implementation

**File**: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/movie_page_job.ex`
**Lines**: 398-407 (updated `rate_limit_delay/0`)

```elixir
# OLD CODE (deterministic, thundering herd):
defp rate_limit_delay do
  Process.sleep(Config.rate_limit() * 1000)  # Always exactly 2000ms
end

# NEW CODE (randomized, prevents thundering herd):
defp rate_limit_delay do
  base_delay = Config.rate_limit() * 1000  # 2000ms base
  jitter = :rand.uniform(1000)             # Random 0-1000ms
  Process.sleep(base_delay + jitter)       # Total: 2000-3000ms
end
```

### How Jitter Solves The Problem

**Without Jitter**:
- 7 parallel tasks all wait exactly 2000ms
- They all hit server at T+2000ms simultaneously
- Thundering herd → server overwhelmed

**With Jitter**:
- Task 1 waits 2000 + 347ms = 2347ms
- Task 2 waits 2000 + 891ms = 2891ms
- Task 3 waits 2000 + 123ms = 2123ms
- Task 4 waits 2000 + 756ms = 2756ms
- Task 5 waits 2000 + 29ms = 2029ms
- Task 6 waits 2000 + 634ms = 2634ms
- Task 7 waits 2000 + 912ms = 2912ms
- Requests spread out over 883ms window (instead of all at once)
- Server handles load gracefully

**Expected Impact**:
- Maintains parallel processing benefits (faster than sequential)
- Prevents thundering herd (avoids severe degradation)
- Target: P95 < 3,000ms (10x improvement from Phase 2 baseline)

---

## Testing Plan

### Step 1: Trigger New Scraper Run
- Application must compile with jitter fix
- Run `mix discovery.sync kino-krakow` or wait for scheduled run
- Monitor job execution times in database

### Step 2: Collect New Baseline
- Sample size: ~50-100 MoviePageJob executions
- Calculate P50, P95, P99, Average, StdDev
- Compare against Phase 2 baseline (30.5s P50, 31.2s P95)

### Step 3: Validate Success Criteria
✅ **P95 < 3,000ms** (currently 197,777ms without jitter, target <3,000ms)
✅ **P50 < 1,500ms** (currently 106,986ms without jitter, target <1,500ms)
✅ **Maintain 100% success rate** (currently 100%)
✅ **Avg < 2,000ms** (currently 108,511ms without jitter, target <2,000ms)

### Step 4: Document Results
- Create Phase 3 completion report
- Compare before/after baselines
- Update GitHub issue #2371

---

## Technical Details

### Parallel Processing Architecture (Already Implemented)

**File**: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/movie_page_job.ex`
**Function**: `fetch_all_days/4` (lines 161-200)

```elixir
defp fetch_all_days(movie_slug, movie_title, cookies, csrf_token) do
  Logger.info("📅 Fetching all 7 days for movie: #{movie_title} (parallel mode)")

  all_showtimes =
    0..6
    |> Task.async_stream(
      fn day_offset ->
        # Fetch showtimes for this day
        fetch_day_showtimes(movie_slug, movie_title, day_offset, cookies, csrf_token)
      end,
      max_concurrency: 7,       # All 7 days in parallel
      timeout: Config.timeout() * 2,  # 60 seconds
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, showtimes}} -> showtimes
      {:ok, {:error, _}} -> []
      {:exit, reason} -> []
    end)

  {:ok, all_showtimes}
end
```

**Configuration**:
- `Config.rate_limit()` = 2 seconds (base delay)
- `Config.timeout()` = 30,000ms (30 seconds per HTTP request)
- `max_concurrency: 7` (all days processed simultaneously)

### HTTP Request Flow Per Movie

Each MoviePageJob executes:
1. **Session establishment** (1 request):
   - GET `/film/{movie_slug}.html` to get CSRF token + cookies
   - Duration: ~500-1000ms

2. **7 parallel day fetches** (14 requests total):
   - For each day 0-6 (in parallel):
     - `rate_limit_delay()` (2000-3000ms with jitter)
     - POST `/settings/set_day/{day_offset}` to set day
     - `rate_limit_delay()` (2000-3000ms with jitter)
     - GET `/film/{movie_slug}.html` for that day's showtimes
     - Parse showtimes using MoviePageExtractor

**Expected Duration**:
- Sequential (old): 1s + (7 × (2s + POST + 2s + GET)) ≈ 30s
- Parallel with jitter: 1s + MAX(7 parallel tasks) ≈ 5-10s
- Parallel without jitter (actual): 1s + (server throttling) ≈ 6-228s (degradation)

---

## Database Queries for Analysis

### Calculate Baseline Statistics

```sql
SELECT
  COUNT(*) as total_jobs,
  ROUND(AVG(duration_ms)) as avg_ms,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration_ms) as p50,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms) as p95,
  PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) as p99,
  ROUND(STDDEV(duration_ms)) as stddev_ms
FROM (
  SELECT EXTRACT(EPOCH FROM (completed_at - inserted_at)) * 1000 as duration_ms
  FROM oban_jobs
  WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MoviePageJob'
    AND state = 'completed'
    AND completed_at BETWEEN {start_time} AND {end_time}
) t;
```

### Identify Performance Patterns

```sql
-- Find fast vs slow jobs
SELECT
  id,
  args->'movie_slug' as movie,
  ROUND(EXTRACT(EPOCH FROM (completed_at - inserted_at)) * 1000) as duration_ms,
  TO_CHAR(inserted_at, 'HH24:MI:SS') as started_at
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MoviePageJob'
  AND state = 'completed'
ORDER BY inserted_at;
```

---

## Next Steps

1. ⏳ **Wait for application recompile** with jitter fix
2. ⏳ **Trigger new test run** or wait for scheduled sync
3. ⏳ **Monitor job execution** to confirm jitter is working
4. ⏳ **Collect new baseline** from jitter run
5. ⏳ **Compare baselines** to validate improvement
6. ⏳ **Document Phase 3 completion** if success criteria met

---

## Expected Outcomes

### If Jitter Fix Works

**Performance Metrics**:
- P50: 6-10 seconds (vs 30.5s baseline) - **3-5x improvement** ✅
- P95: 12-15 seconds (vs 31.2s baseline) - **2-3x improvement** ✅
- Average: 8-12 seconds (vs 18.6s baseline) - **2x improvement** ✅
- Max: <20 seconds (vs 228s without jitter) - **11x improvement** ✅

**SLO Compliance**:
- ❌ **Still above 3,000ms SLO target** (but closer!)
- May need additional optimizations:
  1. Reduce `Config.rate_limit()` from 2s to 1s
  2. Optimize session reuse across days
  3. Implement connection pooling

### If Jitter Fix Insufficient

**Fallback Options**:
1. **Reduce concurrency**: Lower `max_concurrency` from 7 to 3-4
2. **Throttle MoviePageJobs**: Limit Oban queue concurrency to 5
3. **Hybrid approach**: Parallel for first 3 days, sequential for last 4
4. **Connection pooling**: Configure HTTPoison with persistent connections

---

## Lessons Learned

1. **Parallel processing requires jitter** - Don't assume deterministic delays are safe
2. **Monitor real-world performance** - Optimization theory ≠ production reality
3. **Thundering herd is real** - Even with rate limiting, concurrent tasks can overwhelm
4. **Test with realistic load** - Single job ≠ 101 concurrent jobs
5. **Database analysis is essential** - Logs miss patterns, database reveals truth

---

**Report Generated**: 2025-11-23
**Next Update**: After jitter test run completes
**Related**: GitHub Issue #2371, Phase 2 Baseline Reports
