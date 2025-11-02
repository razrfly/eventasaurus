# Inquizition VenueDetailJob Systematic Failures in Production

## 🔴 Critical Production Issue

**Status:** Production Broken
**Affected Component:** `EventasaurusDiscovery.Sources.Inquizition.Jobs.VenueDetailJob`
**Impact:** All Inquizition scraping non-functional in production
**Severity:** Critical - No new events being discovered from Inquizition source

---

## Problem Summary

### What's Happening
- ❌ ALL VenueDetailJob instances failing with `{:error, :all_events_failed}` in production
- ✅ SAME jobs work perfectly in development (fresh database)
- 🔄 Jobs retry up to 3 times, all attempts fail
- 📊 20+ venues affected systematically
- 🚫 Error metadata provides **zero actionable information**

### Example Error Metadata (Useless)
```elixir
%{
  "error_category" => "unknown_error",
  "error_message" => ":all_events_failed",
  "status" => "failed"
}
```

### Source of Truth
Error originates from `lib/eventasaurus_discovery/sources/processor.ex:77`:
```elixir
{:error, :all_events_failed}  # ← Generic atom, all context lost
```

---

## Root Cause Analysis

### Production vs Development Discrepancy

| Environment | Result | Database State |
|-------------|--------|----------------|
| Development (fresh DB) | ✅ Success | No conflicts, clean state |
| Production | ❌ Failure | Existing venues/events causing conflicts |

**Conclusion:** This is a **database state conflict issue**, not a code logic bug.

### Hypothesis: Source ID Migration Conflict

Observed behavior:
- Original failing jobs: `source_id = 10`
- Recent failing jobs: `source_id = 9`

**Likely scenario:**
1. Inquizition source was recreated or migrated (ID changed 10→9)
2. Production database contains venues/events from old `source_id=10`
3. Jobs attempt to create/update with `source_id=9`
4. Database uniqueness constraints fail
5. Specific error details logged to console but **lost before reaching Oban metadata**

### Why Errors Are Invisible

**Current flow:**
1. Individual events fail with specific reasons (venue conflict, event conflict, constraint violation)
2. Errors logged to console: `Event 1 failed: <ACTUAL_REASON>`
3. Error returned as generic atom: `{:error, :all_events_failed}`
4. MetricsTracker receives useless atom
5. Oban metadata shows `"unknown_error"`

**Result:** Impossible to debug without direct access to production logs.

---

## Critical Issues

### Issue 1: Inadequate Error Logging 🔥

**File:** `lib/eventasaurus_discovery/sources/processor.ex:66-77`

**Current Implementation:**
```elixir
case {successful, failed} do
  {[], [_ | _] = failed} ->
    # Logs to console (hard to access in production)
    Logger.error("❌ All #{length(failed)} events failed processing")
    Enum.with_index(failed, 1)
    |> Enum.each(fn {{:error, reason}, index} ->
      Logger.error("  Event #{index} failed: #{inspect(reason)}")
    end)

    # Returns useless atom (no context preserved)
    {:error, :all_events_failed}
```

**Problems:**
- ❌ Specific error reasons logged but not returned
- ❌ MetricsTracker receives generic atom
- ❌ Oban dashboard shows "unknown_error"
- ❌ No way to diagnose without production log access
- ❌ No stack traces, entity IDs, or conflict details captured

### Issue 2: Missing Force Update Mechanism

**Comparison:**

| Scraper | Force Update Support | Development Debugging |
|---------|---------------------|----------------------|
| Speed Quizzing | ✅ Yes | Easy - bypass freshness check |
| Inquizition | ❌ No | Blocked - 7 day wait required |

**Impact:**
- Cannot reproduce production failures in development
- EventFreshnessChecker filters out recently processed venues
- Must wait 7 days between test runs
- No way to force re-processing for debugging

**Location:** `lib/eventasaurus_discovery/sources/inquizition/jobs/index_job.ex:102`

### Issue 3: Development Reproduction Blocked

**Why jobs don't queue in development:**

```elixir
# index_job.ex:102-105
venues_to_process =
  EventFreshnessChecker.filter_events_needing_processing(
    venues_with_external_ids,
    source_id
  )
```

After running scraper once:
- All venues marked as "recently seen" (7 day threshold)
- EventFreshnessChecker filters them out
- No VenueDetailJob instances created
- Cannot reproduce or debug

---

## Debugging Steps

### Step 1: Extract Real Errors from Production Logs 🔍

**CRITICAL FIRST STEP** - Find the actual error reasons:

```bash
# Search for individual event failures
grep -B 2 -A 10 "All.*events failed processing" production.log

# Or search specifically for event failure details
grep "Event.*failed:" production.log
```

**Expected output:**
```
❌ All 1 events failed processing
  Event 1 failed: <ACTUAL_ERROR_REASON_HERE>
```

The `<ACTUAL_ERROR_REASON_HERE>` will reveal:
- Venue uniqueness constraint violation?
- Event external_id conflict?
- Missing required field?
- Database foreign key violation?

### Step 2: Check Production Database for Conflicts

<details>
<summary>SQL Queries to Run</summary>

**Check existing Inquizition venues:**
```sql
SELECT
  v.id,
  v.external_id,
  v.name,
  v.slug,
  v.city,
  ves.source_id,
  ves.created_at
FROM venues v
JOIN venue_event_sources ves ON v.id = ves.venue_id
WHERE v.external_id LIKE 'inquizition_venue_%'
ORDER BY ves.created_at DESC
LIMIT 50;
```

**Check source_id distribution:**
```sql
SELECT
  source_id,
  COUNT(*) as venue_count
FROM venue_event_sources ves
JOIN venues v ON v.id = ves.venue_id
WHERE v.external_id LIKE 'inquizition_venue_%'
GROUP BY source_id;
```

**Check specific failing venue (example):**
```sql
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

**Check source configuration:**
```sql
SELECT id, name, slug, priority, active, created_at
FROM sources
WHERE id IN (9, 10)
   OR slug = 'inquizition';
```

**Check event conflicts:**
```sql
SELECT
  pes.external_id,
  pes.source_id,
  COUNT(*) as occurrence_count
FROM public_event_sources pes
WHERE pes.external_id LIKE 'inquizition_%'
GROUP BY pes.external_id, pes.source_id
HAVING COUNT(*) > 1;
```

</details>

### Step 3: Identify Conflict Pattern

Based on database queries, determine:
- [ ] Are there duplicate venues with different source_ids?
- [ ] Are there venue slug conflicts?
- [ ] Are there event external_id conflicts?
- [ ] Did source_id change from 10 to 9?
- [ ] Are there orphaned records from old source?

---

## Proposed Solutions

### 🔥 Priority 1: Fix Error Logging (IMMEDIATE)

**Objective:** Capture specific error details in Oban metadata for observability.

**File:** `lib/eventasaurus_discovery/sources/processor.ex`

<details>
<summary>Code Changes</summary>

**Replace lines 66-77 with:**
```elixir
case {successful, failed} do
  {[], [_ | _] = failed} ->
    Logger.error("❌ All #{length(failed)} events failed processing")

    # Collect detailed error information
    error_details =
      Enum.with_index(failed, 1)
      |> Enum.map(fn {{:error, reason}, index} ->
        formatted_reason = format_error_reason(reason)
        Logger.error("  Event #{index} failed: #{formatted_reason}")
        %{index: index, reason: formatted_reason}
      end)

    # Return structured error with all failure details
    {:error, {:all_events_failed, %{
      total_failures: length(failed),
      failures: error_details,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }}}
```

**Add helper function:**
```elixir
# Format error reasons for readability
defp format_error_reason(reason) when is_binary(reason), do: reason
defp format_error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
defp format_error_reason({:discard, msg}), do: "discard: #{msg}"
defp format_error_reason({:constraint, field, msg}), do: "constraint #{field}: #{msg}"
defp format_error_reason(%Ecto.Changeset{} = changeset) do
  errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  "validation_errors: #{inspect(errors)}"
end
defp format_error_reason(reason), do: inspect(reason, limit: 500, pretty: true)
```

</details>

**Benefits:**
- ✅ Specific error reasons preserved in return value
- ✅ Captured by MetricsTracker
- ✅ Visible in Oban dashboard metadata
- ✅ Actionable debugging information
- ✅ Structured format for programmatic analysis

### 🔧 Priority 2: Update MetricsTracker Integration

**File:** `lib/eventasaurus_discovery/sources/inquizition/jobs/venue_detail_job.ex`

<details>
<summary>Code Changes</summary>

**Replace lines 66-68:**
```elixir
{:error, {:all_events_failed, details}} ->
  # Extract primary error for summary
  primary_error =
    details[:failures]
    |> List.first()
    |> then(fn failure ->
      if failure, do: Map.get(failure, :reason, "unknown"), else: "unknown"
    end)

  # Record failure with detailed context
  MetricsTracker.record_failure(
    job,
    "all_events_failed: #{primary_error}",
    external_id,
    %{
      error_type: "all_events_failed",
      failure_count: details[:total_failures],
      failures: details[:failures],
      timestamp: details[:timestamp]
    }
  )
  result

{:error, reason} ->
  MetricsTracker.record_failure(job, reason, external_id)
  result
```

</details>

### 🚀 Priority 3: Add Force Update Support

**Objective:** Enable development debugging by bypassing EventFreshnessChecker.

**File 1:** `lib/eventasaurus_discovery/sources/inquizition/source.ex`

<details>
<summary>Code Changes</summary>

```elixir
def sync(source, options \\ %{}) do
  # ... existing fetch code ...

  %{
    "source_id" => source.id,
    "stores" => stores,
    "limit" => options[:limit],
    "force_update" => options[:force_update] || false  # ← NEW
  }
  |> Jobs.IndexJob.new()
  |> Oban.insert()
end
```

</details>

**File 2:** `lib/eventasaurus_discovery/sources/inquizition/jobs/index_job.ex`

<details>
<summary>Code Changes</summary>

**Update perform/1:**
```elixir
def perform(%Oban.Job{args: args}) do
  source_id = args["source_id"]
  stores = args["stores"]
  limit = args["limit"]
  force_update = args["force_update"] || false  # ← NEW

  # ... existing code ...

  process_venues(venues, source_id, limit, force_update)  # ← Updated
end
```

**Update process_venues/4:**
```elixir
defp process_venues(venues, source_id, limit, force_update) do
  venues_to_process = filter_fresh_venues(venues, source_id, limit, force_update)

  Logger.info("""
  📋 Enqueueing #{length(venues_to_process)} detail jobs
  (#{length(venues) - length(venues_to_process)} venues skipped - recently updated)
  #{if force_update, do: "🔄 FORCE UPDATE MODE", else: ""}
  """)

  enqueue_detail_jobs(venues_to_process, source_id)
end
```

**Update filter_fresh_venues/4:**
```elixir
defp filter_fresh_venues(venues, source_id, limit, force_update) do
  venues_with_external_ids =
    Enum.map(venues, fn venue ->
      venue_id = Map.get(venue, :venue_id) || Map.get(venue, "venue_id")
      if venue_id do
        Map.put(venue, :external_id, "inquizition_#{to_string(venue_id)}")
      else
        venue
      end
    end)
    |> Enum.reject(fn venue -> is_nil(Map.get(venue, :external_id)) end)

  # Skip freshness check if force_update enabled
  venues_to_process = if force_update do
    Logger.info("🔄 Force update enabled - bypassing EventFreshnessChecker")
    venues_with_external_ids
  else
    EventFreshnessChecker.filter_events_needing_processing(
      venues_with_external_ids,
      source_id
    )
  end

  # Apply limit if provided
  if limit, do: Enum.take(venues_to_process, limit), else: venues_to_process
end
```

</details>

**Usage:**
```elixir
# In development console - force re-processing
source = Repo.get_by(Source, slug: "inquizition")
Inquizition.sync(source, %{force_update: true})

# Or with limit for testing
Inquizition.sync(source, %{force_update: true, limit: 5})
```

### 🛡️ Priority 4: Enhanced Database Conflict Handling

**Add to VenueProcessor and EventProcessor:**

<details>
<summary>Example Enhancement</summary>

```elixir
# In VenueProcessor
rescue
  e in Ecto.ConstraintError ->
    constraint_name = e.constraint || "unknown"
    {:error, """
    Venue constraint violation: #{constraint_name}
    External ID: #{venue_data.external_id}
    Venue: #{venue_data.name}
    Suggestion: Check for duplicate external_id or slug conflicts in production DB
    """}
```

</details>

---

## Action Plan

### Phase 1: Immediate Diagnosis ⏱️ (Today)
- [ ] Extract production logs showing individual event failures (Step 1)
- [ ] Run database conflict queries (Step 2)
- [ ] Identify specific error pattern (venue/event conflicts, constraint violations)
- [ ] Document root cause in issue comments

### Phase 2: Emergency Logging Fix 🔥 (Next Deploy)
- [ ] Implement Priority 1 (enhanced error logging)
- [ ] Deploy to production
- [ ] Retry 2-3 failed jobs to capture detailed errors in metadata
- [ ] Verify Oban dashboard shows actionable information

### Phase 3: Root Cause Resolution 🔧 (After Diagnosis)
**Depends on Phase 1 findings:**

If **venue source_id conflict**:
- [ ] Migrate old venues from source_id=10 to source_id=9
- [ ] OR delete orphaned venues and re-process
- [ ] Update venue uniqueness constraints if needed

If **event external_id conflict**:
- [ ] Clean up duplicate event sources
- [ ] Review external_id generation logic
- [ ] Fix event merging behavior

If **database constraint issue**:
- [ ] Identify conflicting constraint
- [ ] Add proper error handling
- [ ] Update constraint or modify upsert logic

### Phase 4: Developer Experience 🚀 (Parallel Track)
- [ ] Implement Priority 3 (force_update support)
- [ ] Add integration tests with conflicting data scenarios
- [ ] Document debugging workflow for future issues

---

## Testing Requirements

### Unit Tests
```elixir
# test/eventasaurus_discovery/sources/processor_test.exs
test "all_events_failed includes detailed error information" do
  # Mock multiple event failures with different reasons
  # Verify returned error tuple includes all failure details
  # Verify format is structured and actionable
end
```

### Integration Tests
```elixir
# test/eventasaurus_discovery/sources/inquizition/integration_test.exs
test "force_update bypasses EventFreshnessChecker" do
  # Process venue normally
  # Immediately process again with force_update: true
  # Assert VenueDetailJob is created and executes
end

test "handles production-like source_id conflict" do
  # Create venue with source_id=10
  # Attempt to process same venue with source_id=9
  # Assert specific conflict error is returned with details
end
```

---

## Success Criteria

- [ ] Production logs reveal specific error reasons (not generic `:all_events_failed`)
- [ ] Oban dashboard shows actionable error messages in job metadata
- [ ] Root cause identified and resolved (venues/events processing successfully)
- [ ] Force update mechanism enables development debugging
- [ ] All 20+ failing Inquizition jobs complete successfully
- [ ] New events appear in production database
- [ ] Integration tests prevent regression

---

## Related Files

### Primary Files
- `lib/eventasaurus_discovery/sources/processor.ex:77` - Error origin
- `lib/eventasaurus_discovery/sources/inquizition/jobs/venue_detail_job.ex` - Job implementation
- `lib/eventasaurus_discovery/sources/inquizition/jobs/index_job.ex` - Freshness filtering
- `lib/eventasaurus_discovery/services/event_freshness_checker.ex` - 7-day filter logic
- `lib/eventasaurus_discovery/metrics/metrics_tracker.ex` - Metadata tracking

### Reference Implementation
- `lib/eventasaurus_discovery/sources/speed_quizzing/source.ex` - force_update example

---

## Labels
`bug`, `priority: critical`, `production`, `scraper: inquizition`, `observability`, `needs-investigation`

## Assignees
_(Assign to developer responsible for scraper infrastructure)_

## Milestone
Next Production Hotfix

---

## Additional Context

### Why This Is Critical
- Inquizition is a PRIMARY trivia event source for UK
- Zero new events being discovered since failure started
- Users seeing stale event data
- No visibility into root cause without log access
- Development debugging blocked by missing tooling

### Why Error Logging Must Be Fixed First
Even if we resolve the current conflict, **we'll hit this again** with:
- Other scrapers experiencing similar issues
- Future database migrations
- Source reconfigurations
- Production-only edge cases

**Fixing error logging is an investment** that prevents future multi-hour debugging sessions.
