# Cinema City Scraper - Phase 3 Implementation Complete

## Summary

Phase 3 (Job Chain) has been successfully implemented following the distributed architecture from Kino Krakow.

## Completed Items

### ✅ 1. Update SyncJob to Distributed Architecture
**File**: `lib/eventasaurus_discovery/sources/cinema_city/jobs/sync_job.ex`

**Features**:
- Coordinator job that orchestrates the entire scraping workflow
- Fetches cinema list from Cinema City API
- Filters to target cities (Kraków initially)
- Schedules CinemaDateJobs for each cinema × date combination
- Implements rate limiting through staggered job scheduling
- Uses :discovery queue (max_attempts: 3)

**Architecture**:
```
SyncJob
  ↓ schedules (staggered by cinema_index * rate_limit)
CinemaDateJob (one per cinema/date)
  ↓ schedules (staggered by film_index * rate_limit)
MovieDetailJob (one per unique film)
  ↓ waits for completion, then
ShowtimeProcessJob (one per showtime)
```

**Staggering Strategy**:
- CinemaDateJobs: `(date_offset * cinemas * rate_limit) + (cinema_index * rate_limit)`
- Spreads jobs across time to respect rate limits
- Prevents API overload

**Key Functions**:
```elixir
def perform(%Oban.Job{args: args}) do
  case Client.fetch_cinema_list(until_date) do
    {:ok, cinemas} ->
      filtered_cinemas = CinemaExtractor.filter_by_cities(cinemas, target_cities)
      jobs_scheduled = schedule_cinema_date_jobs(filtered_cinemas, source_id, days_ahead)
      {:ok, %{mode: "distributed", cinemas: length(filtered_cinemas), jobs_scheduled: jobs_scheduled}}
  end
end
```

### ✅ 2. Implement CinemaDateJob
**File**: `lib/eventasaurus_discovery/sources/cinema_city/jobs/cinema_date_job.ex`

**Features**:
- Processes events for a specific cinema on a specific date
- Fetches film events from Cinema City API
- Extracts films and events using EventExtractor
- Identifies unique movies
- Schedules MovieDetailJobs for each unique film
- Schedules ShowtimeProcessJobs for each showtime
- Uses :scraper_index queue (max_attempts: 3)

**Workflow**:
1. Fetch film events from API for cinema/date
2. Extract and match films with events
3. Schedule MovieDetailJobs (one per unique film)
4. Schedule ShowtimeProcessJobs (one per showtime)
5. Calculate delays to ensure MovieDetailJobs complete first

**Rate Limiting**:
- MovieDetailJobs: `index * Config.rate_limit()` (2 seconds between jobs)
- ShowtimeProcessJobs: `base_delay + (index * 2)` (wait for movies + 2s between)
- Base delay calculated as: `movie_count * rate_limit + 30s buffer`

**Key Functions**:
```elixir
defp schedule_movie_detail_jobs(film_ids, extracted_films, source_id) do
  film_ids
  |> Enum.with_index()
  |> Enum.map(fn {film_id, index} ->
    delay_seconds = index * Config.rate_limit()
    scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

    MovieDetailJob.new(%{
      "cinema_city_film_id" => film_id,
      "film_data" => film_data,
      "source_id" => source_id
    }, queue: :scraper_detail, scheduled_at: scheduled_at)
    |> Oban.insert()
  end)
end

defp schedule_showtime_jobs(matched, cinema_data, cinema_city_id, date, source_id, movie_count) do
  base_delay = movie_count * Config.rate_limit() + 30

  showtimes
  |> Enum.with_index()
  |> Enum.map(fn {%{film: film, event: event}, index} ->
    delay_seconds = base_delay + (index * 2)
    scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

    ShowtimeProcessJob.new(%{
      "showtime" => %{
        "film" => film,
        "event" => event,
        "cinema_data" => cinema_data
      },
      "source_id" => source_id
    }, queue: :scraper, scheduled_at: scheduled_at)
    |> Oban.insert()
  end)
end
```

### ✅ 3. Implement MovieDetailJob
**File**: `lib/eventasaurus_discovery/sources/cinema_city/jobs/movie_detail_job.ex`

**Features**:
- Processes individual Cinema City movies
- Matches Polish titles to TMDB using shared TmdbMatcher
- Creates movie records in database
- Stores cinema_city_film_id in metadata for lookups
- Uses :scraper_detail queue (max_attempts: 3)

**TMDB Matching**:
- Reuses `EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher`
- ≥70% confidence: Auto-matched (returns `{:ok, %{status: :matched}}`)
- 60-69% confidence: Now Playing fallback match (returns `{:ok, %{status: :matched}}`)
- 50-59% confidence: Needs review (returns `{:error, :tmdb_needs_review}`)
- <50% confidence: No match (returns `{:error, :tmdb_low_confidence}`)

**Data Normalization**:
```elixir
defp normalize_film_data(film_data) do
  %{
    polish_title: film_data["polish_title"],
    original_title: nil,  # Not provided by Cinema City API
    year: film_data["release_year"],
    runtime: film_data["runtime"],
    director: nil,  # Not provided by Cinema City API
    country: nil    # Not provided by Cinema City API
  }
end
```

**Metadata Storage**:
- Stores `cinema_city_film_id` in `movie.metadata`
- Stores `cinema_city_source_id` in `movie.metadata`
- Used by ShowtimeProcessJob to look up movies

### ✅ 4. Implement ShowtimeProcessJob
**File**: `lib/eventasaurus_discovery/sources/cinema_city/jobs/showtime_process_job.ex`

**Features**:
- Processes individual showtimes into events
- Retrieves matched movie from database
- Enriches showtime with movie and cinema data
- Transforms to unified event format
- Processes through EventProcessor
- Uses :scraper queue (max_attempts: 3)

**Workflow**:
1. Look up movie from database using `cinema_city_film_id`
2. If not found, check MovieDetailJob status
3. If MovieDetailJob failed, skip showtime (not an error)
4. If MovieDetailJob pending, retry (return `{:error, :movie_not_ready}`)
5. If movie found, enrich and transform showtime
6. Process through unified EventProcessor

**Database Lookup**:
```elixir
defp get_movie(cinema_city_film_id) do
  query =
    from(m in Movie,
      where: fragment("?->>'cinema_city_film_id' = ?", m.metadata, ^cinema_city_film_id)
    )

  case Repo.one(query) do
    nil -> {:error, :not_found}
    movie -> {:ok, movie}
  end
end
```

**Critical Pattern** (from BandsInTown):
```elixir
# Mark event as seen BEFORE processing
# Ensures last_seen_at updated even if processing fails
EventProcessor.mark_event_as_seen(external_id, source_id)
```

### ✅ 5. Implement Transformer
**File**: `lib/eventasaurus_discovery/sources/cinema_city/transformer.ex`

**Features**:
- Transforms Cinema City showtime data to unified format
- Builds event title: "Movie Title at Cinema Name"
- Generates unique external_id
- Calculates end_time from runtime
- Builds venue data for VenueProcessor
- Includes metadata (language, format, auditorium)

**Event Structure**:
```elixir
%{
  # Required
  title: "Movie at Cinema",
  external_id: "cinema_city_1090_123456",
  starts_at: ~U[2025-10-04 16:20:00Z],
  ends_at: ~U[2025-10-04 19:32:00Z],  # starts_at + runtime

  # Movie
  movie_id: 42,
  movie_data: %{tmdb_id: 550, title: "Fight Club", original_title: "Fight Club"},

  # Venue
  venue_data: %{
    name: "Kraków - Bonarka",
    address: "ul. Kamieńskiego 11, 30-644 Kraków",
    city: "Kraków",
    country: "Poland",
    latitude: 50.0476,
    longitude: 19.9598
  },

  # Optional
  description: "Dubbed (PL) • 3D • IMAX • Auditorium: Sala 10",
  ticket_url: "https://www.cinema-city.pl/buy/...",
  image_url: "https://image.tmdb.org/t/p/w500/...",
  category: "movies",

  # Metadata
  metadata: %{
    source: "cinema-city",
    cinema_city_id: "1090",
    cinema_city_event_id: "123456",
    auditorium: "Sala 10 - McDonald's",
    language_info: %{is_dubbed: true, dubbed_language: "pl"},
    format_info: %{is_3d: true, is_imax: true},
    genre_tags: ["sci-fi", "action"]
  }
}
```

**Description Builder**:
- Combines language info (Dubbed/Subtitled)
- Combines format info (3D/IMAX/4DX/VIP)
- Adds auditorium
- Joins with " • " separator

### ✅ 6. Verify Oban Queue Configuration
**File**: `config/config.exs`

**Already Configured**:
```elixir
config :eventasaurus, Oban,
  queues: [
    discovery: 3,        # SyncJob
    scraper_index: 2,    # CinemaDateJob
    scraper_detail: 3,   # MovieDetailJob
    scraper: 5           # ShowtimeProcessJob
  ]
```

**No changes needed** - all required queues already exist with appropriate concurrency limits.

## Files Created

```
lib/eventasaurus_discovery/sources/cinema_city/jobs/
├── sync_job.ex (updated - 185 lines)
├── cinema_date_job.ex (206 lines)
├── movie_detail_job.ex (188 lines)
└── showtime_process_job.ex (237 lines)

lib/eventasaurus_discovery/sources/cinema_city/
└── transformer.ex (180 lines)
```

**Total New Code**: ~811 lines (Phase 3 only)

## Job Chain Flow

### Complete Workflow Example

1. **User/Scheduler triggers**: `EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob.new(%{}) |> Oban.insert()`

2. **SyncJob executes**:
   - Fetches cinema list from API
   - Filters to Kraków (3 cinemas)
   - Schedules 3 × 7 = 21 CinemaDateJobs (for 7 days)

3. **CinemaDateJob executes** (for Bonarka on 2025-10-04):
   - Fetches film events from API
   - Finds 19 films, 48 events
   - Schedules 19 MovieDetailJobs (one per unique film)
   - Schedules 48 ShowtimeProcessJobs (one per showtime)

4. **MovieDetailJob executes** (for each film):
   - Matches Polish title to TMDB
   - Creates movie record (if ≥60% confidence)
   - Stores cinema_city_film_id in metadata
   - Returns `{:ok, %{status: :matched}}` or `{:error, reason}`

5. **ShowtimeProcessJob executes** (for each showtime):
   - Waits for MovieDetailJob to complete
   - Looks up movie from database
   - Enriches showtime with movie + cinema data
   - Transforms to unified event format
   - Processes through EventProcessor

### Error Handling

**MovieDetailJob Failures**:
- Low confidence (<50%): Returns `{:error, :tmdb_low_confidence}`
- Medium confidence (50-69%): Returns `{:error, :tmdb_needs_review}`
- No results: Returns `{:error, :tmdb_no_results}`
- Network errors: Returns `{:error, reason}` → Oban retries

**ShowtimeProcessJob Behavior**:
- Movie not found + MovieDetailJob discarded → `{:ok, :skipped}` (not an error)
- Movie not found + MovieDetailJob pending → `{:error, :movie_not_ready}` (retry)

### Rate Limiting Strategy

**API Call Timing**:
- Config.rate_limit() = 2 seconds
- CinemaDateJobs: Staggered by cinema index × 2s
- MovieDetailJobs: Staggered by film index × 2s
- ShowtimeProcessJobs: Wait for all movies + 2s between each

**Example Timeline** (Bonarka, 2025-10-04, 19 films, 48 showtimes):
- T+0s: CinemaDateJob starts
- T+1s: API call completes, schedules jobs
- T+0s: MovieDetailJob #1 scheduled
- T+2s: MovieDetailJob #2 scheduled
- ...
- T+36s: MovieDetailJob #19 scheduled
- T+68s: All MovieDetailJobs likely completed (36s + 30s buffer)
- T+68s: ShowtimeProcessJob #1 scheduled
- T+70s: ShowtimeProcessJob #2 scheduled
- ...
- T+162s: ShowtimeProcessJob #48 scheduled

## Integration Points

### Shared Components Used

1. **TmdbMatcher** (`EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher`):
   - Shared TMDB matching logic
   - Multi-strategy search with fallbacks
   - Confidence scoring (title, year, runtime, director, country)
   - Now Playing fallback for recent releases

2. **EventProcessor** (`EventasaurusDiscovery.Scraping.Processors.EventProcessor`):
   - Unified event processing pipeline
   - Handles venue creation/lookup
   - Manages event deduplication
   - Tracks last_seen_at timestamps

3. **Processor** (`EventasaurusDiscovery.Sources.Processor`):
   - `process_single_event/2` for event creation

4. **MovieStore** (`EventasaurusDiscovery.Movies.MovieStore`):
   - `find_or_create_by_tmdb_id/1`
   - `update_movie/2`
   - `create_movie/1`

### Pattern Consistency

Cinema City follows the exact same patterns as Kino Krakow:
- ✅ Distributed job architecture
- ✅ Oban queue usage (:discovery, :scraper_index, :scraper_detail, :scraper)
- ✅ Rate limiting through job scheduling
- ✅ TMDB matching with confidence levels
- ✅ External ID generation
- ✅ Metadata storage for lookups
- ✅ Unified event transformation

## Testing Readiness

**Phase 3 is ready for testing**. The job chain can be tested with:

```elixir
# Test full chain
alias EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob

# Schedule sync job
SyncJob.new(%{}) |> Oban.insert()

# Monitor in Oban dashboard
# http://localhost:4000/dev/oban
```

**Expected Results** (Kraków, 7 days):
- 3 cinemas × 7 days = 21 CinemaDateJobs
- ~19 films/cinema × 3 cinemas = ~57 unique films → ~57 MovieDetailJobs
- ~48 showtimes/cinema × 3 cinemas × 7 days = ~1,000 ShowtimeProcessJobs

## Next Steps (Phase 4-8)

Phase 3 completes the core scraping functionality. Remaining phases from the spec:

- **Phase 4**: Testing and validation (ready to implement)
- **Phase 5**: Error handling and logging (basic already implemented)
- **Phase 6**: Performance optimization (rate limiting already implemented)
- **Phase 7**: Documentation (this file + code comments)
- **Phase 8**: Deployment and monitoring (pending)

---

**Phase 3 Complete**: ✅ Ready for end-to-end testing with real Cinema City data
