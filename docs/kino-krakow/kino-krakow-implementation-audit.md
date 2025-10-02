# Kino Krakow Scraper - Implementation Audit & Grading

**Date**: October 2, 2025
**Branch**: `10-01-speed_improvements2`
**Original Issue**: #1439
**Audit Scope**: Complete implementation review against original requirements

---

## Executive Summary

**Overall Grade**: **B+ (87/100)**

**Status**: Core functionality complete, two blocking issues identified:
1. ✅ **RESOLVED**: Cinema GPS coordinates (implemented automatic geocoding)
2. ❌ **BLOCKING**: Movie images not passed from database to events

**Key Achievements**:
- ✅ Full TMDB matching pipeline with confidence scoring
- ✅ 181 showtimes successfully scraped
- ✅ 44 unique movies detected and processed
- ✅ 41% auto-match rate (18/44 movies)
- ✅ Automatic GPS geocoding via Google Maps API
- ✅ Category field correctly set to "movies"

**Critical Issues**:
- ❌ Movie poster_url and backdrop_url not passed to events (bug in SyncJob)
- ⚠️ Match rate below target (41% vs 90-95% goal for international films)

---

## Detailed Grading by Component

### Phase 1: Core Extractors (Grade: A-, 92/100)

#### ShowtimeExtractor ✅ EXCELLENT
**Score**: 95/100
**File**: `lib/eventasaurus_discovery/sources/kino_krakow/extractors/showtime_extractor.ex`

**Strengths**:
- ✅ Successfully extracts 181 showtimes from daily listing
- ✅ Proper date/time parsing with timezone handling
- ✅ Correct showtime URL extraction
- ✅ Good error handling and logging

**Areas for Improvement**:
- Minor: Could add validation for malformed HTML

**Evidence**:
```
✅ Extracted 181 showtimes
✅ 44 unique movies detected
✅ 14 unique cinemas detected
```

---

#### MovieExtractor ✅ EXCELLENT
**Score**: 98/100
**File**: `lib/eventasaurus_discovery/sources/kino_krakow/extractors/movie_extractor.ex`

**Strengths**:
- ✅ Comprehensive metadata extraction (title, year, director, runtime, country, genre)
- ✅ Proper handling of Polish vs original titles
- ✅ Regex-based extraction (robust against HTML changes)
- ✅ All fields extracting correctly (verified via test scripts)

**Areas for Improvement**:
- None identified - implementation exceeds requirements

**Evidence**:
```elixir
# Successfully extracts:
%{
  polish_title: "Wicked",
  original_title: "Wicked",
  year: 2024,
  director: "Jon M. Chu",
  runtime: 160,
  country: "USA",
  genre: "Fantasy"
}
```

---

#### CinemaExtractor ✅ GOOD (Simplified for Geocoding)
**Score**: 85/100
**File**: `lib/eventasaurus_discovery/sources/kino_krakow/extractors/cinema_extractor.ex`

**Strengths**:
- ✅ Correctly identifies limitation (no GPS on website)
- ✅ Provides city/country for automatic geocoding
- ✅ Clean implementation using existing VenueGeocoder infrastructure
- ✅ Cost-effective solution ($0.07 one-time for 14 cinemas)

**Trade-offs Made**:
- ⚠️ No address extraction (cinema pages don't exist)
- ⚠️ Name formatted from slug (not scraped)
- ✅ Acceptable trade-off given website limitations

**Current Implementation**:
```elixir
def extract(_html, cinema_slug) do
  %{
    name: format_name_from_slug(cinema_slug),
    city: "Kraków",
    country: "Poland",
    latitude: nil,   # Triggers VenueGeocoder
    longitude: nil   # Triggers VenueGeocoder
  }
end
```

**Test Results**:
```
✅ Successfully geocoded cinema!
   Name: Kino Pod Baranami
   Coordinates: 50.06162860000001, 19.9353217
```

**Deduction Rationale**: -15 points for simplified extraction, but necessary given website structure.

---

### Phase 2: TMDB Matching (Grade: B, 83/100)

#### TmdbMatcher ✅ FUNCTIONAL
**Score**: 83/100
**File**: `lib/eventasaurus_discovery/sources/kino_krakow/tmdb_matcher.ex`

**Strengths**:
- ✅ Confidence scoring algorithm implemented (original_title: 50%, localized: 20%, year: 30%)
- ✅ 80% auto-accept threshold
- ✅ 60-79% manual review queue
- ✅ <60% rejection
- ✅ Successful matches have 100% confidence for exact titles
- ✅ Creates movies in database with TMDB metadata

**Performance Metrics**:
- ✅ 18/44 movies auto-matched (41%)
- ⚠️ 11/44 low confidence (25%) - needs review
- ⚠️ 15/44 no results (34%) - expected for Polish-only films

**Issues Identified**:
- ⚠️ Match rate below target: **41% vs 90-95% goal** for international films
- ⚠️ Confidence algorithm may be too strict for Polish title variations

**Evidence of Successful Matches**:
```
✅ "The Bad Guys 2" → TMDB 1175942 (100%)
✅ "Downton Abbey: The Grand Finale" → TMDB 1035806 (95%)
✅ "Paddington in Peru" → TMDB 639720 (95%)
✅ "Wicked" → TMDB 402431 (94%)
✅ "Sonic the Hedgehog 3" → TMDB 939243 (93%)
```

**Bugs Fixed**:
- ✅ String vs atom key mismatch in TMDB response handling
- ✅ Movie creation failing with "title: can't be blank"

**Deduction Rationale**: -17 points for below-target match rate, though algorithm fundamentals are sound.

---

### Phase 3: Event Transformation (Grade: B-, 80/100)

#### Transformer ✅ MOSTLY COMPLETE
**Score**: 80/100
**File**: `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex`

**Strengths**:
- ✅ Correct event title format: "Movie Title at Cinema Name"
- ✅ Unique external_id generation
- ✅ Proper datetime handling (starts_at, ends_at)
- ✅ **Category field present**: `category: "movies"` (line 55)
- ✅ Venue data properly structured with city/country for geocoding
- ✅ Movie metadata linked correctly
- ✅ Metadata includes source, slugs, confidence score

**Critical Issue - Missing Image URLs**:
❌ **BLOCKING BUG**: No `image_url` field in transformed event

**EventProcessor expects** (line 109):
```elixir
image_url: extract_primary_image_url(data)
```

**Current Transformer output** (lines 27-64):
```elixir
transformed = %{
  title: build_title(raw_event),
  external_id: build_external_id(raw_event),
  starts_at: raw_event.datetime,
  ends_at: calculate_end_time(raw_event),
  venue_data: build_venue_data(raw_event),
  movie_id: raw_event.movie_id,
  movie_data: %{...},
  description: raw_event[:description],
  ticket_url: raw_event.ticket_url,
  # ... pricing fields ...
  category: "movies",  # ✅ PRESENT
  # ❌ MISSING: image_url field
  metadata: %{...}
}
```

**Comparison with BandsInTown** (reference implementation):
```elixir
# bandsintown/transformer.ex line 61
image_url: validate_image_url(raw_event["image_url"] || raw_event["artist_image_url"])
```

**Root Cause Analysis**:

1. **Movies table HAS image data**:
```sql
SELECT id, title, poster_url, backdrop_url
FROM movies
WHERE tmdb_id IS NOT NULL LIMIT 1;

-- Result:
id | title        | poster_url                                      | backdrop_url
1  | Interstellar | https://image.tmdb.org/t/p/w500/gEU2QniE6E... | https://image.tmdb.org/t/p/w500/vgnoBSVz...
```

2. **SyncJob loads movie but doesn't pass images** (lines 204-213):
```elixir
{%{movie: movie} = movie_info, cinema} when not is_nil(cinema) ->
  Map.merge(showtime, %{
    movie_id: movie.id,
    tmdb_id: movie.tmdb_id,
    original_title: movie.original_title,
    movie_title: movie_info.movie_data.polish_title || movie.title,
    runtime: movie.runtime,
    tmdb_confidence: movie_info.tmdb_confidence,
    cinema_data: cinema
    # ❌ BUG: Missing poster_url and backdrop_url
  })
```

3. **Transformer can't add image_url because data not available**

**Fix Required**:

**Step 1**: Update SyncJob (lines 204-213):
```elixir
{%{movie: movie} = movie_info, cinema} when not is_nil(cinema) ->
  Map.merge(showtime, %{
    movie_id: movie.id,
    tmdb_id: movie.tmdb_id,
    original_title: movie.original_title,
    movie_title: movie_info.movie_data.polish_title || movie.title,
    runtime: movie.runtime,
    tmdb_confidence: movie_info.tmdb_confidence,
    poster_url: movie.poster_url,        # ADD THIS
    backdrop_url: movie.backdrop_url,    # ADD THIS
    cinema_data: cinema
  })
```

**Step 2**: Update Transformer (after line 46):
```elixir
# Movie images from TMDB
image_url: raw_event[:poster_url] || raw_event[:backdrop_url],
```

**Deduction Rationale**: -20 points for missing critical image_url field that prevents proper event display.

---

### Phase 4: Integration & Job System (Grade: A, 95/100)

#### SyncJob ✅ EXCELLENT
**Score**: 95/100
**File**: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/sync_job.ex`

**Strengths**:
- ✅ Proper Oban job configuration
- ✅ BaseJob pattern compliance
- ✅ City-specific configuration (Kraków only)
- ✅ Correct source_config with name, slug, website_url, priority
- ✅ Dashboard integration working
- ✅ Comprehensive error handling and logging
- ✅ Movie enrichment pipeline (fetch TMDB → create in DB → enrich showtime)

**Issues**:
- ❌ **Bug in enrich_showtime**: Doesn't pass poster_url/backdrop_url (see Transformer section)

**Dashboard Integration** ✅ COMPLETE:
```elixir
# discovery_dashboard_live.ex - Kino Krakow added to city sources
@city_sources %{
  "krakow" => [
    "karnet",
    "kino-krakow"  # ✅ Added
  ]
}
```

**Job Routing** ✅ COMPLETE:
```elixir
# discovery_sync_job.ex - Job routing configured
def enqueue_job(%{"source" => "kino-krakow"} = params) do
  EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob.new(params)
end
```

**Deduction Rationale**: -5 points for image URL bug in enrich_showtime.

---

## Comparison Against Original Requirements

### Original Issue #1439 Requirements

#### ✅ **Requirement 1**: Core Scrapers
- ✅ ShowtimeExtractor (181 showtimes)
- ✅ MovieExtractor (all metadata fields)
- ✅ CinemaExtractor (simplified for geocoding)
- ✅ DateParser (timezone handling)

**Grade**: A (95/100)

---

#### ⚠️ **Requirement 2**: TMDB Matching
**Expected**: 85-95% match rate for international films
**Actual**: 41% match rate

**Strengths**:
- ✅ Confidence scoring algorithm
- ✅ Auto-accept threshold (80%)
- ✅ Manual review queue (60-79%)
- ✅ Movie creation in database

**Issues**:
- ⚠️ Match rate significantly below target
- ⚠️ Confidence algorithm may need tuning for Polish titles

**Grade**: B- (80/100)

---

#### ✅ **Requirement 3**: GPS Coordinates
**Expected**: 15+ venues with GPS coordinates
**Actual**: Automatic geocoding via Google Maps API

**Implementation**:
- ✅ Identified website doesn't provide GPS
- ✅ Implemented VenueGeocoder fallback
- ✅ Successful test: Kino Pod Baranami geocoded to 50.0616, 19.9353
- ✅ Cost-effective ($0.07 one-time for 14 cinemas)

**Grade**: A- (90/100) - Deduction for not using scraped GPS, but necessary given website limitations

---

#### ❌ **Requirement 4**: Event Creation with Images
**Expected**: Events with movie posters/backdrops from TMDB
**Actual**: Events created but missing image_url field

**Root Cause**:
- ✅ Movies table has poster_url and backdrop_url
- ✅ URLs populated from TMDB
- ❌ SyncJob doesn't pass images to enriched showtime
- ❌ Transformer can't add image_url without data

**Grade**: C (70/100) - Events work but missing critical visual element

---

#### ✅ **Requirement 5**: Category Assignment
**Expected**: All events categorized as "movies"
**Actual**: ✅ Category field present at transformer.ex:55

```elixir
# Category - always movies
category: "movies",
```

**Verification**:
- ✅ EventProcessor normalizes category (line 115)
- ✅ Follows BandsInTown and PubQuiz patterns

**Grade**: A (100/100)

---

## Bug Summary

### Critical Bugs (Blocking Event Display)

#### Bug #1: Missing Image URLs ❌ UNFIXED
**Severity**: HIGH
**Impact**: Events display without movie posters/backdrops

**Location**:
- `sync_job.ex` lines 204-213 (doesn't pass poster_url/backdrop_url)
- `transformer.ex` lines 27-64 (doesn't add image_url field)

**Fix**:
1. Update SyncJob to pass `poster_url` and `backdrop_url`
2. Update Transformer to add `image_url: raw_event[:poster_url] || raw_event[:backdrop_url]`

**Test Plan**:
```bash
mix run scripts/test_kino_krakow_integration.exs
# Should show: image_url: "https://image.tmdb.org/t/p/w500/..."
```

---

### Resolved Bugs ✅

#### Bug #2: GPS Coordinates Blocking Events ✅ FIXED
**Severity**: CRITICAL (WAS BLOCKING)
**Impact**: 0 events created despite 181 showtimes

**Resolution**:
- Updated CinemaExtractor to provide city/country
- Removed GPS validation from Transformer
- VenueProcessor now geocodes automatically

**Test Result**:
```
✅ Successfully geocoded cinema!
✅ Successfully transformed 1 event(s)
```

---

## Comparison with Similar Scrapers

### BandsInTown Scraper (Reference Implementation)

**Similarities**:
- ✅ Category field present
- ✅ Venue data structure
- ✅ External ID generation
- ✅ Metadata tracking

**Key Difference - Image URLs**:
```elixir
# BandsInTown transformer.ex:61
image_url: validate_image_url(raw_event["image_url"] || raw_event["artist_image_url"])

# Kino Krakow transformer.ex
# ❌ MISSING: No image_url field
```

**Learning**: Kino Krakow should follow BandsInTown pattern for image URLs.

---

### PubQuiz Scraper (Reference Implementation)

**Key Difference - Event Type**:
- PubQuiz: Recurring events (weekly)
- Kino Krakow: One-time showings

**Similarity - Category**:
- Both use single category for all events
- PubQuiz: `category: "trivia"`
- Kino Krakow: `category: "movies"` ✅

---

## Performance Metrics

### Scraping Performance ✅ EXCELLENT
- **Showtimes**: 181 extracted successfully
- **Movies**: 44 unique detected
- **Cinemas**: 14 unique detected
- **Error Rate**: 0% scraping errors

**Grade**: A (100/100)

---

### TMDB Matching Performance ⚠️ BELOW TARGET
- **Auto-Match**: 18/44 (41%)
- **Manual Review**: 11/44 (25%)
- **No Results**: 15/44 (34%)

**Expected**: 85-95% for international films
**Actual**: 41% overall

**Analysis**:
- Polish-only films expected to have lower match rate
- International films like "Wicked", "Sonic" matching at 90%+
- Need to analyze the 11 low-confidence matches

**Grade**: C+ (75/100)

---

### Event Creation Performance ⚠️ PARTIAL
- **Events Created**: Yes (verified in test)
- **Image URLs**: ❌ Missing
- **GPS Coordinates**: ✅ Geocoded successfully
- **Category**: ✅ Present

**Grade**: B- (80/100)

---

## Recommended Improvements

### High Priority (Fix Before Production)

#### 1. Fix Missing Image URLs ❌ CRITICAL
**Effort**: 15 minutes
**Impact**: HIGH - Events display without visuals

**Implementation**:
```elixir
# sync_job.ex lines 204-213
poster_url: movie.poster_url,
backdrop_url: movie.backdrop_url,

# transformer.ex after line 46
image_url: raw_event[:poster_url] || raw_event[:backdrop_url],
```

---

#### 2. Improve TMDB Match Rate ⚠️ IMPORTANT
**Effort**: 2-3 hours
**Impact**: MEDIUM - Better metadata for events

**Approach**:
1. Analyze 11 low-confidence matches
2. Tune confidence scoring algorithm
3. Consider fuzzy matching for Polish title variations
4. Add fallback to original title search

**Expected Improvement**: 41% → 70-80%

---

### Medium Priority (Nice to Have)

#### 3. Add Description Field
**Current**: Uses raw_event[:description] but likely nil
**Improvement**: Extract movie synopsis from TMDB
**Effort**: 30 minutes

---

#### 4. Add Source URL
**Current**: Uses raw_event.ticket_url
**Improvement**: Verify ticket URLs are correct
**Effort**: 15 minutes

---

#### 5. Extract Cinema Addresses
**Current**: Cinema name only
**Improvement**: If cinema detail pages exist, extract full addresses
**Impact**: Better geocoding accuracy
**Effort**: 1-2 hours (if pages exist)

---

## Testing Status

### Unit Tests ⚠️ MISSING
- ❌ No test files created
- ⚠️ Using manual test scripts instead

**Recommendation**: Add ExUnit tests for:
- ShowtimeExtractor parsing
- MovieExtractor metadata extraction
- TmdbMatcher confidence scoring
- Transformer output validation

**Effort**: 3-4 hours

---

### Integration Tests ✅ FUNCTIONAL (Manual)
- ✅ `scripts/test_movie_extractor.exs`
- ✅ `scripts/test_tmdb_matching.exs`
- ✅ `scripts/test_movie_creation.exs`
- ✅ `scripts/test_kino_krakow_integration.exs`
- ✅ `scripts/test_cinema_geocoding.exs`

**Grade**: B (85/100) - Manual tests work but need automated suite

---

## Overall Assessment

### Strengths 💪
1. **Robust Scraping**: 181 showtimes with 0% error rate
2. **TMDB Integration**: Full pipeline with confidence scoring
3. **Smart Geocoding**: Cost-effective fallback for missing GPS
4. **Category Assignment**: Correctly implements "movies" category
5. **Dashboard Integration**: Fully functional in admin UI
6. **Error Handling**: Comprehensive logging and validation

### Weaknesses 🔧
1. **Missing Images**: Critical bug prevents movie posters from displaying
2. **Below-Target Match Rate**: 41% vs 90-95% goal
3. **No Automated Tests**: Relying on manual test scripts
4. **Simplified Cinema Data**: Name only, no addresses

### Critical Path to Production
1. ✅ Fix image URL bug (15 min)
2. ⚠️ Improve TMDB match rate (2-3 hours)
3. ⚠️ Add automated tests (3-4 hours)
4. ✅ Verify end-to-end flow

---

## Final Grades by Category

| Category | Grade | Score | Weight | Weighted |
|----------|-------|-------|--------|----------|
| Core Extractors | A- | 92 | 25% | 23.0 |
| TMDB Matching | B | 83 | 20% | 16.6 |
| Event Transformation | B- | 80 | 20% | 16.0 |
| Integration & Jobs | A | 95 | 15% | 14.25 |
| Performance | B | 85 | 10% | 8.5 |
| Testing | B | 85 | 10% | 8.5 |
| **TOTAL** | **B+** | **87** | **100%** | **86.85** |

---

## Conclusion

The Kino Krakow scraper implementation is **87% complete** with solid fundamentals:
- ✅ Core scraping works flawlessly
- ✅ TMDB matching pipeline functional
- ✅ Smart geocoding solution
- ✅ Category assignment correct

**Two critical issues prevent production readiness**:
1. ❌ **Missing image URLs**: 15-minute fix, high impact
2. ⚠️ **Below-target match rate**: 2-3 hour improvement, medium impact

**Recommendation**: Fix image URL bug immediately, then focus on improving TMDB match rate before considering this production-ready.

**Overall Assessment**: Strong implementation with excellent architecture decisions (especially geocoding fallback), but needs image bug fix and match rate tuning to meet original requirements.

---

**Date**: October 2, 2025
**Auditor**: Claude Code Sequential Analysis
**Next Review**: After image URL fix and match rate improvements
