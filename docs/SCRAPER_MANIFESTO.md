# Event Scraper Manifesto

**Version:** 1.0
**Last Updated:** 2025-10-04
**Purpose:** Standardized requirements and patterns for all event data source integrations

---

## 🎯 Core Philosophy

Every scraper must produce **high-quality, geocoded events** that meet strict validation requirements. No exceptions.

> **Golden Rule:** If we can't provide a valid venue with coordinates, we don't save the event.

---

## 📋 Hard Requirements (Non-Negotiable)

### Required Event Fields

Every event **MUST** have:

1. **Venue Information** (CRITICAL - see Venue Requirements below)
2. **title** - Event name/title
3. **external_id** - Unique identifier from the source (prefixed with source slug)
4. **starts_at** - Event start date/time as `DateTime` in UTC
5. **source_url** - Original URL for reference

### Required Venue Fields

Every venue **MUST** have:

1. **name** - Venue name (cannot be empty)
2. **latitude** - GPS coordinate (float)
3. **longitude** - GPS coordinate (float)

**Validation:** The `validate_venue/1` function enforces these requirements. Events with invalid venues are **rejected and logged**.

### Optional But Recommended Fields

- **ends_at** - Event end date/time
- **description** - Event description/details
- **ticket_url** - Link to purchase tickets
- **min_price** / **max_price** - Price range as `Decimal`
- **currency** - Price currency code (ISO 4217)
- **image_url** - Event image/poster
- **performer** - Artist/performer information
  - `name` - Performer name
  - `genres` - List of genre tags
  - `image_url` - Performer image
- **tags** - List of event tags/categories
- **category** - Primary event category
- **is_free** - Boolean for free events

---

## 🔁 Recurring Event Patterns (Optional)

For events with **predictable recurring schedules** (weekly trivia nights, monthly meetups, daily showtimes), scrapers should implement the `recurrence_rule` pattern.

**Benefits:**
- One database record represents hundreds of future occurrences
- Frontend generates next 4+ upcoming dates dynamically
- Better UX (no stale past dates, always shows future events)
- Improved storage efficiency and data freshness

**When to Use:**
- ✅ Weekly or monthly recurring events (predictable pattern)
- ✅ Schedule clearly indicates recurrence (e.g., "Every Tuesday at 7 PM")
- ✅ Timezone is known or reliably inferable
- ❌ One-time events or irregular schedules

**Implementation:**

Add `recurrence_rule` field to event map:

```elixir
%{
  title: "Weekly Trivia Night - The Local Pub",
  starts_at: next_occurrence,  # Calculate next upcoming date

  # Recurring pattern (optional field)
  recurrence_rule: %{
    "frequency" => "weekly",           # "weekly" | "monthly"
    "days_of_week" => ["monday"],      # Day names
    "time" => "19:00",                 # HH:MM format
    "timezone" => "Europe/London"      # IANA timezone
  }
}
```

**Reference Implementation:** PubQuiz scraper (`lib/eventasaurus_discovery/sources/pubquiz/`)

**Full Documentation:** See [RECURRING_EVENT_PATTERNS.md](./RECURRING_EVENT_PATTERNS.md) for complete specification, implementation patterns, timezone handling, edge cases, and examples.

**Current Use Cases:**
- Trivia events (PubQuiz ✅, Question One 🚧, Geeks Who Drink 🚧)
- Future: Movie showtimes, music series, community events

---

## 🏗️ Architecture Pattern

### Module Structure

Every source follows this standardized structure:

```
lib/eventasaurus_discovery/sources/{source_name}/
├── config.ex              # SourceConfig implementation
├── source.ex              # Source metadata and helpers
├── client.ex              # API/HTTP client (if applicable)
├── transformer.ex         # Raw data → Unified format
├── dedup_handler.ex       # Deduplication logic (optional)
├── jobs/
│   ├── sync_job.ex        # Main orchestration job
│   ├── index_page_job.ex  # Pagination handler
│   └── event_detail_job.ex # Individual event enrichment
└── helpers/               # Source-specific utilities
    ├── date_parser.ex
    ├── venue_matcher.ex
    └── ...
```

### Job Pipeline

**Async 3-Stage Pipeline:**

```
SyncJob
  ↓ schedules
IndexPageJob (per page)
  ↓ schedules
EventDetailJob (per event)
  ↓ processes
Transformer → Validator → Processor → Database
```

**Flow Details:**

1. **SyncJob** - Entry point
   - Determines pagination requirements
   - Schedules IndexPageJobs with rate limiting
   - Returns immediately (async)

2. **IndexPageJob** - Per-page processing
   - Fetches event list from one page
   - Extracts event IDs/URLs
   - Schedules EventDetailJobs for each event
   - Respects rate limits (staggered scheduling)

3. **EventDetailJob** - Per-event enrichment
   - Fetches full event details
   - Transforms to unified format
   - Validates venue requirements
   - Processes through Processor

### Configuration (SourceConfig)

Every source implements `EventasaurusDiscovery.Sources.SourceConfig`:

```elixir
@impl EventasaurusDiscovery.Sources.SourceConfig
def source_config do
  EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
    name: "Source Name",
    slug: "source_slug",
    priority: 80,           # 0-100, higher = higher priority
    rate_limit: 2,          # Requests per second
    timeout: 15_000,        # Request timeout (ms)
    max_retries: 3,
    queue: :discovery,
    base_url: "https://...",
    api_key: nil,           # If required
    api_secret: nil
  })
end
```

**Priority System:**
- **90-100:** Premium sources (Ticketmaster)
- **70-89:** Major sources (Bandsintown, Resident Advisor)
- **50-69:** Regional sources (Karnet, Kino Krakow)
- **0-49:** Experimental/low-priority sources

### Transformer Pattern

Every transformer implements:

```elixir
def transform_event(raw_event, context \\ nil) do
  # Extract venue first
  venue_data = extract_venue(raw_event, context)

  # Validate venue (CRITICAL)
  case validate_venue(venue_data) do
    :ok ->
      transformed = %{
        # Required fields
        title: extract_title(raw_event),
        external_id: extract_external_id(raw_event),
        starts_at: extract_starts_at(raw_event),
        venue_data: venue_data,

        # Optional fields
        ends_at: extract_ends_at(raw_event),
        description: extract_description(raw_event),
        # ... more fields
      }

      {:ok, transformed}

    {:error, reason} ->
      Logger.error("Event rejected: #{reason}")
      {:error, reason}
  end
end

def validate_venue(venue_data) do
  cond do
    is_nil(venue_data) ->
      {:error, "Venue data is required"}
    is_nil(venue_data[:name]) || venue_data[:name] == "" ->
      {:error, "Venue name is required"}
    is_nil(venue_data[:latitude]) ->
      {:error, "Venue latitude is required"}
    is_nil(venue_data[:longitude]) ->
      {:error, "Venue longitude is required"}
    true ->
      :ok
  end
end
```

---

## 🗺️ Geocoding Strategy

### Priority Order

1. **Use Source Data** - If source provides coordinates, use them directly
2. **Google Places API** - Geocode venue name + city + country
3. **City Center Fallback** - Use city coordinates with `needs_geocoding: true` flag
4. **Hard-Coded Coordinates** - For common cities (last resort)

### Implementation

```elixir
defp extract_venue(event, city_context) do
  cond do
    # Has coordinates from source
    has_coordinates?(event) ->
      %{
        name: event.venue_name,
        latitude: event.latitude,
        longitude: event.longitude,
        # ... other fields
      }

    # Has venue name - geocode it
    event.venue_name && city_context ->
      %{
        name: event.venue_name,
        latitude: city_context.latitude,
        longitude: city_context.longitude,
        needs_geocoding: true,
        # ... other fields
      }

    # No venue data - reject or create placeholder
    true ->
      Logger.warning("Missing venue data")
      %{
        name: "Venue TBD",
        latitude: default_city_lat,
        longitude: default_city_lng,
        metadata: %{placeholder: true},
        needs_geocoding: false
      }
  end
end
```

### Google Places Integration

For venues needing geocoding:

```elixir
# In EventDetailJob or post-processing
if venue_data[:needs_geocoding] do
  case GooglePlacesClient.geocode(venue_data[:name], city, country) do
    {:ok, coordinates} ->
      # Update venue with real coordinates

    {:error, _reason} ->
      # Keep city center, log for manual review
  end
end
```

---

## 🔄 Data Source Types

### Type 1: API-Based Sources

**Examples:** Bandsintown (GraphQL-like API), Resident Advisor (GraphQL)

**Characteristics:**
- Structured JSON responses
- Built-in pagination
- Usually rate-limited
- May require API keys

**Client Pattern:**

```elixir
defmodule Source.Client do
  def fetch_events(params) do
    url = build_url(params)

    case HTTPoison.get(url, headers(), opts()) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}
      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp headers do
    [
      {"User-Agent", @user_agent},
      {"Accept", "application/json"}
    ]
  end
end
```

### Type 2: HTML Scraping Sources

**Examples:** Karnet, Kino Krakow

**Characteristics:**
- HTML parsing required
- Fragile (breaks when HTML changes)
- Often requires detail page scraping
- May need anti-bot measures

**Client Pattern:**

```elixir
defmodule Source.Client do
  @behaviour EventasaurusDiscovery.Scraping.Behaviors.WebScraper

  def fetch(url, options) do
    case HTTPoison.get(url, headers(), opts()) do
      {:ok, %{status_code: 200, body: html}} ->
        {:ok, %{body: html, url: url}}
      error ->
        error
    end
  end

  def extract_data(html, selectors) do
    doc = Floki.parse_document!(html)

    data = %{
      title: Floki.find(doc, selectors.title) |> Floki.text(),
      date: Floki.find(doc, selectors.date) |> Floki.text(),
      # ... more extractions
    }

    {:ok, data}
  end
end
```

### Type 3: Hybrid Sources

**Example:** Bandsintown (API index + optional detail scraping)

**Characteristics:**
- API provides event list
- Detail pages provide additional data
- Best of both worlds

---

## ⚡ Rate Limiting & Performance

### Rate Limit Strategy

**Per-Source Configuration:**

```elixir
# In config.ex
@rate_limit 2  # requests per second

# In job scheduling
delay_seconds = div(page_num - 1, @rate_limit) * @rate_limit
scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)
```

**Best Practices:**
- Honor source's rate limits (check robots.txt, terms of service)
- Use exponential backoff on errors
- Stagger jobs to avoid thundering herd
- Monitor for 429 (Too Many Requests) responses

### Concurrency Control

**Oban Queue Configuration:**

```elixir
# config/config.exs
config :eventasaurus_app, Oban,
  queues: [
    discovery: 3,          # Main sync jobs
    scraper_index: 10,     # Index page jobs (can be parallel)
    scraper_detail: 20     # Detail jobs (highest concurrency)
  ]
```

### Caching

- Cache venue geocoding results (same venue name + city)
- Cache common city coordinates
- Consider caching API responses for development/testing

---

## 🧪 Testing Requirements

### Test Coverage

Every source must have:

1. **Unit Tests** - Transformer, validators, helpers
2. **Integration Tests** - Client API calls (with VCR cassettes)
3. **Job Tests** - Async job processing
4. **Mix Tasks** - Development testing commands

### Mix Tasks

Provide testing tasks for development:

```elixir
# lib/mix/tasks/source_name.test.ex
defmodule Mix.Tasks.SourceName.Test do
  use Mix.Task

  def run([city_id]) do
    Mix.Task.run("app.start")

    # Test the scraper
    {:ok, city} = Repo.get(City, city_id)
    {:ok, _job} = SourceName.sync(%{city_id: city.id, limit: 10})

    IO.puts("✅ Sync job scheduled")
  end
end
```

---

## 🔍 Deduplication

### Freshness-Based Deduplication (REQUIRED)

**All scrapers MUST use `EventFreshnessChecker` to avoid re-scraping recently updated events.**

The system uses a 7-day (168 hours) freshness window. Events that were `last_seen_at` within this window should NOT be re-scraped.

**Implementation Pattern** (in IndexPageJob or SyncJob):

```elixir
defp schedule_detail_jobs(events, source_id, page_number) do
  alias EventasaurusDiscovery.Services.EventFreshnessChecker

  # Get source to access slug
  source = Repo.get!(Source, source_id)

  # 1. Add external_ids to events (with source prefix)
  events_with_ids = Enum.map(events, fn event ->
    Map.put(event, :external_id, "#{source.slug}_#{event.id}")
  end)

  # 2. Filter to events needing processing based on freshness
  events_to_process = EventFreshnessChecker.filter_events_needing_processing(
    events_with_ids,
    source_id
  )

  # 3. Log metrics
  skipped = length(events) - length(events_to_process)
  threshold = EventFreshnessChecker.get_threshold()

  Logger.info(
    "📋 Processing #{length(events_to_process)}/#{length(events)} events " <>
    "(#{skipped} skipped, threshold: #{threshold}h)"
  )

  # 4. Schedule only stale events
  Enum.each(events_to_process, fn event ->
    # Schedule detail job
  end)
end
```

**Freshness Checking:**
- ✅ Configured globally via `config :eventasaurus, :event_discovery, freshness_threshold_hours: 168`
- ✅ Prevents unnecessary API calls and database writes
- ✅ Automatically handles recurring events (e.g., daily movie showtimes)
- ✅ Updates `last_seen_at` timestamp via `EventProcessor.mark_event_as_seen()` and `Processor.process_single_event()`

**Reference Implementations:**
- `lib/eventasaurus_discovery/sources/bandsintown/jobs/index_page_job.ex:213-228`
- `lib/eventasaurus_discovery/sources/karnet/jobs/index_page_job.ex:153-177`
- `lib/eventasaurus_discovery/sources/ticketmaster/jobs/sync_job.ex:74-141`

### Priority-Based Deduplication

Lower-priority sources check against higher-priority sources:

```elixir
defmodule Source.DedupHandler do
  def check_duplicate(event_data) do
    # Check if event exists from higher-priority source
    case find_existing_event(event_data) do
      nil ->
        {:unique, event_data}

      %{source: %{priority: higher_priority}} when higher_priority > @our_priority ->
        {:duplicate, "Event exists from higher-priority source"}

      existing ->
        # Same or lower priority - enrich if needed
        {:enriched, merge_data(existing, event_data)}
    end
  end

  defp find_existing_event(event_data) do
    # Match by:
    # 1. Same venue + same date (within 2 hours)
    # 2. Same title + same city + same date
    # 3. External ID match across sources
  end
end
```

### Matching Criteria

**Primary Match:**
- Venue name similarity (>80%)
- Date/time within 2-hour window
- Title similarity (>70%)

**Secondary Match:**
- Same city + same date + similar title
- External ID cross-reference (if sources link to each other)

---

## 📊 Monitoring & Logging

### Logging Standards

**Structured Logging:**

```elixir
Logger.info("""
🎵 Starting #{@source_name} sync
City: #{city.name}, #{city.country.name}
Limit: #{limit} events
Pages: #{max_pages}
""")

Logger.error("""
❌ Event rejected: #{reason}
Event: #{event.title}
URL: #{event.url}
Venue: #{inspect(venue_data)}
""")
```

**Log Levels:**
- `:info` - Normal operations, successful syncs
- `:warning` - Missing data, fallbacks used, geocoding failures
- `:error` - Validation failures, API errors, job failures

### Metrics to Track

- Events fetched per sync
- Events saved vs rejected
- Geocoding hit rate
- API response times
- Job success/failure rates
- Duplicate detection rate

---

## 🚨 Error Handling

### Graceful Degradation

**Prioritize partial success over total failure:**

```elixir
# Bad: Fail entire sync if one event is invalid
Enum.map(events, &process_event!/1)

# Good: Process what we can, log what we can't
events
|> Enum.map(&transform_event/1)
|> Enum.filter(fn
  {:ok, _event} -> true
  {:error, reason} ->
    Logger.warning("Skipped event: #{reason}")
    false
end)
|> Enum.map(fn {:ok, event} -> event end)
```

### Retry Strategy

**Exponential Backoff:**

```elixir
# In Oban job
use Oban.Worker,
  queue: :discovery,
  max_attempts: 3,
  # Retry after 1m, 5m, 15m
  backoff: {60, :linear}
```

**When to Retry:**
- Network errors (timeout, connection refused)
- HTTP 5xx errors
- Rate limit errors (429)

**When NOT to Retry:**
- HTTP 404 (not found)
- Validation errors (bad data)
- Authentication errors (401, 403)

---

## 🛠️ Development Workflow

### Adding a New Source

1. **Research**
   - Identify data source type (API, HTML, hybrid)
   - Check for existing scrapers/libraries
   - Document available data fields
   - Test API/HTML structure
   - Check rate limits and terms of service

2. **Implementation**
   - Create module structure
   - Implement `Config` module
   - Implement `Client` module
   - Implement `Transformer` with venue validation
   - Implement job pipeline (Sync → Index → Detail)
   - Add deduplication if lower priority

3. **Testing**
   - Write unit tests for transformer
   - Create Mix task for manual testing
   - Test with real data (small sample)
   - Verify venue validation works
   - Check geocoding fallbacks

4. **Integration**
   - Add to source registry
   - Configure Oban queues
   - Set up monitoring/logging
   - Document in README
   - Create usage examples

### Quality Checklist

Before merging a new scraper:

- [ ] Implements `SourceConfig` behaviour
- [ ] Validates venue with `validate_venue/1`
- [ ] Rejects events without valid venue
- [ ] **Uses `EventFreshnessChecker` to filter events before scheduling detail jobs**
- [ ] **Updates `last_seen_at` timestamp via `EventProcessor.process_event()`**
- [ ] Logs detailed errors for debugging
- [ ] Respects rate limits
- [ ] Has async job pipeline (Sync → Index → Detail)
- [ ] Handles pagination correctly
- [ ] Transforms dates to UTC DateTime
- [ ] Generates unique external_id (with source prefix)
- [ ] Includes source_url for reference
- [ ] Has Mix task for testing
- [ ] Has unit tests for transformer
- [ ] Has integration tests for client
- [ ] Handles errors gracefully
- [ ] Uses geocoding fallbacks
- [ ] Documents data structure

---

## 📚 Reference Implementations

### Best Practices by Source

**Bandsintown** - API-based, async pipeline
- ✅ Clean API integration
- ✅ Async 3-stage pipeline
- ✅ Excellent geocoding fallbacks
- ✅ Comprehensive validation

**Karnet** - HTML scraping, Polish language
- ✅ HTML parsing with Floki
- ✅ Multi-language support
- ✅ Festival handling
- ✅ Venue geocoding

**Resident Advisor** (Planned) - GraphQL API
- 🔄 GraphQL integration pattern
- 🔄 Venue detail enrichment
- 🔄 International events
- 🔄 Genre/tag extraction

---

## 🔗 Related Documentation

- [Source Processor](../lib/eventasaurus_discovery/sources/processor.ex) - Unified event processing
- [WebScraper Behavior](../lib/eventasaurus_discovery/scraping/behaviors/web_scraper.ex) - HTML scraping contract
- [SourceConfig Behavior](../lib/eventasaurus_discovery/sources/source_config.ex) - Configuration contract
- [BaseJob](../lib/eventasaurus_discovery/sources/base_job.ex) - Common job functionality

---

## 🎓 Key Takeaways

1. **Venue coordinates are non-negotiable** - Without them, we don't save the event
2. **Async pipeline is standard** - SyncJob → IndexPageJob → EventDetailJob
3. **Validation happens in Transformer** - Fail fast with detailed errors
4. **Geocoding is critical** - Have multiple fallback strategies
5. **Rate limiting is mandatory** - Respect source limits and terms
6. **Deduplication by priority** - Lower priority sources check higher ones
7. **Graceful degradation** - Save what we can, log what we can't
8. **Testing is required** - Unit tests + Mix tasks for development

---

**Questions?** Review existing implementations in `lib/eventasaurus_discovery/sources/`
