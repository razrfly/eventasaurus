# Kino Krakow Implementation Audit & Next Steps

**Date**: October 2, 2025
**Status**: Partial Implementation Complete
**Source**: https://www.kino.krakow.pl

---

## Executive Summary

The Kino Krakow scraper has been successfully implemented with movie consolidation, TMDB integration, and source linking. However, two critical features remain unimplemented:

1. **Multi-day scraping** - Currently only scrapes 1 day instead of all 7 available days
2. **Category assignment** - Movie events not properly categorized in the database

---

## ✅ What's Working Well

### 1. Movie Consolidation (COMPLETED)
**Implementation**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`

- ✅ Same movie at same venue consolidates into single event with multiple occurrences
- ✅ Different movies at same venue create separate events
- ✅ Movie-based consolidation uses `movie_id` + `venue_id` matching
- ✅ Non-movie events still use fuzzy title matching

**Key Functions**:
- `find_movie_event_parent/4` - Matches by movie_id + venue (lines 938-986)
- `find_non_movie_recurring_parent/4` - Fuzzy matching for non-movie events (lines 988-1118)

**Database Evidence** (Oct 2, 2025 test run):
```
29 events created
Average occurrences per event: 2.34
Max occurrences: 9
All events: EXACTLY 1 movie association ✅
```

**Examples**:
- "Jedna bitwa po drugiej at Cinema City/bonarka" - 9 occurrences, 1 movie ✅
- "Teściowie 3 at Multikino" - 8 occurrences, 1 movie ✅

---

### 2. Movie Associations (COMPLETED)
**Implementation**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:744-798`

- ✅ Events linked to `movies` table via `event_movies` join table
- ✅ TMDB metadata (poster, runtime, etc.) available on events
- ✅ Prevents multiple movie associations per event
- ✅ Gracefully handles association conflicts

**Key Functions**:
- `process_movies/2` - Creates EventMovie associations with duplicate prevention

**Database Schema**:
```sql
event_movies
  ├── event_id (FK to public_events)
  ├── movie_id (FK to movies)
  └── UNIQUE constraint on (event_id, movie_id)
```

---

### 3. Source Links (COMPLETED)
**Implementation**:
- Transformer: `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex:67`
- Display: `lib/eventasaurus_web/live/public_event_show_live.ex:1068`

- ✅ Source links point to specific movie pages, not just homepage
- ✅ URL format: `https://www.kino.krakow.pl/film/{movie_slug}.html`
- ✅ Displays as "Kino Krakow Last updated X minutes ago"
- ✅ Fallback to ticket URL or general website if movie URL unavailable

**Metadata Stored**:
```elixir
%{
  movie_url: "https://www.kino.krakow.pl/film/lilly-i-kangurek.html",
  movie_slug: "lilly-i-kangurek",
  cinema_slug: "galeria-bronowice"
}
```

---

### 4. TMDB Integration (COMPLETED)
**Implementation**: `lib/eventasaurus_discovery/sources/kino_krakow/tmdb_matcher.ex`

- ✅ Matches Polish movie titles to TMDB database
- ✅ Fuzzy matching with configurable thresholds
- ✅ Caches movie data to avoid duplicate API calls
- ✅ Handles movies needing manual review

**Matching Strategy**:
1. Search TMDB by Polish title
2. Compare original titles and release years
3. Calculate Jaro distance for fuzzy matching
4. Store TMDB metadata (poster, runtime, etc.)

---

### 5. Venue Handling (COMPLETED)
**Implementation**: `lib/eventasaurus_discovery/sources/kino_krakow/extractors/cinema_extractor.ex`

- ✅ Extracts cinema name, address, phone from cinema info pages
- ✅ Automatic geocoding for missing GPS coordinates
- ✅ Venue deduplication by name + city

---

### 6. Deduplication (COMPLETED)
**Implementation**: `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex:110`

- ✅ Unique external_id per showtime: `{movie_slug}-{cinema_slug}-{datetime}`
- ✅ Prevents duplicate showtimes across scrapes
- ✅ Updates `last_seen_at` timestamp on re-scraping

---

## ❌ Critical Issues

### Issue 1: Single-Day Scraping Only

**Current Behavior**:
The scraper only fetches showtimes for **one day** (whichever day is currently "active" on the server, typically the current day).

**Expected Behavior**:
Kino Krakow provides a 7-day calendar with days 0-6 (current day + 6 future days). The scraper should fetch **all 7 days** to provide a complete week of showtimes.

**Site Structure**:
```html
<table class="calendar">
  <tr>
    <th colspan="8">Wybierz dzień</th>
  </tr>
  <tr>
    <td class="Thursday">
      <a data-method="post" href="/settings/set_day/0">Czw<br> 2 10</a>
    </td>
    <td class="active Friday">
      <a data-method="post" href="/settings/set_day/1">Pt<br> 3 10</a>
    </td>
    <!-- ... days 2-6 ... -->
  </tr>
</table>
```

**Technical Challenge**:
The site uses session-based day selection via POST requests to `/settings/set_day/{0-6}`. This requires:
1. Cookie/session management across multiple requests
2. Sequential requests to set each day before fetching
3. Combining results from all 7 days

**Current Code** (`lib/eventasaurus_discovery/sources/kino_krakow/jobs/sync_job.ex:93-109`):
```elixir
defp fetch_showtimes_page(_date) do
  url = Config.showtimes_url()  # Always /cinema_program/by_movie
  headers = [{"User-Agent", Config.user_agent()}]

  # No day selection - gets whatever day is active on server
  HTTPoison.get(url, headers, timeout: Config.timeout())
end
```

**Impact**:
- Users only see ~1/7th of available showtimes
- Daily scraping doesn't provide rolling 7-day window
- Events appear to have fewer occurrences than they actually do

---

### Issue 2: Category Assignment Not Working

**Current Behavior**:
The transformer sets `category: "movies"` but this is **not creating category associations** in the database.

**Expected Behavior**:
All Kino Krakow events should be linked to a "Movies" category in the `categories` table via the `event_categories` join table.

**Current Code** (`lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex:58`):
```elixir
# Category - always movies
category: "movies",
```

**Missing Logic**:
The EventProcessor has no `process_categories` function equivalent to the `process_movies` function we added. Categories are currently ignored during event processing.

**Database Schema**:
```sql
categories
  ├── id
  ├── name
  ├── slug
  └── ...

event_categories
  ├── event_id (FK to public_events)
  ├── category_id (FK to categories)
  └── UNIQUE constraint on (event_id, category_id)
```

**Impact**:
- Movie events cannot be filtered by category
- Users cannot browse "Movies" as a category
- Search and discovery features missing category context

---

## 🔧 Implementation Plan

### Task 1: Multi-Day Scraping

**Objective**: Fetch all 7 days of showtimes in a single scrape run

**Implementation Approach**:

#### Option A: Session-Based Scraping (Recommended)
Use HTTPoison with cookie management to iterate through all 7 days:

```elixir
defmodule EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob do
  # New multi-day fetch implementation
  defp fetch_all_days_showtimes do
    base_url = Config.base_url()
    headers = [{"User-Agent", Config.user_agent()}]

    # Initial request to get session cookies
    {:ok, %{headers: response_headers}} =
      HTTPoison.get("#{base_url}/cinema_program/by_movie", headers)

    cookies = extract_cookies(response_headers)

    # Fetch each day 0-6
    Enum.flat_map(0..6, fn day_offset ->
      rate_limit_delay()

      # Set the day via POST
      headers_with_cookies = [{"Cookie", cookies} | headers]
      HTTPoison.post(
        "#{base_url}/settings/set_day/#{day_offset}",
        "",
        headers_with_cookies
      )

      rate_limit_delay()

      # Fetch showtimes for this day
      {:ok, %{body: html}} =
        HTTPoison.get(
          "#{base_url}/cinema_program/by_movie",
          headers_with_cookies
        )

      # Extract showtimes
      ShowtimeExtractor.extract(html, Date.utc_today())
    end)
  end

  defp extract_cookies(headers) do
    headers
    |> Enum.filter(fn {name, _} -> name == "Set-Cookie" end)
    |> Enum.map(fn {_, value} -> value |> String.split(";") |> hd() end)
    |> Enum.join("; ")
  end
end
```

**Files to Modify**:
- `lib/eventasaurus_discovery/sources/kino_krakow/jobs/sync_job.ex`
  - Replace `fetch_showtimes_page/1` with `fetch_all_days_showtimes/0`
  - Add cookie extraction logic
  - Update `fetch_events/3` to use new function

**Testing Strategy**:
1. Test cookie extraction from initial request
2. Verify POST to set_day updates session
3. Confirm each day returns different showtimes
4. Validate total showtimes across 7 days matches website
5. Check for duplicate showtimes (should be none due to external_id)

**Rate Limiting**:
- Already have 2-second delays between requests
- 7 days × 2 requests (POST + GET) = 14 requests
- Total time: ~28 seconds per scrape
- Still within reasonable limits

---

#### Option B: URL Parameter Investigation (Lower Priority)
Before implementing session approach, quickly test if day can be set via URL parameters:

```bash
# Test these URLs manually:
curl "https://www.kino.krakow.pl/cinema_program/by_movie?day=0"
curl "https://www.kino.krakow.pl/cinema_program/by_movie/0"
```

If a parameter approach works, it would be simpler than session management.

---

### Task 2: Category Assignment

**Objective**: Link all Kino Krakow events to "Movies" category

**Implementation Approach**:

Add category processing to EventProcessor similar to the movie processing we already implemented:

```elixir
# lib/eventasaurus_discovery/scraping/processors/event_processor.ex

# Add to process_event pipeline (around line 68)
{:ok, _categories} <- process_categories(event, normalized) do
  {:ok, Repo.preload(event, [:venue, :performers, :categories, :movies])}
end

# New function to handle category assignment
defp process_categories(event, %{category: category_name}) when not is_nil(category_name) do
  # Check if event already has this category
  existing_category_id =
    Repo.one(
      from(ec in EventasaurusDiscovery.PublicEvents.EventCategory,
        where: ec.event_id == ^event.id,
        join: c in assoc(ec, :category),
        where: c.slug == ^category_slug(category_name),
        select: c.id,
        limit: 1
      )
    )

  if is_nil(existing_category_id) do
    # Find or create category
    category = get_or_create_category(category_name)

    # Create association
    changeset =
      %EventasaurusDiscovery.PublicEvents.EventCategory{}
      |> EventasaurusDiscovery.PublicEvents.EventCategory.changeset(%{
        event_id: event.id,
        category_id: category.id
      })

    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: [:event_id, :category_id]) do
      {:ok, association} ->
        Logger.debug("Created category association for event ##{event.id} -> #{category_name}")
        {:ok, [association]}

      {:error, reason} ->
        Logger.warning("Failed to create category association: #{inspect(reason)}")
        {:ok, []}
    end
  else
    Logger.debug("Category association already exists for event ##{event.id}")
    {:ok, []}
  end
end

defp process_categories(_event, _data), do: {:ok, []}

defp get_or_create_category(name) do
  slug = category_slug(name)

  case Repo.get_by(EventasaurusDiscovery.Categories.Category, slug: slug) do
    nil ->
      {:ok, category} =
        %EventasaurusDiscovery.Categories.Category{}
        |> EventasaurusDiscovery.Categories.Category.changeset(%{
          name: String.capitalize(name),
          slug: slug
        })
        |> Repo.insert(on_conflict: :nothing, conflict_target: :slug)

      category

    category ->
      category
  end
end

defp category_slug(name) do
  name
  |> String.downcase()
  |> String.replace(~r/[^a-z0-9\s-]/, "")
  |> String.replace(~r/\s+/, "-")
end
```

**Files to Modify**:
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`
  - Add `process_categories/2` function
  - Add to `process_event` pipeline
  - Import/alias Category and EventCategory modules if needed

**Testing Strategy**:
1. Create "Movies" category in database or verify auto-creation
2. Run Kino Krakow sync
3. Verify all events have category association:
   ```sql
   SELECT e.id, e.title, c.name as category
   FROM public_events e
   JOIN event_categories ec ON ec.event_id = e.id
   JOIN categories c ON c.id = ec.category_id
   WHERE e.id IN (SELECT DISTINCT event_id FROM public_event_sources WHERE source_id = 6)
   ```
4. Check that re-scraping doesn't duplicate categories
5. Verify category appears on event show page

---

### Task 3: Occurrence Update Verification

**Objective**: Verify that daily scraping correctly updates the 7-day rolling window

**Expected Behavior**:

**Day 1 Scrape** (Oct 2):
- Fetch days Oct 2-8
- Create events with occurrences for these dates

**Day 2 Scrape** (Oct 3):
- Fetch days Oct 3-9
- Oct 3-8: Update existing occurrences (refresh last_seen_at)
- Oct 9: Add new occurrences
- Oct 2: Old occurrences still in DB but last_seen_at is now 1 day old

**Day 8 Scrape** (Oct 9):
- Oct 2 occurrences are now 7 days old
- These should be pruned or marked as past events

**Implementation Notes**:
The current system should handle this correctly via `external_id` uniqueness:
- External ID: `{movie_slug}-{cinema_slug}-{iso8601_datetime}`
- Same showtime re-scraped → updates last_seen_at
- New showtime → creates new occurrence
- Missing showtime → last_seen_at becomes stale

**Potential Issue**:
Need to verify that occurrence updates actually update the JSONB array in `public_events.occurrences`, not just the `public_event_sources.last_seen_at`.

**Testing Strategy**:
1. Run scrape on Day 1, record all occurrences
2. Manually remove a showtime from the website (or wait for next day)
3. Run scrape on Day 2
4. Verify:
   - Existing showtimes have updated last_seen_at
   - New showtimes appear in occurrences array
   - Old showtimes still present but stale
5. Check occurrence count changes match expectations

---

## 📊 Database Schema Reference

### Relevant Tables

```sql
-- Events
public_events
  ├── id
  ├── title (e.g., "Lilly i kangurek at Galeria Bronowice")
  ├── slug
  ├── occurrences (JSONB array of date/time objects)
  └── ...

-- Event sources (one per scraped showtime originally)
public_event_sources
  ├── id
  ├── event_id (FK to public_events)
  ├── source_id (6 for Kino Krakow)
  ├── external_id (unique per showtime: movie-cinema-datetime)
  ├── last_seen_at (updated on each scrape)
  ├── source_url (ticket URL if available)
  └── metadata (JSONB with movie_url, movie_slug, cinema_slug)

-- Movies
movies
  ├── id
  ├── tmdb_id
  ├── title
  ├── original_title
  ├── poster_url
  └── runtime

-- Event-Movie associations
event_movies
  ├── event_id (FK to public_events)
  └── movie_id (FK to movies)
  └── UNIQUE (event_id, movie_id)

-- Categories (NOT YET WORKING FOR KINO KRAKOW)
categories
  ├── id
  ├── name (e.g., "Movies")
  └── slug (e.g., "movies")

-- Event-Category associations (NOT YET WORKING FOR KINO KRAKOW)
event_categories
  ├── event_id (FK to public_events)
  └── category_id (FK to categories)
  └── UNIQUE (event_id, category_id)
```

---

## 📋 Acceptance Criteria

### Multi-Day Scraping
- [ ] Scraper fetches all 7 days (0-6) in a single run
- [ ] Each day's showtimes are correctly extracted
- [ ] No duplicate showtimes across days (verified by external_id)
- [ ] Total occurrence count increases significantly (~7x current)
- [ ] Daily re-scraping updates existing occurrences and adds new ones
- [ ] Execution time remains reasonable (<2 minutes)

### Category Assignment
- [ ] "Movies" category exists in categories table
- [ ] All Kino Krakow events linked to Movies category
- [ ] Category appears on event show pages
- [ ] Category filtering works in search/browse
- [ ] Re-scraping doesn't duplicate category associations

### Occurrence Updates
- [ ] Day-to-day scraping updates last_seen_at timestamps
- [ ] New showtimes added to occurrences array
- [ ] Old showtimes remain but become stale
- [ ] Occurrence count accurately reflects available showtimes

---

## 🔍 Investigation Notes

### Day Selection Mechanism
The site uses Rails UJS (`data-remote="true"`) for AJAX day selection:
- POST to `/settings/set_day/{0-6}` updates server session
- Response is HTML fragment replacing the showtime table
- Cookies/session maintain the selected day for subsequent requests

### Alternative Approaches
1. **Scrape calendar differently**: Instead of by_movie view, check if there's a by_cinema view that shows all days
2. **URL parameters**: Investigate if `?day=N` parameter works (seems unlikely given AJAX approach)
3. **API endpoint**: Check if Kino Krakow has a JSON API (unlikely for a cinema website)

### Rate Limiting Considerations
- Current: 2-second delay between requests
- Multi-day: 14 requests total (7 × POST + GET)
- Total time: ~28 seconds
- Well within respectful scraping limits

---

## 📝 Code Quality Notes

### What's Good
- Clean separation of concerns (Extractor, Transformer, Matcher, Processor)
- Comprehensive error handling and logging
- Good use of Elixir patterns (with statements, pattern matching)
- Proper rate limiting
- TMDB integration is robust

### Areas for Improvement
- Need category processing function
- Session management not yet implemented
- Could add more comprehensive tests
- Consider adding metrics/monitoring for scrape success rates

---

## 🚀 Next Steps Priority

1. **HIGH PRIORITY**: Implement multi-day scraping
   - Will immediately 7x the available showtime data
   - Critical for user value

2. **HIGH PRIORITY**: Fix category assignment
   - Required for proper event categorization
   - Affects search and filtering

3. **MEDIUM PRIORITY**: Verify occurrence update behavior
   - Should already work but needs testing
   - Important for data freshness

4. **LOW PRIORITY**: Add monitoring/metrics
   - Track scrape success rates
   - Alert on failures
   - Monitor data quality

---

## 📅 Estimated Implementation Time

- Multi-day scraping: **4-6 hours**
  - Session/cookie management: 2h
  - Testing and debugging: 2h
  - Documentation: 1h

- Category assignment: **2-3 hours**
  - Code implementation: 1h
  - Testing: 1h
  - Verification: 1h

- Occurrence verification: **1-2 hours**
  - Testing: 1h
  - Documentation: 1h

**Total**: 7-11 hours

---

## ✅ Success Metrics

After implementation, we should see:

1. **Occurrence counts increase 5-7x**
   - Current: ~2-3 occurrences per event
   - Expected: ~10-20 occurrences per event

2. **All events categorized**
   - Current: 0% have category associations
   - Expected: 100% linked to "Movies"

3. **Daily data refresh**
   - New showtimes appear within 24 hours
   - Old showtimes marked as stale
   - 7-day rolling window maintained

4. **User experience improved**
   - More showtimes visible to users
   - Proper categorization for discovery
   - Accurate source links to movie pages

---

**Document Version**: 1.0
**Last Updated**: October 2, 2025
**Author**: Development Team
