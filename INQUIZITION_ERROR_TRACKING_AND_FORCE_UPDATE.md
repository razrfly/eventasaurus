# Inquizition: Improve Error Tracking and Add Force Update Support

## Problem Statement

Two critical issues prevent effective debugging and testing of Inquizition VenueDetailJob failures:

### 1. Error Details Lost in Oban Metadata
When all events fail processing, the actual error reasons are logged to console but NOT captured in Oban job metadata. This makes production debugging impossible since we can't see what actually failed (venue conflicts, constraint violations, validation errors, etc.).

**Current Behavior:**
- Individual errors logged: `"Event 1 failed: {:error, :venue_conflict}"`
- Oban metadata shows: `{:error, :all_events_failed}` ← Generic, loses all context
- Console logs are ephemeral and not easily searchable in production

**Impact:**
- Cannot debug production failures without SSH access
- Cannot identify patterns in failures (are they all venue conflicts? constraint violations?)
- Cannot prioritize fixes based on actual error types

### 2. Cannot Force Re-queue in Development
EventFreshnessChecker prevents re-queuing venues processed within 7 days. No `force_update` parameter exists to bypass this check for testing.

**Current Behavior:**
- Venues fail in production with `:all_events_failed`
- Attempting to re-queue in development: "0 venues to process (recently updated)"
- Cannot reproduce production issues locally

**Impact:**
- Cannot test fixes for failing venues
- Cannot verify error handling improvements
- Development-production gap prevents rapid iteration

## Related Issues

- #2122 - Original investigation identifying these root causes
- Processor.ex:77 - Where `:all_events_failed` error originates
- IndexJob.ex:102 - Where EventFreshnessChecker blocks re-queuing

---

## Solution 1: Preserve Error Context in Oban Metadata

### Current Implementation

**File:** `lib/eventasaurus_discovery/sources/processor.ex:77`

```elixir
case {successful, failed} do
  {[], [_ | _] = failed} ->
    Logger.error("❌ All #{length(failed)} events failed processing")
    Enum.with_index(failed, 1)
    |> Enum.each(fn {{:error, reason}, index} ->
      Logger.error("  Event #{index} failed: #{inspect(reason)}")
    end)
    {:error, :all_events_failed}  # ← Generic atom, context lost!
end
```

### Proposed Implementation

**File:** `lib/eventasaurus_discovery/sources/processor.ex:77`

```elixir
case {successful, failed} do
  {[], [_ | _] = failed} ->
    # Log all failures for console debugging
    Logger.error("❌ All #{length(failed)} events failed processing")
    Enum.with_index(failed, 1)
    |> Enum.each(fn {{:error, reason}, index} ->
      Logger.error("  Event #{index} failed: #{inspect(reason)}")
    end)

    # Capture first error for Oban metadata (preserves debugging context)
    first_error = List.first(failed)

    # Return structured error with details
    {:error, {:all_events_failed, %{
      first_error: first_error,
      total_failed: length(failed),
      error_types: failed
        |> Enum.map(fn {:error, reason} ->
          # Extract error type for aggregation
          case reason do
            {:constraint, _} -> :constraint_violation
            {:conflict, _} -> :duplicate_conflict
            {:validation, _} -> :validation_error
            other -> other
          end
        end)
        |> Enum.frequencies()
    }}}
end
```

### Benefits

✅ **Oban metadata shows actual error:** `{:error, {:all_events_failed, %{first_error: {:error, :venue_conflict}, ...}}}`
✅ **Error type aggregation:** `%{constraint_violation: 5, duplicate_conflict: 3}`
✅ **Production debugging:** Can see error patterns without SSH access
✅ **Backwards compatible:** Existing error handling still works
✅ **Actionable insights:** Know which fixes to prioritize based on error types

---

## Solution 2: Add Force Update Support to Inquizition

### Reference Implementation: Speed Quizzing Pattern

**File:** `lib/eventasaurus_discovery/scraping/rate_limiter.ex:55`

```elixir
def force_update?(args) when is_map(args) do
  Map.get(args, "force_update", false) || Map.get(args, :force_update, false)
end
```

**File:** `lib/eventasaurus_discovery/sources/speed_quizzing/source.ex:29`

```elixir
def sync_job_args(options \\ %{}) do
  %{
    "source" => key(),
    "limit" => options[:limit],
    "force_update" => options[:force_update] || false  # ← Passes through to jobs
  }
end
```

### Proposed Implementation for Inquizition

#### Step 1: Update IndexJob to Accept and Use force_update

**File:** `lib/eventasaurus_discovery/sources/inquizition/jobs/index_job.ex`

**Current code (lines 42-48):**
```elixir
@impl Oban.Worker
def perform(%Oban.Job{args: args}) do
  source_id = args["source_id"]
  stores = args["stores"]
  limit = args["limit"]

  Logger.info("🔄 Processing #{length(stores)} Inquizition venues")
```

**Proposed change:**
```elixir
@impl Oban.Worker
def perform(%Oban.Job{args: args}) do
  source_id = args["source_id"]
  stores = args["stores"]
  limit = args["limit"]
  force_update = args["force_update"] || false  # ← Accept force_update parameter

  Logger.info("🔄 Processing #{length(stores)} Inquizition venues")
```

**Current code (lines 65-68):**
```elixir
Logger.info("📋 Successfully parsed #{length(venues)} venues")

# Filter and enqueue detail jobs
process_venues(venues, source_id, limit)
```

**Proposed change:**
```elixir
Logger.info("📋 Successfully parsed #{length(venues)} venues")

# Filter and enqueue detail jobs
process_venues(venues, source_id, limit, force_update)  # ← Pass force_update
```

**Current code (lines 72-83):**
```elixir
# Filter venues by freshness and enqueue detail jobs
defp process_venues(venues, source_id, limit) do
  # Filter venues using freshness checker
  venues_to_process = filter_fresh_venues(venues, source_id, limit)

  Logger.info("""
  📋 Enqueueing #{length(venues_to_process)} detail jobs
  (#{length(venues) - length(venues_to_process)} venues skipped - recently updated)
  """)

  # Enqueue detail jobs for each venue
  enqueue_detail_jobs(venues_to_process, source_id)
end
```

**Proposed change:**
```elixir
# Filter venues by freshness and enqueue detail jobs
defp process_venues(venues, source_id, limit, force_update) do
  # Filter venues using freshness checker (skip if force_update)
  venues_to_process =
    if force_update do
      Logger.info("🔄 FORCE UPDATE: Bypassing freshness check for all #{length(venues)} venues")
      # Apply limit but skip freshness filtering
      if limit, do: Enum.take(venues, limit), else: venues
    else
      filter_fresh_venues(venues, source_id, limit)
    end

  skipped_count = length(venues) - length(venues_to_process)

  Logger.info("""
  📋 Enqueueing #{length(venues_to_process)} detail jobs
  #{if force_update, do: "(FORCE UPDATE - freshness check bypassed)", else: "(#{skipped_count} venues skipped - recently updated)"}
  """)

  # Enqueue detail jobs for each venue
  enqueue_detail_jobs(venues_to_process, source_id)
end
```

#### Step 2: Update Inquizition Source Module

**File:** `lib/eventasaurus_discovery/sources/inquizition/source.ex`

**Find the `sync_job_args/1` function and update it:**

```elixir
def sync_job_args(options \\ %{}) do
  %{
    "source" => key(),
    "limit" => options[:limit],
    "force_update" => options[:force_update] || false  # ← Add force_update support
  }
end
```

### Benefits

✅ **Development testing:** Can re-queue failing venues immediately
✅ **Production fixes:** Can force update specific venues after fixing bugs
✅ **Consistent pattern:** Matches Speed Quizzing implementation
✅ **Backwards compatible:** Default `false` maintains current behavior
✅ **Explicit control:** Clear logging when force update is active

---

## Implementation Checklist

### Phase 1: Error Tracking (High Priority)
- [ ] Update `Processor.ex:77` to capture first error and error type aggregation
- [ ] Test error capture with intentionally failing venue
- [ ] Verify Oban metadata shows detailed error information
- [ ] Verify console logging still works for debugging
- [ ] Deploy to production and monitor error patterns

### Phase 2: Force Update Support (Medium Priority)
- [ ] Add `force_update` parameter to `Inquizition.Jobs.IndexJob.perform/1`
- [ ] Update `process_venues/4` to accept and use `force_update`
- [ ] Update `Inquizition.source.ex` `sync_job_args/1` to include `force_update`
- [ ] Add logging to clearly indicate when force update is active
- [ ] Test in development: Force update should bypass freshness check
- [ ] Test without force update: Should maintain current 7-day filtering
- [ ] Document usage in job comments

### Phase 3: Validation (Required)
- [ ] Integration test: Create failing venue, verify error details captured
- [ ] Integration test: Force update should re-queue recently processed venues
- [ ] Integration test: Non-force update should skip recent venues (7-day check)
- [ ] Production test: Queue single failing venue with force_update
- [ ] Verify Oban admin shows actionable error information

---

## Testing Strategy

### Test Error Tracking

```elixir
# In dev console or test
alias EventasaurusDiscovery.Sources.Inquizition.Jobs.VenueDetailJob

# Create a job that will fail (invalid venue data)
VenueDetailJob.new(%{
  "source_id" => 4,
  "venue_id" => "test-fail",
  "venue_data" => %{invalid: "data"}
}) |> Oban.insert!()

# Check Oban admin - metadata should show:
# {:error, {:all_events_failed, %{
#   first_error: {:error, :validation_error},
#   total_failed: 1,
#   error_types: %{validation_error: 1}
# }}}
```

### Test Force Update

```elixir
# In dev console
alias EventasaurusDiscovery.Sources.Inquizition

# Get source
source = EventasaurusApp.Repo.get_by!(EventasaurusDiscovery.Sources.Source, slug: "inquizition")

# Normal sync (should skip recently processed venues)
Inquizition.queue_sync_job(source.id, limit: 5)
# Expected: "0-2 venues to process (recently updated)"

# Force update sync (should process ALL venues)
Inquizition.queue_sync_job(source.id, limit: 5, force_update: true)
# Expected: "5 venues to process (FORCE UPDATE - freshness check bypassed)"
```

### Verify Error Aggregation in Production

```sql
-- After deploying error tracking improvements
-- Check Oban errors for Inquizition VenueDetailJob

SELECT
  args->>'venue_id' as venue_id,
  errors[array_length(errors, 1)]->'error'->>'first_error' as first_error,
  errors[array_length(errors, 1)]->'error'->'error_types' as error_type_counts,
  attempted_at
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.Inquizition.Jobs.VenueDetailJob'
  AND state = 'retryable'
ORDER BY attempted_at DESC
LIMIT 20;
```

---

## Success Criteria

### Error Tracking Success
- [ ] Oban job metadata contains actual error details (not just `:all_events_failed`)
- [ ] Can identify error patterns without console access (venue conflicts vs constraints vs validation)
- [ ] Error type aggregation shows: `%{venue_conflict: 12, constraint_violation: 8}`
- [ ] First error preserved: `{:error, {:venue_conflict, "Duplicate external_id: inquizition_1234"}}`

### Force Update Success
- [ ] `force_update: true` bypasses EventFreshnessChecker
- [ ] `force_update: false` (or omitted) maintains 7-day freshness filtering
- [ ] Logging clearly indicates force update mode: "🔄 FORCE UPDATE: Bypassing freshness check"
- [ ] Can reproduce production failures in development
- [ ] Can test fixes by force re-queuing specific failing venues

---

## Files Modified

1. **lib/eventasaurus_discovery/sources/processor.ex** (Error tracking)
   - Line 77: Update `:all_events_failed` to preserve error details

2. **lib/eventasaurus_discovery/sources/inquizition/jobs/index_job.ex** (Force update)
   - Line 45: Accept `force_update` parameter
   - Line 67: Pass `force_update` to `process_venues/4`
   - Line 72-83: Update `process_venues/3` → `process_venues/4` with force update logic

3. **lib/eventasaurus_discovery/sources/inquizition/source.ex** (Force update)
   - Update `sync_job_args/1` to include `force_update` parameter

---

## Additional Context

### Why This Matters

**Production Debugging:**
- 66960 VenueDetailJob failures in production show `:all_events_failed`
- Zero visibility into actual failure reasons
- Cannot prioritize fixes without error type breakdown

**Development Velocity:**
- Cannot reproduce production issues locally
- 7-day freshness check blocks testing
- Force update enables rapid iteration

### Alternative Approaches Considered

**Error Tracking Alternatives:**
1. ❌ **Only log to console** - Logs are ephemeral, hard to search
2. ❌ **Separate error tracking table** - Over-engineering, Oban metadata sufficient
3. ✅ **Enhanced Oban metadata** - Simple, searchable, already in admin UI

**Force Update Alternatives:**
1. ❌ **Manual SQL updates** - Error-prone, requires DB access
2. ❌ **Lower freshness threshold** - Affects all venues, not targeted
3. ✅ **force_update parameter** - Explicit, controlled, matches Speed Quizzing pattern

### Migration Notes

**No Database Migrations Required** - These are code-only changes.

**Backwards Compatible** - Existing error handling and job queuing continue working.

**Deployment Safe** - Can deploy without downtime or coordination.
