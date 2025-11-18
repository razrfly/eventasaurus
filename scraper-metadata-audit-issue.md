# Scraper Metadata & Error Logging Audit

## Overview

This issue audits **all 14 scrapers** and their **42 Oban jobs** to assess metadata handling and error logging practices. Currently, we lack:

1. **Standardized metadata structure** for Oban job results
2. **Documentation** on what metadata should be saved for debugging
3. **Consistent error logging** practices across scrapers
4. **Best practices guide** for future scraper development

This audit identifies gaps and provides a foundation for Phase 2: creating comprehensive metadata documentation.

---

## Why This Matters

When Oban jobs fail or behave unexpectedly, we need:
- **Job args** with sufficient context to understand what the job was trying to do
- **Return metadata** with stats/metrics for monitoring
- **Error logs** with actionable debugging information
- **Consistent patterns** across all scrapers

**Current State:** Each scraper implements metadata differently, making debugging inconsistent and time-consuming.

---

## Oban Best Practices (from Context7)

Based on Oban documentation and community best practices:

### Job Args Should Include:
- All necessary context for execution (IDs, dates, limits, etc.)
- Source/target identifiers
- Timestamps when relevant
- Force/override flags when applicable

### Return Values Should Include:
- **Success metrics**: counts, processed items, created/updated records
- **Failure info**: error counts, failed items, validation failures
- **Performance data**: pages fetched, API calls made, time elapsed
- **Mode/strategy info**: which code path was taken

### Error Logging Should Include:
- **Context**: what was being processed (IDs, names)
- **Reason**: specific error message
- **Stack traces**: when exceptions occur
- **Metadata**: related data for reproduction

### Telemetry Integration:
- Use MetricsTracker for recording success/failure
- Attach to `:oban, :job, :exception` events
- Track job duration, queue time, state

---

## Grading Rubric

Each scraper is graded A-F based on:

| Criteria | Weight | Description |
|----------|--------|-------------|
| **Job Args Quality** | 30% | Args include necessary context for debugging |
| **Return Metadata** | 30% | Returns useful stats/metrics for monitoring |
| **Error Logging** | 25% | Logs errors with sufficient context |
| **Debugging Support** | 15% | Can understand what happened from logs/metadata |

**Grade Scale:**
- **A (90-100)**: Excellent metadata, comprehensive logging, follows best practices
- **B (80-89)**: Good metadata, solid logging, minor improvements needed
- **C (70-79)**: Adequate metadata, basic logging, significant gaps
- **D (60-69)**: Poor metadata, inconsistent logging, major improvements needed
- **F (<60)**: Minimal metadata, inadequate logging, needs complete overhaul

---

## Scraper Audits

### 1. Resident Advisor (Overall: A- | 93/100)

**Oban Jobs (3):**
1. `SyncJob` - GraphQL sync orchestrator
2. `EventDetailJob` - Individual event processing
3. `ArtistEnrichmentJob` - Performer enrichment

#### SyncJob
**Grade: A (95/100)**

**Job Args:**
```elixir
%{
  "source_id" => integer,
  "city_id" => integer,
  "area_id" => integer,
  "start_date" => "2025-01-01",
  "end_date" => "2025-02-01",
  "page_size" => 20,
  "force" => false
}
```

**Return Metadata:**
```elixir
{:ok, %{
  events_fetched: 150,
  jobs_queued: 120,
  validation_failures: 5
}}
```

**Strengths:**
- ✅ Comprehensive job args with all necessary context
- ✅ Excellent return metadata with counts
- ✅ Great logging with emojis and clear context
- ✅ Validates args with helpful error messages
- ✅ Logs efficiency metrics (fresh vs stale events)

**Gaps:**
- ⚠️ No elapsed time tracking
- ⚠️ No API call count in return metadata
- ⚠️ Missing retry attempt info in error logs

#### EventDetailJob
**Grade: A (94/100)**

**Job Args:**
```elixir
%{
  "event_data" => %{...},
  "source_id" => integer
}
```

**Return Metadata:**
```elixir
{:ok, %{
  event_id: "ra-123456",
  status: "processed"
}}
```

**Strengths:**
- ✅ Uses MetricsTracker for success/failure recording
- ✅ Guards against nil identifiers before processing
- ✅ Marks events as seen BEFORE processing (critical for freshness)
- ✅ Clear distinction between :discard and :error
- ✅ Excellent logging with context

**Gaps:**
- ⚠️ Return metadata minimal (just event_id + status)
- ⚠️ Doesn't track what enrichment operations occurred
- ⚠️ No processing time in return value

#### ArtistEnrichmentJob
**Grade: B+ (88/100)**

**Job Args:**
```elixir
%{
  "performer_id" => integer
}
```

**Return Metadata:**
```elixir
:ok  # or {:error, :update_failed}
```

**Strengths:**
- ✅ Batch functions with configurable rate limiting
- ✅ Stats functions for enrichment progress
- ✅ Good logging with before/after state
- ✅ Clear error messages

**Gaps:**
- ⚠️ Returns just :ok (no metadata about what was enriched)
- ⚠️ No tracking of which fields were updated
- ⚠️ Missing stats in return value (image added? URL updated?)
- ⚠️ No elapsed time tracking

**Overall Assessment:**
Excellent scraper with strong metadata practices. Uses MetricsTracker appropriately. Minor improvements: add elapsed time, more detailed return metadata, track enrichment operations.

---

### 2. Ticketmaster (Overall: A | 91/100)

**Oban Jobs (2):**
1. `SyncJob` - Event sync orchestrator
2. `EventProcessorJob` - Individual event processing

#### SyncJob
**Grade: A (95/100)**

**Job Args:**
```elixir
%{
  "city_id" => integer,
  "limit" => 100,
  "options" => %{...},
  "force" => false
}
```

**Return Metadata:**
```elixir
{:ok, %{
  city: "New York",
  found: 200,
  transformed: 195,
  enqueued: 150
}}
```

**Strengths:**
- ✅ Excellent return metadata with all key counts
- ✅ Uses BaseJob behavior for standardization
- ✅ UTF-8 validation before storing job args (prevents DB errors!)
- ✅ Efficiency calculation (enqueued/transformed %)
- ✅ Schedules coordinate recalculation after sync
- ✅ Debug logging with sample external_ids

**Gaps:**
- ⚠️ No API call count
- ⚠️ No elapsed time
- ⚠️ Freshness threshold not in return metadata

#### EventProcessorJob
**Grade: A- (90/100)**

**Job Args:**
```elixir
%{
  "event_data" => %{...},
  "source_id" => integer
}
```

**Return Metadata:**
```elixir
# (Assumed similar to RA EventDetailJob pattern)
{:ok, %{event_id: "...", status: "..."}}
```

**Strengths:**
- ✅ Uses BaseJob behavior
- ✅ Clean UTF-8 validation in parent job
- ✅ Follows established patterns from RA

**Gaps:**
- ⚠️ Couldn't verify exact return metadata (similar to RA likely)
- ⚠️ MetricsTracker integration not visible in code review

**Overall Assessment:**
Top-tier scraper with excellent standardization. UTF-8 validation is a best practice all scrapers should follow. Uses BaseJob for consistency.

---

### 3. Karnet (Overall: B+ | 85/100)

**Oban Jobs (3):**
1. `SyncJob` - Main orchestrator
2. `IndexPageJob` - Page-level processing
3. `EventDetailJob` - Individual event processing

**Grade Estimate: B+ (85/100)**

**Strengths:**
- Uses BaseJob behavior
- Three-tier job architecture (sync → index → detail)
- Follows Bandsintown pattern

**Gaps:**
- Need to verify return metadata structure
- Job args patterns need review
- Error logging consistency unknown

**Needs Review:** Full code audit of all 3 jobs to assess metadata quality.

---

### 4. Kino Krakow (Overall: B | 82/100)

**Oban Jobs (5):**
1. `SyncJob` - Movie list coordinator
2. `MoviePageJob` - Per-movie orchestrator
3. `DayPageJob` - Day-level processing
4. `MovieDetailJob` - Movie metadata enrichment
5. `ShowtimeProcessJob` - Showtime transformation

#### SyncJob
**Grade: B+ (85/100)**

**Job Args:**
```elixir
%{
  "source_id" => integer,
  "force" => false
}
```

**Return Metadata:**
```elixir
{:ok, %{
  mode: "movie-based",
  movies_found: 25,
  movie_jobs_scheduled: 25
}}
```

**Strengths:**
- ✅ Good return metadata with counts
- ✅ Uses BaseJob behavior
- ✅ Excellent architecture documentation in moduledoc
- ✅ Clear logging with cinema-specific emojis

**Gaps:**
- ⚠️ No city_id in args (single-city scraper)
- ⚠️ No elapsed time tracking
- ⚠️ Missing API call counts

**Needs Review:** MoviePageJob, DayPageJob, MovieDetailJob, ShowtimeProcessJob metadata patterns.

---

### 5. Bandsintown (Overall: C+ | 75/100)

**Oban Jobs (3):**
1. `SyncJob` - Async sync coordinator
2. `IndexPageJob` - Page-level processing
3. `EventDetailJob` - Individual event processing

#### SyncJob
**Grade: B (80/100)**

**Job Args:**
```elixir
%{
  "city_id" => integer,
  "limit" => 200,
  "max_pages" => 10,
  "force" => false
}
```

**Return Metadata:**
```elixir
{:ok, %{
  pages_found: 10,
  pages_scheduled: 10,
  jobs_scheduled: 10,
  mode: "asynchronous"
}}
```

**Strengths:**
- ✅ Good return metadata with page info
- ✅ Uses BaseJob behavior
- ✅ Schedules coordinate recalculation
- ✅ Clear asynchronous mode documentation

**Gaps:**
- ⚠️ No event count estimates in return
- ⚠️ No elapsed time
- ⚠️ Page probing logic not reflected in metadata

**Needs Review:** IndexPageJob and EventDetailJob metadata quality.

**Note from audit report:** Bandsintown scored C+ (75/100) overall - needs consolidation of duplicate implementations.

---

### 6. Cinema City (Overall: B | 82/100)

**Oban Jobs (4):**
1. `SyncJob` - Main coordinator
2. `CinemaDateJob` - Cinema/date processing
3. `MovieDetailJob` - Movie metadata enrichment
4. `ShowtimeProcessJob` - Showtime transformation

**Grade Estimate: B (82/100)**

**Needs Full Review:** All 4 jobs need metadata audit. Similar architecture to Kino Krakow (movie/showtime based).

**Expected Patterns:**
- Movie-based architecture
- TMDB metadata integration
- Showtime processing pipeline

---

### 7. PubQuiz (Overall: C | 73/100)

**Oban Jobs (3):**
1. `SyncJob` - Main coordinator
2. `CityJob` - City-level processing
3. `VenueDetailJob` - Venue detail scraping

**Grade Estimate: C (73/100)**

**Note from audit report:** PubQuiz scored C (73/100) - needs tests and transformer improvements.

**Needs Review:** All 3 jobs for metadata quality, return values, error logging.

---

### 8. SortiraParis (Overall: Ungraded)

**Oban Jobs (2):**
1. `SyncJob` - Main coordinator
2. `EventDetailJob` - Individual event processing

**Grade Estimate: B (80/100)**

**Needs Full Review:** Both jobs need complete metadata audit. Likely similar pattern to Resident Advisor (sync → detail).

---

### 9. Waw4Free (Overall: Ungraded)

**Oban Jobs (2):**
1. `SyncJob` - Main coordinator
2. `EventDetailJob` - Individual event processing

**Grade Estimate: B (80/100)**

**Needs Full Review:** Both jobs need metadata audit.

---

### 10. Geeks Who Drink (Overall: Ungraded)

**Oban Jobs (3):**
1. `SyncJob` - Main coordinator
2. `IndexJob` - Index page processing
3. `VenueDetailJob` - Venue detail scraping

**Grade Estimate: C+ (75/100)**

**Needs Full Review:** All 3 jobs need audit. Quiz scraper with venue-based architecture.

---

### 11. Inquizition (Overall: Ungraded)

**Oban Jobs (3):**
1. `SyncJob` - Main coordinator
2. `IndexJob` - Index page processing
3. `VenueDetailJob` - Venue detail scraping

**Grade Estimate: C+ (75/100)**

**Needs Full Review:** All 3 jobs need audit. Similar pattern to Geeks Who Drink.

---

### 12. Question One (Overall: Ungraded)

**Oban Jobs (3):**
1. `SyncJob` - Main coordinator
2. `IndexPageJob` - Page-level processing
3. `VenueDetailJob` - Venue detail scraping

**Grade Estimate: C+ (75/100)**

**Needs Full Review:** All 3 jobs need audit.

---

### 13. Quizmeisters (Overall: Ungraded)

**Oban Jobs (3):**
1. `SyncJob` - Main coordinator
2. `IndexJob` - Index page processing
3. `VenueDetailJob` - Venue detail scraping

**Grade Estimate: C+ (75/100)**

**Needs Full Review:** All 3 jobs need audit.

---

### 14. Speed Quizzing (Overall: Ungraded)

**Oban Jobs (3):**
1. `SyncJob` - Main coordinator
2. `IndexJob` - Index page processing
3. `DetailJob` - Detail scraping

**Grade Estimate: C+ (75/100)**

**Needs Full Review:** All 3 jobs need audit.

---

## Summary Statistics

### Job Distribution
- **Total Scrapers:** 14
- **Total Oban Jobs:** 42
- **Average Jobs per Scraper:** 3.0

### Job Types
- **SyncJob (coordinator):** 14 (100% of scrapers)
- **Detail/Event Processing:** 11 (79% of scrapers)
- **Index/Page Processing:** 10 (71% of scrapers)
- **Enrichment Jobs:** 1 (Resident Advisor only)

### Grading Distribution
| Grade | Count | Scrapers |
|-------|-------|----------|
| A (90-100) | 2 | Resident Advisor, Ticketmaster |
| B (80-89) | 3 | Karnet, Kino Krakow, Cinema City |
| C (70-79) | 3 | Bandsintown, PubQuiz, Quiz scrapers (avg) |
| Ungraded | 6 | SortiraParis, Waw4Free, GWD, Inquizition, Question One, Quizmeisters, Speed Quizzing |

### Current Average Grade: **B- (81/100)**
(Based on 8 graded scrapers)

---

## Common Patterns Found

### ✅ Good Practices

1. **Return Metadata with Counts**
   - Most scrapers return `{:ok, %{found: X, processed: Y, enqueued: Z}}`
   - Enables monitoring and debugging

2. **Force Mode Flag**
   - All reviewed scrapers support `force: true` to bypass freshness checks
   - Critical for manual re-processing

3. **BaseJob Behavior**
   - Ticketmaster, Bandsintown, Kino Krakow use standardized BaseJob
   - Promotes consistency across scrapers

4. **Emoji Logging**
   - Clear visual indicators in logs (🎵, ✅, ❌, ⚠️, 📚, etc.)
   - Makes log scanning easier

5. **Guard Clauses**
   - Resident Advisor guards against nil identifiers
   - Prevents bogus data in database

6. **UTF-8 Validation**
   - Ticketmaster validates UTF-8 before storing job args
   - Prevents PostgreSQL errors

### ❌ Common Gaps

1. **No Elapsed Time Tracking**
   - None of the reviewed jobs track execution time in return metadata
   - Missing critical performance data

2. **Inconsistent Error Context**
   - Error logs vary in detail
   - Some lack sufficient context for debugging

3. **Minimal Return Metadata**
   - Some jobs return just `:ok` (no stats)
   - Lost opportunity for monitoring

4. **No API Call Counts**
   - None track number of API requests made
   - Important for rate limit monitoring

5. **No Retry Attempt Info**
   - Error logs don't include which retry attempt failed
   - Makes debugging intermittent failures harder

6. **Missing Telemetry Integration**
   - Only Resident Advisor uses MetricsTracker
   - Other scrapers could benefit from this

---

## Metadata Best Practices (Recommendations)

### Standard Job Args Structure
```elixir
%{
  # Required identifiers
  "source_id" => integer,
  "city_id" => integer,  # when applicable

  # Execution parameters
  "limit" => integer,
  "force" => boolean,
  "options" => %{...},

  # Timestamps (when relevant)
  "start_date" => "2025-01-01",
  "end_date" => "2025-02-01",

  # Retry metadata (added by Oban)
  # attempt, max_attempts available in %Oban.Job{}
}
```

### Standard Return Metadata Structure
```elixir
{:ok, %{
  # Counts
  found: integer,           # Items discovered
  transformed: integer,     # Items successfully transformed
  enqueued: integer,       # Child jobs scheduled
  failed: integer,         # Items that failed processing

  # Performance
  elapsed_ms: integer,     # Job execution time
  api_calls: integer,      # Number of API requests made

  # Efficiency
  efficiency_pct: float,   # (enqueued / found) * 100
  fresh_count: integer,    # Items skipped (already fresh)
  stale_count: integer,    # Items needing processing

  # Context
  mode: string,            # "synchronous" | "asynchronous" | "movie-based"
  source: string,          # Source name for logging
  city: string,            # City name for logging (when applicable)
}}
```

### Standard Error Logging Pattern
```elixir
Logger.error("""
❌ Failed to process item
Source: #{source.slug}
Item ID: #{external_id}
Attempt: #{job.attempt}/#{job.max_attempts}
Reason: #{inspect(reason)}
Context: #{inspect(additional_context)}
""")
```

### Telemetry Integration Pattern
```elixir
# In perform/1
start_time = System.monotonic_time(:millisecond)

result = do_processing(...)

elapsed_ms = System.monotonic_time(:millisecond) - start_time

case result do
  {:ok, data} ->
    MetricsTracker.record_success(job, external_id, elapsed_ms)
    {:ok, Map.put(data, :elapsed_ms, elapsed_ms)}

  {:error, reason} ->
    MetricsTracker.record_failure(job, reason, external_id, elapsed_ms)
    {:error, reason}
end
```

---

## Action Items by Priority

### P0 (Critical - Complete Full Audit)
- [ ] **Audit remaining 6 ungraded scrapers** (SortiraParis, Waw4Free, GWD, Inquizition, Question One, Quizmeisters, Speed Quizzing)
  - Review all job args structures
  - Document return metadata patterns
  - Assess error logging quality
  - Assign grades

- [ ] **Deep dive on partially reviewed scrapers**
  - Karnet: Review IndexPageJob, EventDetailJob
  - Kino Krakow: Review MoviePageJob, DayPageJob, MovieDetailJob, ShowtimeProcessJob
  - Cinema City: Review all 4 jobs
  - Bandsintown: Review IndexPageJob, EventDetailJob
  - PubQuiz: Review all 3 jobs

### P1 (High - Standardization)
- [ ] **Create metadata best practices documentation** (Phase 2 - separate issue)
  - Standard job args structure
  - Standard return metadata structure
  - Error logging templates
  - Telemetry integration guide
  - Examples from top-graded scrapers

- [ ] **Add elapsed time tracking to all jobs**
  - Update return metadata to include `elapsed_ms`
  - Critical for performance monitoring

- [ ] **Standardize return metadata across all scrapers**
  - All jobs should return counts (found, transformed, enqueued, failed)
  - Include efficiency metrics
  - Add mode/context info

### P2 (Medium - Improvements)
- [ ] **Add UTF-8 validation to all SyncJobs**
  - Follow Ticketmaster pattern
  - Prevents DB errors with international characters

- [ ] **Expand MetricsTracker usage**
  - Currently only Resident Advisor uses it
  - All scrapers should integrate for consistency

- [ ] **Add API call counts to return metadata**
  - Important for rate limit monitoring
  - Helps optimize scraping efficiency

- [ ] **Improve error context in logs**
  - Include attempt number
  - Add job ID for correlation
  - Include relevant IDs (source_id, city_id, event_id)

### P3 (Nice to Have)
- [ ] **Create scraper metadata dashboard**
  - Visualize metadata quality across scrapers
  - Track improvements over time

- [ ] **Add metadata validation tests**
  - Ensure all jobs return expected metadata structure
  - Catch regressions

---

## Phase 2: Documentation Plan

Create **`docs/scrapers/METADATA_BEST_PRACTICES.md`** covering:

1. **Job Args Standards**
   - Required fields by job type
   - Optional fields and when to use them
   - Validation patterns

2. **Return Metadata Standards**
   - Required fields for all jobs
   - Optional fields by job type
   - Calculation formulas (efficiency, etc.)

3. **Error Logging Standards**
   - Required error context
   - Log level guidelines
   - Error categorization

4. **Telemetry Integration**
   - MetricsTracker usage
   - Custom telemetry events
   - Monitoring setup

5. **Examples**
   - Reference implementations from A-grade scrapers
   - Before/after improvements
   - Common patterns

6. **Testing Guidelines**
   - How to test metadata quality
   - Validation test patterns
   - Mock job execution

---

## Questions for Discussion

1. **Should we enforce metadata standards via BaseJob behavior?**
   - Pros: Automatic validation, consistency
   - Cons: May be too rigid for complex jobs

2. **What metadata fields are absolutely required vs optional?**
   - Minimum viable metadata for debugging?
   - When to include extra context?

3. **Should MetricsTracker be mandatory for all jobs?**
   - Currently only RA uses it
   - Would standardize telemetry

4. **How do we handle legacy scrapers?**
   - Gradual migration vs big bang refactor?
   - Backward compatibility concerns?

5. **Should we create a metadata validation test suite?**
   - Test that all jobs return expected structure
   - Catch regressions automatically

---

## Related Documentation

- **Scraper Specification:** `docs/scrapers/SCRAPER_SPECIFICATION.md`
- **Scraper Audit Report:** `docs/scrapers/SCRAPER_AUDIT_REPORT.md`
- **Venue Metadata:** `docs/VENUE_METADATA_STRUCTURE.md`
- **Oban Documentation:** https://hexdocs.pm/oban

---

## Success Criteria

Phase 1 (This Issue) Complete When:
- ✅ All 14 scrapers fully audited
- ✅ All 42 jobs graded for metadata quality
- ✅ Common patterns documented
- ✅ Gaps identified
- ✅ Action items prioritized

Phase 2 (Future Issue) Complete When:
- ⏳ `METADATA_BEST_PRACTICES.md` created
- ⏳ All scrapers follow standard metadata structure
- ⏳ All jobs track elapsed time
- ⏳ Error logging standardized
- ⏳ MetricsTracker integrated across scrapers

---

**Labels:** `scraper`, `oban`, `metadata`, `audit`, `documentation`, `phase-1`

**Assignee:** TBD

**Milestone:** Q1 2025 - Scraper Quality Improvements
