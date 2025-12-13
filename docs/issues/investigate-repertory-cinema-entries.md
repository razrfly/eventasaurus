# GitHub Issue: Investigate Repertory Cinema Entries

**Title:** Investigate: Only Cinema City entries appear for movies, no repertory cinema entries

**Labels:** bug, investigation, scraper, movies

---

## Problem

On movie detail pages (e.g., https://wombie.com/c/krakow/movies/zootopia-2-1084242), only Cinema City showtimes appear. Repertory/art-house cinema entries are not showing up.

## Investigation Summary

### Architecture Overview

The system has two separate movie scraper sources:

1. **Cinema City** (`lib/eventasaurus_discovery/sources/cinema_city/`)
   - Scrapes the Cinema City multiplex chain (mainstream blockbusters)
   - Uses Cinema City's JSON API: `/data-api-service/v1/quickbook/10103/`
   - Covers 3 Kraków locations: Bonarka (1090), Galeria Kazimierz (1076), Zakopianka (1064)
   - Priority: 15

2. **Repertuary** (`lib/eventasaurus_discovery/sources/repertuary/`)
   - Scrapes from repertuary.pl network (art-house/independent cinemas)
   - Kraków uses legacy domain: `www.kino.krakow.pl`
   - Covers 29+ Polish cities with independent cinemas
   - Priority: 15 (same as Cinema City)

### How Movie Screenings Are Displayed

The movie detail page (`PublicMovieScreeningsLive`) fetches screenings by:

```elixir
screenings =
  from(pe in PublicEvent,
    join: em in "event_movies",
    on: pe.id == em.event_id,
    join: v in assoc(pe, :venue),
    on: v.city_id == ^city.id,
    where: em.movie_id == ^movie.id,
    ...
  )
```

This should include events from **both** Cinema City and Repertuary sources if they're properly linked to movies via TMDB matching.

### Potential Root Causes

#### 1. Repertuary Scraper Not Running or Failing
- The Repertuary scraper requires the TMDB API key (`TMDB_API_KEY` env var)
- If TMDB matching fails, movies don't get stored in DB, and showtimes aren't processed
- Check: `mix monitor.jobs list --source repertuary`

#### 2. TMDB Matching Failures for New Movies
- Both scrapers use TMDB matching with confidence thresholds:
  - ≥70%: Auto-match
  - 50-69%: Fallback matching
  - <50%: Skipped
- New releases like Zootopia 2 might not match well if:
  - Polish title differs significantly from English
  - Release date in Poland differs
  - TMDB data is incomplete

#### 3. Movie Slug/ID Mismatch
- Cinema City stores `cinema_city_film_id` in movie metadata
- Repertuary stores `repertuary_slug` in movie metadata
- If they create separate movie records for the same film, showtimes won't aggregate

#### 4. Event Freshness Filtering
- `EventFreshnessChecker` may be filtering out Repertuary events
- Check if events are being created but not displayed

#### 5. City Configuration
- Repertuary enabled cities config: `Application.get_env(:eventasaurus, :repertuary_enabled_cities, ["krakow"])`
- Default is only `["krakow"]` - but Kraków might not be properly enabled

### Diagnostic Queries

To investigate this issue, run these queries:

```elixir
# Check if Repertuary scraper is running and has recent executions
alias EventasaurusDiscovery.Monitoring.Health
{:ok, health} = Health.check("repertuary", hours: 24)

# Check Repertuary job failures
alias EventasaurusDiscovery.Monitoring.Errors
{:ok, analysis} = Errors.analyze("repertuary", hours: 48)

# Check if movie exists with both sources
alias EventasaurusDiscovery.Movies.Movie
Repo.one(from m in Movie, where: m.tmdb_id == 1084242)

# Check events linked to this movie
Repo.all(
  from pe in PublicEvent,
  join: em in "event_movies", on: em.event_id == pe.id,
  join: m in Movie, on: m.id == em.movie_id,
  where: m.tmdb_id == 1084242,
  preload: [:venue, sources: :source]
)
```

### CLI Commands

```bash
# Check recent Repertuary job executions
mix monitor.jobs list --source repertuary --limit 50

# Check Repertuary failures
mix monitor.jobs failures --source repertuary

# Check job stats
mix monitor.jobs stats --source repertuary --hours 48

# Check specific worker failures
mix monitor.jobs worker MovieDetailJob --source repertuary --state failure
```

### Files to Review

- `lib/eventasaurus_discovery/sources/repertuary/jobs/sync_job.ex` - Main orchestration
- `lib/eventasaurus_discovery/sources/repertuary/jobs/movie_detail_job.ex` - TMDB matching
- `lib/eventasaurus_discovery/sources/repertuary/tmdb_matcher.ex` - Matching logic
- `lib/eventasaurus_discovery/sources/repertuary/cities.ex` - City configuration

## Expected Behavior

Movie detail pages should show showtimes from **all** cinema sources in the city:
- Cinema City multiplexes (mainstream showings)
- Independent/art-house cinemas from Repertuary (repertory showings)
- Any other movie sources

## Questions to Answer

1. Is the Repertuary scraper successfully running for Kraków?
2. Are Repertuary events being created but not linked to the same Movie record?
3. Is TMDB matching working correctly for new releases?
4. Are there venue/city matching issues preventing Repertuary venues from appearing?

## Technical Details

### Data Flow Comparison

| Step | Cinema City | Repertuary |
|------|-------------|------------|
| Entry Point | `SyncJob` with `city_name` | `SyncJob` with `city` |
| API/Scrape | JSON API | HTML scraping |
| Movie Matching | TMDB via shared matcher | TMDB via shared matcher |
| Movie Metadata Key | `cinema_city_film_id` | `repertuary_slug` |
| Event External ID | `cinema_city_showtime_{ids}` | `repertuary_showtime_{ids}` |

### Shared Components

Both scrapers use the same TMDB matching logic:
- `EventasaurusDiscovery.Sources.Repertuary.TmdbMatcher` (also used by Cinema City)
- Confidence scoring based on title similarity, year, runtime, director, country
- Movies stored in `EventasaurusDiscovery.Movies.Movie` table

### Possible Fix Locations

If the issue is identified, fixes might be needed in:

1. **Scraper scheduling** - Ensure Repertuary is scheduled to run
2. **TMDB matching** - Improve matching for Polish titles
3. **Movie deduplication** - Ensure both scrapers link to same movie record
4. **Venue/city matching** - Ensure Repertuary venues are in correct city
