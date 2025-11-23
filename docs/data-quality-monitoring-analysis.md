# Data Quality Monitoring Analysis: Kino Krakow Scraper

**Date**: 2025-11-23
**Related**: GitHub Issue #2371 - Improve Cinema City and Kino Krakow scrapers
**Status**: ANALYSIS COMPLETE - Ready for Issue Creation

---

## Executive Summary

Analysis of the Kino Krakow scraper's data quality monitoring capabilities reveals that **the current monitoring system CAN track most drop points** in the multi-stage pipeline, but has **critical gaps in determining extraction completeness**.

### Key Findings

✅ **What We CAN Track**:
- Movies found vs jobs scheduled (Stage 1)
- Showtimes extracted per movie (Stage 2)
- TMDB matching success rate: **70% success, 30% failure** (Stage 3A)
- Freshness checker filtering (Stage 3B)
- Event creation success rate (Stage 4)

❌ **What We CANNOT Track**:
- Whether HTML extraction missed showtimes (no ground truth)
- If "1 showtime" is legitimate or extraction failure
- True availability on kino.krakow.pl website

🔴 **Critical Discovery**: **30% TMDB Matching Failure Rate**
- 1,318 failures out of 4,398 events (30%)
- All failures: `:tmdb_needs_review` with 50-69% confidence
- Examples: "Minu universum", "Galeria Uffizi we Florencji"

---

## Complete Pipeline Analysis

### Pipeline Architecture

```
SyncJob (Coordinator)
    ↓ Schedules 101 MoviePageJobs
MoviePageJob (Per-Movie Coordinator)
    ↓ Fetches 7 days of showtimes in parallel
    ├─→ MovieDetailJob (TMDB Matching) → 30% FAILURE RATE
    └─→ ShowtimeProcessJob (Event Creation) → Filtered by Freshness Checker
```

### Stage-by-Stage Drop Point Analysis

#### **Stage 1: SyncJob → MoviePageJob Scheduling**

**Monitored Metadata** (`job_execution_summaries.results`):
```json
{
  "mode": "movie-based",
  "movies_found": 101,
  "movie_jobs_scheduled": 101
}
```

**Drop Point**: Job scheduling failures
- ✅ **CAN TRACK**: Compare `movies_found` vs `movie_jobs_scheduled`
- **SQL Query**:
```sql
SELECT
  results->>'movies_found' as movies_found,
  results->>'movie_jobs_scheduled' as jobs_scheduled,
  (results->>'movies_found')::int - (results->>'movie_jobs_scheduled')::int as dropped
FROM job_execution_summaries
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob'
  AND state = 'completed'
ORDER BY inserted_at DESC
LIMIT 10;
```

**Current Status**: ✅ **No drops detected** (101 movies found = 101 jobs scheduled)

---

#### **Stage 2: MoviePageJob → Showtime Extraction**

**Monitored Metadata** (`job_execution_summaries.results`):
```json
{
  "job_role": "coordinator",
  "entity_id": "movie-slug",
  "showtimes_extracted": 2,
  "child_jobs_scheduled": 2,
  "detail_job_scheduled": 1,
  "showtime_jobs_scheduled": 1,
  "movie_detail_job_id": 6500
}
```

**Drop Points**:
1. **Movies with ZERO showtimes** (extraction failures)
2. **Movies with suspiciously LOW counts** (1-2 showtimes across 7 days)

**What We Can Track**:
- ✅ Showtimes extracted per movie
- ✅ Movies that extracted 0 showtimes
- ✅ Suspicious patterns (1 showtime when 7 expected)

**What We Cannot Track**:
- ❌ Expected showtime count (no ground truth from kino.krakow.pl)
- ❌ Whether extraction missed some showtimes in HTML parsing
- ❌ If low count is legitimate (movie only playing 1 day) or bug

**SQL Queries**:

**Find Movies with ZERO Showtimes**:
```sql
SELECT
  results->>'entity_id' as movie_slug,
  inserted_at::date as date,
  duration_ms
FROM job_execution_summaries
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MoviePageJob'
  AND state = 'completed'
  AND (results->>'showtimes_extracted')::int = 0
ORDER BY inserted_at DESC;
```

**Find Movies with Suspicious Counts (1-2 showtimes)**:
```sql
SELECT
  results->>'entity_id' as movie_slug,
  (results->>'showtimes_extracted')::int as showtimes_count,
  inserted_at::date as date
FROM job_execution_summaries
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MoviePageJob'
  AND state = 'completed'
  AND (results->>'showtimes_extracted')::int BETWEEN 1 AND 2
ORDER BY inserted_at DESC
LIMIT 50;
```

**Recent Example**: "modigliani-portret-odarty-z-legendy" extracted 0 showtimes

---

#### **Stage 3A: MovieDetailJob → TMDB Matching**

**Monitored Metadata** (`job_execution_summaries.results`):

**SUCCESS**:
```json
{
  "status": "matched",
  "tmdb_id": 1440660,
  "confidence": 0.6309,
  "match_type": "now_playing_fallback",
  "movie_id": 26,
  "job_role": "detail_fetcher",
  "entity_id": "movie-slug",
  "items_processed": 1
}
```

**FAILURE**:
```json
{
  "error_reason": "%{reason: :tmdb_needs_review, original_title: \"Minu universum\", movie_slug: \"jestes-wszechswiatem\", polish_title: \"Jesteś wszechświatem\", confidence_range: \"50-69%\"}"
}
```

**Drop Point**: TMDB matching failures
- ✅ **CAN TRACK**: Success vs failure rate
- ✅ **CAN TRACK**: Confidence scores (50-69% = needs review, 70%+ = matched)
- 🔴 **CRITICAL ISSUE**: **30% failure rate** (1,318 failures / 4,398 events)

**Additional Monitoring** (`scraper_processing_logs`):
- All failures logged with `error_type = "unknown_error"`
- Metadata contains `:tmdb_needs_review` details

**SQL Queries**:

**TMDB Matching Success Rate**:
```sql
SELECT
  CASE
    WHEN results->>'status' = 'matched' THEN 'Success'
    WHEN results->>'error_reason' IS NOT NULL THEN 'Failed'
    ELSE 'Unknown'
  END as tmdb_status,
  COUNT(*) as count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as percentage
FROM job_execution_summaries
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob'
  AND inserted_at > NOW() - INTERVAL '7 days'
GROUP BY tmdb_status;
```

**Recent Failures Analysis** (from scraper_processing_logs):
```sql
SELECT
  source_id,
  status,
  error_type,
  COUNT(*) as count
FROM scraper_processing_logs
WHERE source_id = 13
  AND inserted_at > NOW() - INTERVAL '7 days'
GROUP BY source_id, status, error_type;
```

**Results** (last 7 days):
- 3,079 successes
- 1,318 failures (30% failure rate)
- 1 HTTP server error

**Impact**: Movies that fail TMDB matching don't get enriched metadata (genres, runtime, etc.)

---

#### **Stage 3B: MoviePageJob → ShowtimeProcessJob Scheduling**

**Monitored Metadata**:
- `showtimes_extracted`: Total showtimes found
- `showtime_jobs_scheduled`: Jobs actually created (after freshness filtering)

**Drop Points**:
1. **Freshness checker filtering** (INTENTIONAL - recently seen showtimes skipped)
2. **Job scheduling failures** (UNINTENTIONAL - should match extracted count after filtering)

**What We Can Track**:
- ✅ Showtimes extracted vs jobs scheduled (gap = freshness skips)
- ✅ Freshness threshold (from code: configured hours)

**SQL Query**:

**Freshness Checker Impact**:
```sql
SELECT
  results->>'entity_id' as movie_slug,
  (results->>'showtimes_extracted')::int as extracted,
  (results->>'showtime_jobs_scheduled')::int as scheduled,
  (results->>'showtimes_extracted')::int - (results->>'showtime_jobs_scheduled')::int as skipped_by_freshness
FROM job_execution_summaries
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MoviePageJob'
  AND state = 'completed'
  AND (results->>'showtimes_extracted')::int > (results->>'showtime_jobs_scheduled')::int
ORDER BY skipped_by_freshness DESC
LIMIT 20;
```

**Example**: "spektakl-triathlon-story-czyli-chlopaki-z-zelaza"
- Extracted: 2 showtimes
- Scheduled: 1 job
- Skipped: 1 (freshness checker filtered)

---

#### **Stage 4: ShowtimeProcessJob → Events Table**

**Monitored Metadata** (`job_execution_summaries.results`):
```json
{
  "status": "created",
  "event_id": 915,
  "event_title": "Home Sweet Home at Multikino",
  "job_role": "processor",
  "entity_id": "kino_krakow_dom-dobry_multikino_2025-11-27_12_50",
  "items_processed": 1
}
```

**Possible Status Values**:
- `"created"` - New event created in database
- `"updated"` - Existing event updated
- `"skipped"` - Event not processed (duplicate or error)

**Drop Point**: Event creation failures
- ✅ **CAN TRACK**: Created vs updated vs skipped counts
- ✅ **CAN TRACK**: NULL event_id (failed saves)

**SQL Query**:

**ShowtimeProcessJob Success Rate**:
```sql
SELECT
  results->>'status' as processing_status,
  COUNT(*) as count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*) ) OVER (), 2) as percentage
FROM job_execution_summaries
WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob'
  AND inserted_at > NOW() - INTERVAL '7 days'
GROUP BY results->>'status';
```

**Current Status**: Data needed (query not yet run)

---

## End-to-End Pipeline Tracking

**SQL Query**: Track complete pipeline for a single SyncJob run:

```sql
WITH sync_run AS (
  SELECT
    job_id,
    results->>'pipeline_id' as pipeline_id,
    (results->>'movies_found')::int as movies_found,
    (results->>'movie_jobs_scheduled')::int as movie_jobs_scheduled
  FROM job_execution_summaries
  WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob'
  ORDER BY inserted_at DESC
  LIMIT 1
),
movie_jobs AS (
  SELECT
    COUNT(*) as completed_movie_jobs,
    SUM((results->>'showtimes_extracted')::int) as total_showtimes_extracted,
    SUM((results->>'showtime_jobs_scheduled')::int) as total_showtime_jobs_scheduled,
    SUM(CASE WHEN (results->>'showtimes_extracted')::int = 0 THEN 1 ELSE 0 END) as movies_with_zero_showtimes
  FROM job_execution_summaries
  WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MoviePageJob'
    AND results->>'pipeline_id' = (SELECT pipeline_id FROM sync_run)
    AND state = 'completed'
),
tmdb_jobs AS (
  SELECT
    COUNT(*) as total_tmdb_jobs,
    COUNT(*) FILTER (WHERE results->>'status' = 'matched') as tmdb_successes,
    COUNT(*) FILTER (WHERE results->>'error_reason' IS NOT NULL) as tmdb_failures
  FROM job_execution_summaries
  WHERE worker = 'EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob'
    AND results->>'pipeline_id' = (SELECT pipeline_id FROM sync_run)
)
SELECT
  s.movies_found,
  s.movie_jobs_scheduled,
  m.completed_movie_jobs,
  m.movies_with_zero_showtimes,
  m.total_showtimes_extracted,
  m.total_showtime_jobs_scheduled,
  m.total_showtimes_extracted - m.total_showtime_jobs_scheduled as freshness_skipped,
  t.total_tmdb_jobs,
  t.tmdb_successes,
  t.tmdb_failures,
  ROUND(100.0 * t.tmdb_failures / NULLIF(t.total_tmdb_jobs, 0), 2) as tmdb_failure_rate
FROM sync_run s
CROSS JOIN movie_jobs m
CROSS JOIN tmdb_jobs t;
```

**Expected Output**:
```
movies_found: 101
movie_jobs_scheduled: 101
completed_movie_jobs: 101
movies_with_zero_showtimes: 1
total_showtimes_extracted: ~150
total_showtime_jobs_scheduled: ~100
freshness_skipped: ~50
tmdb_successes: ~70
tmdb_failures: ~30
tmdb_failure_rate: 30.00%
```

---

## Monitoring Capabilities Assessment

### ✅ What Current Monitoring CAN Do

1. **Track Job-Level Drops**:
   - Movies found → jobs scheduled
   - Showtimes extracted → jobs scheduled
   - TMDB matching success rate
   - Event creation success rate

2. **Identify Suspicious Patterns**:
   - Movies with 0 showtimes (extraction failures)
   - Movies with 1-2 showtimes (suspicious - may be incomplete)
   - High TMDB failure rates

3. **Measure Pipeline Efficiency**:
   - End-to-end tracking from SyncJob → Events
   - Freshness checker impact quantification
   - Success rates at each stage

4. **Provide Actionable Data**:
   - Specific movie slugs with issues
   - Confidence scores for TMDB matching
   - Timestamps for debugging

### ❌ What Current Monitoring CANNOT Do

1. **Validate Extraction Completeness**:
   - Cannot verify if HTML extraction missed showtimes
   - No ground truth from kino.krakow.pl
   - Cannot distinguish "legitimate 1 showtime" from "extraction bug"

2. **Detect Partial Extraction**:
   - If movie has 10 showtimes but we only extract 7, we won't know
   - No comparison against source website

3. **Automatic Root Cause**:
   - Can detect 30% TMDB failure rate
   - Cannot automatically determine WHY matching failed
   - Requires manual investigation

---

## Answers to User's Questions

### Q1: "Can we study how good the scraper is?"

**Answer**: **Partially YES**
- ✅ Can measure job-level success rates (100% job completion)
- ✅ Can measure TMDB matching rate (70% success, 30% failure)
- ✅ Can identify suspicious patterns (movies with 0-2 showtimes)
- ❌ Cannot measure extraction completeness (no ground truth)

### Q2: "Can we use monitoring to figure out where things are getting stuck?"

**Answer**: **YES** - Complete pipeline tracking available
- ✅ Stage 1: SyncJob → MoviePageJob (trackable)
- ✅ Stage 2: MoviePageJob → Showtime extraction (trackable)
- ✅ Stage 3A: TMDB matching (trackable - 30% failure discovered!)
- ✅ Stage 3B: Freshness filtering (trackable)
- ✅ Stage 4: Event creation (trackable)

### Q3: "What percentage of movies fail TMDB matching?"

**Answer**: **30% FAILURE RATE** (1,318 failures / 4,398 events)
- All failures: `:tmdb_needs_review` with 50-69% confidence
- Unavoidable for obscure/foreign titles
- Examples: "Minu universum", "Galeria Uffizi we Florencji"

### Q4: "What other drop points exist beyond TMDB matching?"

**Answer**: **Multiple drop points identified**:
1. ✅ Movies with 0 showtimes extracted (extraction failures)
2. ✅ Freshness checker skips (INTENTIONAL - recently seen showtimes)
3. ✅ TMDB matching failures (30% - CRITICAL)
4. ⚠️ Movies with suspiciously low counts (1-2 showtimes) - needs investigation

### Q5: "Is our system good enough to define these and to see it?"

**Answer**: **YES for job-level tracking, NO for extraction completeness**

**What Works**:
- ✅ Comprehensive pipeline metadata in `job_execution_summaries.results`
- ✅ Event-level failure logs in `scraper_processing_logs`
- ✅ SQL queries can identify all major drop points
- ✅ Baseline monitoring for performance tracking

**What's Missing**:
- ❌ Ground truth from kino.krakow.pl (no expected showtime counts)
- ❌ HTML extraction validation (can't verify completeness)
- ❌ Automated alerting for suspicious patterns

---

## Recommendations

### Immediate Actions

1. **Investigate TMDB Matching Failures** 🔴 CRITICAL
   - 30% failure rate is significant
   - Review `:tmdb_needs_review` cases manually
   - Consider implementing fallback matching strategies
   - Potentially lower confidence threshold or use alternative data sources

2. **Analyze Movies with 0 Showtimes** 🟡 HIGH
   - Run Query 3 (zero showtimes) to identify movies
   - Manually check kino.krakow.pl for these movies
   - Determine if extraction bug or legitimate (removed from schedule)

3. **Investigate Suspicious Low Counts** 🟡 MEDIUM
   - Run Query 2 (1-2 showtimes across 7 days)
   - Sample movies and manually verify on kino.krakow.pl
   - Distinguish legitimate low counts from extraction bugs

### Monitoring Enhancements

1. **Create Dashboard Queries** 🟢 LOW
   - Implement all SQL queries as saved views or admin panel reports
   - Automated weekly summaries showing:
     - TMDB success rate trend
     - Movies with 0 showtimes count
     - Freshness checker impact
     - End-to-end pipeline efficiency

2. **Implement Alerting** 🟡 MEDIUM
   - Alert if TMDB failure rate exceeds 35%
   - Alert if >5% of movies extract 0 showtimes
   - Alert if freshness checker skips >80% of showtimes

3. **Ground Truth Sampling** 🟡 MEDIUM
   - Weekly manual spot-checks of 5-10 movies
   - Compare extraction count vs kino.krakow.pl actual count
   - Build confidence in extraction completeness over time

### Future Improvements

1. **TMDB Matching Enhancements** 🔴 CRITICAL
   - Implement manual review queue for 50-69% confidence matches
   - Add alternative matching strategies (OMDb, manual mapping)
   - Lower threshold to 50% with manual review flag

2. **Extraction Validation** 🟡 MEDIUM
   - Add extraction confidence scores
   - Implement "expected patterns" detection (e.g., most movies should have 5-7 days)
   - Flag anomalies for manual review

3. **Automated Quality Checks** 🟢 LOW
   - Post-scrape validation: check for suspicious patterns
   - Cross-source verification (if multiple sources for same cinema)
   - Historical comparison (dramatic drop in showtimes = investigate)

---

## Issue #2371 Status Assessment

### Original Issue Goals

**#2371**: "Improve Cinema City and Kino Krakow scrapers"
- Concern: "dropping a certain number of Entries"
- Goal: Make scrapers better

### Accomplishments

✅ **Phase 1**: Monitoring system implemented
✅ **Phase 2**: Baseline analysis completed
- Cinema City: Perfect (P95 2,473ms, 100% success)
- Kino Krakow: Performance issue identified (P95 31,178ms)

✅ **Phase 3** (Partial):
- COMPLETED: Thundering herd problem identified and fixed (jitter implemented)
- ⏳ PENDING: Baseline validation after jitter fix
- ⏳ PENDING: Jitter effectiveness confirmation

❌ **NOT ADDRESSED**:
- Data quality/completeness analysis (this document)
- 30% TMDB matching failure rate (discovered but not resolved)
- Extraction completeness validation

### Recommendation: **DO NOT CLOSE #2371 YET**

**Reasons**:
1. **Original Goal Partially Met**: Monitoring improved but data drops not fully investigated
2. **Critical Issue Discovered**: 30% TMDB failure rate needs resolution
3. **Performance Fix Unvalidated**: Jitter fix awaiting baseline confirmation
4. **Data Quality Questions Unanswered**: Need to validate extraction completeness

**Suggested Path Forward**:
1. Keep #2371 OPEN as parent issue
2. Create NEW issue: "Data Quality Analysis: Kino Krakow TMDB Matching Failures"
3. Create NEW issue: "Validate Extraction Completeness for Kino Krakow"
4. Link new issues to #2371
5. Close #2371 ONLY after:
   - Jitter fix validated with baseline
   - TMDB matching improved or accepted as-is
   - Extraction completeness spot-checked and validated
   - All critical data quality issues addressed

---

## Next Steps

1. **Create GitHub Issue**: Convert this analysis into a GitHub issue
2. **Run Validation Queries**: Execute all SQL queries against production data
3. **Manual Spot-Check**: Sample 10 movies and verify extraction completeness
4. **TMDB Failure Review**: Analyze failed matches and determine improvement strategy
5. **Jitter Baseline Collection**: Wait for new run to complete, collect baseline
6. **Phase 3 Completion**: Document jitter fix results and close performance work

---

**Analysis By**: Claude Code SuperClaude
**Date**: 2025-11-23
**Related Documents**:
- `docs/phase-3-analysis-thundering-herd.md` - Performance analysis
- `docs/phase-2-github-issue.md` - Phase 2 completion summary
- `docs/baseline-report-kino-krakow.md` - Original baseline report
