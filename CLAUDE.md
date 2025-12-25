# Eventasaurus Development Guide

## ⚠️ CRITICAL: GIT WORKFLOW RULES

**DO NOT USE GIT COMMANDS** unless explicitly requested by the user.

### Why This Matters

This project uses **Graphite** for stacked diffs and branch management. When Claude Code commits directly using `git commit`, it creates conflicts with the Graphite workflow and breaks the stack.

### What You Should Do

1. **Make code changes only** - Edit files, run tests, implement features
2. **Let the user handle git** - They will commit and manage branches using Graphite
3. **Report what you changed** - Summarize the files modified and changes made
4. **Suggest commit messages** - Provide a commit message template the user can use

### When Git Commands Are OK

- **NEVER** use `git commit`
- **NEVER** use `git add`
- **NEVER** use `git push`
- **NEVER** use `git branch`
- **NEVER** use `git merge`
- **NEVER** use `git rebase`

You MAY use read-only git commands if needed:
- `git status` - Check current state
- `git diff` - View changes
- `git log` - View history
- `git show` - View specific commits

## Project Overview

Eventasaurus is an Elixir/Phoenix application that aggregates events from multiple sources using a scraper-based architecture. The project uses:

- **Elixir/Phoenix** - Main web framework
- **Oban** - Background job processing
- **PostgreSQL** - Database with PostGIS for location data
- **LiveView** - Real-time UI components
- **Graphite** - Stacked diff workflow for git

## Key Directories

```
eventasaurus/
├── lib/
│   ├── eventasaurus/              # Core domain logic
│   ├── eventasaurus_app/          # Phoenix app layer
│   ├── eventasaurus_discovery/    # Scraper & monitoring systems
│   │   ├── sources/               # Individual scraper sources
│   │   ├── monitoring/            # Monitoring API modules
│   │   └── metrics/               # MetricsTracker & error categories
│   └── eventasaurus_web/          # Web interface (LiveView, controllers)
├── lib/mix/tasks/                 # Mix CLI tasks
├── test/                          # Test files
└── docs/                          # Documentation guides
```

## Development Workflow

### Running the Application

```bash
# Start Phoenix server
mix phx.server

# Run in IEx console
iex -S mix phx.server

# Run tests
mix test

# Run specific test file
mix test test/path/to/test_file.exs

# Format code
mix format

# Run database migrations
mix ecto.migrate
```

### Common Mix Tasks

```bash
# Database operations
mix ecto.setup              # Create and migrate database
mix ecto.reset              # Drop, create, and migrate database
mix ecto.migrate            # Run migrations
mix ecto.rollback           # Rollback last migration

# Code quality
mix format                  # Format all Elixir files
mix compile --warnings-as-errors  # Strict compilation

# Background jobs (Oban)
# Jobs run automatically in development, or trigger manually via IEx
```

## Scraper Monitoring System

Eventasaurus includes comprehensive monitoring for all scrapers. This system tracks performance, errors, health, and job chains.

### Job Execution Monitoring (mix monitor.jobs)

Real-time job execution monitoring with formatted CLI output:

```bash
# List recent executions (default: 50)
mix monitor.jobs list
mix monitor.jobs list --limit 100

# Filter by state
mix monitor.jobs list --state failure
mix monitor.jobs list --state success

# Filter by source
mix monitor.jobs list --source week_pl
mix monitor.jobs list --source bandsintown --limit 20

# Show recent failures with error details
mix monitor.jobs failures
mix monitor.jobs failures --limit 50
mix monitor.jobs failures --source karnet

# Show execution statistics
mix monitor.jobs stats                    # Last 24 hours
mix monitor.jobs stats --hours 168        # Last week
mix monitor.jobs stats --source week_pl   # Source-specific

# Filter by worker type
mix monitor.jobs worker SyncJob
mix monitor.jobs worker EventDetailJob --state failure
```

**Output Format:**
```text
Recent Job Executions:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Source               Worker               State      Duration   Started At
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
week_pl              SyncJob              success    1.2s       2025-01-23 10:30:00
resident_advisor     SyncJob              failure    0.5s       2025-01-23 10:29:00
pubquiz              RegionSyncJob        success    2.3s       2025-01-23 10:28:00

Summary:
  Total: 50
  Success: 45
  Failures: 5
  Success Rate: 90.0%
  Avg Duration: 1.45s
```

### Performance & Error Analysis (mix monitor.*)

Advanced monitoring tools for baseline tracking and error analysis:

```bash
# Create performance baseline
mix monitor.baseline cinema_city --hours=24 --limit=100 --save

# Analyze error patterns
mix monitor.errors cinema_city --hours=48 --category=network_error

# Check health and SLO compliance
mix monitor.health cinema_city --hours=24 --threshold=90

# Analyze job execution chains
mix monitor.chain cinema_city --limit=5 --failed-only

# Compare two baselines
mix monitor.compare --before=baseline1.json --after=baseline2.json

# Monitor collision/deduplication metrics
mix monitor.collisions stats                       # Show statistics (default: last 24h)
mix monitor.collisions stats --hours 168           # Last week
mix monitor.collisions list --source cinema_city   # Recent collisions by source
mix monitor.collisions list --type cross_source    # Filter by collision type
mix monitor.collisions matrix                      # Cross-source overlap matrix
mix monitor.collisions confidence                  # Confidence score distribution
```

### Programmatic API (Elixir Code)

All monitoring functionality is available as a programmatic API in `EventasaurusDiscovery.Monitoring.*`:

#### Baseline Creation & Management

```elixir
alias EventasaurusDiscovery.Monitoring.Baseline

# Create baseline for a source
{:ok, baseline} = Baseline.create("cinema_city", hours: 24, limit: 100)
# Returns: %{
#   source: "cinema_city",
#   period_start: ~U[...],
#   period_end: ~U[...],
#   sample_size: 98,
#   success_rate: 91.8,
#   avg_duration: 1238.5,
#   p50: 850.0,
#   p95: 2100.0,
#   p99: 3500.0,
#   ...
# }

# Save baseline to file
{:ok, filepath} = Baseline.save(baseline, "cinema_city")
# Saves to: .taskmaster/baselines/cinema_city_20241123.json

# Load baseline from file
{:ok, baseline} = Baseline.load(".taskmaster/baselines/cinema_city_20241123.json")
```

#### Error Analysis

```elixir
alias EventasaurusDiscovery.Monitoring.Errors

# Analyze errors for a source
{:ok, analysis} = Errors.analyze("cinema_city", hours: 24, limit: 20)

# Get summary statistics
summary = Errors.summary(analysis)
# Returns: %{
#   total_failures: 14,
#   total_executions: 127,
#   error_rate: 11.0,
#   top_category: "network_error",
#   unique_error_types: 5
# }

# Get top error messages
top_errors = Errors.top_messages(analysis, 5)

# Get recommendations for each error category
recommendations = Errors.recommendations(analysis)
# Returns: %{
#   "network_error" => "Consider implementing retry logic with exponential backoff",
#   "validation_error" => "Add upstream validation before processing"
# }
```

#### Health Monitoring & SLO Tracking

```elixir
alias EventasaurusDiscovery.Monitoring.Health

# Check health for a source
{:ok, health} = Health.check("cinema_city", hours: 24)

# Calculate overall health score (0-100)
score = Health.score(health)  # => 95.7

# Check if meeting SLOs (95% success rate, 3000ms P95)
meeting_slos? = Health.meeting_slos?(health)  # => true

# Find degraded workers
degraded = Health.degraded_workers(health, threshold: 90.0)
# Returns: [{"MovieDetailJob", 85.2}, {"ShowtimeProcessJob", 88.1}]

# Get recent failures for investigation
failures = Health.recent_failures(health, limit: 5)
```

#### Job Chain Analysis

```elixir
alias EventasaurusDiscovery.Monitoring.Chain

# Analyze specific job execution chain
{:ok, chain} = Chain.analyze_job(12345)

# Get recent chains for a source
{:ok, chains} = Chain.recent_chains("cinema_city", limit: 5, failed_only: true)

# Calculate chain statistics
stats = Chain.statistics(chain)
# Returns: %{
#   total: 10,
#   completed: 8,
#   failed: 2,
#   success_rate: 80.0,
#   cascade_failures: [...]
# }

# Find cascade failures (parent failures blocking children)
cascades = Chain.cascade_failures(chain)

# Calculate total cascade impact
impact = Chain.cascade_impact(chain)  # => 15 jobs prevented
```

#### Baseline Comparison

```elixir
alias EventasaurusDiscovery.Monitoring.Compare

# Compare two baseline files
{:ok, comparison} = Compare.from_files(
  ".taskmaster/baselines/cinema_city_20241122.json",
  ".taskmaster/baselines/cinema_city_20241123.json"
)

# Get summary of changes
summary = Compare.summary(comparison)
# Returns: %{
#   success_rate_change: 2.3,
#   avg_duration_change: -150.0,
#   improved: true,
#   regression_count: 0
# }

# Check if performance improved
improved? = Compare.improved?(comparison)  # => true

# Get jobs that improved/regressed
improved_jobs = Compare.improved_jobs(comparison)
regressed_jobs = Compare.regressed_jobs(comparison)
```

### Supported Sources

All monitoring tools support these scrapers:
- `cinema_city` - Cinema City scraper
- `kino_krakow` - Kino Krakow scraper
- `karnet` - Karnet scraper
- `week_pl` - Week.pl scraper
- `bandsintown` - Bandsintown scraper
- `resident_advisor` - Resident Advisor scraper
- `sortiraparis` - Sortiraparis scraper
- `inquizition` - Inquizition scraper
- `waw4free` - Waw4Free scraper

### SLO Targets

Default Service Level Objectives:
- **Success Rate**: 95% of executions should complete successfully
- **P95 Duration**: 95th percentile duration should be under 3000ms

### Common Monitoring Workflows

#### Debugging Performance Issues

```elixir
# 1. Check current health
{:ok, health} = Health.check("cinema_city", hours: 24)

# 2. Identify degraded workers
degraded = Health.degraded_workers(health, threshold: 85.0)

# 3. Analyze errors for the source
{:ok, analysis} = Errors.analyze("cinema_city", hours: 24)
top_errors = Errors.top_messages(analysis, 10)

# 4. Check job chains for cascade failures
{:ok, chains} = Chain.recent_chains("cinema_city", limit: 10, failed_only: true)
Enum.each(chains, fn chain ->
  cascades = Chain.cascade_failures(chain)
  IO.inspect(cascades, label: "Cascade failures")
end)
```

#### Measuring Performance Improvements

```elixir
# 1. Create baseline before changes
{:ok, before} = Baseline.create("cinema_city", hours: 24)
Baseline.save(before, "cinema_city_before")

# ... make code changes ...

# 2. Create baseline after changes
{:ok, after_baseline} = Baseline.create("cinema_city", hours: 24)
Baseline.save(after_baseline, "cinema_city_after")

# 3. Compare baselines
{:ok, comparison} = Compare.from_files(
  ".taskmaster/baselines/cinema_city_before.json",
  ".taskmaster/baselines/cinema_city_after.json"
)

summary = Compare.summary(comparison)
IO.inspect(summary)

# 4. Check for regressions
if Compare.has_regressions?(comparison) do
  IO.puts("⚠️  Regressions detected!")
  IO.inspect(comparison.regressions)
end
```

## Scraper Audit Tools (mix audit.*)

Tools for auditing scraper completeness and data quality. These verify that scrapers are running correctly and capturing complete data.

### Scheduler Health Check (mix audit.scheduler_health)

Verifies that scrapers are running daily and identifies gaps or failures:

```bash
# Check last 7 days (default)
mix audit.scheduler_health

# Check specific number of days
mix audit.scheduler_health --days 14

# Check specific source only
mix audit.scheduler_health --source cinema_city
mix audit.scheduler_health --source repertuary
```

**Output includes:**
- Day-by-day breakdown of SyncJob executions
- Execution status (success/failure)
- Duration and jobs spawned
- Alerts for missing days or failures
- Recommendations for fixing issues

### Date Coverage Report (mix audit.date_coverage)

Verifies that scrapers are creating events for the expected date range (7 days ahead):

```bash
# Check default 7-day coverage
mix audit.date_coverage

# Check specific number of days ahead
mix audit.date_coverage --days 14

# Check specific source only
mix audit.date_coverage --source cinema_city
mix audit.date_coverage --source repertuary
```

**Output includes:**
- Day-by-day event counts with visual coverage bars
- Status indicators (OK, LOW, MISSING)
- Coverage percentage per day
- Alerts for missing or low-coverage dates

## Data Maintenance Tasks

Tasks for fixing data quality issues and cleaning up corrupted data.

### Fix Cinema City Duplicate Film IDs

Fixes duplicate `cinema_city_film_id` entries in the movies table that can occur due to race conditions:

```bash
# Dry run - show what would be fixed (no changes)
mix fix_cinema_city_duplicates

# Actually apply the fixes
mix fix_cinema_city_duplicates --apply
```

**What it does:**
1. Finds all `cinema_city_film_id` values that appear on multiple movies
2. For each duplicate group, keeps the OLDEST movie's film_id (first created)
3. Removes `cinema_city_film_id` from the NEWER movies

The affected movies will get correctly re-matched on the next scraper run.

**Production usage** (via release task):
```bash
# Dry run
bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates()"

# Apply fixes
bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates(true)"
```

### Fix Orphaned Events

Fixes orphaned events - events in `public_events` with no corresponding `public_event_sources` record. These orphans are created when the Ecto.Multi transaction partially fails. See GitHub issue #2897 for root cause analysis.

```bash
# Dry run - show orphans that would be deleted
mix fix_orphan_events

# Show detailed info about each orphan
mix fix_orphan_events --verbose

# Actually delete the orphans
mix fix_orphan_events --apply
```

**What it does:**
1. Identifies all events with no corresponding `public_event_sources` record
2. Shows breakdown by likely source (Cinema City, Repertuary, PubQuiz, etc.)
3. Deletes these orphan events (they have no value without source attribution)

**Production usage** (via release task):
```bash
# Dry run
bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_orphan_events()"

# Apply fixes
bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_orphan_events(true)"
```

## Implementing Scraper Monitoring

When adding monitoring to scrapers, follow the patterns in `docs/scraper-monitoring-guide.md`:

### Basic Pattern

```elixir
defmodule MyApp.Sources.MySource.Jobs.MyJob do
  use Oban.Worker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    external_id = "my_source_sync_#{Date.utc_today()}"

    case fetch_and_process_data() do
      {:ok, result} ->
        MetricsTracker.record_success(job, external_id)
        {:ok, result}

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        {:error, reason}
    end
  end
end
```

### Error Categories

The system recognizes 9 standard error categories (see `lib/eventasaurus_discovery/metrics/error_categories.ex`):
- `validation_error` - Missing/invalid required fields
- `geocoding_error` - Address/location resolution failures
- `venue_error` - Venue lookup/creation issues
- `performer_error` - Performer/artist matching problems
- `category_error` - Event categorization failures
- `duplicate_error` - Duplicate event detection
- `network_error` - HTTP timeouts, API failures
- `data_quality_error` - Unexpected data format, parsing issues
- `unknown_error` - Uncategorized failures

## Testing

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/eventasaurus_discovery/monitoring/baseline_test.exs

# Run tests with coverage
mix test --cover

# Run tests matching a pattern
mix test --only tag_name
```

### Testing Monitoring Integration

```elixir
defmodule MyApp.MyJobTest do
  use Eventasaurus.DataCase, async: true
  import Oban.Testing

  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  test "records validation_error for missing required fields" do
    job = insert(:oban_job, worker: "MyJob", args: %{"invalid" => true})

    assert {:error, _} = MyJob.perform(job)

    # Verify error tracked
    summary = Repo.get_by(JobExecutionSummary, job_id: job.id)
    assert summary.results["error_category"] == "validation_error"
  end
end
```

## Admin Dashboards

The application includes several admin dashboards for monitoring:

- `/admin/job-executions` - View all job executions with filtering
- `/admin/error-trends` - Error rate trends and analysis
- `/admin/oban` - Oban job queue dashboard
- `/admin/discovery-dashboard` - Scraper discovery statistics

## Database Access

### Production Database (PlanetScale)

**IMPORTANT**: Production database is hosted on PlanetScale (PostgreSQL), NOT Fly.io.

- **Organization**: `razrfly`
- **Database**: `wombie`
- **Branch**: `main`

Use MCP PlanetScale tools for production queries:
```
mcp__planetscale__run_query with org="razrfly", database="wombie", branch="main"
mcp__planetscale__get_schema with org="razrfly", database="wombie", branch="main"
mcp__planetscale__list_tables with org="razrfly", database="wombie", branch="main"
```

### Via IEx (Development)

```elixir
# Start IEx with application
iex -S mix

# Access Repo
alias Eventasaurus.Repo
alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

# Query jobs
Repo.all(from j in JobExecutionSummary, limit: 10)

# Get specific job
Repo.get(JobExecutionSummary, 123)
```

### Via psql (Development)

```bash
# Connect to development database
psql -d eventasaurus_dev

# Common queries
SELECT * FROM job_execution_summaries ORDER BY attempted_at DESC LIMIT 10;
SELECT worker, state, COUNT(*) FROM job_execution_summaries GROUP BY worker, state;
```

## Source Implementation Standards

**⚠️ REQUIRED READING**: When implementing or modifying scrapers, follow the standards in `docs/source-implementation-guide.md`.

### Job Naming Conventions

All Oban jobs must follow the `{JobType}Job` pattern:

- `SyncJob` - Top-level orchestration job that triggers child jobs
- `IndexPageJob` - Fetches listing/index pages
- `EventDetailJob` - Fetches individual event details
- `ShowtimeProcessJob` - Processes showtime data
- `MovieDetailJob` - Fetches movie-specific information

**Example**: `EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob`

### External ID Format

All events must have external IDs in this format:

```
{source}_{type}_{source_id}_{date}
```

**Examples**:
- `cinema_city_event_123456_2024-11-15`
- `kino_krakow_movie_abc789_2024-11-15`
- `week_pl_activity_xyz123_2024-11-15`

**Rules**:
- Dates use hyphens (`YYYY-MM-DD`), not underscores
- All parts lowercase with underscores
- `{type}` = `event`, `movie`, `activity`, `show`, etc.
- Must be globally unique and stable across re-scrapes

### BaseJob Usage

Use `EventasaurusDiscovery.Sources.BaseJob` for standard fetch-transform-process pattern:

```elixir
defmodule EventasaurusDiscovery.Sources.MySource.Jobs.MyJob do
  use EventasaurusDiscovery.Sources.BaseJob

  @impl true
  def fetch_events(from_date, to_date, _context) do
    # Fetch raw data from external source
    {:ok, raw_events}
  end

  @impl true
  def transform_events(raw_events) do
    # Transform to standardized format
    events = Enum.map(raw_events, &transform_event/1)
    {:ok, events}
  end
end
```

**When NOT to use BaseJob**:
- Complex orchestration with multiple child jobs (use plain `Oban.Worker`)
- Custom retry/error handling logic
- Multi-stage processing pipelines

See `docs/source-implementation-guide.md` for detailed examples.

### MetricsTracker Integration

**REQUIRED**: All jobs must integrate MetricsTracker for monitoring:

```elixir
defmodule MySource.Jobs.MyJob do
  use Oban.Worker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    external_id = build_external_id()

    case do_work() do
      {:ok, result} ->
        MetricsTracker.record_success(job, external_id)
        {:ok, result}

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        {:error, reason}
    end
  end
end
```

**Error Categories**: Use standard categories from `EventasaurusDiscovery.Metrics.ErrorCategories`:
- `validation_error`, `geocoding_error`, `venue_error`
- `performer_error`, `category_error`, `duplicate_error`
- `network_error`, `data_quality_error`, `unknown_error`

### Source Module Structure

Required files for each source:

```
lib/eventasaurus_discovery/sources/my_source/
├── client.ex              # HTTP client for external API
├── config.ex             # Source configuration
├── transformer.ex        # Data transformation logic
└── jobs/
    ├── sync_job.ex       # Main orchestration job
    ├── index_page_job.ex # Optional: list fetching
    └── detail_job.ex     # Optional: detail fetching
```

## Code Style & Conventions

- Use `mix format` before committing
- Follow Elixir naming conventions (snake_case for functions/variables, PascalCase for modules)
- Return `{:ok, result}` or `{:error, reason}` tuples for fallible operations
- Use `with` for multi-step operations with early returns
- Prefer pattern matching over conditionals
- Add `@spec` type specifications for public functions
- **Jobs must follow naming convention**: `{JobType}Job` pattern
- **External IDs must follow format**: `{source}_{type}_{id}_{date}`
- **All jobs must integrate MetricsTracker** for monitoring

## Graphite Workflow (User)

**NOTE: These commands are for the USER to run, not Claude Code.**

After Claude Code makes changes:

```bash
# User commits using Graphite (NOT Claude Code)
gt commit -m "feat: implement feature (task 1.2)"

# User creates stacked PRs
gt stack submit
```

## Getting Help

**Documentation:**
- **Source Implementation Guide**: `docs/source-implementation-guide.md` - Job naming, external IDs, BaseJob patterns
- Scraper Monitoring Guide: `docs/scraper-monitoring-guide.md` - Monitoring integration and best practices
- Error Categories: `lib/eventasaurus_discovery/metrics/error_categories.ex` - Standard error types
- MetricsTracker: `lib/eventasaurus_discovery/metrics/metrics_tracker.ex` - Monitoring API
- BaseJob: `lib/eventasaurus_discovery/sources/base_job.ex` - Base behavior for standard jobs

**CLI Tools Quick Reference:**
- `mix monitor.jobs` - Real-time job execution monitoring
- `mix monitor.collisions` - Collision/deduplication metrics
- `mix monitor.health` - Health and SLO compliance
- `mix audit.scheduler_health` - Verify scrapers running daily
- `mix audit.date_coverage` - Verify 7-day event coverage
- `mix fix_cinema_city_duplicates` - Fix duplicate film ID data

**Example Implementations:**
- Cinema City: `lib/eventasaurus_discovery/sources/cinema_city/jobs/` - Complex multi-stage scraper
- Kino Krakow: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/` - BaseJob usage example
- Week.pl: `lib/eventasaurus_discovery/sources/week_pl/jobs/` - Custom orchestration pattern

---

_This guide provides essential context for Claude Code when working on Eventasaurus._
