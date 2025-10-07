# Event Source Scraper Specification

> **Version**: 1.0
> **Last Updated**: 2025-10-07
> **Purpose**: Unified specification for all event data sources (scrapers, APIs, feeds) in Eventasaurus

---

## Table of Contents

1. [Overview](#overview)
2. [Directory Structure](#directory-structure)
3. [Required Files](#required-files)
4. [Data Flow](#data-flow)
5. [Deduplication Strategy](#deduplication-strategy)
6. [GPS Coordinates & Geocoding](#gps-coordinates--geocoding)
7. [Job Patterns](#job-patterns)
8. [Transformer Standards](#transformer-standards)
9. [Configuration Standards](#configuration-standards)
10. [Error Handling](#error-handling)
11. [Testing Requirements](#testing-requirements)
12. [Daily Operation Requirements](#daily-operation-requirements)

---

## Overview

All event data sources must follow a unified architecture that:

- **Transforms** data into a standard format
- **Deduplicates** venues, events, and performers automatically
- **Handles GPS coordinates** via Google Places API when missing
- **Processes** data through shared processors (VenueProcessor, EventProcessor, PerformerStore)
- **Runs daily** without creating duplicates
- **Tracks** last_seen_at timestamps for data freshness

### Core Principles

1. **Single Responsibility**: Each module has one clear purpose
2. **Shared Processors**: Never duplicate venue/event/performer logic
3. **Idempotency**: Running daily should update, not duplicate
4. **GPS-First Matching**: Venues match by coordinates first, then name
5. **External ID Tracking**: Every entity has a stable external_id

---

## Directory Structure

### Standard Layout

```
lib/eventasaurus_discovery/sources/{source_name}/
├── source.ex                    # Source metadata & configuration
├── config.ex                    # Runtime configuration
├── client.ex                    # HTTP/API client (if applicable)
├── transformer.ex               # Data transformation to standard format
├── dedup_handler.ex            # Deduplication logic (recommended)
├── extractors/                 # HTML/data extraction modules
│   ├── event_extractor.ex
│   ├── venue_extractor.ex
│   └── ...
├── helpers/                    # Helper modules
│   ├── date_parser.ex
│   ├── area_mapper.ex
│   └── ...
├── jobs/                       # Oban job workers
│   ├── sync_job.ex            # Main orchestration job
│   ├── index_page_job.ex      # Index/listing page job (scrapers)
│   ├── event_detail_job.ex    # Detail page job
│   └── ...
└── README.md                   # Source-specific documentation
```

### Naming Conventions

- **Source directory**: `snake_case` matching source slug (e.g., `resident_advisor`, `cinema_city`)
- **Module names**: `PascalCase` with full source name (e.g., `EventasaurusDiscovery.Sources.ResidentAdvisor`)
- **Job queues**: Use `:scraper_index` for index jobs, `:scraper_detail` for detail jobs
- **External IDs**: Prefix with source slug (e.g., `"ra_event_123"`, `"tm_venue_456"`)

---

## Required Files

### 1. `source.ex` - Source Metadata

**Purpose**: Defines source configuration, priority, and job arguments

**Required Functions**:

```elixir
def name()           # Human-readable name
def key()            # Slug/identifier (lowercase, underscored)
def enabled?()       # Runtime enable/disable
def priority()       # Integer 0-100 (higher = more trusted)
def config()         # Full configuration map
def sync_job_args(options \\ %{})      # Arguments for sync job
def detail_job_args(id, metadata \\ %{})  # Arguments for detail job (if applicable)
def validate_config()  # Connectivity/config validation
```

**Priority Levels**:
- 90-100: Premium APIs (Ticketmaster)
- 70-89: Trusted international sources (Resident Advisor, Bandsintown)
- 50-69: Regional reliable sources
- 30-49: Local/niche sources (Karnet, PubQuiz)
- 0-29: Experimental/low-confidence sources

### 2. `config.ex` - Runtime Configuration

**Purpose**: Centralizes environment-specific settings

**Required Settings**:

```elixir
def base_url()         # Base URL for scraping/API
def rate_limit()       # Seconds between requests
def timeout()          # Request timeout (milliseconds)
def headers()          # Default HTTP headers (if applicable)
```

**Optional Settings**:
- `max_pages()` - Maximum pages to scrape per run
- `api_key()` - API authentication key
- `graphql_endpoint()` - GraphQL endpoint URL

### 3. `transformer.ex` - Data Transformation

**Purpose**: Converts source-specific data into unified format

**Required Functions**:

```elixir
@doc "Transform event to unified format"
def transform_event(raw_event, options \\ %{})
# Returns: {:ok, transformed_event} | {:error, reason}

@doc "Validate venue has required fields"
def validate_venue(venue_data)
# Returns: :ok | {:error, reason}
```

**Unified Event Format**:

```elixir
%{
  # Required fields
  external_id: "source_event_123",        # Stable identifier from source
  title: "Event Title",
  starts_at: ~U[2025-10-08 18:00:00Z],   # DateTime in UTC

  # Venue data (REQUIRED - even if GPS coordinates missing)
  venue_data: %{
    name: "Venue Name",
    address: "Street Address",
    city: "City Name",
    country: "Country Name",
    latitude: 50.0647,     # Float or nil (VenueProcessor geocodes if nil)
    longitude: 19.9450,    # Float or nil
    external_id: "source_venue_456",  # Optional but recommended
    metadata: %{}          # Source-specific data
  },

  # Optional but recommended
  ends_at: ~U[2025-10-08 22:00:00Z],     # DateTime or nil
  description: "Event description",
  source_url: "https://source.com/event/123",
  image_url: "https://cdn.source.com/image.jpg",

  # Pricing
  is_ticketed: true,
  is_free: false,
  min_price: 50.0,       # Decimal or nil
  max_price: 100.0,      # Decimal or nil
  currency: "PLN",

  # Performers (optional)
  performers: [
    %{
      "name" => "Artist Name",
      "external_id" => "source_artist_789",  # Optional
      "metadata" => %{}
    }
  ],

  # Metadata
  metadata: %{
    source_specific_field: "value",
    raw_data: %{}  # Optional: preserve original data
  },

  # Category (optional - will be extracted from raw_event_data)
  category: "concerts",

  # Translations (optional)
  title_translations: %{"pl" => "Tytuł", "en" => "Title"},
  description_translations: %{"pl" => "Opis", "en" => "Description"}
}
```

### 4. `jobs/sync_job.ex` - Main Sync Job

**Purpose**: Orchestrates the data sync process

**Must Implement**:

```elixir
use EventasaurusDiscovery.Sources.BaseJob,
  queue: :scraper_index,
  max_attempts: 3,
  priority: 1

@impl EventasaurusDiscovery.Sources.BaseJob
def fetch_events(city, limit, options)
# Returns: {:ok, raw_events} | {:error, reason}

@impl EventasaurusDiscovery.Sources.BaseJob
def transform_events(raw_events)
# Returns: list of transformed events

def source_config()
# Returns: source configuration map
```

**Job Flow**:
1. Fetch raw events from source
2. Transform to unified format
3. Pass to `Processor.process_source_data/2`
4. Processor handles venue/performer/event deduplication

### 5. `client.ex` - HTTP/API Client (if applicable)

**Purpose**: Handles HTTP requests with rate limiting, retries, error handling

**Required Functions**:

```elixir
def fetch_page(url, options \\ %{})
# Returns: {:ok, %{status_code: 200, body: html}} | {:error, reason}

def get(url, options \\ %{})
# For API sources: {:ok, parsed_json} | {:error, reason}
```

**Best Practices**:
- Respect rate limits defined in config
- Implement exponential backoff for retries
- Log all HTTP errors with context
- Clean UTF-8 in responses before parsing
- Use streaming for large responses

---

## Data Flow

```
Source (API/Scraper)
  ↓
Client (HTTP/GraphQL)
  ↓
Extractor (Parse HTML/JSON)
  ↓
Transformer (Unified format)
  ↓
DedupHandler (Optional validation)
  ↓
Processor.process_source_data/2
  ↓
VenueProcessor → find_or_create_venue
  ├→ GPS-based matching (50m/200m radius)
  ├→ Name similarity matching
  ├→ Google Places geocoding (if no GPS)
  └→ Deduplication by place_id
  ↓
PerformerStore → find_or_create_performer
  └→ Deduplication by name + source
  ↓
EventProcessor → process_event
  ├→ Deduplication by external_id
  ├→ Deduplication by title+date+venue
  ├→ Category extraction from raw data
  └→ Update last_seen_at timestamp
```

---

## Deduplication Strategy

### Freshness-Based Deduplication (CRITICAL - Required for All Sources)

**All scrapers MUST use `EventFreshnessChecker` to avoid re-processing recently updated events.**

The system maintains a 7-day (168 hours) freshness window tracked via `last_seen_at` timestamps. Events processed within this window should be skipped to prevent unnecessary work.

**When to Apply**: In index jobs or sync jobs, BEFORE scheduling detail jobs for individual events.

**Implementation** (in IndexPageJob or SyncJob):

```elixir
defp schedule_detail_jobs(events, source_id) do
  alias EventasaurusDiscovery.Services.EventFreshnessChecker

  # 1. Ensure events have external_id field (with source prefix)
  events_with_ids = Enum.map(events, fn event ->
    Map.put(event, :external_id, "#{source_slug}_#{extract_id(event)}")
  end)

  # 2. Filter to only stale events needing re-processing
  events_to_process = EventFreshnessChecker.filter_events_needing_processing(
    events_with_ids,
    source_id
  )

  # 3. Log efficiency metrics
  skipped = length(events) - length(events_to_process)
  threshold = EventFreshnessChecker.get_threshold()

  Logger.info("""
  📋 #{source_name}: Processing #{length(events_to_process)}/#{length(events)} events
  Skipped: #{skipped} (fresh within #{threshold}h)
  """)

  # 4. Schedule detail jobs ONLY for stale events
  Enum.each(events_to_process, fn event ->
    DetailJob.new(%{"event_data" => event, "source_id" => source_id})
    |> Oban.insert()
  end)
end
```

**Key Benefits**:
- ✅ Reduces API calls by 80-90% for recurring events (e.g., daily movie showtimes)
- ✅ Lowers database write load significantly
- ✅ Improves scraper run times
- ✅ Prevents rate limiting issues
- ✅ Automatically handles recurring events (movies, weekly trivia, etc.)

**Configuration**:
```elixir
# config/dev.exs, config/test.exs, config/runtime.exs
config :eventasaurus, :event_discovery,
  # Default threshold for all sources (7 days)
  freshness_threshold_hours: 168,

  # Source-specific overrides (by source slug)
  source_freshness_overrides: %{
    "kino-krakow" => 24,    # Daily scraping due to data quality issues
    "cinema-city" => 48      # Every 2 days (movie showtimes change frequently)
  }
```

**Source-Specific Thresholds**: Different sources may require different scraping frequencies based on:
- **Data Quality**: Sources with inconsistent data need more frequent validation (e.g., Kino Krakow daily)
- **Update Frequency**: Sources with rapidly changing content need shorter windows (e.g., Cinema City every 2 days)
- **Default Fallback**: Sources without specific overrides use the default 168-hour threshold

The `EventFreshnessChecker` automatically detects source-specific thresholds by looking up the source's slug in the configuration. No code changes needed in scrapers - just add the override to the config map.

**Timestamp Updates**: The `EventProcessor.mark_event_as_seen/2` and `Processor.process_single_event/2` functions automatically update `last_seen_at` when processing events, ensuring the freshness system works correctly.

**Reference Implementations**:
- ✅ Bandsintown: `lib/eventasaurus_discovery/sources/bandsintown/jobs/index_page_job.ex:213-228`
- ✅ Karnet: `lib/eventasaurus_discovery/sources/karnet/jobs/index_page_job.ex:153-177`
- ✅ Ticketmaster: `lib/eventasaurus_discovery/sources/ticketmaster/jobs/sync_job.ex:74-141`

**Related Issue**: See GitHub issue #1556 for audit findings and migration guide.

### Venue Deduplication

**VenueProcessor handles deduplication automatically**. Transformers should:

1. **Always provide venue_data** - Even if GPS coordinates are missing
2. **Include external_id** - For source-specific venue tracking
3. **Don't geocode manually** - VenueProcessor handles Google Places API

**Matching Priority**:

1. **place_id** - Google Places ID (highest priority)
2. **GPS coordinates** - 50m tight radius, 200m broad radius
3. **Name similarity** - Jaro distance + PostgreSQL trigram matching
4. **City context** - Always within same city

**Example**:

```elixir
# GOOD: Let VenueProcessor handle geocoding
venue_data: %{
  name: "Jazz Club Kraków",
  address: "ul. Floriańska 3",
  city: "Kraków",
  country: "Poland",
  latitude: nil,  # VenueProcessor will geocode
  longitude: nil
}

# BETTER: Provide GPS if available
venue_data: %{
  name: "Jazz Club Kraków",
  address: "ul. Floriańska 3",
  city: "Kraków",
  country: "Poland",
  latitude: 50.0647,
  longitude: 19.9450,
  external_id: "source_venue_123"  # Recommended
}
```

### Event Deduplication

**EventProcessor handles deduplication automatically** via:

1. **external_id** - Exact match (e.g., `"ra_event_123"`)
2. **Title + Date + Venue** - Fuzzy match for cross-source detection

**Daily Operation**:
- Events matched by external_id are **updated**, not duplicated
- `last_seen_at` timestamp is refreshed
- Allows events to disappear from source without deletion

**Example**:

```elixir
# Events with same external_id are updated
transform_event(%{
  "id" => "12345",
  "title" => "Concert Night"
}) do
  %{
    external_id: "source_event_12345",  # Must be stable across runs
    title: "Concert Night",
    starts_at: ~U[2025-10-08 19:00:00Z],
    # ...
  }
end
```

### Performer Deduplication

**PerformerStore handles deduplication** via:

1. **external_id** - Source-specific performer ID
2. **Name + Source** - Same performer name from same source

**Best Practice**:

```elixir
# Each source tracks its own performers
performers: [
  %{
    "name" => "The Beatles",
    "external_id" => "spotify_artist_123",  # Optional but recommended
    "source_id" => source.id
  }
]
```

---

## GPS Coordinates & Geocoding

### When to Geocode

**Never geocode manually in transformers**. VenueProcessor handles this automatically:

1. Check if venue exists by name/city
2. If new venue without GPS → Call Google Places API
3. If API fails → Job is **discarded** (prevents bad data)
4. Cache place_id for future runs

### Fallback Strategy

1. **Scraper provides GPS** → Use directly (best case)
2. **Scraper provides address** → VenueProcessor geocodes via Google Places
3. **No GPS or address** → Job fails with {:discard, reason}

### GPS Coordinate Format

```elixir
# Always use Float type
latitude: 50.0647    # NOT "50.0647" or 50
longitude: 19.9450

# nil is acceptable (VenueProcessor will geocode)
latitude: nil
longitude: nil
```

---

## Job Patterns

### Pattern 1: Simple API Source

**Example**: Ticketmaster, Resident Advisor

```elixir
jobs/
├── sync_job.ex           # Fetches events, transforms, processes
└── event_detail_job.ex   # Optional: enriches with additional data
```

**Sync Job Flow**:
1. Fetch events from API (paginated)
2. Transform each event
3. Pass batch to Processor

### Pattern 2: Multi-Stage Scraper

**Example**: Karnet, Bandsintown

```elixir
jobs/
├── sync_job.ex           # Orchestrates index + detail jobs
├── index_page_job.ex     # Scrapes event listing pages
└── event_detail_job.ex   # Scrapes individual event pages
```

**Flow**:
1. SyncJob enqueues IndexPageJob for each page
2. IndexPageJob enqueues EventDetailJob for each event
3. EventDetailJob transforms and processes event

### Pattern 3: Cinema Source

**Example**: Cinema City, Kino Krakow

```elixir
jobs/
├── sync_job.ex              # Orchestrates cinema + movie jobs
├── cinema_date_job.ex       # Fetches showtimes for date
├── movie_detail_job.ex      # Fetches movie details + TMDB matching
└── showtime_process_job.ex  # Creates events from showtimes
```

**Special Handling**:
- Links to `movies` table via `movie_id`
- One event per showtime (not per movie)
- Title format: "{Movie Title} at {Cinema Name}"

### Job Best Practices

1. **Use Oban.Worker** via BaseJob for consistency
2. **Log progress** with emoji for visibility (✅ success, ❌ error, 🔄 processing)
3. **Handle rate limits** in client, not jobs
4. **Batch processing** - Process 20-100 events per job
5. **Retry strategy** - 3 attempts with exponential backoff

---

## Transformer Standards

### Required Validations

Every transformer must validate:

1. **Event has title**
2. **Event has starts_at** (DateTime, not NaiveDateTime)
3. **Event has external_id** (stable across runs)
4. **Venue has name**
5. **Venue has city** (can infer country)

### Optional Validations

Recommended in `dedup_handler.ex`:

1. **Date sanity** - Not in past, not >2 years future
2. **Umbrella event detection** - Multi-day festivals as containers
3. **Duplicate checking** - Against higher-priority sources

### Date Handling

```elixir
# GOOD: DateTime in UTC
starts_at: ~U[2025-10-08 18:00:00Z]

# BAD: NaiveDateTime (missing timezone)
starts_at: ~N[2025-10-08 18:00:00]

# Use shared helper for timezone conversion
alias EventasaurusDiscovery.Scraping.Helpers.TimezoneConverter

TimezoneConverter.convert_local_to_utc(
  ~N[2025-10-08 20:00:00],
  "Europe/Warsaw"
)
```

### Price Handling

```elixir
# Free events
is_free: true,
min_price: nil,    # Must be nil when free
max_price: nil,
currency: "PLN"    # Still specify currency

# Paid events
is_free: false,
min_price: 50.0,   # Decimal
max_price: 150.0,
currency: "PLN"

# Unknown pricing
is_free: false,
min_price: nil,
max_price: nil,
currency: nil      # Or default to "PLN" for Poland
```

---

## Configuration Standards

### Source Configuration Map

```elixir
def config do
  %{
    # Connection settings
    base_url: Config.base_url(),
    rate_limit_ms: Config.rate_limit() * 1000,
    timeout: Config.timeout(),
    retry_attempts: 2,
    retry_delay_ms: 5_000,

    # API characteristics
    api_type: :rest | :graphql | :scraper,
    requires_auth: true | false,

    # Job configuration
    sync_job: SyncJob,
    detail_job: EventDetailJob,  # nil if not applicable

    # Queue settings
    sync_queue: :scraper_index,
    detail_queue: :scraper_detail,

    # Feature flags
    supports_api: true | false,
    supports_pagination: true | false,
    supports_date_filtering: true | false,
    supports_venue_details: true | false,
    supports_performer_details: true | false,
    supports_ticket_info: true | false,

    # Geocoding strategy
    requires_geocoding: true | false,
    geocoding_strategy: :google_places | :provided,

    # Data quality indicators
    has_coordinates: true | false,
    has_ticket_urls: true | false,
    has_performer_info: true | false,
    has_images: true | false,
    has_descriptions: true | false
  }
end
```

---

## Error Handling

### Critical vs Retryable Errors

**Critical (Discard Job)**:

```elixir
# Missing GPS coordinates (VenueProcessor geocoding failed)
{:discard, "GPS coordinate validation failed: ..."}

# Invalid configuration
{:discard, "API key not configured"}

# Source permanently unavailable
{:discard, "Source website shutdown"}
```

**Retryable (Retry Job)**:

```elixir
# Temporary network issues
{:error, :timeout}

# Rate limit hit
{:error, :rate_limited}

# Partial failures
{:error, {:partial_failure, failed_count, total_count}}
```

### Logging Standards

```elixir
# Success
Logger.info("✅ Successfully processed #{count} events")

# Warning
Logger.warning("⚠️ Partial failure: #{failed}/#{total} events failed")

# Error
Logger.error("❌ Failed to geocode venue: #{venue_name}")

# Critical
Logger.error("🚫 CRITICAL: Discarding job due to missing GPS coordinates")
```

---

## Testing Requirements

### Unit Tests

Every source must have tests for:

1. **Transformer**:
   - Valid event transformation
   - Invalid event rejection
   - Edge cases (missing fields, malformed data)

2. **Extractor** (if applicable):
   - HTML parsing accuracy
   - Handles missing elements

3. **Date Parser**:
   - Various date formats
   - Timezone conversion

### Integration Tests

1. **End-to-end flow** with fixture data
2. **Deduplication** behavior
3. **Error handling** (network failures, invalid data)

### Test Files Location

```
test/eventasaurus_discovery/sources/{source_name}/
├── transformer_test.exs
├── client_test.exs
├── jobs/
│   ├── sync_job_test.exs
│   └── event_detail_job_test.exs
└── fixtures/
    ├── api_response.json
    └── html_page.html
```

---

## Daily Operation Requirements

### Idempotency Checklist

✅ **Events are updated, not duplicated** when run daily
✅ **Venues are matched by GPS first, then name**
✅ **Performers are deduplicated within source**
✅ **External IDs are stable across runs**
✅ **last_seen_at timestamps are updated**

### Monitoring

Each source should log:

1. **Events processed** - Total count
2. **Events created** - New events
3. **Events updated** - Existing events refreshed
4. **Venues created** - New venues
5. **Failures** - Count and reasons

### Performance Targets

- **Sync frequency**: Daily (configurable per source)
- **Job timeout**: 10 minutes max per job
- **Rate limits**: Respect source-specific limits
- **Batch size**: 20-100 events per job

---

## Migration Checklist for Existing Scrapers

When updating an existing scraper to match this spec:

- [ ] Move to `lib/eventasaurus_discovery/sources/{source_name}/`
- [ ] Implement `source.ex` with all required functions
- [ ] Update `transformer.ex` to return unified format
- [ ] Use `BaseJob` for all Oban workers
- [ ] Remove manual geocoding (let VenueProcessor handle it)
- [ ] **Add `EventFreshnessChecker` filtering in index/sync jobs (CRITICAL)**
- [ ] **Verify `EventProcessor.process_event()` updates `last_seen_at` timestamp**
- [ ] Add `dedup_handler.ex` for complex sources
- [ ] Update external_id generation to be stable (with source prefix)
- [ ] Ensure jobs are idempotent (can run daily without duplicates)
- [ ] Add comprehensive logging with freshness metrics
- [ ] Write unit tests for transformer
- [ ] Update documentation (README.md)

---

## Example Implementation

See `lib/eventasaurus_discovery/sources/resident_advisor/` for a reference implementation that follows all specifications.

**Key Files**:
- `source.ex` - Configuration and metadata
- `client.ex` - GraphQL client with rate limiting
- `transformer.ex` - GraphQL response → unified format
- `dedup_handler.ex` - Validation and duplicate detection
- `jobs/sync_job.ex` - Orchestration
- `jobs/event_detail_job.ex` - Enrichment

---

## Version History

- **v1.0** (2025-10-07): Initial specification based on current architecture
