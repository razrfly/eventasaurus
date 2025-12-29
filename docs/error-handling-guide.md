# Error Handling & Categorization Guide

**Version**: 1.0
**Status**: Active
**Last Updated**: 2025-01-29

---

## Purpose

This guide defines the standard error handling patterns for all Eventasaurus scrapers. Proper error categorization enables:

- **Accurate monitoring dashboards** - See error trends by category
- **Faster debugging** - Know exactly what type of error occurred
- **SLO tracking** - Measure scraper health against targets
- **Pattern detection** - Identify systemic issues across scrapers

**Key Principle**: All errors MUST include category trigger words in their message so `ErrorCategories.categorize_error/1` can properly classify them.

---

## Table of Contents

1. [Error Categories](#1-error-categories)
2. [Structured Error Returns](#2-structured-error-returns)
3. [MetricsTracker Integration](#3-metricsTracker-integration)
4. [Error Message Formatting](#4-error-message-formatting)
5. [Common Patterns by Job Type](#5-common-patterns-by-job-type)
6. [Debugging Unknown Errors](#6-debugging-unknown-errors)
7. [Scraper Compliance Checklist](#7-scraper-compliance-checklist)
8. [Related Documentation](#8-related-documentation)

---

## 1. Error Categories

The system recognizes **12 standard error categories + 1 fallback** as defined in [GitHub Issue #3054](https://github.com/razrfly/eventasaurus/issues/3054). Each category suggests a specific action and has trigger patterns for automatic classification.

### Category Reference Table

| Category | Description | Examples | Action |
|----------|-------------|----------|--------|
| `validation_error` | Missing/invalid required fields | Missing title, invalid date format | Fix data source |
| `parsing_error` | HTML/JSON/XML parsing failures | Malformed response, DOM structure changed | Fix parser |
| `data_quality_error` | Unexpected values, business rule violations | "Special event with no schedule" | Review logic |
| `data_integrity_error` | DB duplicates, constraint violations | `Ecto.MultipleResultsError`, unique constraint | Fix data/query |
| `dependency_error` | Waiting for parent job to complete | `:movie_not_ready`, `:venue_not_processed` | Auto-resolves on retry |
| `network_error` | HTTP/connection failures | Timeout, connection refused, 500/502/503/504 | Retry or check network |
| `rate_limit_error` | API throttling | HTTP 429 Too Many Requests | Back off and retry |
| `authentication_error` | API auth failures | HTTP 401/403 responses | Fix credentials |
| `geocoding_error` | Address resolution failures | Invalid address, coordinates out of range | Fix address data |
| `venue_error` | Venue lookup/creation issues | Duplicate venue, ambiguous match | Fix venue data |
| `performer_error` | Artist matching problems | Unknown performer, Spotify mismatch | Manual review |
| `tmdb_error` | Movie database matching failures | No TMDB match, low confidence | Manual review |
| `uncategorized_error` | Fallback for novel errors | Errors not matching any pattern | Investigate and add pattern |

### Trigger Patterns Reference

| Category | Trigger Patterns |
|----------|------------------|
| `validation_error` | "is required", "missing required", "cannot be blank", "validation failed", "invalid format", "must be", "should be" |
| `parsing_error` | "parse", "parsing", "invalid json", "invalid xml", "malformed", "decode", "format error", "unexpected token" |
| `data_quality_error` | "unexpected value", "business rule", "no schedule", "encoding", "data quality" |
| `data_integrity_error` | "multipleresultserror", "unique constraint", "constraint violation", "integrity", "duplicate key" |
| `dependency_error` | "not ready", "dependency", "waiting for", "parent job", "movie_not_ready" |
| `network_error` | "http", "timeout", "connection", "network", "500", "502", "503", "504", "econnrefused" |
| `rate_limit_error` | "rate limit", "rate_limit", "429", "too many requests", "throttle" |
| `authentication_error` | "401", "403", "unauthorized", "forbidden", "authentication", "auth failed" |
| `geocoding_error` | "geocode", "geocoding", "address not found", "coordinates", "latitude", "longitude" |
| `venue_error` | "venue", "venue processing", "venue not found", "venue matching" |
| `performer_error` | "performer", "artist", "performer processing", "artist not found" |
| `tmdb_error` | "tmdb", "movie not found", "movie_not_matched", "no_results", "low_confidence", "needs_review" |

### Category Definitions (Detailed)

#### `validation_error`
**Use when**: Required fields are missing or data doesn't meet format requirements.
**Action**: Fix data source or add validation upstream.

```elixir
# Examples of validation errors:
"Validation failed: Event title is required"
"Validation failed: start_date cannot be blank"
"Validation failed: Invalid date format for: 2024-13-45"
"Missing required field: external_id"
```

#### `parsing_error`
**Use when**: HTML/JSON/XML parsing fails due to malformed responses or changed DOM structure.
**Action**: Fix the parser or handle the new format.

```elixir
# Examples of parsing errors:
"JSON parsing failed: Unexpected token at position 42"
"HTML parsing failed: Unable to find event container"
"XML parse error: Unclosed tag at line 15"
"Malformed response: Expected object, got array"
```

#### `data_quality_error`
**Use when**: Data exists but contains unexpected values or violates business rules.
**Action**: Review business logic or add data cleansing.

```elixir
# Examples of data quality errors:
"Data quality issue: Special event with no recurring schedule"
"Unexpected value: Event duration is negative"
"Business rule violation: End date before start date"
"Encoding error: Invalid UTF-8 sequence in title"
```

#### `data_integrity_error`
**Use when**: Database operations fail due to duplicates, constraint violations, or query issues.
**Action**: Fix data or query logic.

```elixir
# Examples of data integrity errors:
"Data integrity error: Ecto.MultipleResultsError - expected 1, got 3"
"Unique constraint violation on public_events.external_id"
"Duplicate key error: Event already exists with this ID"
"Foreign key constraint failed: venue_id references non-existent venue"
```

#### `dependency_error`
**Use when**: Job is waiting for a parent job to complete (e.g., movie not yet in database).
**Action**: Usually auto-resolves on retry. No immediate action needed.

```elixir
# Examples of dependency errors:
"Dependency not ready: Movie not ready in database, will retry"
"Waiting for parent job: MovieDetailJob hasn't completed"
"Dependency error: Venue not processed yet"
"movie_not_ready: TMDB lookup still pending"
```

#### `network_error`
**Use when**: HTTP connections fail, timeouts occur, or servers return 5xx errors.
**Action**: Retry or check network/service health.

```elixir
# Examples of network errors:
"HTTP 500: Internal server error from API"
"HTTP 502: Bad gateway"
"Connection timeout after 30s"
"Network error: ECONNREFUSED"
"HTTP 503: Service temporarily unavailable"
```

#### `rate_limit_error`
**Use when**: API returns 429 or indicates rate limiting/throttling.
**Action**: Back off and retry with exponential delay.

```elixir
# Examples of rate limit errors:
"HTTP 429: Rate limit exceeded"
"Rate limit: Too many requests, retry after 60s"
"API throttled: Request quota exceeded"
"Rate limit error: Slow down requests"
```

#### `authentication_error`
**Use when**: API returns 401/403 indicating auth problems.
**Action**: Check and fix API credentials.

```elixir
# Examples of authentication errors:
"HTTP 401: Unauthorized - Invalid API key"
"HTTP 403: Forbidden - Access denied"
"Authentication failed: Token expired"
"Auth error: Invalid credentials"
```

#### `geocoding_error`
**Use when**: Address geocoding fails or coordinates are invalid.
**Action**: Fix address data or try alternate geocoding service.

```elixir
# Examples of geocoding errors:
"Geocoding failed for address: ul. Nieistniejąca 123"
"Address not found: Could not resolve location"
"Invalid coordinates: latitude 95.0 out of range"
"Geocoding service unavailable"
```

#### `venue_error`
**Use when**: Venue lookup fails, creation fails, or matching is ambiguous.
**Action**: Fix venue data or improve matching logic.

```elixir
# Examples of venue errors:
"Venue not found: Cinema City Arkadia"
"Venue processing failed: Unable to create venue"
"Venue matching ambiguous: multiple matches found"
"Venue error: Duplicate venue detected"
```

#### `performer_error`
**Use when**: Artist/performer lookup fails or matching is unsuccessful.
**Action**: Manual review or improve matching algorithm.

```elixir
# Examples of performer errors:
"Performer not found: Unknown Artist"
"Artist matching failed: No Spotify match for 'Some Band'"
"Performer processing failed: Invalid artist data"
"Performer error: Ambiguous artist name"
```

#### `tmdb_error`
**Use when**: TMDB movie lookup fails, returns no results, or match confidence is too low.
**Action**: Manual review for matching or accept low-confidence match.

```elixir
# Examples of TMDB errors:
"TMDB movie not found for: Polish Movie Title"
"TMDB no_results for film_id: 12345"
"TMDB low_confidence match: 45% for Movie Title"
"TMDB needs_review: Multiple matches found"
"movie_not_matched: No TMDB results"
```

#### `uncategorized_error`
**Avoid this category**. If errors fall through to `uncategorized_error`, the error message is missing proper trigger patterns. Investigate and add appropriate patterns to `ErrorCategories`.

```elixir
# If you see these, investigate and categorize:
# - Add new trigger patterns to ErrorCategories
# - Update the job to return properly formatted messages
# - Consider if a new category is needed
```

---

## 2. Structured Error Returns

### The Problem

Many scrapers return errors as atoms, which don't match the string-based pattern matching:

```elixir
# ❌ WRONG - Atom returns result in unknown_error categorization
{:error, :movie_not_ready}
{:error, :missing_external_id}
{:error, :invalid_showtime}
```

When `ErrorCategories.categorize_error/1` receives these atoms, it calls `inspect/1` which produces `":movie_not_ready"` - this doesn't match any trigger patterns and falls through to `unknown_error`.

### The Solution

Always return error messages as strings that include category trigger words:

```elixir
# ✅ CORRECT - String messages with trigger patterns
{:error, "TMDB movie not found: Film title here"}
{:error, "Validation failed: Missing external_id in job args"}
{:error, "Network timeout: API request exceeded 30s limit"}
```

### Pattern: Atom-to-String Conversion

If you need to preserve the atom for internal logic, convert to a categorizable message:

```elixir
# ✅ CORRECT - Convert atom to categorizable message
defp handle_movie_lookup(nil) do
  {:error, "TMDB movie not found: No results from database"}
end

defp handle_movie_lookup(:not_ready) do
  # Use validation_error for dependency issues
  {:error, "Validation failed: Movie not ready, will retry"}
end
```

### Pattern: Tuple Format for Explicit Category

For cases where you want to be explicit about the category:

```elixir
# ✅ RECOMMENDED - Tuple with explicit category
{:error, {:tmdb_error, "Movie not found for film_id: 12345"}}
{:error, {:validation_error, "Missing required field: external_id"}}
{:error, {:network_error, "HTTP 429: Rate limit exceeded"}}
```

**Note**: MetricsTracker needs to handle this tuple format. See [MetricsTracker Integration](#3-metricsTracker-integration).

---

## 3. MetricsTracker Integration

All Oban jobs MUST use `MetricsTracker` to record success/failure outcomes.

### Basic Pattern

```elixir
defmodule MySource.Jobs.MyJob do
  use Oban.Worker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    external_id = job.args["external_id"]

    case do_work(job.args) do
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

### Error Message Requirements

The `reason` passed to `MetricsTracker.record_failure/3` MUST be a string containing trigger patterns:

```elixir
# ✅ CORRECT - Categorizable error messages
MetricsTracker.record_failure(job, "Validation failed: Event title is required", external_id)
MetricsTracker.record_failure(job, "TMDB movie not found for: Some Title", external_id)
MetricsTracker.record_failure(job, "HTTP 500: API returned server error", external_id)

# ❌ WRONG - Will result in unknown_error
MetricsTracker.record_failure(job, :validation_failed, external_id)
MetricsTracker.record_failure(job, "Something went wrong", external_id)
MetricsTracker.record_failure(job, "Error", external_id)
```

### Pattern: Exception Handling

When catching exceptions, extract the message with trigger patterns:

```elixir
def perform(%Oban.Job{} = job) do
  external_id = job.args["external_id"]

  try do
    case process_event(job.args) do
      {:ok, result} ->
        MetricsTracker.record_success(job, external_id)
        {:ok, result}

      {:error, reason} when is_binary(reason) ->
        MetricsTracker.record_failure(job, reason, external_id)
        {:error, reason}

      {:error, reason} ->
        # Convert non-string reasons to categorizable messages
        message = format_error_message(reason)
        MetricsTracker.record_failure(job, message, external_id)
        {:error, reason}
    end
  rescue
    e in Jason.DecodeError ->
      message = "JSON parsing failed: #{Exception.message(e)}"
      MetricsTracker.record_failure(job, message, external_id)
      {:error, message}

    e in Req.Error ->
      message = "HTTP connection failed: #{Exception.message(e)}"
      MetricsTracker.record_failure(job, message, external_id)
      {:error, message}
  end
end

defp format_error_message(:movie_not_ready), do: "Dependency not ready: Movie not ready in database, will retry"
defp format_error_message(:missing_title), do: "Validation failed: Event title is required"
defp format_error_message(:rate_limited), do: "Rate limit: HTTP 429 Too Many Requests"
defp format_error_message(:unauthorized), do: "Authentication failed: HTTP 401 Unauthorized"
defp format_error_message(:parse_failed), do: "Parsing failed: Unable to extract data from response"
defp format_error_message(other), do: "Processing error: #{inspect(other)}"
```

---

## 4. Error Message Formatting

### Message Structure

Error messages should follow this structure:

```
{Category Trigger}: {Specific Details}
```

Examples:
- `"Validation failed: Event title is required"`
- `"TMDB movie not found for: Wielka Kolekcja Filmów"`
- `"HTTP 500: API returned internal server error"`
- `"Geocoding failed for address: ul. Marszałkowska 100, Warszawa"`

### Trigger Word Placement

The trigger words MUST appear in the message (case-insensitive matching):

```elixir
# ✅ CORRECT - Trigger word at start
"Validation failed: missing title"
"TMDB no_results for film_id: 12345"
"Venue not found: Cinema City"

# ✅ CORRECT - Trigger word in middle
"Event title is required"  # "is required" triggers validation_error
"Failed to geocode address"  # "geocode" triggers geocoding_error
"Movie not found in TMDB"  # "movie not found" triggers tmdb_error

# ❌ WRONG - No trigger words
"Something went wrong"
"Error processing event"
"Failed"
"Unknown issue"
```

### Include Context

Always include relevant context for debugging:

```elixir
# ✅ GOOD - Includes context
"TMDB movie not found for: 'Wielka Przygoda' (film_id: 12345)"
"Validation failed: start_date '2024-13-45' is not a valid date"
"HTTP 429: Rate limit exceeded after 5 retries (endpoint: /api/events)"

# ❌ BAD - No context
"Movie not found"
"Validation failed"
"Rate limited"
```

---

## 5. Common Patterns by Job Type

### SyncJob (Coordinator)

```elixir
defmodule MySource.Jobs.SyncJob do
  use Oban.Worker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    external_id = "my_source_sync_#{Date.utc_today()}"

    case fetch_and_schedule_events() do
      {:ok, count} ->
        MetricsTracker.record_success(job, external_id)
        {:ok, %{events_scheduled: count}}

      {:error, %Req.Error{} = error} ->
        message = "HTTP connection failed: #{Exception.message(error)}"
        MetricsTracker.record_failure(job, message, external_id)
        {:error, message}

      {:error, :rate_limited} ->
        message = "HTTP 429: Rate limit exceeded"
        MetricsTracker.record_failure(job, message, external_id)
        {:error, message}
    end
  end
end
```

### EventDetailJob

```elixir
defmodule MySource.Jobs.EventDetailJob do
  use Oban.Worker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = args["external_id"]

    # Validate required fields first
    with :ok <- validate_args(args),
         {:ok, html} <- fetch_page(args["url"]),
         {:ok, event_data} <- parse_event(html),
         {:ok, event} <- process_event(event_data, args["source_id"]) do
      MetricsTracker.record_success(job, external_id)
      {:ok, event}
    else
      {:error, :missing_url} ->
        message = "Validation failed: Missing required field 'url' in job args"
        MetricsTracker.record_failure(job, message, external_id)
        {:error, message}

      {:error, {:http_error, status}} ->
        message = "HTTP #{status}: Failed to fetch event page"
        MetricsTracker.record_failure(job, message, external_id)
        {:error, message}

      {:error, :parse_failed} ->
        message = "HTML parsing failed: Unable to extract event data"
        MetricsTracker.record_failure(job, message, external_id)
        {:error, message}

      {:error, :venue_not_found} ->
        message = "Venue not found: Unable to match or create venue"
        MetricsTracker.record_failure(job, message, external_id)
        {:error, message}
    end
  end

  defp validate_args(%{"url" => url, "external_id" => _}) when is_binary(url), do: :ok
  defp validate_args(%{"url" => nil}), do: {:error, :missing_url}
  defp validate_args(_), do: {:error, :missing_url}
end
```

### ShowtimeProcessJob (Cinema)

```elixir
defmodule CinemaCity.Jobs.ShowtimeProcessJob do
  use Oban.Worker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = args["external_id"]

    # Validate external_id first
    if is_nil(external_id) do
      message = "Validation failed: Missing external_id in job args"
      MetricsTracker.record_failure(job, message, nil)
      {:error, message}
    else
      # Mark event as seen before processing
      EventProcessor.mark_event_as_seen(external_id, args["source_id"])

      case process_showtime(args) do
        {:ok, event} ->
          MetricsTracker.record_success(job, external_id)
          {:ok, event}

        {:ok, :skipped} ->
          # Movie not matched in TMDB - use cancel with explicit message
          {:cancel, "TMDB movie_not_matched: Skipping showtime for unmatched movie"}

        {:error, :movie_not_ready} ->
          message = "Dependency not ready: Movie not ready in database, will retry"
          MetricsTracker.record_failure(job, message, external_id)
          {:error, message}

        {:error, reason} when is_binary(reason) ->
          MetricsTracker.record_failure(job, reason, external_id)
          {:error, reason}
      end
    end
  end
end
```

---

## 6. Debugging Unknown Errors

### Finding Unknown Errors

Use the admin dashboards to identify unknown errors:

1. **Scraper Logs Dashboard** (`/admin/scraper-logs`)
   - Filter by source
   - Look for `error_type: unknown` entries
   - Check the `error_message` field for patterns to add

2. **Error Trends Dashboard** (`/admin/error-trends`)
   - View top error messages
   - Identify patterns that should be categorized

3. **CLI Monitoring** (mix tasks)
   ```bash
   # View recent failures
   mix monitor.jobs failures --source cinema_city

   # View error statistics
   mix monitor.jobs stats --hours 24
   ```

### Common Causes of Unknown Errors

| Cause | Example | Fix |
|-------|---------|-----|
| Atom returns | `{:error, :invalid_data}` | Convert to string with trigger pattern |
| Generic messages | `"Error occurred"` | Add specific category trigger word |
| Exception not caught | `** (KeyError)...` | Catch and format with trigger pattern |
| Tuple returns | `{:error, {:some, :tuple}}` | Extract and format as categorizable string |

### Adding New Pattern Triggers

If you find recurring error messages that should be categorized:

1. Open `lib/eventasaurus_discovery/metrics/error_categories.ex`
2. Add the pattern to the appropriate category function
3. Test with: `ErrorCategories.categorize_error("your new message")`

```elixir
# Example: Adding a new pattern to network_error
defp network_error?(error_lower) do
  Enum.any?(
    [
      "http",
      "timeout",
      # ... existing patterns ...
      "ssl handshake failed",  # NEW PATTERN
      "certificate error"       # NEW PATTERN
    ],
    &String.contains?(error_lower, &1)
  )
end
```

---

## 7. Scraper Compliance Checklist

Use this checklist when reviewing or creating scrapers:

### Error Handling Checklist

- [ ] All `{:error, reason}` returns use string messages (not atoms)
- [ ] Error messages include category trigger patterns
- [ ] Error messages include context (IDs, values, endpoints)
- [ ] `MetricsTracker.record_failure/3` called for all error paths
- [ ] `MetricsTracker.record_success/2` called for success paths
- [ ] Exceptions are caught and formatted with trigger patterns
- [ ] External ID is passed to MetricsTracker calls
- [ ] `{:cancel, reason}` uses string message with trigger pattern

### Error Category Coverage

For each job, verify these common error types are handled:

- [ ] **Validation errors**: Missing fields, invalid formats
- [ ] **Network errors**: HTTP failures, timeouts, rate limits
- [ ] **Data quality errors**: Parse failures, encoding issues
- [ ] **Domain-specific errors**:
  - Cinema jobs: TMDB errors
  - Event jobs: Venue errors
  - Performer jobs: Artist matching errors

### Example Audit Output

```
Scraper: cinema_city
Files reviewed: 5 jobs

✅ SyncJob - All error paths categorized
✅ CinemaDateJob - All error paths categorized
⚠️ MovieDetailJob - Line 145: Returns {:error, :api_failed} (atom)
   Fix: Change to {:error, "HTTP connection failed: API returned error"}
⚠️ ShowtimeProcessJob - Line 89: Returns {:error, :movie_not_ready}
   Fix: Change to {:error, "TMDB movie not found: Movie not ready in database"}
✅ Transformer - N/A (no MetricsTracker calls)
```

---

## 8. Related Documentation

- **[Source Implementation Guide](source-implementation-guide.md)** - Section 6 covers MetricsTracker basics
- **[Scraper Monitoring Guide](scraper-monitoring-guide.md)** - Dashboard usage and CLI tools
- **[Venue Metadata Structure](VENUE_METADATA_STRUCTURE.md)** - Example of structured data patterns
- **[ErrorCategories Module](../lib/eventasaurus_discovery/metrics/error_categories.ex)** - Source code for categorization logic
- **[MetricsTracker Module](../lib/eventasaurus_discovery/metrics/metrics_tracker.ex)** - Success/failure recording API

---

## Appendix: Quick Reference

### Error Message Templates (12+1 Categories)

Copy-paste templates for all error categories:

```elixir
# 1. validation_error
"Validation failed: {field} is required"
"Validation failed: {field} cannot be blank"
"Validation failed: Invalid format for {field}: {value}"
"Missing required field: {field}"

# 2. parsing_error
"JSON parsing failed: {details}"
"HTML parsing failed: {details}"
"XML parse error: {details}"
"Malformed response: {details}"

# 3. data_quality_error
"Data quality issue: {description}"
"Unexpected value: {field} is {value}"
"Business rule violation: {description}"
"Encoding error: {details}"

# 4. data_integrity_error
"Data integrity error: Ecto.MultipleResultsError - {details}"
"Unique constraint violation: {constraint_name}"
"Duplicate key error: {details}"
"Foreign key constraint failed: {details}"

# 5. dependency_error
"Dependency not ready: {resource} not ready, will retry"
"Waiting for parent job: {job_name} hasn't completed"
"Dependency error: {resource} not processed yet"
"movie_not_ready: TMDB lookup still pending"

# 6. network_error
"HTTP {status}: {description}"
"Connection timeout after {seconds}s"
"Network error: {description}"
"HTTP 5xx: Server error from {service}"

# 7. rate_limit_error
"Rate limit: HTTP 429 Too Many Requests"
"Rate limit exceeded: Retry after {seconds}s"
"API throttled: Request quota exceeded"

# 8. authentication_error
"Authentication failed: HTTP 401 Unauthorized"
"HTTP 403: Forbidden - Access denied"
"Auth error: {details}"
"API key invalid or expired"

# 9. geocoding_error
"Geocoding failed for address: {address}"
"Address not found: {address}"
"Invalid coordinates: {details}"
"Geocoding service unavailable"

# 10. venue_error
"Venue not found: {venue_name}"
"Venue processing failed: {details}"
"Venue matching ambiguous: {details}"

# 11. performer_error
"Performer not found: {artist_name}"
"Artist matching failed: {details}"
"Performer processing failed: {details}"

# 12. tmdb_error
"TMDB movie not found for: {title}"
"TMDB no_results for film_id: {id}"
"TMDB low_confidence match: {percentage}% for {title}"
"movie_not_matched: No TMDB results for {title}"

# 13. uncategorized_error (avoid - investigate and add patterns)
# These should trigger investigation, not be used directly
```

### Category Selection Flowchart

```
Is the error about missing/invalid input data?
  YES → validation_error

Is the error about parsing HTML/JSON/XML?
  YES → parsing_error

Is the error about unexpected values or business rules?
  YES → data_quality_error

Is the error about database constraints or duplicates?
  YES → data_integrity_error

Is the error about waiting for another job?
  YES → dependency_error

Is the error HTTP 429 or "rate limit"?
  YES → rate_limit_error

Is the error HTTP 401/403 or auth-related?
  YES → authentication_error

Is the error HTTP 5xx or connection failure?
  YES → network_error

Is the error about geocoding/coordinates?
  YES → geocoding_error

Is the error about venue matching/creation?
  YES → venue_error

Is the error about performer/artist matching?
  YES → performer_error

Is the error about TMDB movie matching?
  YES → tmdb_error

None of the above?
  → uncategorized_error (investigate!)
```

---

*Last updated: 2025-01-29*
