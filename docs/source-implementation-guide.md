# Source Implementation Guide

**Version:** 1.0
**Status:** Proposed Standard
**Last Updated:** 2025-01-23

## Purpose

This guide defines the standard naming conventions, architecture patterns, and implementation requirements for all EventasaurusDiscovery data sources. Following these standards ensures:

- **Predictability:** Developers can navigate any source with familiarity
- **Maintainability:** Consistent patterns reduce cognitive load
- **Tooling:** AI agents and generators can work with predictable structures
- **Monitoring:** Standardized external IDs enable robust monitoring dashboards
- **Testing:** Shared test utilities work across all sources

## Table of Contents

1. [Quick Start: Using the Source Generator](#1-quick-start-using-the-source-generator)
2. [Job Naming Conventions](#2-job-naming-conventions)
3. [External ID Format Specification](#3-external-id-format-specification)
4. [Module Structure Template](#4-module-structure-template)
5. [BaseJob Adoption Pattern](#5-basejob-adoption-pattern)
6. [MetricsTracker Integration](#6-metricstracker-integration)
7. [Testing Requirements](#7-testing-requirements)
8. [Examples](#8-examples)

---

## 1. Quick Start: Using the Source Generator

### Overview

The fastest way to create a new source is using the built-in generator:

```bash
mix discovery.generate_source my_source
```

This command generates a complete source structure following all standards in this guide, including:
- ✅ Standard directory structure
- ✅ Stub modules with TODO comments and examples
- ✅ MetricsTracker integration in all jobs
- ✅ External IDs following the standard format
- ✅ Test files with example test cases
- ✅ BaseJob integration (optional)

### Usage

```bash
# Generate basic source with BaseJob (recommended for most sources)
mix discovery.generate_source my_source

# Generate source with index and detail jobs
mix discovery.generate_source my_source --with-index --with-detail

# Generate source without BaseJob (for custom orchestration)
mix discovery.generate_source my_source --no-base-job

# Force overwrite existing files
mix discovery.generate_source my_source --force
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--base-job` | Use BaseJob behavior for SyncJob | `true` |
| `--no-base-job` | Custom implementation without BaseJob | - |
| `--with-index` | Generate IndexPageJob for pagination | `false` |
| `--with-detail` | Generate EventDetailJob for detail fetching | `false` |
| `--force` | Overwrite existing files | `false` |

### Generated Structure

```
lib/eventasaurus_discovery/sources/my_source/
├── client.ex                 # HTTP client wrapper with examples
├── config.ex                 # Configuration constants
├── transformer.ex            # Raw data → unified format
└── jobs/
    ├── sync_job.ex           # Main orchestration job (BaseJob or custom)
    ├── index_page_job.ex     # Optional: pagination (--with-index)
    └── event_detail_job.ex   # Optional: detail fetching (--with-detail)

test/eventasaurus_discovery/sources/my_source/
├── client_test.exs           # Client tests with examples
├── transformer_test.exs      # Transformer tests
└── jobs/
    └── sync_job_test.exs     # SyncJob tests
```

### Post-Generation Steps

After running the generator, complete these steps:

1. **Update Configuration** (`config.ex`)
   - Set API base URL and authentication details
   - Configure rate limits based on API documentation
   - Set retry settings

2. **Implement HTTP Client** (`client.ex`)
   - Complete the `fetch_events/3` function
   - Add authentication headers
   - Handle pagination if needed
   - Implement error handling

3. **Implement Transformer** (`transformer.ex`)
   - Map raw API data to standardized event format
   - Extract all required fields (title, dates, venue, etc.)
   - Build proper external IDs
   - Add validation and error handling

4. **Complete Job Implementation** (`jobs/sync_job.ex`)
   - **If using BaseJob:** Verify `fetch_events/3` and `transform_events/1` callbacks
   - **If custom:** Implement full sync workflow
   - Test MetricsTracker integration
   - Add any child job enqueueing logic

5. **Write Tests**
   - Add HTTP mocks for client tests
   - Test transformation edge cases
   - Verify job execution and error handling
   - Test MetricsTracker integration

6. **Register Source**
   - Add source to `lib/mix/tasks/discovery.sync.ex`:
     ```elixir
     @sources %{
       # ... existing sources
       "my_source" => EventasaurusDiscovery.Sources.MySource.Jobs.SyncJob
     }
     ```

7. **Test Your Source**
   ```bash
   # Run tests
   mix test test/eventasaurus_discovery/sources/my_source/

   # Test sync with small limit
   mix discovery.sync my_source --limit 10 --inline
   ```

### Generated Code Examples

**Generated SyncJob with BaseJob:**
```elixir
defmodule EventasaurusDiscovery.Sources.MySource.Jobs.SyncJob do
  use EventasaurusDiscovery.Sources.BaseJob

  @impl true
  def fetch_events(from_date, to_date, context) do
    Client.fetch_events(from_date, to_date, context)
  end

  @impl true
  def transform_events(raw_events) do
    Transformer.transform_events(raw_events)
  end

  @impl true
  def source_config do
    %{
      source_slug: Config.source_slug(),
      rate_limit: Config.rate_limit(),
      retry_config: Config.retry_config()
    }
  end
end
```

**Generated Transformer:**
```elixir
defmodule EventasaurusDiscovery.Sources.MySource.Transformer do
  def transform_event(raw_event) do
    %{
      external_id: build_external_id(raw_event),
      title: extract_title(raw_event),
      description: extract_description(raw_event),
      start_time: extract_start_time(raw_event),
      end_time: extract_end_time(raw_event),
      venue: extract_venue(raw_event),
      performers: extract_performers(raw_event),
      categories: extract_categories(raw_event),
      source_url: extract_source_url(raw_event),
      source_data: raw_event
    }
  end

  defp build_external_id(raw_event) do
    # Format: {source}_{type}_{id}_{date}
    source_id = raw_event["id"]
    date = Date.utc_today() |> Date.to_string()
    "my_source_event_#{source_id}_#{date}"
  end
end
```

All generated code includes TODO comments marking areas that need implementation.

---

## 2. Job Naming Conventions

### 8.1 Naming Pattern

**Rule:** All job modules MUST follow the pattern:

```
EventasaurusDiscovery.Sources.{SourceSlug}.Jobs.{JobType}Job
```

**File naming:** Convert to snake_case for file names:

```
lib/eventasaurus_discovery/sources/{source_slug}/jobs/{job_type}_job.ex
```

### 8.2 Standard Job Types

Job types MUST be one of the following (in typical execution order):

| Job Type | Purpose | Required | File Name |
|----------|---------|----------|-----------|
| **SyncJob** | Coordinator/orchestrator for entire source | ✅ YES | `sync_job.ex` |
| **IndexPageJob** | Fetches index/listing pages (with pagination) | Optional | `index_page_job.ex` |
| **IndexJob** | Fetches single index (no pagination) | Optional | `index_job.ex` |
| **EventDetailJob** | Event-specific detail fetcher | Optional | `event_detail_job.ex` |
| **VenueDetailJob** | Venue-specific detail fetcher | Optional | `venue_detail_job.ex` |
| **PerformerDetailJob** | Performer/artist-specific detail fetcher | Optional | `performer_detail_job.ex` |
| **EnrichmentJob** | Post-processing enrichment (metadata, images, etc.) | Optional | `enrichment_job.ex` |

### 8.3 Migration from Legacy Names

| ❌ Legacy Name | ✅ Standard Name | Reason |
|---------------|-----------------|---------|
| `index_job.ex` | `index_page_job.ex` | Clarifies pagination support |
| `artist_detail_job.ex` | `performer_detail_job.ex` | Consistent terminology (performers includes artists, DJs, comedians) |
| `movie_detail_job.ex` | `event_detail_job.ex` | Align with domain model (movies are events) |

**Note:** Sources with domain-specific terminology (e.g., `MoviePageJob` for Cinema City) MAY keep their names if they provide clear abstraction over the standard pattern.

### 8.4 Examples

✅ **Correct:**
```
EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob
EventasaurusDiscovery.Sources.Karnet.Jobs.VenueDetailJob
EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.PerformerDetailJob
```

❌ **Incorrect:**
```
EventasaurusDiscovery.Sources.CinemaCity.Jobs.cinema_city_sync  (lowercase, wrong pattern)
EventasaurusDiscovery.Sources.Karnet.Jobs.VenueJob              (missing "Detail")
EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.ArtistDetailJob  (should be PerformerDetailJob)
```

---

## 3. External ID Format Specification

### 8.1 Format

External IDs MUST follow the pattern:

```
{source_slug}_{job_type}_{entity_id}_{date}
```

**Components:**
- `source_slug`: Source identifier (snake_case, e.g., `cinema_city`, `week_pl`)
- `job_type`: Job classification (snake_case, e.g., `sync`, `venue`, `event`, `performer`)
- `entity_id`: Entity identifier (optional, use for detail jobs)
- `date`: ISO 8601 date with **hyphens** (e.g., `2025-01-23`)

### 8.2 Rules

1. **Date Format:** MUST use hyphens (`2025-01-23`), NOT underscores (`2025_01_23`)
2. **Entity ID:** Optional for coordinator jobs (SyncJob), REQUIRED for detail jobs
3. **Separator:** Components MUST be separated by single underscore `_`
4. **Uniqueness:** External ID should be unique per job execution within a reasonable time window
5. **No URLs:** Do NOT use full URLs as external IDs
6. **No Special Characters:** Avoid spaces, slashes, or other special characters

### 8.3 Examples by Job Type

**SyncJob (no entity ID):**
```
cinema_city_sync_2025-01-23
karnet_sync_2025-01-23
week_pl_sync_2025-01-23
```

**VenueDetailJob (with entity ID):**
```
cinema_city_venue_12345_2025-01-23
karnet_venue_warszawa-centralna_2025-01-23
```

**EventDetailJob (with entity ID):**
```
resident_advisor_event_abc123_2025-01-23
sortiraparis_article_98765_2025-01-23
```

**PerformerDetailJob (with entity ID):**
```
resident_advisor_performer_dj-smith_2025-01-23
bandsintown_performer_789456_2025-01-23
```

### 8.4 Benefits

- ✅ **Parseable:** Easy to extract source, job type, entity, and date
- ✅ **Sortable:** Chronological sorting works naturally
- ✅ **Filterable:** Monitor dashboards can filter by any component
- ✅ **Readable:** Human-friendly format for debugging
- ✅ **Searchable:** Easy to find specific job executions

---

## 4. Module Structure Template

### 8.1 Standard Directory Layout

Every source MUST follow this structure:

```
lib/eventasaurus_discovery/sources/{source_slug}/
├── client.ex                    # HTTP client wrapper (REQUIRED)
├── config.ex                    # Configuration constants (REQUIRED)
├── transformer.ex               # Raw → unified format (REQUIRED)
├── source.ex                    # Source metadata/config (OPTIONAL)
├── extractors/                  # HTML/JSON parsing (if needed)
│   ├── index_extractor.ex
│   ├── detail_extractor.ex
│   └── showtime_extractor.ex
├── jobs/                        # Oban workers (REQUIRED)
│   ├── sync_job.ex              # REQUIRED
│   ├── index_page_job.ex
│   ├── event_detail_job.ex
│   └── venue_detail_job.ex
└── helpers/                     # Source-specific utilities (if needed)
    ├── url_filter.ex
    └── date_parser.ex
```

### 8.2 Core Modules

#### Client Module

**Purpose:** HTTP client wrapper with rate limiting and error handling

**Required Functions:**
```elixir
@spec fetch_index(map()) :: {:ok, binary()} | {:error, term()}
@spec fetch_detail(String.t(), map()) :: {:ok, binary()} | {:error, term()}
```

**Pattern:**
```elixir
defmodule EventasaurusDiscovery.Sources.{SourceSlug}.Client do
  @moduledoc """
  HTTP client for {Source Name} API/website.

  Handles rate limiting, authentication, and error responses.
  """

  use Tesla
  require Logger

  plug Tesla.Middleware.BaseUrl, "https://api.source.com"
  plug Tesla.Middleware.Headers, [{"user-agent", "Eventasaurus/1.0"}]
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Retry, max_retries: 3, delay: 1_000

  @rate_limit_ms 1_000  # 1 request per second

  def fetch_index(opts \\ %{}) do
    :timer.sleep(@rate_limit_ms)

    case get("/events", query: opts) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

#### Config Module

**Purpose:** Configuration constants and source metadata

**Required Constants:**
```elixir
@source_slug :: String.t()
@source_name :: String.t()
@base_url :: String.t()
@rate_limit_ms :: integer()
```

**Pattern:**
```elixir
defmodule EventasaurusDiscovery.Sources.{SourceSlug}.Config do
  @moduledoc """
  Configuration constants for {Source Name}.
  """

  @source_slug "{source_slug}"
  @source_name "{Source Display Name}"
  @base_url "https://source.com"
  @rate_limit_ms 1_000

  def source_slug, do: @source_slug
  def source_name, do: @source_name
  def base_url, do: @base_url
  def rate_limit_ms, do: @rate_limit_ms

  # Source-specific constants
  @default_limit 100
  @max_retries 3

  def default_limit, do: @default_limit
  def max_retries, do: @max_retries
end
```

#### Transformer Module

**Purpose:** Transform raw source data into standardized event format

**Required Function:**
```elixir
@spec transform(map()) :: EventasaurusDiscovery.Event.t()
```

**Pattern:**
```elixir
defmodule EventasaurusDiscovery.Sources.{SourceSlug}.Transformer do
  @moduledoc """
  Transforms {Source Name} raw data to Eventasaurus event format.
  """

  alias EventasaurusDiscovery.Event

  def transform(raw_event) do
    %Event{
      title: extract_title(raw_event),
      description: extract_description(raw_event),
      starts_at: parse_datetime(raw_event["start_time"]),
      ends_at: parse_datetime(raw_event["end_time"]),
      venue_name: raw_event["venue"],
      external_id: build_external_id(raw_event),
      source_url: raw_event["url"],
      metadata: %{
        "source" => Config.source_slug(),
        "raw_id" => raw_event["id"]
      }
    }
  end

  defp build_external_id(event) do
    "#{Config.source_slug()}_event_#{event["id"]}_#{Date.utc_today()}"
  end

  # ... helper functions
end
```

---

## 5. BaseJob Adoption Pattern

### 8.1 When to Use BaseJob

**Use BaseJob when:**
- ✅ Job is a **SyncJob** coordinator
- ✅ Job follows simple fetch → transform → process pattern
- ✅ Job doesn't require complex orchestration logic
- ✅ Job processes city-specific data

**DO NOT use BaseJob when:**
- ❌ Job requires complex orchestration (use plain `Oban.Worker`)
- ❌ Job needs custom perform/1 logic with branching
- ❌ Job is a detail job (EventDetailJob, VenueDetailJob, etc.)

### 8.2 BaseJob Implementation

**Minimal Example:**
```elixir
defmodule EventasaurusDiscovery.Sources.ExampleSource.Jobs.SyncJob do
  @moduledoc """
  Coordinator job for ExampleSource integration.

  Fetches events for a city and processes them using BaseJob behavior.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3,
    priority: 1

  alias EventasaurusDiscovery.Sources.ExampleSource.{Client, Transformer, Config}

  # Required callback: Fetch raw events from source
  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, options) do
    case Client.fetch_events(city.name, limit: limit) do
      {:ok, events} ->
        {:ok, events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Required callback: Transform raw events to standard format
  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    Enum.map(raw_events, &Transformer.transform/1)
  end

  # Required callback: Source configuration
  def source_config do
    %{
      name: Config.source_name(),
      slug: Config.source_slug(),
      website_url: Config.base_url()
    }
  end
end
```

### 8.3 Override perform/1 When Needed

**When to override:** Complex orchestration that doesn't fit BaseJob pattern

**Example:**
```elixir
defmodule EventasaurusDiscovery.Sources.ComplexSource.Jobs.SyncJob do
  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  # Override perform for custom orchestration
  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "complex_source_sync_#{Date.utc_today()}"

    # Custom logic here
    result = case check_preconditions() do
      {:ok, :can_proceed} ->
        # Use BaseJob pattern via super
        super(job)

      {:skip, reason} ->
        Logger.info("Skipping sync: #{reason}")
        {:ok, %{status: "skipped", reason: reason}}
    end

    # Track metrics
    case result do
      {:ok, _} -> MetricsTracker.record_success(job, external_id)
      {:error, reason} -> MetricsTracker.record_failure(job, reason, external_id)
    end

    result
  end

  # Still implement required callbacks for consistency
  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, options), do: # ...

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events), do: # ...
end
```

---

## 6. MetricsTracker Integration

### 8.1 Required Integration

**Every job MUST integrate MetricsTracker for monitoring:**

```elixir
alias EventasaurusDiscovery.Metrics.MetricsTracker

def perform(%Oban.Job{} = job) do
  # Build external ID following standard format
  external_id = "{source}_{job_type}_{entity_id}_#{Date.utc_today()}"

  result = # ... job logic

  # Track metrics based on result
  case result do
    {:ok, data} ->
      MetricsTracker.record_success(job, external_id)
      result

    {:error, reason} ->
      MetricsTracker.record_failure(job, reason, external_id)
      result
  end
end
```

### 8.2 Error Categorization

**MetricsTracker.record_failure/3** supports error categorization:

**Standard Error Categories:**
```elixir
:network_error        # HTTP errors, timeouts, connection failures
:validation_error     # Data validation failures
:geocoding_error      # Geocoding service failures
:venue_error          # Venue matching/creation failures
:performer_error      # Performer matching/creation failures
:category_error       # Event categorization failures
:duplicate_error      # Duplicate detection issues
:data_quality_error   # Missing/invalid data from source
:unknown_error        # Uncategorized errors
```

**Usage Example:**
```elixir
case fetch_and_process() do
  {:ok, result} ->
    MetricsTracker.record_success(job, external_id)
    {:ok, result}

  {:error, %HTTPError{} = reason} ->
    MetricsTracker.record_failure(job, reason, external_id, :network_error)
    {:error, reason}

  {:error, %ValidationError{} = reason} ->
    MetricsTracker.record_failure(job, reason, external_id, :validation_error)
    {:error, reason}

  {:error, reason} ->
    MetricsTracker.record_failure(job, reason, external_id, :unknown_error)
    {:error, reason}
end
```

---

## 7. Testing Requirements

### 8.1 Required Tests

Every source MUST include:

1. **Client Tests**
   - HTTP request formatting
   - Rate limiting behavior
   - Error handling (404, 500, timeout)
   - Response parsing

2. **Transformer Tests**
   - Valid input → correct output mapping
   - Missing field handling
   - Date/time parsing edge cases
   - External ID format validation

3. **Job Integration Tests**
   - Successful execution flow
   - Error handling and retry behavior
   - MetricsTracker integration
   - External ID format compliance

### 8.2 Test Structure

```
test/eventasaurus_discovery/sources/{source_slug}/
├── client_test.exs
├── transformer_test.exs
└── jobs/
    ├── sync_job_test.exs
    └── event_detail_job_test.exs
```

### 8.3 External ID Test Example

```elixir
defmodule EventasaurusDiscovery.Sources.ExampleSource.Jobs.SyncJobTest do
  use EventasaurusApp.DataCase, async: true

  describe "external ID format" do
    test "follows standard format for sync job" do
      job = %Oban.Job{args: %{}}
      external_id = SyncJob.build_external_id(job)

      # Format: {source}_{type}_{date}
      assert external_id =~ ~r/^example_source_sync_\d{4}-\d{2}-\d{2}$/
    end

    test "uses hyphens in date, not underscores" do
      job = %Oban.Job{args: %{}}
      external_id = SyncJob.build_external_id(job)

      # Should be 2025-01-23, not 2025_01_23
      refute external_id =~ ~r/\d{4}_\d{2}_\d{2}/
    end
  end
end
```

---

## 8. Examples

### 8.1 Complete Source Example (Simple)

**Directory structure:**
```
lib/eventasaurus_discovery/sources/simple_source/
├── client.ex
├── config.ex
├── transformer.ex
└── jobs/
    └── sync_job.ex
```

**SyncJob (using BaseJob):**
```elixir
defmodule EventasaurusDiscovery.Sources.SimpleSource.Jobs.SyncJob do
  @moduledoc """
  Coordinator job for SimpleSource event synchronization.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  alias EventasaurusDiscovery.Sources.SimpleSource.{Client, Config, Transformer}

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, _options) do
    Client.fetch_events(%{
      city: city.name,
      limit: limit
    })
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    Enum.map(raw_events, &Transformer.transform/1)
  end

  def source_config do
    %{
      name: Config.source_name(),
      slug: Config.source_slug(),
      website_url: Config.base_url()
    }
  end
end
```

### 8.2 Complete Source Example (Complex)

**Directory structure:**
```
lib/eventasaurus_discovery/sources/complex_source/
├── client.ex
├── config.ex
├── transformer.ex
├── extractors/
│   ├── index_extractor.ex
│   └── detail_extractor.ex
└── jobs/
    ├── sync_job.ex
    ├── index_page_job.ex
    └── event_detail_job.ex
```

**SyncJob (custom orchestration):**
```elixir
defmodule EventasaurusDiscovery.Sources.ComplexSource.Jobs.SyncJob do
  @moduledoc """
  Coordinator job that orchestrates index and detail jobs.
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3

  require Logger
  alias EventasaurusDiscovery.Sources.ComplexSource.Jobs.IndexPageJob
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "complex_source_sync_#{Date.utc_today()}"
    city_id = args["city_id"]

    Logger.info("Starting ComplexSource sync for city #{city_id}")

    result = schedule_index_jobs(city_id, job.id)

    case result do
      {:ok, jobs_count} ->
        Logger.info("Scheduled #{jobs_count} index jobs")
        MetricsTracker.record_success(job, external_id)
        {:ok, %{jobs_scheduled: jobs_count}}

      {:error, reason} ->
        Logger.error("Failed to schedule jobs: #{inspect(reason)}")
        MetricsTracker.record_failure(job, reason, external_id, :unknown_error)
        {:error, reason}
    end
  end

  defp schedule_index_jobs(city_id, parent_job_id) do
    # Schedule 7 days of index jobs
    jobs = for day_offset <- 0..6 do
      date = Date.add(Date.utc_today(), day_offset)

      %{
        "city_id" => city_id,
        "date" => Date.to_iso8601(date)
      }
      |> IndexPageJob.new(meta: %{parent_job_id: parent_job_id})
      |> Oban.insert()
    end

    case Enum.filter(jobs, fn {:error, _} -> true; _ -> false end) do
      [] -> {:ok, length(jobs)}
      errors -> {:error, "#{length(errors)} jobs failed to schedule"}
    end
  end
end
```

---

## 9. Migration Guide

### 8.1 Renaming Jobs

**Steps:**
1. Create new file with standard name
2. Copy implementation from old file
3. Update module name
4. Update all references in other modules
5. Run tests
6. Delete old file
7. Commit with clear message

**Example commit message:**
```
refactor(sources): rename Inquizition index_job → index_page_job

Standardizes job naming to follow source implementation guide.

- Renamed: index_job.ex → index_page_job.ex
- Updated module: Inquizition.Jobs.IndexJob → Inquizition.Jobs.IndexPageJob
- Updated references in: sync_job.ex, tests
- All tests passing ✅

Part of #2366 Phase 3
```

### 8.2 Standardizing External IDs

**Steps:**
1. Audit current external ID format in job file
2. Update external ID generation to follow standard format
3. Update tests to verify format
4. Run job in staging and verify monitoring dashboard
5. Deploy to production
6. Monitor for 24 hours

**Migration script** (if needed to update historical data):
```sql
-- Update job_execution_summaries with standardized external IDs
UPDATE job_execution_summaries
SET external_id = REPLACE(external_id, '_', '-')
WHERE worker LIKE 'EventasaurusDiscovery.Sources.%'
AND external_id ~ '\d{4}_\d{2}_\d{2}';  -- Find underscore dates
```

---

## 10. Checklist for New Sources

Use this checklist when implementing a new source:

- [ ] **Directory Structure**
  - [ ] Created `lib/eventasaurus_discovery/sources/{source_slug}/`
  - [ ] Created `client.ex`, `config.ex`, `transformer.ex`
  - [ ] Created `jobs/sync_job.ex`
  - [ ] Created additional job files as needed

- [ ] **Naming Conventions**
  - [ ] All job files follow `{job_type}_job.ex` pattern
  - [ ] Module names follow `{SourceSlug}.Jobs.{JobType}Job`
  - [ ] External IDs follow `{source}_{type}_{id}_{date}` format
  - [ ] Dates use hyphens, not underscores

- [ ] **BaseJob Integration**
  - [ ] SyncJob uses BaseJob (if applicable)
  - [ ] Implemented `fetch_events/3` callback
  - [ ] Implemented `transform_events/1` callback
  - [ ] Implemented `source_config/0` function

- [ ] **MetricsTracker Integration**
  - [ ] All jobs call `MetricsTracker.record_success/2`
  - [ ] All jobs call `MetricsTracker.record_failure/3` with error category
  - [ ] External IDs are consistent across job and metrics

- [ ] **Testing**
  - [ ] Client tests with HTTP mocking
  - [ ] Transformer tests with fixtures
  - [ ] Job integration tests
  - [ ] External ID format tests

- [ ] **Documentation**
  - [ ] Module @moduledoc explains purpose
  - [ ] Complex functions have @doc
  - [ ] Source added to `docs/ADDING_NEW_SOURCES.md`

- [ ] **Code Review**
  - [ ] Follows Elixir style guide
  - [ ] No hardcoded credentials
  - [ ] Rate limiting implemented
  - [ ] Error handling comprehensive

---

## 11. Architecture Decision Records (ADRs)

### ADR-001: Job Naming Convention

**Status:** Proposed
**Date:** 2025-01-23

**Decision:** Use `{JobType}Job` pattern for all job modules

**Context:**
- Legacy sources use inconsistent naming (`index_job` vs `index_page_job`)
- Module names should follow Elixir conventions (PascalCase)
- Need predictable naming for AI tooling and generators

**Consequences:**
- Requires renaming ~5 job files across sources
- Improves consistency and developer experience
- Enables better tooling and automation

**Alternatives Considered:**
1. Keep legacy names → Rejected (inconsistent)
2. Use `Job{JobType}` suffix → Rejected (non-idiomatic)

---

### ADR-002: External ID Format

**Status:** Proposed
**Date:** 2025-01-23

**Decision:** Use `{source}_{type}_{id}_{date}` format with hyphenated dates

**Context:**
- Current external IDs are inconsistent (URLs, underscored dates, etc.)
- Monitoring dashboards need parseable IDs
- Need unique identifiers for job execution tracking

**Consequences:**
- May require migration script for historical data
- All new sources must follow format
- Enables better filtering and searching in dashboards

**Alternatives Considered:**
1. Use UUIDs → Rejected (not human-readable)
2. Use ISO 8601 timestamps → Rejected (too verbose)
3. Use full URLs → Rejected (not parseable)

---

### ADR-003: BaseJob Adoption

**Status:** Proposed
**Date:** 2025-01-23

**Decision:** All SyncJob files should use BaseJob behavior when applicable

**Context:**
- Reduces code duplication across sources
- Enforces consistent patterns (fetch → transform → process)
- Simplifies testing and maintenance

**Consequences:**
- Sources with complex orchestration may override `perform/1`
- Requires documentation of when to use vs. when to override
- Reduces boilerplate for simple sources

**Alternatives Considered:**
1. No shared behavior → Rejected (too much duplication)
2. Require BaseJob for ALL jobs → Rejected (too restrictive)
3. Create separate coordinators → Rejected (adds complexity)

---

## Related Documentation

- [ADDING_NEW_SOURCES.md](./ADDING_NEW_SOURCES.md) - Step-by-step guide for new sources
- [SCRAPER_MANIFESTO.md](./SCRAPER_MANIFESTO.md) - High-level scraper philosophy
- [scraper-monitoring-guide.md](./scraper-monitoring-guide.md) - Monitoring and metrics
- [SCRAPER_QUALITY_GUIDELINES.md](./SCRAPER_QUALITY_GUIDELINES.md) - Code quality standards

---

**Questions or Feedback?** Open a GitHub issue with label `documentation` or `source-implementation`.
