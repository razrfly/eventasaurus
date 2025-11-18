# Kino Krakow: ShowtimeProcessJob Failing with `:movie_not_ready` (100% Failure Rate)

## Problem Statement

**Status**: 🔴 Critical - 100% of showtime processing jobs are failing
**Symptom**: ShowtimeProcessJob fails with `{:error, :movie_not_ready}` on every attempt
**Impact**: Zero movie showtimes are being created from Kino Krakow scraper

## User Observation (Critical)

> "This happens 100% of the time because none of them get created ever. I find it hard to believe queue congestion causes 100% failures."

**This is a valid point.** Queue congestion might cause *intermittent* failures, but a 100% failure rate indicates a **systematic bug** beyond just timing issues.

## Error Details

### Example Failed Job

```
Job: EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob
Queue: scraper
Attempt: 2 of 3
Status: Failed

Args:
%{
  "showtime" => %{
    "cinema_name" => "Cinema City Bonarka",
    "cinema_slug" => "cinema-city/bonarka",
    "datetime" => "2025-11-18T20:50:00Z",
    "external_id" => "kino_krakow_aniol-stroz_cinema-city_bonarka_2025-11-18_20_50",
    "movie_slug" => "aniol-stroz",
    "movie_title" => "Anioł Stróż",
    "ticket_url" => "https://www.kino.krakow.pl/showtime/20021845"
  },
  "source_id" => 13
}

Error:
** (Oban.PerformError) EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob
   failed with {:error, :movie_not_ready}
```

## Investigation Findings

### ✅ Movie EXISTS in Database

**Query**:
```sql
SELECT id, tmdb_id, title, original_title, metadata
FROM movies
WHERE metadata->>'kino_krakow_slug' = 'aniol-stroz';
```

**Result**:
```
id: 7
tmdb_id: 1114967
title: "Good Fortune"
original_title: "Good Fortune"
metadata.kino_krakow_slug: "aniol-stroz" ✅
```

**Conclusion**: The movie is properly created with the correct slug in metadata.

### ✅ MovieDetailJob Completed Successfully

**Query**:
```sql
SELECT id, worker, state, args->>'movie_slug' as movie_slug,
       inserted_at, scheduled_at, attempted_at, completed_at
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob'
  AND args->>'movie_slug' = 'aniol-stroz';
```

**Result**:
```
id: 112
state: completed
inserted_at:  2025-11-18 14:01:15
scheduled_at: 2025-11-18 14:01:15
attempted_at: 2025-11-18 14:04:58  (⚠️ 3min 43s wait)
completed_at: 2025-11-18 14:04:58
```

**Conclusion**: MovieDetailJob completed successfully and created the movie.

### ❌ ShowtimeProcessJob Runs Too Early

**Timeline**:
```
14:01:15 - MovieDetailJob scheduled
14:03:17 - ShowtimeProcessJob Attempt 1 (101s before movie ready) ❌
14:03:34 - ShowtimeProcessJob Attempt 2 (84s before movie ready) ❌
14:04:58 - MovieDetailJob executes and completes (movie now ready)
14:05:XX - ShowtimeProcessJob Attempt 3 should succeed...but doesn't? 🤔
```

## Two Separate Issues Identified

### Issue #1: Queue Congestion (Timing Problem)

**Current State**:
- `scraper_detail` queue: 116 jobs waiting
- Concurrency: 3 workers only
- Estimated wait time: ~270 seconds (4.5 minutes)

**Code Assumption** (movie_page_job.ex:265):
```elixir
base_delay = movie_count * rate_limit + 120  # Assumes 120s is enough
```

**Reality**: Queue backlog adds 3-4 minutes of wait time.

**Expected Impact**: Some jobs fail, some succeed (depending on queue load at the time)

### Issue #2: Systematic Bug (100% Failure Rate) ⚠️

**The Mystery**: Even after MovieDetailJob completes and movie exists in database, ShowtimeProcessJob continues to fail on retry attempts.

**Why This Doesn't Make Sense**:
1. ShowtimeProcessJob has 3 attempts with delays
2. By Attempt 2-3, MovieDetailJob should be complete
3. Movie exists in database with correct metadata
4. Query `WHERE metadata->>'kino_krakow_slug' = 'aniol-stroz'` returns the movie
5. Yet the job still fails with `:movie_not_ready`

**Possible Root Causes**:

#### A. Bug in `get_movie()` Query Logic

**File**: `showtime_process_job.ex:188-200`

```elixir
defp get_movie(movie_slug) do
  query =
    from(m in EventasaurusDiscovery.Movies.Movie,
      where: fragment("?->>'kino_krakow_slug' = ?", m.metadata, ^movie_slug)
    )

  case Repo.one(query) do
    nil -> {:error, :not_found}
    movie -> {:ok, movie}
  end
end
```

**Potential Issues**:
- [ ] Case sensitivity mismatch in slug comparison
- [ ] Metadata field is NULL instead of %{} (even though DB shows it's not)
- [ ] JSONB query syntax issue
- [ ] Database connection issue (different DB instance?)
- [ ] Transaction isolation preventing visibility of committed data

#### B. Bug in `check_movie_detail_job_status()` Logic

**File**: `showtime_process_job.ex:204-235`

```elixir
defp check_movie_detail_job_status(movie_slug) do
  query =
    from(j in Oban.Job,
      where: j.worker == "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob",
      where: fragment("args->>'movie_slug' = ?", ^movie_slug),
      select: %{state: j.state, id: j.id},
      order_by: [desc: j.id],
      limit: 1
    )

  case Repo.one(query) do
    nil ->
      :not_found_or_pending

    %{state: "completed"} ->
      :completed_without_match  # ⚠️ Assumes movie doesn't exist

    %{state: state} when state in ["discarded"] ->
      :completed_without_match

    %{state: state} when state in ["retryable"] ->
      :not_found_or_pending

    %{state: _other} ->
      :not_found_or_pending
  end
end
```

**CRITICAL LOGIC ISSUE**:
When MovieDetailJob is "completed", the function returns `:completed_without_match`, which causes ShowtimeProcessJob to skip the event with `{:ok, :skipped}`.

But this ONLY happens if `get_movie()` returns `{:error, :not_found}` first.

**The Logic**:
```elixir
case get_movie(showtime["movie_slug"]) do
  {:ok, movie} ->
    # Movie found, process normally
    process_showtime_with_movie(...)

  {:error, :not_found} ->
    # Movie NOT found, check why
    case check_movie_detail_job_status(showtime["movie_slug"]) do
      :completed_without_match ->
        # Job finished but didn't create movie (TMDB match failed)
        {:ok, :skipped}

      :not_found_or_pending ->
        # Job hasn't finished yet, retry later
        {:error, :movie_not_ready}
    end
end
```

**Question**: If the movie exists but the query fails to find it, why?

#### C. Slug Format Mismatch

**Potential Issue**: The slug being queried might be different from the slug stored.

**Example**:
- Stored in DB: `"aniol-stroz"`
- Queried with: `"aniol-stroz"` with extra whitespace?
- Or URL encoding difference?
- Or case difference?

**Need to verify**:
- [ ] Log the actual `movie_slug` value being queried
- [ ] Compare byte-for-byte with database value
- [ ] Check for Unicode normalization issues

#### D. Silent Failure in `store_kino_krakow_slug()`

**File**: `movie_detail_job.ex:154-171`

```elixir
defp store_kino_krakow_slug(movie, kino_slug) do
  updated_metadata = Map.put(movie.metadata || %{}, "kino_krakow_slug", kino_slug)

  case EventasaurusDiscovery.Movies.MovieStore.update_movie(movie, %{metadata: updated_metadata}) do
    {:ok, _updated_movie} ->
      Logger.debug("💾 Stored Kino Krakow slug...")
      :ok

    {:error, changeset} ->
      Logger.error("❌ Failed to store Kino Krakow slug...")
      :error  # ⚠️ Returns :error but caller ignores it!
  end
end
```

**CRITICAL BUG** (movie_detail_job.ex:69-90):
```elixir
{:ok, movie} ->
  # Store slug in metadata
  store_kino_krakow_slug(movie, movie_slug)  # ⚠️ Return value IGNORED!

  # Job completes successfully regardless
  {:ok, %{
    status: :matched,
    confidence: confidence,
    movie_id: movie.id,
    ...
  }}
```

**If this update fails**:
- Movie exists in database ✅
- MovieDetailJob shows as "completed" ✅
- But `metadata.kino_krakow_slug` is NULL or missing ❌
- ShowtimeProcessJob can't find the movie ❌

**But wait**: Manual query shows the slug IS stored, so this isn't the issue for "aniol-stroz".

#### E. Retry Timing Issues

**ShowtimeProcessJob retry configuration**:
```elixir
use Oban.Worker,
  queue: :scraper,
  max_attempts: 3
```

**Default retry schedule**: Exponential backoff (1s, 16s, 64s, etc.)

**Question**: Are the retries happening too quickly, before the metadata update commits?

- Attempt 1: T+122s (too early)
- Attempt 2: T+138s (16s later, still too early)
- Attempt 3: T+202s (64s later, should be ready by now...)

**If Attempt 3 also fails**, this rules out timing and suggests query/logic bug.

## Architecture Context

### Recent Changes (Commit 822cdbd4)

The scraper architecture was completely rewritten:

**Old (Working)**:
```
SyncJob
  → DayPageJob (7 instances for days 0-6)
    → MovieDetailJob (unique movies)
    → ShowtimeProcessJob (showtimes)
```

**New (Current/Broken)**:
```
SyncJob
  → MoviePageJob (1 per movie)
    → MovieDetailJob
    → ShowtimeProcessJob
```

**Changes**:
- Removed DayPageJob entirely
- Added MovieListExtractor
- Added MoviePageJob that loops through days 0-6
- All MovieDetailJobs hit scraper_detail queue simultaneously

**User Statement**: "This previously worked in the previous branch"

## Diagnostic Plan

### Step 1: Add Debug Logging

**In `showtime_process_job.ex:get_movie/1`**:
```elixir
defp get_movie(movie_slug) do
  Logger.info("🔍 Looking up movie with slug: #{inspect(movie_slug)} (length: #{String.length(movie_slug)})")

  query =
    from(m in EventasaurusDiscovery.Movies.Movie,
      where: fragment("?->>'kino_krakow_slug' = ?", m.metadata, ^movie_slug)
    )

  result = Repo.one(query)

  Logger.info("🔍 Query result: #{inspect(result)}")

  case result do
    nil ->
      Logger.warning("❌ Movie not found for slug: #{inspect(movie_slug)}")
      {:error, :not_found}
    movie ->
      Logger.info("✅ Found movie: #{movie.title} (ID: #{movie.id})")
      {:ok, movie}
  end
end
```

### Step 2: Verify Slug Values

**Run this query to compare**:
```sql
-- Check what slugs are actually stored
SELECT id, title, metadata->>'kino_krakow_slug' as stored_slug
FROM movies
WHERE metadata ? 'kino_krakow_slug'
ORDER BY id DESC
LIMIT 20;

-- Check what slugs are being requested
SELECT args->>'showtime'->>'movie_slug' as requested_slug, COUNT(*)
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob'
  AND state = 'retryable'
GROUP BY requested_slug;
```

### Step 3: Test Query Directly

**In IEx**:
```elixir
# Test the exact query that's failing
movie_slug = "aniol-stroz"

query = from(m in EventasaurusDiscovery.Movies.Movie,
  where: fragment("?->>'kino_krakow_slug' = ?", m.metadata, ^movie_slug)
)

Repo.one(query)
# Should return the movie or nil

# Also try
Repo.all(query)  # See if multiple matches

# Try case-insensitive
query2 = from(m in EventasaurusDiscovery.Movies.Movie,
  where: fragment("LOWER(?->>'kino_krakow_slug') = LOWER(?)", m.metadata, ^movie_slug)
)

Repo.one(query2)
```

### Step 4: Check Job Execution Order

**Query to verify timing**:
```sql
-- For a specific movie, see the order of job attempts
WITH movie_slug AS (SELECT 'aniol-stroz' as slug)
SELECT
  j.id,
  j.worker,
  j.state,
  j.attempt,
  j.inserted_at,
  j.attempted_at,
  j.completed_at,
  j.discarded_at
FROM oban_jobs j, movie_slug
WHERE
  (j.worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob'
   AND j.args->>'movie_slug' = movie_slug.slug)
  OR
  (j.worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob'
   AND j.args->'showtime'->>'movie_slug' = movie_slug.slug)
ORDER BY j.attempted_at ASC NULLS LAST;
```

### Step 5: Monitor Attempt 3

**Question**: Does Attempt 3 also fail?

If yes → Query/logic bug (movie exists but can't be found)
If no → Pure timing issue (but doesn't explain 100% failure rate)

## Potential Solutions (Not Implementing)

### Solution 1: Fix Silent Failure in store_kino_krakow_slug

**Change** (movie_detail_job.ex:69-90):
```elixir
{:ok, movie} ->
  # Store slug - MUST succeed or fail the job
  case store_kino_krakow_slug(movie, movie_slug) do
    :ok ->
      {:ok, %{
        status: :matched,
        confidence: confidence,
        movie_id: movie.id,
        ...
      }}

    :error ->
      # Fail the job so it retries
      {:error, "Failed to store kino_krakow_slug in metadata"}
  end
```

### Solution 2: Increase Queue Concurrency

**Change** (config/config.exs):
```elixir
scraper_detail: 15  # Was: 3
```

**Effect**: Reduces queue wait from ~270s to ~54s

### Solution 3: Increase Base Delay

**Change** (movie_page_job.ex:265):
```elixir
base_delay = movie_count * rate_limit + 300  # Was: 120
```

**Effect**: Gives more time for MovieDetailJob to complete

### Solution 4: Use Oban Job Dependencies

**Change** (movie_page_job.ex):
```elixir
# Make ShowtimeProcessJob depend on MovieDetailJob
ShowtimeProcessJob.new(...)
|> Oban.insert(
  schedule_in: 2,
  deps: [%{worker: "MovieDetailJob", args: %{"movie_slug" => movie_slug}}]
)
```

**Effect**: ShowtimeProcessJob won't run until MovieDetailJob completes

### Solution 5: Revert to DayPageJob Architecture

**Change**: Git revert to commit ff1584a5 "before the cleaning"

**Effect**: Return to known working state

### Solution 6: Add Fallback Lookup

**Change** (showtime_process_job.ex):
```elixir
defp get_movie(movie_slug) do
  # Try primary lookup
  query = from(m in EventasaurusDiscovery.Movies.Movie,
    where: fragment("?->>'kino_krakow_slug' = ?", m.metadata, ^movie_slug)
  )

  case Repo.one(query) do
    nil ->
      # Fallback: Try finding by title match if slug lookup fails
      # (In case slug storage failed but movie exists)
      fallback_lookup_by_title(movie_slug)

    movie ->
      {:ok, movie}
  end
end
```

## Questions for Further Investigation

1. **Why does the manual query work but the code query fails?**
   - Same database?
   - Same Repo configuration?
   - Transaction isolation level?

2. **What happens on Attempt 3?**
   - Does it succeed (suggesting timing)?
   - Does it fail (suggesting bug)?

3. **Are ALL movies failing or just some?**
   - If some succeed: Pattern in the failures?
   - If all fail: Systematic issue confirmed

4. **What changed between branches?**
   - Code changes: ✅ Documented (MoviePageJob architecture)
   - Config changes: ❓ Unknown
   - Database migrations: ❓ Unknown

5. **Is the error consistent across all ShowtimeProcessJobs?**
   - Same error message?
   - Same timing pattern?
   - Same retry behavior?

## Recommendations

### Immediate (P0)

1. ✅ Add debug logging to `get_movie()` to see actual query values
2. ✅ Run diagnostic queries to compare stored vs requested slugs
3. ✅ Test the query directly in IEx to verify it works
4. ✅ Monitor if Attempt 3 succeeds or fails

### Short-term (P1)

1. Fix the silent failure in `store_kino_krakow_slug()` (make it fail the job if update fails)
2. Increase `scraper_detail` queue concurrency to 15-20
3. Consider reverting to DayPageJob architecture as emergency fix

### Long-term (P2)

1. Implement Oban job dependencies for proper sequencing
2. Review and optimize overall job architecture
3. Add monitoring/alerting for job failure rates

## Related Issues

- #2285 - Race condition in day selection (separate issue, different problem)

---

**Created**: 2025-11-18
**Status**: Investigation Required
**Priority**: P0 - Critical
**Affects**: 100% of Kino Krakow showtimes
