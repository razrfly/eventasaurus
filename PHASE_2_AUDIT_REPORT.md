# Phase 2 Audit Report: Last Seen At Logic Analysis

**Date**: October 31, 2025
**Status**: ✅ Complete
**GitHub Issue**: #2116

## Executive Summary

This audit documents the current implementation of the 7-day "last seen" threshold logic across all scrapers in the Eventasaurus Discovery system. The analysis reveals:

- **Centralized Service**: ✅ `EventFreshnessChecker` service already exists
- **Default Threshold**: 168 hours (7 days)
- **Configuration**: Centralized in config files with source-specific overrides
- **Adoption**: 13 of 14 scrapers use `EventFreshnessChecker`
- **Root Cause**: Question One bug is NOT a threshold issue - it's a **recurring event date generation bug**

---

## 1. Core Service Analysis

### EventFreshnessChecker Service
**Location**: `lib/eventasaurus_discovery/services/event_freshness_checker.ex`

**Purpose**: Filters events based on `last_seen_at` timestamps to avoid re-scraping fresh data.

**Key Logic** (line 59-66):
```elixir
threshold_datetime = DateTime.add(DateTime.utc_now(), -threshold, :hour)

fresh_data =
  from(pes in PublicEventSource,
    where: pes.source_id == ^source_id,
    where: pes.external_id in ^external_ids,
    where: pes.last_seen_at > ^threshold_datetime,  # ← The 7-day check
    select: %{external_id: pes.external_id, event_id: pes.event_id}
  )
  |> Repo.all()
```

**Threshold Resolution**:
1. Check function parameter (`threshold_hours`)
2. Fall back to source-specific override from config
3. Fall back to default: 168 hours (7 days)

**Advanced Features**:
- **Recurring Event Detection** (lines 85-127): Predicts which events will merge into existing events
- **Batch Performance**: Single query for all events (avoids N+1 queries)
- **Smart Filtering**: Skips events if ANY occurrence was recently updated

---

## 2. Configuration Locations

### Default Threshold
```elixir
# Default: 7 days = 168 hours
freshness_threshold_hours: 168
```

**Files**:
- `config/dev.exs:131`
- `config/test.exs:99`
- `config/runtime.exs:384` (production, env var override: `EVENT_FRESHNESS_THRESHOLD_HOURS`)

### Source-Specific Overrides
```elixir
source_freshness_overrides: %{
  "kino-krakow" => 24,    # Daily (movies change frequently)
  "cinema-city" => 48      # Every 2 days (showtimes update frequently)
}
```

**Files**:
- `config/dev.exs:134-139`
- `config/test.exs:102-107`
- `config/runtime.exs:388-393`

---

## 3. Scraper Categorization

### Recurring Events (Weekly/Monthly Patterns)

| Scraper | Uses EFC | Threshold | Event Pattern | Notes |
|---------|----------|-----------|---------------|-------|
| **question-one** | ✅ | 168h (7d) | Weekly trivia nights | **BUG**: Fails to regenerate future dates |
| **inquizition** | ✅ | 168h (7d) | Weekly quiz nights | UK-wide trivia |
| **speed-quizzing** | ✅ | 168h (7d) | Weekly quiz nights | Pattern-based recurring |
| **quizmeisters** | ✅ | 168h (7d) | Weekly quiz nights | US trivia events |
| **geeks-who-drink** | ✅ | 168h (7d) | Weekly pub quizzes | US-based recurring |
| **pubquiz** | ✅ | 168h (7d) | Weekly pub quizzes | Multi-city recurring |

**Common Pattern**: These scrapers use `occurrences` field to store recurring patterns (day of week, frequency).

### Exhibitions & Long-Running Events

| Scraper | Uses EFC | Threshold | Event Pattern | Notes |
|---------|----------|-----------|---------------|-------|
| **kino-krakow** | ✅ | 24h (1d) | Movie showtimes | Daily override due to showtime changes |
| **cinema-city** | ✅ | 48h (2d) | Movie showtimes | Every 2 days override |
| **karnet** | ✅ | 168h (7d) | Cultural events | Exhibitions, theater, concerts |
| **waw4free** | ✅ | 168h (7d) | Free events | Exhibitions, workshops, festivals |
| **sortiraparis** | ❓ | 168h (7d) | Parisian events | Mixed (needs verification) |

**Common Pattern**: Fixed start/end dates, NO recurring patterns. Events have duration but don't repeat.

### Concerts & Live Music

| Scraper | Uses EFC | Threshold | Event Pattern | Notes |
|---------|----------|-----------|---------------|-------|
| **bandsintown** | ✅ | 168h (7d) | Concerts, live music | One-time events, venue-based |
| **resident-advisor** | ✅ | 168h (7d) | Electronic music events | DJ sets, club nights |
| **ticketmaster** | ✅ | 168h (7d) | Major events | Concerts, sports, theater |

**Common Pattern**: One-time events with specific dates. No recurring patterns.

---

## 4. EventFreshnessChecker Adoption

### ✅ Scrapers Using EventFreshnessChecker (13/14)

**Index/Sync Job Usage**:
1. `question_one/jobs/index_page_job.ex:126`
2. `inquizition/jobs/index_job.ex` ✅
3. `speed_quizzing/jobs/index_job.ex` ✅
4. `quizmeisters/jobs/index_job.ex` ✅
5. `geeks_who_drink/jobs/index_job.ex` ✅
6. `pubquiz/jobs/city_job.ex` ✅
7. `kino_krakow/jobs/day_page_job.ex` ✅
8. `cinema_city/jobs/cinema_date_job.ex` ✅
9. `karnet/jobs/index_page_job.ex` ✅
10. `waw4free/jobs/sync_job.ex` ✅
11. `resident_advisor/jobs/sync_job.ex` ✅
12. `bandsintown/jobs/index_page_job.ex` ✅
13. `ticketmaster/jobs/sync_job.ex` ✅

**Integration Pattern**:
```elixir
# Generate external_ids
events_with_ids = generate_external_ids(events)

# Filter using EventFreshnessChecker
events_to_process =
  EventFreshnessChecker.filter_events_needing_processing(events_with_ids, source_id)

# Schedule jobs for filtered events only
schedule_detail_jobs(events_to_process)
```

### ❓ Scraper NOT Using EventFreshnessChecker (1/14)

**sortiraparis**: Needs verification. README mentions EventFreshnessChecker but implementation unclear.

---

## 5. Critical Finding: Question One Bug is NOT a Threshold Issue

### Original Hypothesis (INCORRECT)
> "Events are skipped because last_seen_at < 7 days, causing 0 future events"

### Actual Root Cause (CORRECT)
**Question One scraper DOES update `last_seen_at` but FAILS to regenerate future dates from recurring patterns.**

**Evidence from Phase 1 Testing**:
```
After running scraper:
├─ 160 VenueDetailJob processed
├─ 45 events updated (last_seen_at touched to NOW) ✅
└─ BUT: All events still have expired dates (Oct 29) ❌
```

**Example from database**:
```sql
title: Quiz Night at Alwyne Castle
starts_at: 2025-10-29 13:46:15 (EXPIRED! 2 days ago)
ends_at: 2025-10-29 13:46:15 (EXPIRED!)
has_occurrences: true (recurring pattern EXISTS!)
last_seen_at: 2025-10-31 13:49:48 (JUST UPDATED!)
```

**The Real Bug**:
- Events have `occurrences` field with weekly recurring patterns ✅
- Scraper successfully sees events and updates `last_seen_at` ✅
- Scraper FAILS to compute and update next future occurrence date ❌
- Result: 0 future events, permanently stuck ❌

---

## 6. Last Seen At Update Logic

### When is `last_seen_at` Updated?

**EventProcessor** (`lib/eventasaurus_discovery/scraping/processors/event_processor.ex`):
```elixir
# When processing events through Processor.process_source_data/2
# The EventProcessor automatically updates last_seen_at for:
# 1. Existing events being re-scraped
# 2. New occurrences of recurring events
```

**DetailJob Pattern** (all scrapers):
```elixir
def perform(%Oban.Job{args: args}) do
  with {:ok, body} <- Client.fetch_page(url),
       {:ok, data} <- Extractor.extract(body),
       {:ok, transformed} <- Transformer.transform(data),
       {:ok, results} <- Processor.process_source_data([transformed], source_id) do
    # ↑ This call updates last_seen_at automatically
    {:ok, results}
  end
end
```

**VenueProcessor/EventProcessor Chain**:
1. `VenueProcessor` creates/finds venue
2. `EventProcessor` creates/updates event
3. `PublicEventSource` record updated with `last_seen_at = NOW()`

---

## 7. Recommendations for Phase 3

### ✅ Good News: Infrastructure Already Exists

1. **EventFreshnessChecker is centralized** ✅
2. **Configuration is unified** ✅
3. **13/14 scrapers already use it** ✅
4. **Source-specific overrides working** ✅

### ⚠️ The Real Problem: Recurring Event Date Generation

**Phase 3 Focus Should Be**:

1. **NOT the 7-day threshold** (it's working correctly)
2. **NOT the last_seen_at logic** (it's updating correctly)
3. **YES: Recurring event date calculation**

**Required Changes**:
- Add logic to regenerate future dates from `occurrences` patterns
- Update `starts_at` and `ends_at` when all occurrences expire
- Ensure recurring events always have at least N future occurrences

### Phase 3 Implementation Plan (REVISED)

**Original Plan**: Centralize 7-day threshold ❌ (already centralized!)

**New Plan**: Fix recurring event date generation ✅

```
Phase 3: Implement Recurring Event Regeneration Logic
├─ 3.1: Create RecurringEventUpdater service
├─ 3.2: Add logic to compute next N occurrences from pattern
├─ 3.3: Integrate into EventProcessor
├─ 3.4: Test with Question One (45 events with patterns)
└─ 3.5: Rollout to all pattern-based scrapers
```

---

## 8. Configuration Audit

### Current Default
```elixir
freshness_threshold_hours: 168  # 7 days
```

**Used by**: 11 scrapers (all except kino-krakow, cinema-city)

### Current Overrides
```elixir
source_freshness_overrides: %{
  "kino-krakow" => 24,    # 1 day (daily scraping for showtimes)
  "cinema-city" => 48      # 2 days (bi-daily scraping for showtimes)
}
```

**Rationale**: Movie showtimes change frequently, need more frequent updates.

### Recommended Changes for Phase 4

**None immediately required.** Current configuration is appropriate:
- 7 days for recurring events (trivia, concerts, exhibitions)
- 1-2 days for movies (showtimes change frequently)

**Future Consideration**: Add override for high-volume scrapers if needed.

---

## 9. Files Involved in Fix

### Core Service (Working Correctly)
- ✅ `lib/eventasaurus_discovery/services/event_freshness_checker.ex` (lines 1-339)

### Configuration (Working Correctly)
- ✅ `config/dev.exs` (lines 127-139)
- ✅ `config/test.exs` (lines 95-107)
- ✅ `config/runtime.exs` (lines 380-393)

### Needs New Implementation (Phase 3)
- ⚠️ `lib/eventasaurus_discovery/scraping/processors/event_processor.ex` (add recurring date logic)
- ⚠️ New service: `lib/eventasaurus_discovery/services/recurring_event_updater.ex`

### All Scrapers Using EventFreshnessChecker
```
lib/eventasaurus_discovery/sources/
├── question_one/jobs/index_page_job.ex:126
├── inquizition/jobs/index_job.ex
├── speed_quizzing/jobs/index_job.ex
├── quizmeisters/jobs/index_job.ex
├── geeks_who_drink/jobs/index_job.ex
├── pubquiz/jobs/city_job.ex
├── kino_krakow/jobs/day_page_job.ex
├── cinema_city/jobs/cinema_date_job.ex
├── karnet/jobs/index_page_job.ex
├── waw4free/jobs/sync_job.ex
├── resident_advisor/jobs/sync_job.ex
├── bandsintown/jobs/index_page_job.ex
└── ticketmaster/jobs/sync_job.ex
```

---

## 10. Phase 2 Conclusions

### Key Findings

1. **Centralization Complete** ✅
   All threshold logic is already centralized in `EventFreshnessChecker`.

2. **Configuration Unified** ✅
   Single source of truth in config files with env var override for production.

3. **Wide Adoption** ✅
   13 of 14 scrapers use the service. Only sortiraparis needs verification.

4. **Bug Misdiagnosed** ⚠️
   The Question One issue is NOT about the 7-day threshold. It's about failing to regenerate future dates from recurring patterns.

5. **Phase 3 Redirect Required** ⚡
   Next phase should focus on recurring event date generation, NOT threshold centralization.

### Status: Phase 2 Complete ✅

**Next Step**: Revise Phase 3 plan to focus on recurring event date regeneration logic.

---

## Appendix A: Test Data from Phase 1

### Question One Event Analysis (Post-Scrape)
```sql
-- Total events
SELECT COUNT(*) FROM public_events pe
JOIN public_event_sources pes ON pe.id = pes.event_id
JOIN sources s ON pes.source_id = s.id
WHERE s.slug = 'question-one';
-- Result: 124 events

-- Future events
SELECT COUNT(*) FROM public_events pe
JOIN public_event_sources pes ON pe.id = pes.event_id
JOIN sources s ON pes.source_id = s.id
WHERE s.slug = 'question-one' AND pe.starts_at > NOW();
-- Result: 0 events (BUG!)

-- Recently updated events
SELECT COUNT(*) FROM public_event_sources pes
JOIN sources s ON pes.source_id = s.id
WHERE s.slug = 'question-one' AND pes.last_seen_at > NOW() - INTERVAL '1 hour';
-- Result: 45 events (✅ last_seen_at updated!)

-- Events with recurring patterns
SELECT COUNT(*) FROM public_events pe
JOIN public_event_sources pes ON pe.id = pes.event_id
JOIN sources s ON pes.source_id = s.id
WHERE s.slug = 'question-one' AND pe.occurrences IS NOT NULL;
-- Result: 124 events (all have patterns!)
```

### Key Insight
**All 124 Question One events have `occurrences` patterns, but none have future dates.** The scraper successfully touches `last_seen_at` but fails to regenerate dates from patterns.

---

**Report Generated**: October 31, 2025
**Prepared By**: Claude Code (Sonnet 4.5)
**GitHub Issue**: #2116 Phase 2
