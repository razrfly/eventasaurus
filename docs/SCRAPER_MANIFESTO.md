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

## 🗺️ Geocoding & City Resolution Strategy

### City Name Resolution (CRITICAL - Prevents Data Pollution)

**All scrapers MUST use `CityResolver` for reliable city name extraction from GPS coordinates.**

City data pollution (postcodes, street addresses, venue names stored as city names) is a critical data quality issue. The `CityResolver` helper provides:

- **100% offline geocoding** - Zero API costs, using GeoNames database (156,710+ cities)
- **Built-in validation** - Rejects postcodes, street addresses, numeric values, venue names
- **Fast lookups** - Sub-millisecond via k-d tree algorithm
- **Fallback handling** - Conservative address parsing when coordinates unavailable

#### Implementation Pattern

```elixir
alias EventasaurusDiscovery.Helpers.CityResolver

def resolve_location(latitude, longitude, address) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} ->
      # Successfully resolved city from coordinates
      {city_name, "United States"}

    {:error, reason} ->
      # Geocoding failed - use conservative fallback
      Logger.warning("Geocoding failed: #{reason}. Falling back to address parsing.")
      parse_location_from_address_conservative(address)
  end
end

# Conservative fallback - prefers nil over garbage
defp parse_location_from_address_conservative(address) when is_binary(address) do
  parts = String.split(address, ",")

  case parts do
    # Has at least 3 parts (street, city, state+zip)
    [_street, city_candidate, _state_zip | _rest] ->
      city_trimmed = String.trim(city_candidate)

      # CRITICAL: Validate city candidate before using
      case CityResolver.validate_city_name(city_trimmed) do
        {:ok, validated_city} ->
          {validated_city, "United States"}

        {:error, _reason} ->
          Logger.warning("Invalid city candidate: #{inspect(city_trimmed)}")
          {nil, "United States"}
      end

    # Insufficient parts - prefer nil over garbage
    _ ->
      {nil, "United States"}
  end
end
```

#### Validation Rules

`CityResolver.validate_city_name/1` rejects:

- ❌ **UK postcodes** - "SW18 2SS", "E1 6AN", "W1A 1AA"
- ❌ **US ZIP codes** - "90210", "10001", "12345"
- ❌ **Street addresses** - "123 Main Street", "76 Narrow Street"
- ❌ **Numeric values** - "12345", "999"
- ❌ **Venue names** - "The Rose and Crown Pub", "Sports Bar at Stadium"
- ❌ **Single characters** - "A", "X" (likely abbreviations)
- ❌ **Empty strings** - "", "   "

#### Example Usage

```elixir
# ✅ CORRECT - Using CityResolver
resolve_location(40.7128, -74.0060, "123 Main St, New York, NY 10001")
# => {"New York City", "United States"}

resolve_location(nil, nil, "123 Main St, Chicago, IL 60601")
# => {"Chicago", "United States"}  # Conservative parser with validation

resolve_location(nil, nil, "13 Bollo Lane, SW18 2SS")
# => {nil, "United States"}  # Safely rejects garbage

# ❌ WRONG - Naive parsing (causes pollution)
String.split("13 Bollo Lane, SW18 2SS", ",") |> Enum.at(1)
# => "SW18 2SS"  # GARBAGE POSTCODE IN DATABASE!
```

#### Reference Implementations

**All A-grade scrapers follow the same pattern**: GPS coordinates (primary) → API validation (fallback) → nil (safe default)

##### Pattern 1: GeeksWhoDrink (A+ Grade) - US Events with GPS
**File**: `lib/eventasaurus_discovery/sources/geeks_who_drink/transformer.ex:238-285`

**Strategy**: API provides GPS coordinates directly
```elixir
def resolve_location(latitude, longitude, address) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} ->
      # Successfully resolved city from coordinates
      {city_name, "United States"}

    {:error, reason} ->
      # Geocoding failed - use conservative fallback
      Logger.warning("Geocoding failed: #{reason}. Falling back to address parsing.")
      parse_location_from_address_conservative(address)
  end
end

# Conservative fallback - validates before using
defp parse_location_from_address_conservative(address) when is_binary(address) do
  parts = String.split(address, ",")

  case parts do
    [_street, city_candidate, _state_zip | _rest] ->
      case CityResolver.validate_city_name(String.trim(city_candidate)) do
        {:ok, validated_city} -> {validated_city, "United States"}
        {:error, _} -> {nil, "United States"}  # Prefer nil over garbage
      end
    _ -> {nil, "United States"}
  end
end
```

**Key Features**:
- ✅ Uses GPS coordinates from API (most reliable)
- ✅ Conservative US address parsing fallback (\"Street, City, State+ZIP\")
- ✅ Validates all city candidates before using
- ✅ Prefers `nil` over invalid data
- ✅ Comprehensive error logging

**Use When**: Source provides GPS coordinates, US addresses as fallback

---

##### Pattern 2: Bandsintown (A Grade) - International Events
**File**: `lib/eventasaurus_discovery/sources/bandsintown/transformer.ex:508-548`

**Strategy**: API coordinates + city context validation
```elixir
def resolve_location(latitude, longitude, api_city, known_country) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} ->
      # Successfully resolved city from coordinates
      country = known_country || "United States"
      {city_name, country}

    {:error, reason} ->
      # Geocoding failed - validate API city name
      Logger.warning("Geocoding failed: #{reason}. Falling back to API city validation.")
      validate_api_city(api_city, known_country)
  end
end

defp validate_api_city(api_city, known_country) when is_binary(api_city) do
  case CityResolver.validate_city_name(String.trim(api_city)) do
    {:ok, validated_city} ->
      {validated_city, known_country || "United States"}

    {:error, reason} ->
      Logger.warning("API returned invalid city: #{inspect(api_city)} (#{reason})")
      {nil, known_country || "United States"}
  end
end
```

**Key Features**:
- ✅ Uses GPS coordinates from API (primary)
- ✅ Validates API-provided city names (fallback)
- ✅ Uses known country from city context (more reliable than API)
- ✅ Handles missing coordinates gracefully
- ✅ Multiple fallback scenarios

**Use When**: International events, API provides coordinates and city names

---

##### Pattern 3: Ticketmaster (A Grade) - Complex Venue Fallbacks
**File**: `lib/eventasaurus_discovery/sources/ticketmaster/transformer.ex:760-800`

**Strategy**: GPS coordinates + venue fallbacks + timezone inference
```elixir
def resolve_location(latitude, longitude, api_city, known_country) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} ->
      # Successfully resolved city from coordinates
      {city_name, known_country || "Poland"}

    {:error, reason} ->
      # Geocoding failed - validate API city
      Logger.warning("Geocoding failed: #{reason}. Falling back to API city validation.")
      validate_api_city(api_city, known_country)
  end
end

defp validate_api_city(api_city, known_country) when is_binary(api_city) do
  case CityResolver.validate_city_name(String.trim(api_city)) do
    {:ok, validated_city} ->
      {validated_city, known_country || "Poland"}

    {:error, reason} ->
      Logger.warning("API returned invalid city: #{inspect(api_city)} (#{reason})")
      {nil, known_country || "Poland"}
  end
end

# Additional fallback: timezone inference (when no coordinates or city)
defp extract_venue_fallback(event) do
  case infer_location_from_timezone(event["timezone"]) do
    {city_name, country_name, lat, lng} when not is_nil(city_name) ->
      %{
        name: "Venue TBD - #{city_name}",
        city: city_name,
        country: country_name,
        latitude: lat,
        longitude: lng,
        metadata: %{inferred: true}
      }
    _ -> nil  # No valid venue data
  end
end
```

**Key Features**:
- ✅ Uses GPS coordinates from API (primary)
- ✅ Validates API-provided city names (fallback 1)
- ✅ Timezone-based inference (fallback 2)
- ✅ Multiple layered fallbacks
- ✅ Clear metadata marking inferred data

**Use When**: Complex APIs with multiple venue data sources, need deep fallback chains

---

##### Pattern 4: CinemaCity (A Grade) - Poland-Specific Events
**File**: `lib/eventasaurus_discovery/sources/cinema_city/transformer.ex:230-268`

**Strategy**: Same as Bandsintown/Ticketmaster but Poland-specific
```elixir
def resolve_location(latitude, longitude, api_city, known_country) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} ->
      {city_name, known_country}

    {:error, reason} ->
      Logger.warning("Geocoding failed: #{reason}. Falling back to API city validation.")
      validate_api_city(api_city, known_country)
  end
end

defp validate_api_city(api_city, known_country) when is_binary(api_city) do
  case CityResolver.validate_city_name(String.trim(api_city)) do
    {:ok, validated_city} -> {validated_city, known_country}
    {:error, reason} ->
      Logger.warning("API returned invalid city: #{inspect(api_city)} (#{reason})")
      {nil, known_country}
  end
end
```

**Key Features**:
- ✅ Cinema City API provides GPS coordinates
- ✅ Validates API city names as fallback
- ✅ Poland-specific context (known_country = \"Poland\")
- ✅ Simple, clean implementation

**Use When**: Single-country events with reliable API coordinates

---

##### Pattern 5: ResidentAdvisor (A Grade) - International Events with VenueEnricher
**File**: `lib/eventasaurus_discovery/sources/resident_advisor/transformer.ex:208-277`

**Strategy**: Integrate with VenueEnricher for GPS, validate API city, similar to Bandsintown
```elixir
def extract_venue(event, city_context) do
  venue = event["venue"]

  if venue && venue["name"] do
    # Get coordinates from RA GraphQL via VenueEnricher (may return nil)
    {lat, lng, _needs_geocoding} =
      VenueEnricher.get_coordinates(
        venue["id"],
        venue["name"],
        city_context
      )

    # A-grade city resolution: Use CityResolver with GPS coordinates (primary)
    # or validate API city name (fallback)
    {resolved_city, resolved_country} =
      resolve_location(
        lat,
        lng,
        city_context.name,
        get_country_name(city_context)
      )

    %{
      name: venue["name"],
      latitude: lat,
      longitude: lng,
      city: resolved_city,
      country: resolved_country
    }
  end
end

defp resolve_location(latitude, longitude, api_city, country_name)
     when is_float(latitude) and is_float(longitude) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} ->
      {city_name, country_name}

    {:error, reason} ->
      Logger.warning("CityResolver geocoding failed (#{reason}), falling back to API city validation")
      validate_api_city(api_city, country_name)
  end
end

defp resolve_location(_latitude, _longitude, api_city, country_name) do
  validate_api_city(api_city, country_name)
end

defp validate_api_city(api_city, country_name) when is_binary(api_city) do
  case CityResolver.validate_city_name(String.trim(api_city)) do
    {:ok, validated_city} -> {validated_city, country_name}
    {:error, reason} ->
      Logger.warning("API city failed validation (#{reason})")
      {nil, country_name}
  end
end
```

**Key Features**:
- ✅ Integrates with VenueEnricher for GPS coordinates (may be nil)
- ✅ Uses CityResolver.resolve_city() when GPS available (primary)
- ✅ Validates API city names from city_context (fallback)
- ✅ Handles placeholder venues with validation
- ✅ International events across all major cities worldwide
- ✅ Comprehensive test coverage (19 tests)

**Use When**: Source requires external enrichment service for GPS, API provides city context, international events

**Special Notes**:
- ResidentAdvisor GraphQL API typically does NOT provide GPS coordinates
- VenueEnricher fetches coordinates via Google Places API when needed
- This pattern shows how to upgrade D-grade scrapers that rely on Layer 2 only
- Upgraded from D+ to A grade by adding Layer 1 CityResolver validation

---

### City Resolution Decision Tree

**Step 1: Does your API provide GPS coordinates?**
- ✅ YES → Use Pattern 1-4 (GeeksWhoDrink/Bandsintown/Ticketmaster/CinemaCity)
- ❌ NO → Continue to Step 2

**Step 1a: Can you fetch GPS coordinates via external service?**
- ✅ YES → Use Pattern 5 (ResidentAdvisor with VenueEnricher)
- ❌ NO → Continue to Step 2

**Step 2: Does your API provide city names?**
- ✅ YES → Use `validate_api_city()` pattern with validation
- ❌ NO → Continue to Step 3

**Step 3: Can you parse addresses reliably?**
- ✅ YES → Use conservative parsing with validation (GeeksWhoDrink fallback)
- ❌ NO → Return `nil` and let VenueProcessor handle it

**Step 4: Is the scraper country/city-specific?**
- ✅ YES (e.g., all events in Kraków) → Hardcode city name (Grade: C, safe)
- ❌ NO → Implement at least validation layer (minimum requirement)

---

### City Resolution Quality Grades

**A-Grade Requirements** (Excellent):
- ✅ Uses `CityResolver.resolve_city()` for GPS coordinates
- ✅ Uses `CityResolver.validate_city_name()` for fallbacks
- ✅ Conservative fallbacks prefer `nil` over garbage
- ✅ Comprehensive error logging
- ✅ Documented implementation

**B-Grade Requirements** (Good):
- ✅ Uses `CityResolver.validate_city_name()` for validation
- ✅ Conservative approach (no naive string parsing)
- ✅ Safe fallbacks

**C-Grade Requirements** (Safe):
- ✅ Hardcoded city names (for single-city scrapers)
- ✅ Uses database records (already validated)
- ✅ No raw city name parsing

**D-Grade (Needs Improvement)**:
- ⚠️ No CityResolver usage
- ⚠️ Relies entirely on VenueProcessor safety net (Layer 2)
- ⚠️ Should add Layer 1 validation

**F-Grade (Unacceptable)**:
- ❌ Naive string parsing without validation
- ❌ Would cause pollution without VenueProcessor safety net
- ❌ Must be fixed immediately

---

### Current Scraper Grades Summary

**Status as of Phase 2 Completion (October 2025)**

| Scraper | Grade | Strategy | Layer 1 Validation | GPS Primary | Tests |
|---------|-------|----------|-------------------|-------------|-------|
| **GeeksWhoDrink** | **A+** | GPS + US address fallback | ✅ CityResolver | ✅ Yes | ✅ 13 tests |
| **Bandsintown** | **A** | GPS + API city validation | ✅ CityResolver | ✅ Yes | ✅ External |
| **Ticketmaster** | **A** | GPS + timezone inference | ✅ CityResolver | ✅ Yes | ✅ External |
| **CinemaCity** | **A** | GPS + API city validation | ✅ CityResolver | ✅ Yes | ✅ External |
| **ResidentAdvisor** | **A** | GPS (enriched) + API validation | ✅ CityResolver | ✅ Yes* | ✅ 19 tests |
| QuestionOne | B+ | UK address parsing | ✅ CityResolver | ❌ No | ⚠️ Needs tests |
| PubQuiz | C | Database records | ✅ Safe (DB) | N/A | ⚠️ Needs tests |
| Karnet | C- | Hardcoded (Kraków) | ✅ Safe (hardcoded) | N/A | ⚠️ Needs tests |
| KinoKrakow | C- | Hardcoded (Kraków) | ✅ Safe (hardcoded) | N/A | ⚠️ Needs tests |

\* ResidentAdvisor fetches GPS via VenueEnricher (Google Places API) when not provided by GraphQL

**Key Achievements:**
- ✅ **5/9 scrapers at A-grade** (GeeksWhoDrink, Bandsintown, Ticketmaster, CinemaCity, ResidentAdvisor)
- ✅ **All scrapers protected by defense-in-depth architecture** (Layer 1 + Layer 2)
- ✅ **Zero database pollution risk** (VenueProcessor safety net catches all invalid cities)
- ✅ **100% CityResolver adoption** (all scrapers use validation or are hardcoded/DB-based)

**Upgrade Path for Remaining Scrapers:**
- **QuestionOne (B+ → A)**: Add Google Places geocoding in transformer before VenueProcessor (3-4 hours)
- **Karnet (C- → A)**: Scrape GPS coordinates from Karnet.pl venue pages (4-6 hours)
- **KinoKrakow (C- → A)**: Scrape GPS coordinates from kino.krakow.pl venue pages (4-6 hours)

**Testing Status:**
- ✅ CityResolver: 26 comprehensive tests
- ✅ VenueProcessor safety net: 10+ validation tests
- ✅ GeeksWhoDrink city resolution: 13 tests
- ✅ ResidentAdvisor city resolution: 19 tests
- ⚠️ Need tests for: Bandsintown, Ticketmaster, CinemaCity, QuestionOne, PubQuiz, Karnet, KinoKrakow

---

### Geocoding Priority Order

1. **Use Source Data** - If source provides coordinates, use them directly
2. **CityResolver** - Offline reverse geocoding (coordinates → city name)
3. **Google Places API** - Geocode venue name + city + country
4. **City Center Fallback** - Use city coordinates with `needs_geocoding: true` flag
5. **Hard-Coded Coordinates** - For common cities (last resort)

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
- [ ] **Uses `CityResolver` for city name extraction from coordinates**
- [ ] **Validates city names before storing (no postcodes, street addresses, garbage)**
- [ ] **Prefers `nil` city over invalid data**
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
2. **City names must be validated** - Use `CityResolver` to prevent data pollution (postcodes, street addresses)
3. **Prefer nil over garbage** - Invalid city data is worse than missing data
4. **Async pipeline is standard** - SyncJob → IndexPageJob → EventDetailJob
5. **Validation happens in Transformer** - Fail fast with detailed errors
6. **Geocoding is critical** - Have multiple fallback strategies (CityResolver → Google Places → Fallback)
7. **Rate limiting is mandatory** - Respect source limits and terms
8. **Deduplication by priority** - Lower priority sources check higher ones
9. **Graceful degradation** - Save what we can, log what we can't
10. **Testing is required** - Unit tests + Mix tasks for development

---

**Questions?** Review existing implementations in `lib/eventasaurus_discovery/sources/`
