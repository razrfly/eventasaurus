# Scraper Monitoring Guide

## Overview

This guide explains how to integrate comprehensive monitoring into all Eventasaurus scrapers using our unified monitoring system. Following these guidelines ensures your scraper failures are properly categorized, trackable, and actionable.

## Why Monitor?

**Problem Without Monitoring:**
- Debugging relies on console logs
- Can't identify error patterns across time
- Don't know true success rates
- Silent failures (job succeeds but creates nothing) go unnoticed

**Benefits With Monitoring:**
- Error dashboard shows "15 validation errors, 8 network errors" at a glance
- Filter jobs by error category
- Track success rate trends over time
- Detect silent failures automatically
- Visualize complex job chains and cascade failures

## Core Concepts

### 1. Automatic Telemetry

**All jobs are automatically tracked** via ObanTelemetry:
- `JobExecutionSummary` created for every job (start, stop, exception)
- Timing, state, and metadata captured
- Data retained beyond Oban's 7-day default

**Location**: `lib/eventasaurus_app/monitoring/oban_telemetry.ex`

### 2. Error Categorization

**9 Standard Categories** (defined in `ErrorCategories` module):
- `validation_error` - Missing/invalid required fields
- `geocoding_error` - Address/location resolution failures
- `venue_error` - Venue lookup/creation issues
- `performer_error` - Performer/artist matching problems
- `category_error` - Event categorization failures
- `duplicate_error` - Duplicate event detection
- `network_error` - HTTP timeouts, API failures
- `data_quality_error` - Unexpected data format, parsing issues
- `unknown_error` - Uncategorized failures

**Location**: `lib/eventasaurus_discovery/metrics/error_categories.ex`

### 3. MetricsTracker

**Opt-in module** that enriches job metadata with:
- Error category
- Error message
- External ID (for correlation)

**Location**: `lib/eventasaurus_discovery/metrics/metrics_tracker.ex`

## Implementation Guide

### Step 1: Alias MetricsTracker

Add to top of your job module:

```elixir
defmodule MyApp.Sources.MySource.Jobs.MyJob do
  use Oban.Worker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # ...
end
```

### Step 2: Wrap Core Logic with Success/Failure Tracking

**Pattern 1: Simple Success/Failure**

```elixir
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
```

**Pattern 2: Complex with Explicit Categories**

```elixir
@impl Oban.Worker
def perform(%Oban.Job{} = job) do
  external_id = "event_#{job.args["event_id"]}"

  with {:ok, raw_data} <- fetch_data(),
       {:ok, validated} <- validate_data(raw_data),
       {:ok, event} <- create_event(validated) do

    MetricsTracker.record_success(job, external_id)
    {:ok, %{event_id: event.id}}
  else
    {:error, %HTTPoison.Error{reason: :timeout}} = error ->
      MetricsTracker.record_failure(job, "Network timeout", external_id)
      error

    {:error, {:validation, message}} = error ->
      MetricsTracker.record_failure(job, "Validation: #{message}", external_id)
      error

    {:error, reason} = error ->
      MetricsTracker.record_failure(job, reason, external_id)
      error
  end
end
```

**Pattern 3: Async with Task.async_stream**

```elixir
@impl Oban.Worker
def perform(%Oban.Job{} = job) do
  items = job.args["items"]
  external_id = "bulk_process_#{Date.utc_today()}"

  results =
    items
    |> Task.async_stream(&process_item/1, timeout: 30_000)
    |> Enum.to_list()

  {successes, failures} =
    Enum.split_with(results, fn
      {:ok, {:ok, _}} -> true
      _ -> false
    end)

  if Enum.empty?(failures) do
    MetricsTracker.record_success(job, external_id)
    {:ok, %{processed: length(successes)}}
  else
    error_msg = "#{length(failures)}/#{length(items)} items failed"
    MetricsTracker.record_failure(job, error_msg, external_id)
    {:error, error_msg}
  end
end
```

### Step 3: Choose Meaningful External IDs

External IDs help correlate related jobs. **Best Practices:**

**✅ Good External IDs:**
```elixir
# For sync/coordinator jobs
"question_one_sync_#{Date.utc_today()}"

# For entity-specific jobs
"event_#{event_id}"
"movie_#{movie_title}_#{cinema_id}"
"showtime_#{showtime_id}"

# For batch jobs
"bulk_geocode_batch_#{batch_id}"
```

**❌ Bad External IDs:**
```elixir
# Too generic - can't correlate
"sync"
"process"

# Includes sensitive data
"user_email_#{email}"

# Too long/redundant
"question_one_restaurant_detail_job_for_region_#{region_id}_on_#{timestamp}"
```

### Step 4: Handle Silent Failures

**Silent Failure** = Job succeeds but creates zero entities

**Detection Pattern:**

```elixir
def perform(%Oban.Job{} = job) do
  {:ok, events} = fetch_and_create_events()

  result = %{
    events_found: length(events),
    events_created: count_created(events)
  }

  # Detect silent failure
  if result.events_created == 0 and result.events_found > 0 do
    MetricsTracker.record_failure(
      job,
      "Silent failure: Found #{result.events_found} events but created 0",
      external_id
    )
    {:error, :silent_failure}
  else
    MetricsTracker.record_success(job, external_id)
    {:ok, result}
  end
end
```

### Step 5: Test Your Integration

**Manual Testing:**

1. Trigger your job with known failure scenarios
2. Check `/admin/job-executions` dashboard
3. Verify error category appears correctly
4. Verify error message is clear and actionable

**Automated Testing:**

```elixir
defmodule MyApp.Sources.MySource.Jobs.MyJobTest do
  use Eventasaurus.DataCase, async: true
  import Oban.Testing

  alias MyApp.Sources.MySource.Jobs.MyJob
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  describe "error tracking" do
    test "records validation_error for missing required fields" do
      # Setup job with invalid data
      job = insert(:oban_job, worker: "MyJob", args: %{"invalid" => true})

      # Perform job
      assert {:error, _} = MyJob.perform(job)

      # Verify error tracked
      summary = Repo.get_by(JobExecutionSummary, job_id: job.id)
      assert summary.results["error_category"] == "validation_error"
      assert summary.error =~ "required field"
    end
  end
end
```

## Common Patterns by Error Type

### Validation Errors

```elixir
case validate_event_data(data) do
  {:ok, validated} ->
    create_event(validated)

  {:error, :missing_title} ->
    MetricsTracker.record_failure(job, "Event title is required", external_id)
    {:error, :validation_failed}

  {:error, :invalid_date} ->
    MetricsTracker.record_failure(job, "Event date is invalid", external_id)
    {:error, :validation_failed}
end
```

### Network Errors

```elixir
case HTTPoison.get(url, [], timeout: 30_000) do
  {:ok, %{status_code: 200, body: body}} ->
    parse_and_process(body)

  {:ok, %{status_code: status}} ->
    MetricsTracker.record_failure(job, "HTTP #{status}", external_id)
    {:error, :http_error}

  {:error, %HTTPoison.Error{reason: :timeout}} ->
    MetricsTracker.record_failure(job, "Request timeout", external_id)
    {:error, :timeout}

  {:error, %HTTPoison.Error{reason: reason}} ->
    MetricsTracker.record_failure(job, "Network error: #{reason}", external_id)
    {:error, :network_error}
end
```

### Geocoding Errors

```elixir
case Geocoding.geocode_address(address) do
  {:ok, coordinates} ->
    create_venue_with_coordinates(coordinates)

  {:error, :not_found} ->
    MetricsTracker.record_failure(
      job,
      "Address not found: #{address}",
      external_id
    )
    {:error, :geocoding_failed}

  {:error, :ambiguous} ->
    MetricsTracker.record_failure(
      job,
      "Ambiguous address: #{address}",
      external_id
    )
    {:error, :geocoding_failed}
end
```

### Data Quality Errors

```elixir
case parse_html(html) do
  {:ok, data} when map_size(data) > 0 ->
    process_data(data)

  {:ok, data} when map_size(data) == 0 ->
    MetricsTracker.record_failure(
      job,
      "Parsed HTML but extracted no data - site structure may have changed",
      external_id
    )
    {:error, :no_data_extracted}

  {:error, reason} ->
    MetricsTracker.record_failure(
      job,
      "HTML parsing failed: #{inspect(reason)}",
      external_id
    )
    {:error, :parsing_failed}
end
```

## Complex Job Chains

For scrapers with multiple job types (coordinator → detail → process), track parent-child relationships:

### Coordinator Job

```elixir
defmodule MySource.Jobs.SyncJob do
  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    external_id = "my_source_sync_#{Date.utc_today()}"

    case fetch_items() do
      {:ok, items} ->
        # Schedule child jobs with parent reference
        Enum.each(items, fn item ->
          %{item_id: item.id, parent_job_id: job.id}
          |> MySource.Jobs.DetailJob.new()
          |> Oban.insert()
        end)

        MetricsTracker.record_success(job, external_id)
        {:ok, %{items_scheduled: length(items)}}

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        {:error, reason}
    end
  end
end
```

### Child Job

```elixir
defmodule MySource.Jobs.DetailJob do
  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    item_id = job.args["item_id"]
    parent_job_id = job.args["parent_job_id"]
    external_id = "item_#{item_id}"

    # Check if parent job succeeded
    parent_summary = Repo.get_by(JobExecutionSummary, job_id: parent_job_id)

    if parent_summary.state != "completed" do
      MetricsTracker.record_failure(
        job,
        "Skipped - parent job failed",
        external_id
      )
      {:error, :parent_failed}
    else
      case process_item(item_id) do
        {:ok, result} ->
          MetricsTracker.record_success(job, external_id)
          {:ok, result}

        {:error, reason} ->
          MetricsTracker.record_failure(job, reason, external_id)
          {:error, reason}
      end
    end
  end
end
```

## Dashboard Features

After implementing MetricsTracker, you can:

### 1. Filter by Error Category

Navigate to `/admin/job-executions` and use the error category filter dropdown to see only:
- Validation errors
- Network errors
- Geocoding errors
- etc.

### 2. View Error Trends

Navigate to `/admin/error-trends` to see:
- Error rate over time (24h, 7d, 30d)
- Top error messages
- Scraper comparison with SLO indicators
- Export to CSV

### 3. View Job Chains

Click "View Tree" on coordinator jobs to see:
- Parent-child relationships
- Cascade failures (parent failed → children skipped)
- Success rate across the chain

### 4. Detect Silent Failures

Dashboard shows alert banner:
- "⚠️ 12 silent failures in last 24h"
- Click to investigate which jobs succeeded but created nothing

## Best Practices Checklist

Before marking your scraper integration complete, verify:

- [ ] MetricsTracker imported and used in all job modules
- [ ] `record_success` called on successful completion
- [ ] `record_failure` called with meaningful messages on errors
- [ ] External IDs are meaningful and help correlation
- [ ] Silent failures detected (check `events_created == 0`)
- [ ] Error messages are actionable (not just "failed")
- [ ] Common error types categorized correctly
- [ ] Complex chains track parent_job_id
- [ ] Tests verify MetricsTracker usage
- [ ] Manual testing confirms dashboard displays correctly

## Common Mistakes to Avoid

### ❌ Mistake 1: Generic Error Messages

```elixir
# Bad
MetricsTracker.record_failure(job, "Error occurred", external_id)

# Good
MetricsTracker.record_failure(job, "HTTP 404: Event not found at #{url}", external_id)
```

### ❌ Mistake 2: Not Tracking Success

```elixir
# Bad - only tracks failures
case process() do
  {:ok, result} -> {:ok, result}
  {:error, reason} ->
    MetricsTracker.record_failure(job, reason, external_id)
    {:error, reason}
end

# Good - tracks both
case process() do
  {:ok, result} ->
    MetricsTracker.record_success(job, external_id)
    {:ok, result}
  {:error, reason} ->
    MetricsTracker.record_failure(job, reason, external_id)
    {:error, reason}
end
```

### ❌ Mistake 3: Swallowing Errors

```elixir
# Bad - error not tracked
try do
  risky_operation()
  MetricsTracker.record_success(job, external_id)
  {:ok, result}
rescue
  e -> {:ok, %{failed: true}}  # Appears successful!
end

# Good - errors tracked
try do
  risky_operation()
  MetricsTracker.record_success(job, external_id)
  {:ok, result}
rescue
  e ->
    MetricsTracker.record_failure(job, Exception.message(e), external_id)
    {:error, Exception.message(e)}
end
```

### ❌ Mistake 4: Inconsistent External IDs

```elixir
# Bad - can't correlate related jobs
SyncJob: external_id = "sync"
DetailJob: external_id = "detail_123"
ProcessJob: external_id = "process_item"

# Good - clear hierarchy
SyncJob: external_id = "question_one_sync_2025-01-22"
DetailJob: external_id = "question_one_restaurant_123"
ProcessJob: external_id = "question_one_event_456"
```

## SLO Targets by Scraper Type

**High Reliability (95%+ success)**:
- Coordinator/sync jobs (should almost never fail)
- Simple HTTP fetches without parsing
- Database-only operations

**Medium Reliability (85-90% success)**:
- Complex parsing with external dependencies
- Third-party API matching (e.g., TMDB)
- Geocoding operations

**Lower Reliability (80-85% success)**:
- Duplicate detection (expected to reject some)
- Multi-step validation chains
- Experimental/new scrapers

## CLI Audit & Maintenance Tools

In addition to dashboards, Eventasaurus provides command-line tools for auditing scraper health, detecting data issues, and performing maintenance.

### Scheduler Health Audit (`mix audit.scheduler_health`)

Verify that scheduler-triggered jobs are running successfully and on schedule:

```bash
# Check all cinema scrapers
mix audit.scheduler_health

# JSON output for automation
mix audit.scheduler_health --json

# Production database
USE_PROD_DB=true mix audit.scheduler_health
```

**What it checks:**
- Last successful execution time for each cinema scraper
- Whether jobs are running on expected schedule
- Job failure patterns and error rates

### Date Coverage Audit (`mix audit.date_coverage`)

Analyze showtime date coverage to identify gaps in scraped data:

```bash
# Check date coverage for all cinemas
mix audit.date_coverage

# JSON output
mix audit.date_coverage --json

# Production database
USE_PROD_DB=true mix audit.date_coverage
```

**What it checks:**
- Date range coverage for each cinema
- Missing dates that should have showtimes
- Coverage gaps and anomalies

### Collision Monitoring (`mix monitor.collisions`)

Detect and analyze TMDB matching collisions where different films match to the same TMDB ID:

```bash
# Check for collisions
mix monitor.collisions

# Detailed output with affected showtimes
mix monitor.collisions --verbose

# JSON output
mix monitor.collisions --json
```

**What it detects:**
- Multiple Cinema City films matching same TMDB movie
- Potential false-positive TMDB matches
- Data integrity issues in movie matching

### Fix Cinema City Duplicates (`mix fix_cinema_city_duplicates`)

Repair duplicate `cinema_city_film_id` entries caused by incorrect TMDB matching:

```bash
# Dry run - show what would be fixed
mix fix_cinema_city_duplicates

# Apply fixes
mix fix_cinema_city_duplicates --apply
```

**What it fixes:**
- Removes duplicate `cinema_city_film_id` from newer movie entries
- Preserves the oldest (most likely correct) movie's film_id
- Allows correct re-matching on next scraper run

**Production Usage** (via Fly.io):
```bash
fly ssh console -C "bin/eventasaurus eval 'EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates()'"
fly ssh console -C "bin/eventasaurus eval 'EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates(true)'"
```

## Getting Help

**Documentation:**
- Error Categories: `lib/eventasaurus_discovery/metrics/error_categories.ex`
- MetricsTracker: `lib/eventasaurus_discovery/metrics/metrics_tracker.ex`
- Telemetry Handler: `lib/eventasaurus_app/monitoring/oban_telemetry.ex`

**Dashboard:**
- Job Executions: `/admin/job-executions`
- Error Trends: `/admin/error-trends`
- Oban Dashboard: `/admin/oban`

**CLI Audit Tools:**
- Scheduler Health: `mix audit.scheduler_health`
- Date Coverage: `mix audit.date_coverage`
- Collision Monitor: `mix monitor.collisions`
- Duplicate Fix: `mix fix_cinema_city_duplicates`

**Example Implementations:**
- Cinema City: `lib/eventasaurus_discovery/sources/cinema_city/jobs/`
- Kino Krakow: `lib/eventasaurus_discovery/sources/kino_krakow/jobs/`

---

**Last Updated**: 2025-12-15
**Phase**: Phase 4 - Rollout to All Scrapers
