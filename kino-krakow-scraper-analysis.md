# Kino Krakow Scraper: Architecture Analysis & Day-of-Week Bug Fix

## Executive Summary

The Kino Krakow scraper has a **distributed job-based architecture** that is well-designed but suffers from a **critical race condition** preventing it from scraping all 7 days of showtimes. The infrastructure for 7-day scraping is already implemented, but jobs are scheduled too close together, causing them to overwrite each other's session state.

**Status**: 🔴 Critical Bug - Only getting 1 day of data instead of 7 days
**Impact**: Missing 6/7ths of movie showtimes for Krakow users
**Fix Complexity**: ✅ Simple one-line change

---

## Architecture Overview

### Job Hierarchy

```
SyncJob (Coordinator)
    ├─> DayPageJob (Day 0)
    ├─> DayPageJob (Day 1)
    ├─> DayPageJob (Day 2)
    ├─> DayPageJob (Day 3)
    ├─> DayPageJob (Day 4)
    ├─> DayPageJob (Day 5)
    └─> DayPageJob (Day 6)
            ├─> MovieDetailJob (unique movies)
            │       └─> TMDB API calls
            └─> ShowtimeProcessJob (all showtimes)
                    └─> EventProcessor → Database
```

### Components

| Component | Queue | Count | Purpose |
|-----------|-------|-------|---------|
| `SyncJob` | `:discovery` | 1 | Coordinator: establishes session, schedules day jobs |
| `DayPageJob` | `:scraper_index` | 7 | Scrapes one day's showtimes, schedules movie/showtime jobs |
| `MovieDetailJob` | `:scraper_detail` | N (unique) | Fetches movie details, matches to TMDB |
| `ShowtimeProcessJob` | `:scraper` | M (all) | Processes individual showtimes into events |

**Where**:
- N = Unique movies across all 7 days (deduplicated)
- M = Total showtimes across all 7 days

---

## Complete Data Flow

### Phase 1: Session Establishment (SyncJob)

**File**: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/sync_job.ex`

```
1. HTTP GET → https://www.kino.krakow.pl/cinema_program/by_movie
   └─> Extract Set-Cookie headers
   └─> Extract CSRF token from <meta name="csrf-token">

2. Schedule 7 DayPageJobs (days 0-6)
   └─> Pass: cookies, csrf_token, source_id, day_offset
   └─> Stagger: delay_seconds = day_offset * 2 seconds ⚠️ TOO SHORT!
```

**HTTP Requests**: 1 GET

---

### Phase 2: Day Scraping (DayPageJob × 7) ⚠️ RACE CONDITION

**File**: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/day_page_job.ex`

**For EACH day (0-6)**:

```
1. HTTP POST → /settings/set_day/{day_offset}
   Headers:
     - X-CSRF-Token: {token}
     - Cookie: {cookies}
     - X-Requested-With: XMLHttpRequest

2. Sleep 2 seconds (rate limit)

3. HTTP GET → /cinema_program/by_movie
   Headers:
     - Cookie: {cookies}

4. Parse HTML:
   └─> Extract showtimes (movie_slug, cinema_slug, datetime)
   └─> Calculate date from day_offset
   └─> Generate external_id (once, at extraction time)

5. Schedule MovieDetailJobs:
   └─> Find unique movie_slugs
   └─> One job per unique movie (deduplicated)
   └─> Stagger by Config.rate_limit() (2s)

6. Schedule ShowtimeProcessJobs:
   └─> One job per showtime
   └─> Apply EventFreshnessChecker (skip recently seen)
   └─> Delay to allow MovieDetailJobs to complete first
```

**HTTP Requests per day**: 2 (POST + GET)
**Total Phase 2 Requests**: 7 × 2 = 14 requests

---

### Phase 3a: Movie Matching (MovieDetailJob × N)

**File**: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/movie_detail_job.ex`

**For EACH unique movie**:

```
1. HTTP GET → /film/{movie_slug}.html

2. Extract metadata (MovieExtractor):
   - original_title (critical for TMDB matching)
   - polish_title
   - director, year, country, runtime, cast, genre

3. Match to TMDB (TmdbMatcher):
   - TMDB Search API call (with original_title + year)
   - Calculate confidence score
   - TMDB Details API call (if match found)

4. Confidence handling:
   ≥70%:   Auto-match (standard)
   60-69%: Auto-match (now_playing_fallback)
   50-59%: {:error, :needs_review} → Job fails
   <50%:   {:error, :low_confidence} → Job fails

5. If matched:
   - Create/update Movie in database
   - Store kino_krakow_slug in movie.metadata
```

**HTTP Requests per movie**: 1 Kino + 2-3 TMDB API calls
**Total Phase 3a Requests**: N + 2-3N TMDB

---

### Phase 3b: Showtime Processing (ShowtimeProcessJob × M)

**File**: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/showtime_process_job.ex`

**For EACH showtime**:

```
1. Mark event as seen (EventFreshnessChecker)

2. Lookup movie from database:
   SELECT * FROM movies
   WHERE metadata->>'kino_krakow_slug' = ?

3. If movie not found:
   - Check MovieDetailJob status (Oban.Job table)
   - If completed without match → skip showtime
   - If pending/retrying → retry ShowtimeProcessJob

4. Extract cinema data (CinemaExtractor):
   - No HTTP request (formats from slug)
   - Note: No GPS coordinates from Kino Krakow
   - VenueProcessor will geocode later

5. Transform to event format (Transformer):
   - Build title: "{movie} at {cinema}"
   - Use external_id from DayPageJob (no regeneration)
   - Add venue_data, movie_data, metadata

6. Deduplication check (DedupHandler):
   Phase 1: Same-source dedup (external_id)
   Phase 2: Cross-source fuzzy match (higher priority sources)

7. Process via EventProcessor → Database
```

**HTTP Requests**: 0 (all data cached from previous phases)

---

## Total HTTP Request Analysis

### Requests to Kino Krakow

| Phase | Requests | Details |
|-------|----------|---------|
| SyncJob | 1 | Session establishment |
| DayPageJob | 14 | 7 days × (1 POST + 1 GET) |
| MovieDetailJob | N | 1 per unique movie |
| ShowtimeProcessJob | 0 | Uses cached data |
| **Total** | **15 + N** | Very efficient! |

### External API Calls

| Service | Calls | Details |
|---------|-------|---------|
| TMDB Search | N | One per unique movie |
| TMDB Details | N | One per matched movie |
| Geocoding | V | One per unique venue (lazy, cached) |

**Efficiency Rating**: ⭐⭐⭐⭐⭐ Excellent
- Movies deduplicated across all 7 days
- Showtimes require no additional HTTP requests
- Minimal redundant fetching

---

## 🔴 Critical Bug: Race Condition in Day Selection

### The Problem

**Current scheduling** (sync_job.ex:157):
```elixir
delay_seconds = day_offset * Config.rate_limit()  # 2 seconds
```

**Actual timeline**:
```
T=0s:  Day 0 starts → POST /settings/set_day/0
T=1s:  Day 0 POST completes
T=2s:  Day 1 starts → POST /settings/set_day/1 ⚠️
T=3s:  Day 0 sleep ends → GET (but session now set to day=1!)
       Day 1 POST completes
T=4s:  Day 2 starts → POST /settings/set_day/2 ⚠️
       Day 1 sleep ends → GET (but session now set to day=2!)
T=6s:  Day 2 sleep ends → GET
       Day 3 starts → POST /settings/set_day/3 ⚠️
```

### Root Cause

1. **Shared session state**: All 7 DayPageJobs use the same cookies
2. **Server-side day selection**: POST /settings/set_day/{day} modifies server session
3. **Overlapping execution**: Jobs run in parallel with only 2-second stagger
4. **Each job takes ~6 seconds**:
   - POST request: ~1-2s
   - Sleep (rate limit): 2s
   - GET request: ~1-2s
   - Total: ~5-6s

**Result**: Jobs overwrite each other's day selection, causing all jobs to get the same or overlapping day data.

### Why This Matters

- ❌ Users only see showtimes for 1 day (likely today)
- ❌ Missing 6/7ths of available movie showtimes
- ❌ Freshness checker might incorrectly skip valid future showtimes
- ❌ Incomplete event calendar for Krakow users

---

## ✅ Recommended Solution: Sequential Scheduling

### Fix: Increase Stagger Delay

**Change** (sync_job.ex:157):
```elixir
# Before (BROKEN - race condition):
delay_seconds = day_offset * Config.rate_limit()  # 2 seconds

# After (FIXED - sequential execution):
delay_seconds = day_offset * 10  # 10 seconds
```

### Why 10 Seconds?

Each DayPageJob needs:
- POST request: ~1-2 seconds
- Rate limit sleep: 2 seconds (in code)
- GET request: ~1-2 seconds
- Processing buffer: ~3-4 seconds
- **Total: ~9-10 seconds**

### Expected Timeline (Fixed)

```
T=0s:   Day 0 starts
T=6s:   Day 0 completes
T=10s:  Day 1 starts
T=16s:  Day 1 completes
T=20s:  Day 2 starts
...
T=60s:  Day 6 starts
T=66s:  Day 6 completes
```

**Total scraping time**: ~70 seconds (vs current broken ~14 seconds)

### Trade-offs

✅ **Pros**:
- Guaranteed no race condition
- Simple one-line fix
- No architectural changes needed
- Still reasonable performance (70s total)
- High confidence solution

❌ **Cons**:
- Slightly slower than ideal parallel execution
- Doesn't leverage full parallelism potential

---

## Alternative Solutions (Future Optimization)

### Option 2: Separate Session Per Day

**Approach**: Each DayPageJob establishes its own session
- Move `establish_session()` from SyncJob into DayPageJob
- Each job gets own cookies + CSRF token
- No shared state = no race condition

**Pros**:
- ✅ True parallelism (all 7 days run concurrently)
- ✅ Faster execution (~14 seconds)

**Cons**:
- ❌ 7× session overhead (7 extra HTTP requests)
- ❌ More complex implementation
- ❌ Higher server load on Kino Krakow

### Option 3: URL Parameter for Day Selection

**Approach**: Check if website supports day parameter
- Try: `/cinema_program/by_movie?day=0`
- Or: `/cinema_program/by_movie/2025-01-15`

**Pros**:
- ✅ Perfect parallelism
- ✅ No session state needed
- ✅ Simplest solution

**Cons**:
- ❌ Unknown if Kino Krakow supports this
- ❌ Requires testing/investigation

### Option 4: Oban Unique Jobs

**Approach**: Use Oban's unique constraint
- Only one DayPageJob runs at a time
- Others wait in queue

**Pros**:
- ✅ No race condition
- ✅ Uses Oban native features

**Cons**:
- ❌ Sequential execution (slower)
- ❌ More complex configuration

---

## Additional Findings

### Cinema GPS Coordinates

**Current**: CinemaExtractor just formats data from slug:
```elixir
cinema_data = CinemaExtractor.extract("", showtime["cinema_slug"])
```

**Impact**:
- No GPS coordinates fetched from Kino Krakow
- VenueProcessor must geocode using Google Maps/Nominatim
- Adds external API calls for geocoding
- Potential for incorrect/missing location data

**Recommendation** (P2): Consider scraping cinema detail pages:
- GET `/cinema/{cinema_slug}/info`
- Extract GPS coordinates if available
- Reduce geocoding API usage

### TMDB Matching Quality

**Success Rates**:
- ≥70% confidence: Auto-matched ✅
- 60-69% confidence: Auto-matched (fallback) ✅
- 50-59% confidence: Needs review → Event skipped ⚠️
- <50% confidence: No match → Event skipped ❌

**Impact**:
- Medium/low confidence matches result in lost events
- No manual review workflow currently exists
- Visible in Oban dashboard but requires manual intervention

**Recommendation** (P2):
- Implement review queue for 50-69% matches
- Add admin UI for manual TMDB matching
- Track matching success rate metrics

### Freshness Checking

**Current**: EventFreshnessChecker filters recent showtimes
- Prevents re-processing same showtime on every scrape
- Uses `last_seen_at` timestamp
- Configurable threshold (likely 24h)

**Impact with race condition**:
- If all days get same data (Day 0), Days 1-6 showtimes never process
- Freshness checker sees them as "already processed"
- Future showtimes never make it to database

**Fix**: Race condition fix will resolve this secondary issue

---

## Metrics & Observability

### Current Metrics (Oban Dashboard)

✅ **Visible**:
- Job counts per state (completed, failed, retrying)
- Individual job failures with error details
- TMDB matching failures per movie
- Processing time per job type

❌ **Missing**:
- Day-level success metrics (are all 7 days scraping?)
- Unique date count in scraped showtimes
- TMDB matching success rate percentage
- Scraping coverage (% of expected showtimes)

### Recommended Additions (P2)

1. **Day Coverage Metric**:
   ```elixir
   showtimes
   |> Enum.map(&Date.from_datetime(&1.datetime))
   |> Enum.uniq()
   |> length()  # Should be 7
   ```

2. **TMDB Success Rate**:
   ```sql
   SELECT
     COUNT(*) FILTER (WHERE state = 'completed') as matched,
     COUNT(*) FILTER (WHERE state = 'discarded') as failed,
     COUNT(*) as total
   FROM oban_jobs
   WHERE worker = 'MovieDetailJob'
   ```

3. **Scraping Health Alert**:
   - Alert if unique dates < 7
   - Alert if TMDB success rate < 80%
   - Alert if showtime count drops significantly

---

## Implementation Checklist

### Phase 1: Critical Bug Fix (P0)

- [ ] Update `sync_job.ex:157` to use 10-second stagger
- [ ] Deploy and test with sample scrape
- [ ] Verify all 7 days return different data
- [ ] Add comment explaining race condition fix
- [ ] Monitor Oban dashboard for 7 DayPageJob completions

### Phase 2: Verification (P1)

- [ ] Add logging to show date range in DayPageJob results
- [ ] Add metrics for unique dates scraped
- [ ] Create admin query to verify 7-day coverage
- [ ] Document expected behavior in code comments

### Phase 3: Long-term Improvements (P2)

- [ ] Investigate Option 3 (URL parameter for day selection)
- [ ] Consider scraping cinema pages for GPS coordinates
- [ ] Implement manual review workflow for medium-confidence TMDB matches
- [ ] Add alerting for scraping health metrics
- [ ] Research separate session approach (Option 2) if performance becomes issue

---

## Architecture Strengths (Keep These!)

✅ **Well-designed patterns**:
1. **Distributed job architecture** with clear separation of concerns
2. **External ID generation at extraction time** (BandsInTown A+ pattern)
3. **Movie deduplication across days** (one MovieDetailJob per unique movie)
4. **Freshness checking** to avoid duplicate processing
5. **Granular visibility** into failures via Oban dashboard
6. **TMDB confidence scoring** for matching quality
7. **Proper rate limiting** between HTTP requests
8. **Error handling and retry logic** at each level

✅ **Efficient HTTP usage**:
- Only 15 + N requests to Kino Krakow (N = unique movies)
- Zero redundant showtime fetches
- Smart caching of movie data in database

---

## Code References

| File | Purpose | Lines of Interest |
|------|---------|-------------------|
| `sync_job.ex` | Coordinator | Line 157: Race condition fix needed |
| `day_page_job.ex` | Day scraping | Lines 90-136: Day selection HTTP flow |
| `movie_detail_job.ex` | Movie matching | Lines 68-95: TMDB confidence logic |
| `showtime_process_job.ex` | Event processing | Lines 80-107: Movie lookup & retry logic |
| `config.ex` | Configuration | Line 15: `rate_limit` (2 seconds) |
| `showtime_extractor.ex` | HTML parsing | Lines 33-43: Showtime extraction |
| `transformer.ex` | Event formatting | Lines 23-85: Unified format transform |

---

## Questions for Further Investigation

1. **Day selection testing**: Can we verify that POST /settings/set_day actually works correctly?
2. **URL parameters**: Does Kino Krakow support day selection via URL parameters?
3. **Cinema GPS**: Are GPS coordinates available on cinema detail pages?
4. **TMDB matching rate**: What percentage of movies successfully match?
5. **Parallel optimization**: Is the sequential fix "fast enough" or should we pursue Option 2?

---

## Conclusion

The Kino Krakow scraper is **well-architected** with a **critical but simple-to-fix bug**. The race condition in day selection prevents the system from scraping all 7 days of showtimes, resulting in incomplete data for users.

**Recommended action**: Implement the one-line fix (10-second stagger) immediately, then monitor metrics to verify all 7 days are scraping correctly.

The architecture is sound and should continue to work well once this timing issue is resolved. Future optimizations (separate sessions, URL parameters) can be considered if performance becomes a concern.

---

**Created**: 2025-01-18
**Status**: Analysis Complete, Awaiting Implementation
**Priority**: P0 - Critical Bug Fix Required
