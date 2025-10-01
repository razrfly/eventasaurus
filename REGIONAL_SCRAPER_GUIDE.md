# Regional Trivia Scraper Implementation Guide

## Overview

This guide documents the pattern for implementing regional trivia brand scrapers in Eventasaurus Discovery. Each scraper targets a specific trivia brand that operates in one or more countries/regions (e.g., PubQuiz.pl in Poland, Geeks Who Drink in USA/Canada, SpeedQuizzing in UK).

**Reference Implementation**: PubQuiz.pl (`lib/eventasaurus_discovery/sources/pubquiz/`)

## Key Principles

### 1. One Scraper Per Brand

Each scraper targets a **specific brand/company**, not a generic event type:

- ✅ **PubQuiz.pl** (Poland) - Brand-specific scraper for pubquiz.pl website
- ✅ **Geeks Who Drink** (USA/Canada) - Brand-specific scraper for geekswhodrink.com
- ✅ **SpeedQuizzing** (UK) - Brand-specific scraper for speedquizzing.com
- ❌ **Generic "Trivia Events"** - Too vague, would cause confusion

### 2. Hard-Coding Country/Timezone is Appropriate

Since each scraper targets a specific brand operating in known countries, hard-coding geographic information is **correct and expected**:

```elixir
# PubQuiz.pl - Poland only
def country, do: "Poland"
def timezone, do: "Europe/Warsaw"

# SpeedQuizzing - UK only
def country, do: "United Kingdom"
def timezone, do: "Europe/London"

# Geeks Who Drink - Multiple timezones
def country, do: "United States"  # or "Canada"
def timezone, do: varies_by_city()  # Requires lookup
```

**Why this is correct**: Just like Karnet hard-codes "Kraków, Poland" because it's a Kraków-specific cultural events source, regional trivia brands operate in known, fixed locations.

### 3. Clear Naming Convention

Use descriptive slugs that identify the brand and region:

- ✅ `pubquiz-pl` - Clear it's PubQuiz Poland
- ✅ `geeks-who-drink` - Internationally recognized brand name
- ✅ `speed-quizzing` - Clear brand identification
- ❌ `pubquiz` - Ambiguous, could be confused with other regions
- ❌ `trivia-poland` - Too generic, doesn't identify the brand

## File Structure

All regional trivia scrapers follow this structure:

```
lib/eventasaurus_discovery/sources/[source_name]/
├── config.ex              # URLs, rate limits, constants
├── source.ex              # Source definition with metadata
├── client.ex              # HTTP client for fetching pages
├── city_extractor.ex      # Extract city/region list
├── venue_extractor.ex     # Extract venue cards from listings
├── detail_extractor.ex    # Extract venue details from individual pages
├── transformer.ex         # Transform scraped data to PublicEvent schema
└── jobs/
    ├── sync_job.ex        # Country/region-level orchestrator
    ├── city_job.ex        # City/region-level processing
    └── venue_detail_job.ex # Individual venue processing
```

## Implementation Checklist

### Phase 1: Source Configuration

#### 1.1 Create `config.ex`

Define base URL, rate limits, and HTTP headers:

```elixir
defmodule EventasaurusDiscovery.Sources.[SourceName].Config do
  @base_url "https://example.com/venues"
  @rate_limit_seconds 2
  @timeout_ms 30_000

  def base_url, do: @base_url
  def rate_limit, do: @rate_limit_seconds
  def timeout, do: @timeout_ms

  def headers do
    [
      {"User-Agent", "Eventasaurus Discovery Bot/1.0"},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "[locale];q=0.9,en-US;q=0.8,en;q=0.7"}
    ]
  end

  def max_retries, do: 2
  def retry_delay_ms, do: 5_000
end
```

#### 1.2 Create `source.ex`

Define the source with geographic metadata:

```elixir
defmodule EventasaurusDiscovery.Sources.[SourceName].Source do
  @moduledoc """
  [Brand Name] source configuration for the unified discovery system.

  Regional scraper for [region]-wide weekly trivia events.
  Priority [XX]: Position in source hierarchy.

  ## City Matching Strategy

  [Explain why CityMatcher is/isn't needed - see PubQuiz example]
  """

  def name, do: "[Brand Name]"
  def key, do: "[brand-slug]"  # e.g., "geeks-who-drink"
  def enabled?, do: Application.get_env(:eventasaurus, :[source]_enabled, true)
  def priority, do: 25  # Regional tier: between global (20) and city-specific (30)

  def config do
    %{
      base_url: Config.base_url(),
      rate_limit_ms: Config.rate_limit() * 1000,

      # Geographic settings
      country: "[Country Name]",        # e.g., "Poland", "United States"
      timezone: "[Timezone]",           # e.g., "Europe/Warsaw", "America/New_York"
      locale: "[locale]",               # e.g., "pl_PL", "en_US"

      # Feature flags
      supports_api: false,              # Most are HTML scraping
      supports_recurring_events: true,  # Weekly trivia nights
      supports_ticket_info: false       # Usually free events
    }
  end
end
```

**Priority Guidelines**:
- **10**: Global APIs with highest data quality (Ticketmaster)
- **20**: Global APIs with good coverage (BandsInTown)
- **25**: Regional scrapers (PubQuiz, Geeks Who Drink, SpeedQuizzing)
- **30**: City-specific sources (Karnet - Kraków only)

#### 1.3 Create `client.ex`

HTTP client with retry logic and error handling:

```elixir
defmodule EventasaurusDiscovery.Sources.[SourceName].Client do
  require Logger
  alias EventasaurusDiscovery.Sources.[SourceName].Config

  def fetch_index do
    fetch_page(Config.base_url())
  end

  def fetch_city_page(city_url) do
    fetch_page(city_url)
  end

  def fetch_venue_page(venue_url) do
    fetch_page(venue_url)
  end

  defp fetch_page(url) do
    Logger.debug("Fetching [Source] page: #{url}")

    case HTTPoison.get(url, Config.headers(),
           follow_redirect: true,
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: 404}} ->
        Logger.warning("[Source] page not found: #{url}")
        {:error, :not_found}

      {:ok, %{status_code: status}} ->
        Logger.error("[Source] returned status #{status} for: #{url}")
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("[Source] HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

### Phase 2: Data Extraction

#### 2.1 Create Extractor Modules

Implement extractors based on the site's HTML structure:

- `city_extractor.ex` - Extract list of cities/regions from index
- `venue_extractor.ex` - Extract venue cards from city pages
- `detail_extractor.ex` - Extract details from individual venue pages

**Key Pattern**: Use Floki for HTML parsing with clear, testable functions.

See PubQuiz implementation for examples.

#### 2.2 Create `transformer.ex`

Transform scraped data into PublicEvent format with recurring event support:

```elixir
defmodule EventasaurusDiscovery.Sources.[SourceName].Transformer do
  @moduledoc """
  Transforms [Source] venue data into PublicEvent schema with recurrence rules.
  """

  def transform_venue_to_event(venue_data, venue_record, _city) do
    with {:ok, recurrence_rule} <- parse_schedule_to_recurrence(venue_data[:schedule]),
         {:ok, next_occurrence} <- calculate_next_occurrence(recurrence_rule) do

      event_map = %{
        title: build_title(venue_data[:name]),
        starts_at: next_occurrence,
        ends_at: DateTime.add(next_occurrence, 2 * 3600, :second),  # 2 hours
        venue_id: venue_record.id,
        recurrence_rule: recurrence_rule,

        source_metadata: %{
          "venue_name" => venue_data[:name],
          "description" => venue_data[:description],
          "schedule_text" => venue_data[:schedule]
        }
      }

      {:ok, event_map}
    end
  end

  def parse_schedule_to_recurrence(schedule_text) do
    # Parse schedule text (language-specific)
    # Return: {:ok, %{"frequency" => "weekly", "days_of_week" => [...], "time" => "19:00", "timezone" => "..."}}
  end

  def calculate_next_occurrence(recurrence_rule) do
    # Calculate next occurrence datetime from rule
    # Return: {:ok, DateTime}
  end
end
```

### Phase 3: Job Implementation

#### 3.1 Create `jobs/sync_job.ex`

Country/region-level orchestrator:

```elixir
defmodule EventasaurusDiscovery.Sources.[SourceName].Jobs.SyncJob do
  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.[SourceName].{Client, CityExtractor, Jobs.CityJob}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🎯 Starting [Source] sync...")

    source = get_or_create_source()
    limit = args["limit"]

    with {:ok, html} <- Client.fetch_index(),
         city_urls <- CityExtractor.extract_cities(html),
         city_urls <- maybe_limit_cities(city_urls, limit),
         scheduled_count <- schedule_city_jobs(city_urls, source.id) do

      Logger.info("✅ [Source] sync completed - scheduled #{scheduled_count} city jobs")
      {:ok, %{cities_found: length(city_urls), jobs_scheduled: scheduled_count}}
    end
  end

  defp get_or_create_source do
    alias EventasaurusDiscovery.Sources.[SourceName].Source, as: SourceModule

    case Repo.get_by(Source, slug: SourceModule.key()) do
      nil ->
        %Source{}
        |> Source.changeset(%{
          name: SourceModule.name(),
          slug: SourceModule.key(),
          website_url: "[brand URL]",
          priority: SourceModule.priority(),
          config: %{
            "rate_limit_seconds" => 2,
            "language" => "[locale]",
            "supports_recurring_events" => true
          }
        })
        |> Repo.insert!()
      source -> source
    end
  end

  defp schedule_city_jobs(city_urls, source_id) do
    # Schedule with staggered delays to respect rate limits
  end
end
```

#### 3.2 Create `jobs/city_job.ex` and `jobs/venue_detail_job.ex`

Similar to PubQuiz implementation - see reference code.

### Phase 4: Seeds & Configuration

#### 4.1 Add to `priv/repo/seeds/sources.exs`

```elixir
%{
  name: "[Brand Name]",
  slug: "[brand-slug]",
  website_url: "[URL]",
  priority: 25,
  metadata: %{
    "rate_limit_seconds" => 2,
    "max_requests_per_hour" => 300,
    "language" => "[locale]",
    "supports_recurring_events" => true
  }
}
```

#### 4.2 Add to `config/config.exs`

```elixir
config :eventasaurus,
  [source]_enabled: true
```

#### 4.3 Register in Discovery System

Add to `lib/eventasaurus_discovery/admin/discovery_sync_job.ex`:

```elixir
@sources %{
  "[brand-slug]" => EventasaurusDiscovery.Sources.[SourceName].Jobs.SyncJob
}

# If country-wide (doesn't need city):
@country_wide_sources ["[brand-slug]"]
```

### Phase 5: Testing

#### 5.1 Create Mix Test Task

```elixir
defmodule Mix.Tasks.[Source].Test do
  use Mix.Task

  def run(args) do
    # Parse args: --city, --limit, --full
    # Test configuration
    # Test city extraction
    # Test venue extraction
    # Test detail extraction (if --full)
  end
end
```

#### 5.2 Test Commands

```bash
# Basic test
mix [source].test

# Test specific city
mix [source].test --city [city-name]

# Test with limit
mix [source].test --limit 2

# Full test including details
mix [source].test --full --limit 1
```

## Timezone Handling Strategies

### Single Timezone (Simple)

**Examples**: PubQuiz (Poland), SpeedQuizzing (UK)

```elixir
# In config.ex or source.ex
def timezone, do: "Europe/Warsaw"

# In transformer.ex
recurrence_rule = %{
  "timezone" => Config.timezone()  # Single value
}
```

### Multiple Timezones (Complex)

**Examples**: Geeks Who Drink (USA/Canada), QuizMeisters (Australia)

**Option 1: Timezone Lookup by City**

```elixir
defmodule EventasaurusDiscovery.Sources.[Source].TimezoneMapper do
  @timezone_map %{
    "Los Angeles" => "America/Los_Angeles",
    "New York" => "America/New_York",
    "Chicago" => "America/Chicago",
    "Denver" => "America/Denver"
  }

  def get_timezone(city_name) do
    Map.get(@timezone_map, city_name, "America/New_York")  # Default
  end
end
```

**Option 2: Timezone from Coordinates**

```elixir
def determine_timezone(latitude, longitude) do
  # Use a timezone lookup library/service
  # Return appropriate timezone string
end
```

**Recommendation**: Start with Option 1 (manual mapping) for known cities, add Option 2 if needed for edge cases.

## When to Use CityMatcher

A dedicated `CityMatcher` module is needed when:

1. **Ambiguous City Names**: City exists in multiple countries (e.g., "Cambridge" in UK and USA)
2. **Alternative Spellings**: Source uses different names than database (e.g., "Warszawa" vs "Warsaw")
3. **Multiple Cities Same Name**: Same country has cities with identical names
4. **Pre-Geocoding Matching**: Need to match before geocoding happens

**When NOT Needed** (like PubQuiz):
- City names are unambiguous within the country
- VenueProcessor auto-creates cities from geocoding
- Geocoding provides definitive coordinates

## Common Patterns & Best Practices

### 1. Respect Rate Limits

```elixir
# In jobs, stagger with delays
delay_seconds = index * 3
scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)
```

### 2. Mark Events as Seen

```elixir
# At start of venue_detail_job
EventProcessor.mark_event_as_seen(external_id, source_id)
```

### 3. Generate Stable External IDs

```elixir
def extract_external_id(venue_url) do
  venue_url
  |> String.trim_trailing("/")
  |> String.split("/")
  |> Enum.take(-2)
  |> Enum.join("_")
  |> String.replace("-", "_")
  |> then(&"[source-slug]_#{&1}")
end
```

### 4. Pass City/Country as Strings

```elixir
venue_data: %{
  name: venue_name,
  address: address,
  city: city_name,          # STRING - VenueProcessor handles
  country: "Poland",        # STRING
  latitude: lat,            # May be nil
  longitude: lng            # May be nil
}
```

### 5. Handle Missing Data Gracefully

```elixir
if event_map.starts_at do
  Processor.process_single_event(event_map, source)
else
  Logger.warning("⚠️ Skipping venue without valid schedule")
  {:discard, :no_valid_schedule}
end
```

## Troubleshooting

### Issue: Cities not being created

**Solution**: Verify VenueProcessor is receiving city name as string, not ID. Check geocoding is working.

### Issue: Timezone incorrect for events

**Solution**: For multi-timezone sources, verify timezone lookup logic. Log the timezone being used.

### Issue: Schedule extraction failing

**Solution**: Add detailed logging in `extract_schedule`. Test multiple venue pages to understand variations.

### Issue: External IDs colliding

**Solution**: Ensure external ID includes source slug prefix. Use more specific venue identifiers.

## Next Steps After Implementation

1. ✅ Test with `mix [source].test --full --limit 5`
2. ✅ Run full sync: `mix discovery.sync [brand-slug] --limit 10`
3. ✅ Verify events in database
4. ✅ Check admin dashboard shows correct data
5. ✅ Run production sync on schedule (daily/weekly)
6. ✅ Monitor for HTML structure changes

## Reference Implementations

### Simple (Single Timezone)
- **PubQuiz.pl**: Poland-wide, single timezone, HTML scraping
- **SpeedQuizzing**: UK-wide, single timezone

### Complex (Multiple Timezones)
- **Geeks Who Drink**: USA/Canada, multiple timezones, needs timezone mapping
- **QuizMeisters**: Australia, multiple timezones

### International (Multiple Countries)
- **Inquizition**: Multiple countries, needs country + timezone per venue
- **Question One**: Multiple countries

---

**Remember**: Each regional trivia scraper is for a **specific brand operating in known locations**. Hard-coding country/timezone is appropriate and follows the same pattern as city-specific scrapers like Karnet.
