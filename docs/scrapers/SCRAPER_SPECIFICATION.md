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

### Pattern-Based Scraper External IDs

For scrapers that track **recurring events** (weekly trivia, daily movie showtimes), external_id generation follows a **venue-based pattern** rather than including temporal metadata.

#### Core Principle

> **For pattern-based recurring events, the venue IS the unique identifier.**

- **Venue location** = Identity (describes WHICH event it is)
- **Day of week, time, scheduling** = Metadata (describes WHEN event happens)

This approach enables:
- ✅ EventFreshnessChecker to skip recently-updated venues (80-90% reduction in API calls)
- ✅ Recurring event consolidation via EventProcessor
- ✅ Stable external_ids across scraper runs

#### Pattern-Based vs Explicit-Date Scrapers

**Pattern-Based Scrapers** (use venue-based external_id):
- **Examples**: Question One, PubQuiz, Inquizition, Geeks Who Drink, Speed Quizzing
- **Characteristics**: Weekly/recurring events at fixed venues
- **External ID Format**: `{source}_{venue_identifier}`
  - Question One: `question_one_royal_oak_twickenham`
  - PubQuiz: `pubquiz-pl_warszawa_centrum`
  - Inquizition: `inquizition_12345`
  - Geeks Who Drink: `geeks_who_drink_12345`
  - Speed Quizzing: `speed-quizzing-12345`

**Explicit-Date Scrapers** (use event-based external_id):
- **Examples**: Ticketmaster, Bandsintown, Resident Advisor, Karnet
- **Characteristics**: One-time events with specific dates
- **External ID Format**: `{source}_event_{event_id}`
  - Ticketmaster: `tm_event_G5vZZ9RVZV8V3`
  - Bandsintown: `bandsintown_event_103844808`

#### Implementation Pattern

For pattern-based scrapers, generate external_id from venue identifier:

```elixir
# Transformer - Generate stable external_id from venue
def transform_event(venue_data, _options \\ %{}) do
  # Use venue identifier (not day_of_week!)
  venue_slug = slugify(venue_data.name)
  external_id = "question_one_#{venue_slug}"

  %{
    external_id: external_id,
    title: "Quiz Night at #{venue_data.name}",
    starts_at: next_occurrence,
    recurrence_rule: %{
      "frequency" => "weekly",
      "days_of_week" => ["monday"],  # Metadata, not in external_id
      "time" => "19:00",
      "timezone" => "Europe/London"
    }
  }
end
```

**Two-Stage Architecture** (IndexJob + DetailJob):

```elixir
# IndexJob - Generate external_id for freshness filtering
defp schedule_detail_jobs(venues, source_id) do
  # Generate external_ids for venues
  venues_with_ids = Enum.map(venues, fn venue ->
    venue_slug = extract_venue_slug(venue.url)
    Map.put(venue, :external_id, "question_one_#{venue_slug}")
  end)

  # EventFreshnessChecker filters out fresh venues
  venues_to_process = EventFreshnessChecker.filter_events_needing_processing(
    venues_with_ids,
    source_id
  )

  # Schedule detail jobs ONLY for stale venues
  Enum.each(venues_to_process, fn venue ->
    VenueDetailJob.new(%{
      "venue_url" => venue.url,
      "source_id" => source_id
    })
    |> Oban.insert()
  end)
end
```

#### Edge Case Handling

**Q: What if a venue has multiple different events?**

A: EventProcessor's title-based matching handles this automatically via three-layer matching:

1. **Direct external_id match**: Skip if seen within threshold
2. **Existing event_id match**: Skip if belongs to recently-updated recurring event
3. **Predicted event_id match**: Uses title+venue similarity for new events

**Example**:
- Regular quiz: external_id = `geeks_who_drink_bar_xyz`, title = "General Trivia Night"
- Special event: external_id = `geeks_who_drink_bar_xyz`, title = "Halloween Special Trivia"
- **Result**: Different titles → EventFreshnessChecker's prediction layer groups them separately → both processed ✅

**Q: What if titles are very similar?**

A: Intentional consolidation for recurring event detection:
- "Monday Night Trivia" and "Monday Trivia Night"
- Jaro distance > 0.85 → merged as recurring event ✅
- This is desired behavior for pattern-based scrapers

#### Reference Implementations

**Best Practices**:
- ✅ Question One: `lib/eventasaurus_discovery/sources/question_one/README.md` (External ID Pattern section)
- ✅ PubQuiz: `lib/eventasaurus_discovery/sources/pubquiz/README.md` (External ID Pattern section)
- ✅ Speed Quizzing: `lib/eventasaurus_discovery/sources/speed_quizzing/README.md` (External ID Pattern section)
- ✅ Inquizition: `lib/eventasaurus_discovery/sources/inquizition/README.md` (External ID Pattern section)
- ✅ Geeks Who Drink: `lib/eventasaurus_discovery/sources/geeks_who_drink/README.md` (External ID Pattern section)

**EventFreshnessChecker Integration**:
- Three-layer matching system: `lib/eventasaurus_discovery/services/event_freshness_checker.ex`
- Recurring event consolidation: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:1132-1391`

**Related Issues**:
- GitHub Issue #1944 - Pattern-based scraper external_id standardization

---

## GPS Coordinates & Geocoding

### Multi-Provider Geocoding System

Eventasaurus uses a **sophisticated multi-provider geocoding orchestrator** that automatically handles address geocoding with intelligent fallback across 8 providers. **You do not need to geocode manually** - the system handles this automatically.

**Key Points**:
- ✅ 6 free providers (Mapbox, HERE, Geoapify, LocationIQ, OpenStreetMap, Photon)
- ✅ 2 paid providers disabled by default (Google Maps, Google Places)
- ✅ Automatic failover when providers are rate-limited or unavailable
- ✅ Built-in rate limiting to respect provider quotas
- ✅ Comprehensive metadata tracking for debugging

**See [Geocoding System Documentation](../geocoding/GEOCODING_SYSTEM.md) for complete details.**

### When to Geocode

**Never geocode manually in transformers**. VenueProcessor handles this automatically:

1. Check if venue exists by name/city
2. If new venue without GPS → Call multi-provider geocoding orchestrator
3. Orchestrator tries providers in priority order (free providers first)
4. If all providers fail → Job is **discarded** (prevents bad data)
5. Cache coordinates and metadata for future runs

### Fallback Strategy

1. **Scraper provides GPS** → Use directly (best case)
2. **Scraper provides address** → VenueProcessor geocodes via multi-provider system
3. **No GPS or address** → Job fails with {:discard, reason}

**Geocoding Flow**:
```
Address String
  ↓
VenueProcessor.geocode_venue_address/2
  ↓
AddressGeocoder.geocode_address_with_metadata/1
  ↓
Orchestrator.geocode/1 (tries providers: Mapbox → HERE → Geoapify → LocationIQ → OSM → Photon)
  ↓
{:ok, coordinates + metadata} OR {:error, :all_failed, metadata}
```

### GPS Coordinate Format

```elixir
# Always use Float type
latitude: 50.0647    # NOT "50.0647" or 50
longitude: 19.9450

# nil is acceptable (VenueProcessor will geocode via multi-provider system)
latitude: nil
longitude: nil
```

### Geocoding Best Practices for Scrapers

1. **Provide full addresses** - Include street, city, country for best geocoding results
2. **Include GPS if available** - Bypass geocoding entirely when coordinates are provided
3. **Don't implement custom geocoding** - Use the multi-provider system
4. **Check geocoding metadata** - Available in venue records for debugging
5. **Monitor geocoding costs** - Use admin dashboard at `/admin/geocoding`

For implementation examples and troubleshooting, see [Geocoding System Documentation](../geocoding/GEOCODING_SYSTEM.md).

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

## Category Mapping System

### Overview

Eventasaurus uses a **unified category taxonomy** with **YAML-based mappings** to normalize source-specific categories across all scrapers. This system ensures consistent categorization regardless of how different sources label their events.

### Why Use YAML Category Mappings?

- ✅ **Consistent taxonomy** across all sources (concerts, theatre, arts, etc.)
- ✅ **Easy maintenance** - Update mappings without code changes
- ✅ **Multi-language support** - Handle Polish, French, English categories
- ✅ **Pattern matching** - Flexible regex-based fallback rules
- ✅ **Source-specific customization** - Each scraper can have unique mappings

### Internal Category Taxonomy

Our standardized categories (stored in `categories` table):

| Slug | Description | Examples |
|------|-------------|----------|
| `concerts` | Music events, live performances | Concerts, festivals, music shows |
| `theatre` | Theater, plays, performance art | Drama, musicals, stage shows |
| `arts` | Visual arts, exhibitions | Galleries, museums, art shows |
| `film` | Cinema, film screenings | Movies, film festivals |
| `comedy` | Stand-up, comedy shows | Comedy nights, improv |
| `sports` | Sports events, competitions | Games, matches, races |
| `food-drink` | Food events, tastings | Wine tastings, food festivals |
| `nightlife` | Clubs, DJ events, parties | Club nights, raves |
| `family` | Family-friendly events | Kids activities, family shows |
| `community` | Community events, meetups | Local gatherings, meetups |
| `education` | Workshops, classes, seminars | Educational events |
| `business` | Conferences, networking | Business events, expos |
| `trivia` | Trivia nights, quiz events | Pub quiz, trivia competitions |
| `festivals` | Multi-day festival events | Music festivals, art festivals |
| `other` | Uncategorized (fallback) | Events without clear category |

### YAML Mapping Files

#### File Location

`priv/category_mappings/{source-slug}.yml`

**Examples**:
- `priv/category_mappings/karnet.yml` - Polish categories
- `priv/category_mappings/sortiraparis.yml` - French categories
- `priv/category_mappings/ticketmaster.yml` - Ticketmaster API categories
- `priv/category_mappings/_defaults.yml` - Universal fallback mappings

#### File Structure

```yaml
# {source-slug}.yml - Category mappings for {Source Name}
# Maps source-specific category names/codes to internal category slugs

mappings:
  # Direct string-to-category mappings
  # Format: source_category: internal_category_slug

  koncerty: concerts        # Polish "concerts" → internal "concerts"
  festiwale: festivals      # Polish "festivals" → internal "festivals"
  teatr: theatre           # Polish "theater" → internal "theatre"
  wystawa: arts            # Polish "exhibition" → internal "arts"
  kino: film              # Polish "cinema" → internal "film"

  # Multi-language support
  concert: concerts
  concert-music: concerts
  music-festival: concerts

  # URL segment mappings (for scrapers that use URL paths)
  concerts-music-festival: concerts
  exhibit-museum: arts
  theater: theatre

# Pattern-based mappings (optional)
# Use regex patterns for flexible matching when direct mappings aren't sufficient
patterns:
  # Music genres → concerts
  - match: "jazz|blues|rock|pop|electronic"
    categories: [concerts]

  # Art-related keywords → arts
  - match: "gallery|exhibition|museum|art"
    categories: [arts]

  # Theater variations → theatre
  - match: "theater|theatre|play|drama"
    categories: [theatre]

  # Multi-category events (festival can be concerts + festivals)
  - match: "festival.*music|music.*festival"
    categories: [concerts, festivals]

  # Family events (can have multiple categories)
  - match: "child|kid|family|dziec"
    categories: [family, community]
```

#### Default Fallback Mappings

The `_defaults.yml` file provides common English mappings used when source-specific mappings don't match:

```yaml
# _defaults.yml - Universal fallback mappings

mappings:
  concert: concerts
  music: concerts
  theatre: theatre
  theater: theatre
  exhibition: arts
  museum: arts
  film: film
  movie: film
  comedy: comedy
  sports: sports
  # ... more common English terms

patterns:
  - match: "concert|musik|music"
    categories: [concerts]
  - match: "theater|theatre|play"
    categories: [theatre]
  # ... universal patterns
```

### Integration Pattern

#### Step 1: Create YAML Mapping File

Create `priv/category_mappings/{your-source}.yml` with mappings specific to your source.

#### Step 2: Pass Category Data in Transformer

Your transformer should extract category information from the source data and pass it in the unified format:

```elixir
# lib/eventasaurus_discovery/sources/{your_source}/transformer.ex

def transform_event(raw_event) do
  %{
    # ... other fields ...

    # Pass category data for CategoryExtractor
    category: extract_category_from_source(raw_event),

    # Include raw event data so CategoryExtractor can access all fields
    raw_event_data: raw_event,

    # ... rest of fields ...
  }
end

# Extract category from source-specific location
defp extract_category_from_source(raw_event) do
  cond do
    # Strategy 1: Direct category field
    category = raw_event[:category] || raw_event["category"] ->
      String.downcase(category)

    # Strategy 2: Extract from URL path
    url = raw_event[:url] || raw_event["url"] ->
      extract_category_from_url(url)

    # Strategy 3: Tags or genre fields
    tags = raw_event[:tags] || raw_event["tags"] ->
      List.first(tags)

    true ->
      nil
  end
end
```

#### Step 3: Add CategoryExtractor Case

Update `lib/eventasaurus_discovery/categories/category_extractor.ex` to handle your source:

```elixir
def assign_categories_to_event(event_id, source, external_data) do
  categories =
    case source do
      # ... existing sources ...

      # ADD YOUR SOURCE
      "your-source" ->
        extract_your_source_categories(external_data)

      # Fallback for sources without specific handling
      _ ->
        classifications = extract_generic_categories(external_data)
        map_to_categories(source, classifications)
    end

  # ... rest of function assigns categories to event
end

# Add extraction function for your source
def extract_your_source_categories(event_data) when is_map(event_data) do
  category_values = []

  # Extract from category field
  category_values =
    if category = event_data[:category] || event_data["category"] do
      [{"your-source", nil, String.downcase(category)} | category_values]
    else
      category_values
    end

  # Extract from URL or other fields
  category_values =
    if url = event_data[:url] || event_data["url"] do
      extracted = extract_category_from_your_source_url(url)

      if extracted do
        [{"your-source", nil, extracted} | category_values]
      else
        category_values
      end
    else
      category_values
    end

  # Add secondary categories from title/description (optional)
  category_values = extract_your_source_secondary_categories(event_data, category_values)

  # Map to internal categories using YAML
  # CategoryMapper automatically loads your YAML file and applies mappings
  map_to_categories("your-source", category_values)
end
```

#### How CategoryMapper Works

The `CategoryMapper` module automatically:

1. **Loads YAML files** from `priv/category_mappings/` at runtime
2. **Tries source-specific mappings first** (`{source}.yml`)
3. **Falls back to defaults** (`_defaults.yml`) if no match
4. **Applies pattern matching** using regex patterns
5. **Returns category IDs** with primary/secondary flags

You don't need to modify `CategoryMapper` - it automatically discovers and uses your YAML file.

### Reference Implementations

#### Karnet (Polish Categories)

**File**: `priv/category_mappings/karnet.yml`

```yaml
mappings:
  koncerty: concerts
  festiwale: festivals
  spektakle: theatre
  wystawa: arts
  film: film
  literatura: education
  warsztaty: education

patterns:
  - match: "jazz"
    categories: [concerts, arts]
  - match: "dzieci|rodzin"
    categories: [family, education]
```

**Integration**: `lib/eventasaurus_discovery/categories/category_extractor.ex:70-101`

#### Resident Advisor (Electronic Music)

**File**: `priv/category_mappings/resident-advisor.yml`

```yaml
mappings:
  electronic: concerts
  techno: concerts
  house: concerts
  club: nightlife

patterns:
  - match: "festival|fest"
    categories: [festivals, concerts, nightlife]
```

#### Sortiraparis (French/English Categories)

**File**: `priv/category_mappings/sortiraparis.yml`

```yaml
mappings:
  concerts-music-festival: concerts
  exhibit-museum: arts
  theater: theatre
  cinema: film

patterns:
  - match: "concert|music"
    categories: [concerts]
  - match: "exposition|museum"
    categories: [arts]
```

### When to Use Category Mappings

#### ✅ Use YAML Category Mappings When:

- Source provides categorical data (genres, event types, tags, classifications)
- Categories need normalization across multiple sources
- Multiple category formats exist (strings, codes, hierarchies, URL segments)
- Non-English categories need mapping (Polish, French, etc.)
- Categories change over time (YAML is easier to update than code)

#### ❌ Don't Use When:

- Source has no category information → Use "other" fallback category
- Categories are already in our internal format → Pass through directly
- One-off mapping that won't change → Simple code mapping is fine

### Testing Category Mappings

#### Verify YAML Loading

```elixir
iex> CategoryMapper.map_categories("karnet", ["koncerty"], category_lookup)
[{1, true}]  # Returns category ID for "concerts" with primary flag
```

#### Test Extraction

```elixir
iex> CategoryExtractor.extract_karnet_categories(%{category: "koncert"})
[{1, true}]  # Mapped to "concerts" category ID
```

#### Integration Test

```elixir
# In your transformer test
test "assigns correct category from YAML mapping" do
  raw_event = %{"category" => "koncerty", "title" => "Jazz Concert"}

  {:ok, transformed} = Transformer.transform_event(raw_event)

  # Category field should be lowercase
  assert transformed.category == "koncerty"

  # After EventProcessor.process_event(), verify category assigned
  # (This happens in EventProcessor, not transformer)
end
```

### Validation

After implementing category mappings, verify coverage:

```sql
-- Check category coverage for your source
SELECT
  s.slug as source,
  COUNT(DISTINCT pe.id) as total_events,
  COUNT(DISTINCT pe.category_id) as events_with_category,
  ROUND(100.0 * COUNT(DISTINCT pe.category_id) / COUNT(DISTINCT pe.id), 1) as coverage_pct
FROM public_events pe
JOIN event_sources es ON es.event_id = pe.id
JOIN sources s ON s.id = es.source_id
WHERE s.slug = 'your-source'
GROUP BY s.slug;
```

**Target**: >90% category coverage for A grade

### Common Patterns

#### URL-Based Categories (Sortiraparis, Karnet)

```elixir
# Extract category from URL path segments
defp extract_category_from_url(url) when is_binary(url) do
  case Regex.run(~r{/what-to-see-in-paris/([^/]+)/articles/}, url) do
    [_, category_segment] -> String.downcase(category_segment)
    _ -> nil
  end
end
```

#### Tag-Based Categories (Bandsintown, Resident Advisor)

```elixir
# Extract from tags array
def extract_categories_from_tags(event_data) do
  tags = event_data[:tags] || event_data["tags"] || []

  tags
  |> Enum.map(&String.downcase/1)
  |> Enum.map(fn tag -> {"source", nil, tag} end)
end
```

#### API Classification Hierarchies (Ticketmaster)

```elixir
# Handle multi-level classifications (segment > genre > subgenre)
def extract_ticketmaster_categories(tm_event) do
  classifications = tm_event["classifications"] || []

  classifications
  |> Enum.flat_map(fn class ->
    [
      get_in(class, ["segment", "name"]),
      get_in(class, ["genre", "name"]),
      get_in(class, ["subGenre", "name"])
    ]
    |> Enum.filter(&(&1 != nil))
    |> Enum.map(fn name -> {"ticketmaster", nil, String.downcase(name)} end)
  end)
end
```

### Troubleshooting

#### Categories Not Being Assigned

1. **Check YAML file exists**: `ls priv/category_mappings/{source}.yml`
2. **Verify CategoryExtractor case**: Look for your source in `assign_categories_to_event/3`
3. **Check logs**: Look for CategoryMapper errors in logs
4. **Test mapping directly**: Use `iex` to test `CategoryMapper.map_categories/3`

#### Wrong Categories Assigned

1. **Check mapping precedence**: Source-specific YAML overrides defaults
2. **Verify pattern matching**: Regex patterns in YAML must be valid
3. **Check category slugs**: Must match exactly what's in `categories` table
4. **Test with sample data**: Use real source data to verify mappings

#### Low Category Coverage

1. **Add more mappings**: Cover edge cases and variations
2. **Use pattern matching**: Catch similar terms with regex
3. **Check extraction logic**: Ensure category data is being extracted from source
4. **Review logs**: Look for "category not found" warnings

---

## Multilingual Date Parsing

### Overview

Eventasaurus provides a **shared multilingual date parsing system** for scrapers that need to extract and normalize dates from non-English content. This system supports multiple languages (English, French, Polish, etc.) with a plugin architecture that makes adding new languages a 30-minute task.

**Key Principle**: When your scraper handles multilingual content (e.g., French event listings, Polish cinema sites), **defer to the shared parser** rather than implementing source-specific date parsing logic.

### Why Use Multilingual Date Parser?

- ✅ **Reusable across sources** - Polish date parsing for all 3 Krakow cinema scrapers
- ✅ **Language plugins** - Add German, Spanish, Italian by creating single module
- ✅ **Three-stage pipeline** - Extract → Normalize → Parse for reliability
- ✅ **Unknown occurrence fallback** - Gracefully handles unparseable dates (See Issue #1839, #1841)
- ✅ **Easy maintenance** - Update date patterns without touching scraper code

### When to Use

#### ✅ Use Shared Multilingual Parser When:

- Source content is in non-English languages (French, Polish, German, etc.)
- Multiple sources share the same language (e.g., 3 Polish cinema scrapers)
- Date formats vary within same source (e.g., "19 mars 2025", "du 19 au 21 mars")
- You want "unknown occurrence" fallback for unparseable dates

#### ❌ Don't Use When:

- Source provides ISO 8601 dates (2025-10-19) → Use `DateTime.from_iso8601/1` directly
- Source is English-only with simple formats → Consider simpler regex-based parsing
- One-off date format that won't appear elsewhere → Source-specific helper is acceptable

### Architecture

#### Three-Stage Pipeline

```
Raw Text (multilingual)
  ↓
Stage 1: Extract Date Components
  - Regex patterns for date ranges, single dates, relative dates
  - Language-specific month names (mars, marca, März)
  - Return: %{type: :range, start_day: 19, start_month: 3, end_day: 21, end_month: 3, year: 2025}
  ↓
Stage 2: Normalize to ISO Format
  - Convert language-specific components to YYYY-MM-DD
  - Handle multi-day events, recurring patterns, relative dates
  - Return: {:ok, %{starts_at: "2025-03-19", ends_at: "2025-03-21"}}
  ↓
Stage 3: Parse & Validate
  - Convert ISO strings to DateTime structs (UTC timezone)
  - Validate with Timex/NaiveDateTime
  - Return: {:ok, %{starts_at: ~U[2025-03-19 00:00:00Z], ends_at: ~U[2025-03-21 23:59:59Z]}}
```

#### Language Plugin System

Each language implements the `DatePatternProvider` behavior:

```elixir
# lib/eventasaurus_discovery/sources/shared/parsers/date_pattern_provider.ex

@doc """
Behavior for language-specific date pattern providers.
Each language module (English, French, Polish) implements this behavior.
"""
@callback month_names() :: %{String.t() => integer()}
@callback patterns() :: list(Regex.t())
@callback extract_components(String.t()) :: {:ok, map()} | {:error, atom()}
```

**Plugin Structure**:
```
lib/eventasaurus_discovery/sources/shared/parsers/
├── multilingual_date_parser.ex     # Core orchestration
├── date_pattern_provider.ex        # Behavior definition
└── date_patterns/
    ├── english.ex                  # English patterns + month names
    ├── french.ex                   # French patterns + month names (implemented)
    ├── polish.ex                   # Polish patterns (FUTURE - Issue #1846)
    ├── german.ex                   # German patterns (FUTURE)
    └── ...
```

### API Usage

#### Single Language

```elixir
# French event listing
{:ok, result} = MultilingualDateParser.extract_and_parse(
  "du 19 mars au 7 juillet 2025",
  languages: [:french]
)

# Returns:
# {:ok, %{
#   starts_at: ~U[2025-03-19 00:00:00Z],
#   ends_at: ~U[2025-07-07 23:59:59Z]
# }}
```

#### Multiple Languages (Fallback)

```elixir
# Try French first, fallback to English
{:ok, result} = MultilingualDateParser.extract_and_parse(
  "From March 19 to July 7, 2025",
  languages: [:french, :english]
)
```

#### Polish Cinema Scraper Example

```elixir
# Kino Krakow, Karnet, Cinema City (all Polish)
{:ok, result} = MultilingualDateParser.extract_and_parse(
  "od 19 marca do 21 marca 2025",  # Polish date format
  languages: [:polish, :english]     # Try Polish first, English fallback
)
```

#### Unknown Occurrence Fallback

When date parsing fails, the transformer creates an "unknown occurrence" event:

```elixir
case MultilingualDateParser.extract_and_parse(date_text, languages: [:french]) do
  {:ok, %{starts_at: starts_at, ends_at: ends_at}} ->
    # Normal event with known dates
    %{
      starts_at: starts_at,
      ends_at: ends_at,
      metadata: %{occurrence_type: "one_time"}
    }

  {:error, :unsupported_date_format} ->
    # Fallback: Unknown occurrence event
    Logger.info("📅 Date parsing failed, using unknown occurrence fallback")
    %{
      starts_at: DateTime.utc_now(),  # Use first_seen as starts_at
      ends_at: nil,
      metadata: %{
        occurrence_type: "unknown",
        occurrence_fallback: true,
        original_date_string: date_text
      }
    }
end
```

**Unknown Events Behavior**:
- Stored in database with `occurrence_type = "unknown"` in JSONB metadata
- Appear in public listings based on `last_seen_at` freshness (7-day threshold)
- Allow events with unparseable dates to be discovered without blocking scrapers
- See Implementation in `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex:106-117`

### Current Implementation Status

#### ✅ Implemented (Shared Parser - Phase 1-4 Complete)

**Location**: `lib/eventasaurus_discovery/sources/shared/parsers/multilingual_date_parser.ex`

**Supported Languages**: French, English (via language plugins)

**Language Plugins**:
- `shared/parsers/date_patterns/french.ex` - French date patterns and month names
- `shared/parsers/date_patterns/english.ex` - English date patterns and month names

**Date Formats**:
- **French**: "17 octobre 2025", "du 19 mars au 7 juillet 2025", "Le 1er janvier 2026"
- **English**: "October 15, 2025", "October 15, 2025 to January 19, 2026", "October 1st, 2025"
- **Multi-language fallback**: Tries languages in order (e.g., French → English)
- **Unknown dates**: Fallback to `occurrence_type = "unknown"` for unparseable dates

**Features**:
- ✅ Three-stage pipeline (Extract → Normalize → Parse)
- ✅ Language plugin architecture with `DatePatternProvider` behavior
- ✅ Unknown occurrence fallback (Issue #1841)
- ✅ Timezone support (converts to UTC)
- ✅ Comprehensive logging for debugging
- ✅ Integrated with Sortiraparis transformer (Phase 4)

**Currently Used By**: Sortiraparis scraper (French/English bilingual content)

#### 🚀 Production Ready Architecture

**How to Use**:
```elixir
# Shared parser with multi-language support
alias EventasaurusDiscovery.Sources.Shared.Parsers.MultilingualDateParser

# Sortiraparis (French/English)
MultilingualDateParser.extract_and_parse(
  "du 19 mars au 7 juillet 2025",
  languages: [:french, :english],
  timezone: "Europe/Paris"
)

# Returns: {:ok, %{starts_at: ~U[2025-03-19 00:00:00Z], ends_at: ~U[2025-07-07 23:59:59Z]}}
```

#### 📋 Future Enhancements

**Polish Language Plugin** (Ready for implementation when needed):
- Location: `shared/parsers/date_patterns/polish.ex`
- Will unlock: Kino Krakow, Karnet, Cinema City scrapers
- Estimated time: 30 minutes to implement

**Additional Languages** (German, Spanish, Italian):
- Same plugin architecture
- 30 minutes per language to implement

### Adding a New Language

**Estimated Time**: 30 minutes per language

**Steps**:

1. **Create language plugin** (`lib/eventasaurus_discovery/sources/shared/parsers/date_patterns/polish.ex`):

```elixir
defmodule EventasaurusDiscovery.Sources.Shared.Parsers.DatePatterns.Polish do
  @behaviour EventasaurusDiscovery.Sources.Shared.Parsers.DatePatternProvider

  @impl true
  def month_names do
    %{
      # Polish month names (lowercase for case-insensitive matching)
      "stycznia" => 1, "lutego" => 2, "marca" => 3, "kwietnia" => 4,
      "maja" => 5, "czerwca" => 6, "lipca" => 7, "sierpnia" => 8,
      "września" => 9, "października" => 10, "listopada" => 11, "grudnia" => 12,

      # Abbreviated forms
      "sty" => 1, "lut" => 2, "mar" => 3, "kwi" => 4,
      "maj" => 5, "cze" => 6, "lip" => 7, "sie" => 8,
      "wrz" => 9, "paź" => 10, "lis" => 11, "gru" => 12
    }
  end

  @impl true
  def patterns do
    months = Enum.join(Map.keys(month_names()), "|")

    [
      # Single date: "19 marca 2025"
      ~r/(\d{1,2})\s+(#{months})\s+(\d{4})/i,

      # Date range: "od 19 do 21 marca 2025"
      ~r/od\s+(\d{1,2})\s+do\s+(\d{1,2})\s+(#{months})\s+(\d{4})/i,

      # Cross-month range: "od 19 marca do 7 lipca 2025"
      ~r/od\s+(\d{1,2})\s+(#{months})\s+do\s+(\d{1,2})\s+(#{months})\s+(\d{4})/i
    ]
  end

  @impl true
  def extract_components(text) do
    # Pattern matching logic to extract date components
    # Returns: {:ok, %{type: :range, start_day: 19, ...}} | {:error, :no_match}
  end
end
```

2. **Register in MultilingualDateParser**:

```elixir
# lib/eventasaurus_discovery/sources/shared/parsers/multilingual_date_parser.ex

@language_modules %{
  french: DatePatterns.French,
  english: DatePatterns.English,
  polish: DatePatterns.Polish  # ADD THIS
}
```

3. **Use in your scraper's transformer**:

```elixir
# lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex

case MultilingualDateParser.extract_and_parse(date_text, languages: [:polish, :english]) do
  {:ok, dates} -> # Use extracted dates
  {:error, _} -> # Fallback to unknown occurrence
end
```

### Reference Documentation

- **Original Vision**: GitHub Issue #1839 (multilingual date parser for all scrapers)
- **Unknown Occurrence Implementation**: GitHub Issue #1841, #1842
- **Refactoring Plan**: GitHub Issue #1846 (move to shared architecture)
- **Current Implementation**: `lib/eventasaurus_discovery/sources/sortiraparis/parsers/date_parser.ex`
- **Production Validation**: `PHASE_4_VALIDATION_SUMMARY.md`, `UNKNOWN_OCCURRENCE_AUDIT.md`

### Testing

```elixir
# Test language plugin
test "polish date parsing" do
  {:ok, result} = MultilingualDateParser.extract_and_parse(
    "od 19 marca do 21 marca 2025",
    languages: [:polish]
  )

  assert result.starts_at == ~U[2025-03-19 00:00:00Z]
  assert result.ends_at == ~U[2025-03-21 23:59:59Z]
end

# Test unknown fallback
test "unknown occurrence fallback for unparseable dates" do
  {:error, :unsupported_date_format} = MultilingualDateParser.extract_and_parse(
    "sometime in spring",
    languages: [:english]
  )
end
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
