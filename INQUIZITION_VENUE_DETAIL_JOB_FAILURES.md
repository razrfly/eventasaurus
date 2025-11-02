# Inquizition VenueDetailJob Failures - Production Issue

## Issue Summary

**Status**: 🔴 Critical Production Issue
**Affected Jobs**: EventasaurusDiscovery.Sources.Inquizition.Jobs.VenueDetailJob
**Error Pattern**: Systematic failures in production (all events fail), but works perfectly in development
**First Observed**: 2025-11-02
**Impact**: Inquizition scraper completely non-functional in production

## Problem Description

### Production Behavior
- VenueDetailJob fails with `{:error, :all_events_failed}`
- Jobs retry (attempt 2 of 3, then 3 of 3)
- Error metadata provides NO actionable information:
  ```elixir
  %{
    "error_category" => "unknown_error",
    "error_message" => ":all_events_failed",
    "status" => "failed"
  }
  ```
- ALL 20+ venue jobs failing systematically
- Source ID changed from 10 → 9 between failures

### Development Behavior
- ✅ Jobs execute successfully on fresh database
- ✅ No errors when running from scratch
- ✅ All transformations work correctly
- ✅ Venue and event processing completes successfully

### Environment Discrepancy
This is a **production database state issue**, not a code logic issue.

## Root Cause Analysis

### 1. Error Origin (`lib/eventasaurus_discovery/sources/processor.ex:77`)

```elixir
case {successful, failed} do
  {[], [_ | _] = failed} ->
    # All events failed
    Logger.error("❌ All #{length(failed)} events failed processing")

    Enum.with_index(failed, 1)
    |> Enum.each(fn {{:error, reason}, index} ->
      Logger.error("  Event #{index} failed: #{inspect(reason)}")
    end)

    {:error, :all_events_failed}  # ← Generic atom, loses context
```

**Problem**: Individual error reasons are logged but NOT captured in job metadata or returned to Oban for observability.

### 2. Logging Inadequacy

The current logging has **critical gaps**:

#### What's Logged (Console Only)
```
❌ All 1 events failed processing
  Event 1 failed: <actual reason>  # Lost in logs
```

#### What's Stored (Oban Metadata)
```elixir
%{
  "error_category" => "unknown_error",  # Not helpful
  "error_message" => ":all_events_failed",  # Useless
  "status" => "failed"
}
```

#### What's Missing
- ❌ Specific error reasons (venue conflicts? event conflicts? validation failures?)
- ❌ Database constraint violation details
- ❌ Which processing stage failed (venue, performer, event?)
- ❌ Entity IDs or external_ids involved in conflicts
- ❌ Stack traces for unexpected errors
- ❌ Actionable debugging information

### 3. Production vs Development Hypothesis

Since jobs work in development (fresh DB) but fail in production, likely causes:

#### A. Venue Uniqueness Conflicts
Production database likely has:
- Existing venues with same `external_id` but different `source_id`
- Venue slug conflicts
- Unique constraint violations on `(name, city)` or similar

#### B. Source ID Migration Issue
The error shows `source_id` changed from 10 → 9:
- Original failing job: `"source_id" => 10`
- Recent failing jobs: `"source_id" => 9`

This suggests:
1. Source was recreated or migrated
2. Old venues exist with `source_id=10`
3. New jobs try to create venues with `source_id=9`
4. Conflicts occur but error details are lost

#### C. Event External ID Conflicts
Pattern scrapers generate stable external_ids like `inquizition_201329063`. If these events already exist from previous runs with different source_ids or configurations, uniqueness constraints fail.

## Development Reproduction Blockers

### Issue 1: EventFreshnessChecker Prevents Re-queuing

**File**: `lib/eventasaurus_discovery/sources/inquizition/jobs/index_job.ex:102-105`

```elixir
venues_to_process =
  EventFreshnessChecker.filter_events_needing_processing(
    venues_with_external_ids,
    source_id
  )
```

**Problem**: After running the scraper once, EventFreshnessChecker filters out all venues processed within 7 days (default threshold). Jobs won't be created in development for recently processed venues.

### Issue 2: Missing Force Update Mechanism

**Comparison with Speed Quizzing**:

Speed Quizzing has force_update support:
```elixir
# lib/eventasaurus_discovery/sources/speed_quizzing/source.ex:104
"force_update" => options[:force_update] || false
```

**Inquizition does NOT**:
```bash
$ grep -r "force" lib/eventasaurus_discovery/sources/inquizition/
# No results
```

**Impact**: No way to bypass EventFreshnessChecker and re-queue jobs for debugging.

## Debugging Steps Required

### Step 1: Extract Actual Error Reasons from Production Logs

Search production logs for entries immediately before `:all_events_failed`:

```bash
# Look for individual event failure logs
grep -A 10 "All 1 events failed processing" production.log

# OR
grep "Event 1 failed:" production.log
```

**Expected log pattern**:
```
❌ All 1 events failed processing
  Event 1 failed: <ACTUAL_ERROR_REASON_HERE>
```

The `<ACTUAL_ERROR_REASON_HERE>` will reveal the root cause.

### Step 2: Check for Venue Conflicts in Production Database

Connect to production database and check for existing venues:

```sql
-- Check for existing Inquizition venues
SELECT
  v.id,
  v.external_id,
  v.name,
  v.slug,
  v.city,
  ves.source_id,
  ves.created_at,
  ves.updated_at
FROM venues v
JOIN venue_event_sources ves ON v.id = ves.venue_id
WHERE v.external_id LIKE 'inquizition_venue_%'
ORDER BY ves.created_at DESC
LIMIT 50;

-- Check for source_id conflicts
SELECT
  source_id,
  COUNT(*) as venue_count
FROM venue_event_sources ves
JOIN venues v ON v.id = ves.venue_id
WHERE v.external_id LIKE 'inquizition_venue_%'
GROUP BY source_id;

-- Check for specific failing venue
SELECT
  v.id,
  v.external_id,
  v.name,
  v.slug,
  ves.source_id
FROM venues v
JOIN venue_event_sources ves ON v.id = ves.venue_id
WHERE v.external_id = 'inquizition_venue_201329063';
```

### Step 3: Check for Event Conflicts

```sql
-- Check for existing Inquizition events
SELECT
  pe.id,
  pes.external_id,
  pe.title,
  pes.source_id,
  pes.created_at,
  pes.last_seen_at
FROM public_events pe
JOIN public_event_sources pes ON pe.id = pes.event_id
WHERE pes.external_id LIKE 'inquizition_%'
ORDER BY pes.created_at DESC
LIMIT 50;

-- Check source_id distribution
SELECT
  source_id,
  COUNT(*) as event_count
FROM public_event_sources
WHERE external_id LIKE 'inquizition_%'
GROUP BY source_id;
```

### Step 4: Check Source Configuration

```sql
-- Verify source_id 9 vs 10
SELECT id, name, slug, priority, active, created_at
FROM sources
WHERE id IN (9, 10)
OR slug = 'inquizition';
```

### Step 5: Reproduce in Development with Production Data State

To properly debug, development needs to mirror production state:

**Option A**: Clone production venue state
```sql
-- In development, create conflicting venues similar to production
-- This requires knowing what conflicts exist from Step 2
```

**Option B**: Temporarily disable uniqueness constraints in development
```elixir
# This is NOT recommended but can help isolate the issue
# Modify VenueProcessor to log conflicts instead of failing
```

### Step 6: Add Verbose Error Logging (Temporary Patch)

Add detailed logging in `VenueDetailJob.perform/1`:

```elixir
defp process_venue(transformed, source_id) do
  case Processor.process_source_data([transformed], source_id, "inquizition") do
    {:ok, events} ->
      {:ok, events}

    {:error, reason} = error ->
      # ENHANCED LOGGING
      Logger.error("""
      🔴 VENUE PROCESSING FAILED
      Source ID: #{source_id}
      Venue External ID: #{inspect(transformed[:venue_data][:external_id])}
      Venue Name: #{inspect(transformed[:venue_data][:name])}
      Event External ID: #{inspect(transformed[:external_id])}
      Error Reason: #{inspect(reason, pretty: true, limit: :infinity)}
      """)
      error
  end
end
```

## Recommended Solutions

### Priority 1: Fix Inadequate Error Logging (CRITICAL)

**File**: `lib/eventasaurus_discovery/sources/processor.ex`

**Current Code** (Lines 66-77):
```elixir
case {successful, failed} do
  {[], [_ | _] = failed} ->
    Logger.error("❌ All #{length(failed)} events failed processing")

    Enum.with_index(failed, 1)
    |> Enum.each(fn {{:error, reason}, index} ->
      Logger.error("  Event #{index} failed: #{inspect(reason)}")
    end)

    {:error, :all_events_failed}  # ← PROBLEM: Loses all context
```

**Proposed Fix**:
```elixir
case {successful, failed} do
  {[], [_ | _] = failed} ->
    Logger.error("❌ All #{length(failed)} events failed processing")

    # Collect all error reasons
    error_details =
      Enum.with_index(failed, 1)
      |> Enum.map(fn {{:error, reason}, index} ->
        Logger.error("  Event #{index} failed: #{inspect(reason)}")
        %{index: index, reason: format_error_reason(reason)}
      end)

    # Return detailed error that includes all failure reasons
    {:error, {:all_events_failed, %{
      total_failures: length(failed),
      failures: error_details
    }}}
```

Add helper function:
```elixir
defp format_error_reason(reason) when is_binary(reason), do: reason
defp format_error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
defp format_error_reason({:discard, msg}), do: "discard: #{msg}"
defp format_error_reason(reason), do: inspect(reason, limit: 500)
```

**Benefits**:
- ✅ Error details preserved in return value
- ✅ Can be captured by MetricsTracker
- ✅ Visible in Oban dashboard
- ✅ Actionable debugging information

### Priority 2: Update MetricsTracker Integration

**File**: `lib/eventasaurus_discovery/sources/inquizition/jobs/venue_detail_job.ex`

**Current Code** (Lines 66-68):
```elixir
{:error, reason} ->
  MetricsTracker.record_failure(job, reason, external_id)
  result
```

**Issue**: MetricsTracker receives generic atom `:all_events_failed` without details.

**Proposed Enhancement**:
```elixir
{:error, {:all_events_failed, details}} ->
  # Extract first failure as primary error
  primary_error =
    details[:failures]
    |> List.first()
    |> Map.get(:reason, "unknown")

  MetricsTracker.record_failure(
    job,
    primary_error,  # More specific than :all_events_failed
    external_id,
    %{
      error_type: "all_events_failed",
      failure_count: details[:total_failures],
      all_failures: details[:failures]
    }
  )
  result

{:error, reason} ->
  MetricsTracker.record_failure(job, reason, external_id)
  result
```

### Priority 3: Add Force Update Support

**File**: `lib/eventasaurus_discovery/sources/inquizition/source.ex`

Add `force_update` option support (mirror Speed Quizzing implementation):

```elixir
def sync(source, options \\ %{}) do
  # ... existing code ...

  %{
    "source_id" => source.id,
    "stores" => stores,
    "limit" => options[:limit],
    "force_update" => options[:force_update] || false  # ← Add this
  }
  |> Jobs.IndexJob.new()
  |> Oban.insert()
end
```

**File**: `lib/eventasaurus_discovery/sources/inquizition/jobs/index_job.ex`

Update freshness filtering:

```elixir
defp filter_fresh_venues(venues, source_id, limit, force_update \\ false) do
  venues_with_external_ids = # ... existing code ...

  # Skip freshness check if force_update is true
  venues_to_process = if force_update do
    Logger.info("🔄 Force update enabled - bypassing EventFreshnessChecker")
    venues_with_external_ids
  else
    EventFreshnessChecker.filter_events_needing_processing(
      venues_with_external_ids,
      source_id
    )
  end

  # ... rest of existing code ...
end
```

Update `process_venues/3` signature:
```elixir
defp process_venues(venues, source_id, limit) do
  force_update = args["force_update"] || false
  venues_to_process = filter_fresh_venues(venues, source_id, limit, force_update)
  # ...
end
```

**Usage**:
```elixir
# In development, force re-processing
Inquizition.sync(source, %{force_update: true})
```

### Priority 4: Add Database Conflict Handling

**File**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex`

Enhance error messages to include conflict details:

```elixir
# When unique constraint violations occur
rescue
  Ecto.ConstraintError ->
    {:error, "Venue constraint violation: #{venue_data.external_id} (check for duplicate external_id or slug conflicts)"}
```

**File**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`

Similar enhancement for event conflicts:

```elixir
rescue
  Ecto.ConstraintError ->
    {:error, "Event constraint violation: #{event_data.external_id} (check for duplicate external_id)"}
```

## Immediate Action Plan

### Phase 1: Diagnose (Now)
1. ✅ **Extract production logs** showing individual event failures (Step 1 above)
2. ✅ **Run database queries** to find conflicting venues/events (Steps 2-4 above)
3. ✅ **Identify root cause** from actual error reasons

### Phase 2: Fix Logging (Next)
1. Implement Priority 1 (Enhanced error logging in Processor.ex)
2. Deploy to production
3. Retry failed jobs to capture detailed errors

### Phase 3: Fix Root Cause (After Diagnosis)
Depends on findings from Phase 1:

**If venue conflicts**:
- Clean up duplicate venues
- Fix source_id migration issue
- Update uniqueness constraints

**If event conflicts**:
- Clean up duplicate events
- Review external_id generation logic
- Update event merging logic

### Phase 4: Add Developer Tools (Parallel)
1. Implement Priority 3 (force_update support)
2. Enable development debugging without waiting 7 days
3. Add integration tests with conflicting data

## Testing Strategy

### Unit Tests Needed
```elixir
# test/eventasaurus_discovery/sources/inquizition/jobs/venue_detail_job_test.exs

test "captures detailed error when all events fail" do
  # Mock Processor to return multiple failures
  # Verify error tuple includes failure details
  # Verify MetricsTracker receives detailed error
end

test "handles venue uniqueness conflicts gracefully" do
  # Create conflicting venue first
  # Run job
  # Verify specific conflict error is returned
end
```

### Integration Tests Needed
```elixir
test "force_update bypasses EventFreshnessChecker" do
  # Process venue normally
  # Immediately process again with force_update: true
  # Verify job is created and runs
end

test "production-like conflict scenario" do
  # Set up venue with source_id=10
  # Try to process same venue with source_id=9
  # Verify error is descriptive
end
```

## Related Files

### Code Files
- `lib/eventasaurus_discovery/sources/processor.ex:77` - Error origin
- `lib/eventasaurus_discovery/sources/inquizition/jobs/venue_detail_job.ex` - Job implementation
- `lib/eventasaurus_discovery/sources/inquizition/jobs/index_job.ex` - Freshness filtering
- `lib/eventasaurus_discovery/services/event_freshness_checker.ex` - 7-day filtering logic
- `lib/eventasaurus_discovery/metrics/metrics_tracker.ex` - Metadata tracking

### Reference Implementations
- `lib/eventasaurus_discovery/sources/speed_quizzing/source.ex` - force_update example

## Success Criteria

- [ ] Production logs show specific error reasons (not just `:all_events_failed`)
- [ ] Oban dashboard displays actionable error messages in job metadata
- [ ] Root cause of production failures identified and resolved
- [ ] Force update mechanism allows development debugging
- [ ] Integration tests prevent regression
- [ ] All 20+ failing Inquizition jobs successfully complete

## Questions for Further Investigation

1. **Why did source_id change from 10 to 9?** Was there a source migration or recreation?
2. **Are there orphaned venues/events from old source_id?** Should they be cleaned up or migrated?
3. **Is this affecting other pattern scrapers?** Speed Quizzing, Quizmeisters, etc.?
4. **Should EventFreshnessChecker be source_id aware?** Currently filters by external_id only.

## Severity Assessment

**Impact**: 🔴 Critical
- Inquizition scraper completely broken in production
- 20+ jobs failing systematically
- No new Inquizition events being discovered
- Users see stale event data

**Urgency**: 🔴 Immediate
- Production system non-functional
- Error logging inadequate for debugging
- Development reproduction blocked

**Complexity**: 🟡 Medium
- Root cause is environmental (DB state), not code logic
- Requires production database investigation
- Fix involves improving error handling, not architectural changes

---

**Next Steps**:
1. Extract production logs (Step 1) to identify actual error reasons
2. Run database queries (Steps 2-4) to find conflicts
3. Implement enhanced error logging (Priority 1) for future observability
4. Address root cause based on findings
