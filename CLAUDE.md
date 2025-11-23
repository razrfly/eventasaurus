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

### Mix Tasks (CLI Interface)

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

### Via IEx

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

### Via psql

```bash
# Connect to development database
psql -d eventasaurus_dev

# Common queries
SELECT * FROM job_execution_summaries ORDER BY attempted_at DESC LIMIT 10;
SELECT worker, state, COUNT(*) FROM job_execution_summaries GROUP BY worker, state;
```

## Code Style & Conventions

- Use `mix format` before committing
- Follow Elixir naming conventions (snake_case for functions/variables, PascalCase for modules)
- Return `{:ok, result}` or `{:error, reason}` tuples for fallible operations
- Use `with` for multi-step operations with early returns
- Prefer pattern matching over conditionals
- Add `@spec` type specifications for public functions

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
- Scraper Monitoring Guide: `docs/scraper-monitoring-guide.md`
- Error Categories: `lib/eventasaurus_discovery/metrics/error_categories.ex`
- MetricsTracker: `lib/eventasaurus_discovery/metrics/metrics_tracker.ex`

**Example Implementations:**
- Cinema City: `lib/eventasaurus_discovery/sources/cinema_city/jobs/`
- Kino Krakow: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/`

---

_This guide provides essential context for Claude Code when working on Eventasaurus._
