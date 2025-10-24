# Issue: Partial Upload Recovery System for Failed Venue Images

## Problem Statement

After Phase 1 and Phase 2 improvements to venue image enrichment, we now have excellent **observability** (detailed error logging) and **prevention** (rate limiting), but we lack a systematic approach to **recovery** when uploads partially fail.

### Current State

Venues can have **mixed success/failure** states in their `venue_images` JSONB array:
- Some images successfully uploaded to ImageKit (`upload_status: "uploaded"`)
- Some images failed to upload (`upload_status: "failed"`) with detailed error information
- No automated recovery mechanism exists

### Why This Matters

- **User Experience**: Venues display incomplete image galleries
- **Data Quality**: Lost value from API calls that returned valid photo references
- **Cost Efficiency**: We paid for provider API calls but didn't store the images
- **Operational Burden**: No easy way for operators to identify and fix partial failures

---

## Detection Methods

### Primary Detection: Query venue_images JSONB Array

Failed uploads are **permanently stored** in the database (orchestrator.ex:544-549), making detection straightforward:

```sql
-- Find ALL venues with any failed uploads
SELECT
  v.id,
  v.name,
  v.city_id,
  jsonb_array_length(venue_images) as total_images,
  (SELECT COUNT(*) FROM jsonb_array_elements(venue_images) img
   WHERE img->>'upload_status' = 'failed') as failed_count,
  (SELECT COUNT(*) FROM jsonb_array_elements(venue_images) img
   WHERE img->>'upload_status' = 'uploaded') as uploaded_count
FROM venues v
WHERE venue_images @> '[{"upload_status": "failed"}]'::jsonb;
```

### Analysis Queries

**1. Failure Rate by Provider**
```sql
SELECT
  img->>'provider' as provider,
  img->'error_details'->>'error_type' as error_type,
  COUNT(*) as occurrences
FROM venues v,
  jsonb_array_elements(v.venue_images) img
WHERE img->>'upload_status' = 'failed'
GROUP BY provider, error_type
ORDER BY occurrences DESC;
```

**2. Partial Upload Candidates (Mixed Success/Failure)**
```sql
SELECT
  v.id,
  v.name,
  failed_count,
  uploaded_count,
  ROUND(100.0 * failed_count / (failed_count + uploaded_count), 1) as failure_rate_pct
FROM (
  SELECT
    v.id,
    v.name,
    (SELECT COUNT(*) FROM jsonb_array_elements(venue_images) img
     WHERE img->>'upload_status' = 'failed') as failed_count,
    (SELECT COUNT(*) FROM jsonb_array_elements(venue_images) img
     WHERE img->>'upload_status' = 'uploaded') as uploaded_count
  FROM venues v
  WHERE venue_images IS NOT NULL
) sub
WHERE failed_count > 0 AND uploaded_count > 0
ORDER BY failure_rate_pct DESC;
```

**3. Oban Job Metadata (Recent Failures - Last 7 Days)**
```sql
SELECT
  id,
  inserted_at,
  completed_at,
  meta->>'venue_id' as venue_id,
  meta->>'images_discovered' as discovered,
  meta->>'images_uploaded' as uploaded,
  meta->>'images_failed' as failed,
  meta->'failure_breakdown' as error_breakdown
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.VenueImages.EnrichmentJob'
  AND state = 'completed'
  AND CAST(meta->>'images_failed' AS INTEGER) > 0
ORDER BY completed_at DESC;
```

---

## Failure Classification

### From Phase 1 Error Types (orchestrator.ex:686-710)

**Transient Failures (Retry Recommended)**
- `rate_limited` (429) - Temporary rate limit, retry after delay
- `service_unavailable` (503) - Provider temporarily down
- `network_timeout` - Temporary network issue
- `gateway_timeout` (504) - Upstream timeout
- `bad_gateway` (502) - Temporary proxy issue

**Permanent Failures (Retry Pointless)**
- `not_found` (404) - Photo deleted by provider
- `forbidden` (403) - Photo restricted/private
- `auth_error` (401) - API key invalid (system-wide issue)
- `file_too_large` - Image exceeds ImageKit limits

**Ambiguous Failures (Provider-Dependent)**
- `server_error` (500) - Could be transient or permanent
- `download_failed` - Generic failure, needs investigation
- `unknown_error` - Unclassified, needs investigation

---

## Partial Upload Scenarios

### Scenario A: Rate-Limited Batch (Pre-Phase 2)
**Example**: Venue with 10 Google Places photos, 4 uploaded, 6 failed with `rate_limited`

**Cause**: Burst requests without delays (fixed in Phase 2)

**Expected After Phase 2**: Should be rare (<5% of jobs)

**Remediation**:
- Re-run enrichment with Phase 2 deployed
- Success likelihood: 95%+

---

### Scenario B: Mixed Provider Results
**Example**: Google Places succeeded (5 images), Foursquare failed with `service_unavailable`

**Cause**: Provider-specific outage

**Remediation**:
- Retry only failed provider
- Use `enrich_venue(venue, providers: ["foursquare"], force: true)`

---

### Scenario C: Permanent Losses
**Example**: 8 uploaded, 2 failed with `not_found`

**Cause**: Photos removed/restricted by Google after initial API call

**Remediation**:
- Accept data loss
- Mark as `permanently_failed` to skip future retries
- Focus resources on recoverable failures

---

## Current System Gaps

### Gap 1: No Deduplication by provider_url

**Problem**:
```elixir
# Line 669 - Current deduplication logic
|> Enum.group_by(fn img -> img["url"] end)
```

Failed uploads store Google URL in `"url"`, successful uploads store ImageKit URL. They won't deduplicate!

**Impact**: Re-running enrichment creates duplicates (failed Google URL + successful ImageKit URL)

**Fix**: Change to `img["provider_url"] || img["url"]` for proper deduplication

---

### Gap 2: No Direct Retry Mechanism

**Current Flow**:
1. Always calls provider API first (`provider_module.get_images(place_id)`)
2. Then uploads those results to ImageKit
3. No separate "retry failed uploads" path

**Problem**: Can't retry existing failed uploads without calling provider API again

**Impact**:
- Wastes API calls (and money)
- Might get different photos than what originally failed
- Slower than direct retry

---

### Gap 3: No Automated Recovery

**Problem**: Operators must manually identify and fix partial failures

**Impact**:
- Partial failures accumulate over time
- Inconsistent data quality across venues
- Operational burden

---

## Proposed Solution: Phase 3 - Failed Upload Recovery System

### Component 1: Detection & Analysis (Admin Dashboard)

**Dashboard Widget: "Failed Upload Monitor"**

Metrics:
- Total venues with failed uploads
- Total failed images across all venues
- Breakdown by error type (transient vs permanent)
- Breakdown by provider
- Trend over time (failures decreasing after Phase 2?)

**Action Buttons**:
- "Retry Transient Failures" → queues retry jobs for 429/503/timeout errors
- "Re-enrich All" → force re-enrichment for all affected venues
- "View Details" → drill down to specific venue failures

**Priority Scoring Algorithm**:
```
priority_score =
  (failed_count * 10) +              # More failures = higher priority
  (failure_rate_pct) +               # Higher rate = higher priority
  (is_transient ? 20 : 0) +          # Transient errors easier to fix
  (venue_activity_count / 100)       # Popular venues = higher priority
```

---

### Component 2: Deduplication Fix (CRITICAL)

**File**: `lib/eventasaurus_discovery/venue_images/orchestrator.ex:669`

**Change**:
```elixir
# Before
|> Enum.group_by(fn img -> img["url"] end)

# After
|> Enum.group_by(fn img -> img["provider_url"] || img["url"] end)
```

**Impact**:
- Failed and successful uploads of same photo will deduplicate
- Successful upload replaces failed one (keeps higher quality_score + newer fetched_at)
- Safe to re-run enrichment without creating duplicates

**Priority**: HIGH - Blocks safe re-enrichment

---

### Component 3: Intelligent Retry Worker (NEW)

**File**: `lib/eventasaurus_discovery/venue_images/failed_upload_retry_worker.ex`

**Purpose**: Retry transient failures WITHOUT calling provider API

**Logic**:
```elixir
defmodule EventasaurusDiscovery.VenueImages.FailedUploadRetryWorker do
  use Oban.Worker, queue: :venue_enrichment, max_attempts: 3

  @transient_errors ["rate_limited", "service_unavailable", "network_timeout",
                     "gateway_timeout", "bad_gateway"]

  def perform(%Oban.Job{args: %{"venue_id" => venue_id}}) do
    venue = Repo.get!(Venue, venue_id)

    # Find retryable failures
    {retryable, permanent} =
      venue.venue_images
      |> Enum.split_with(fn img ->
        img["upload_status"] == "failed" &&
        img["error_details"]["error_type"] in @transient_errors
      end)

    if Enum.empty?(retryable) do
      {:ok, "No retryable failures"}
    else
      # Retry each failed upload with delays
      retry_results =
        retryable
        |> Enum.with_index()
        |> Enum.map(fn {img, index} ->
          if index > 0 do
            delay_ms = calculate_upload_delay(img["provider"], index)
            Process.sleep(delay_ms)
          end

          retry_upload(venue, img)
        end)

      # Merge retry results with existing images
      update_venue_images(venue, retry_results, permanent)
    end
  end

  defp retry_upload(venue, failed_img) do
    # Use existing upload_to_imagekit logic
    # Update upload_status based on result
  end
end
```

**Trigger**:
- Nightly scheduled job scans for venues with transient failures
- Admin dashboard "Retry Transient" button
- Automatic after failed enrichment job (if transient errors detected)

---

### Component 4: Scheduled Cleanup Job

**File**: `lib/eventasaurus_discovery/venue_images/cleanup_scheduler.ex`

**Purpose**: Nightly scan to identify and queue retry jobs

**Logic**:
```elixir
defmodule EventasaurusDiscovery.VenueImages.CleanupScheduler do
  use Oban.Worker, queue: :maintenance

  def perform(_job) do
    # Query venues with failed uploads
    venues_with_failures =
      from(v in Venue,
        where: fragment("? @> ?", v.venue_images, ^[%{"upload_status" => "failed"}])
      )
      |> Repo.all()

    # Classify and queue retry jobs
    Enum.each(venues_with_failures, fn venue ->
      {transient_count, permanent_count} = classify_failures(venue)

      if transient_count > 0 do
        FailedUploadRetryWorker.new(%{venue_id: venue.id})
        |> Oban.insert()
      end

      if permanent_count > 0 do
        # Maybe log or alert for manual review
        Logger.info("Venue #{venue.id} has #{permanent_count} permanent failures")
      end
    end)

    :ok
  end
end
```

**Schedule**: Add to Oban cron (config/config.exs):
```elixir
# Run daily at 4 AM UTC (after city discovery at midnight)
{"0 4 * * *", EventasaurusDiscovery.VenueImages.CleanupScheduler}
```

---

### Component 5: Enhanced enrich_venue Options

**Add new option**: `retry_failed_only: true`

**Purpose**: Skip provider API call if we already have failed images to retry

**Logic**:
```elixir
def enrich_venue(venue, opts \\ []) do
  retry_failed_only = Keyword.get(opts, :retry_failed_only, false)

  if retry_failed_only do
    # Only retry existing failed uploads, don't call provider
    FailedUploadRetryWorker.perform_now(venue)
  else
    # Normal enrichment flow
    do_enrich_venue(venue, providers, max_retries)
  end
end
```

**Usage**:
```elixir
# Retry only failed uploads (no API call)
Orchestrator.enrich_venue(venue, retry_failed_only: true)

# Full re-enrichment (calls provider API, gets fresh photos)
Orchestrator.enrich_venue(venue, force: true)
```

---

## Implementation Phases

### Phase 3.1: Foundation (Week 1)
- [ ] Fix deduplication logic (provider_url)
- [ ] Add SQL queries to admin dashboard
- [ ] Create "Failed Upload Monitor" widget
- [ ] Test deduplication with mixed failed/successful images

### Phase 3.2: Automated Retry (Week 2)
- [ ] Implement FailedUploadRetryWorker
- [ ] Add retry_failed_only option to enrich_venue
- [ ] Create admin "Retry Transient" button
- [ ] Test retry logic with production-like failures

### Phase 3.3: Scheduled Maintenance (Week 3)
- [ ] Implement CleanupScheduler
- [ ] Add Oban cron job (4 AM daily)
- [ ] Implement max retry tracking (prevent infinite loops)
- [ ] Add metrics: retry_success_rate, retries_per_venue

### Phase 3.4: Permanent Failure Handling (Week 4)
- [ ] Add permanently_failed status to skip future retries
- [ ] Implement classification logic in cleanup scheduler
- [ ] Add admin alerts for high permanent failure rates
- [ ] Create runbook for investigating permanent failures

---

## Success Metrics

### Immediate (After Phase 3.1)
- ✅ Venues with partial failures identifiable via dashboard
- ✅ Re-enrichment doesn't create duplicates (dedup fix)
- ✅ Operators can trigger batch retry with single click

### Short-term (After Phase 3.2)
- ✅ Transient failures auto-retry within 24 hours
- ✅ Retry success rate >80% for transient errors
- ✅ Manual intervention only for permanent failures

### Long-term (After Phase 3.4)
- ✅ <1% of venues have unrecovered transient failures
- ✅ Permanent failures classified and excluded from retry
- ✅ Zero operational burden for partial upload recovery

---

## Risk Assessment

### Low Risk
- Deduplication fix (1-line change, well-tested logic)
- SQL queries (read-only analysis)
- Admin dashboard widgets (visibility only)

### Medium Risk
- FailedUploadRetryWorker (new code path, needs thorough testing)
- Scheduled cleanup job (must handle errors gracefully)

### Mitigation Strategies
- Start with manual retry (admin button) before automation
- Add max_retry_attempts to prevent infinite loops
- Monitor retry success rates in first week
- Implement circuit breaker if retry success rate <50%

---

## Cost Analysis

### Development Cost
- Phase 3.1: 8 hours (dedup fix + dashboard queries)
- Phase 3.2: 16 hours (retry worker + testing)
- Phase 3.3: 8 hours (scheduler + monitoring)
- Phase 3.4: 8 hours (permanent failure handling)
- **Total**: ~40 hours (~1 week)

### Operational Savings
- **Before**: Manual investigation + fix per venue = 15 min/venue
- **After**: Automated retry = 0 min/venue
- **Break-even**: After ~160 venues with partial failures

### Data Quality Improvement
- Current: ~40% success rate on rate-limited images (pre-Phase 2)
- Phase 2: ~95% success rate on first attempt
- Phase 3: ~98% success rate after automatic retry

---

## Dependencies

### Must Complete Before Phase 3
- ✅ Phase 1: Enhanced observability (COMPLETED)
- ✅ Phase 2: Rate limiting + retry logic (COMPLETED)

### Optional Enhancements
- Admin dashboard redesign (can add widget to existing dashboard)
- Monitoring/alerting system (can use Logger for now)

---

## Alternatives Considered

### Alternative 1: "Just Re-run Full Enrichment"
**Pros**: Simple, uses existing code
**Cons**: Wastes API calls, might get different photos, creates duplicates without dedup fix
**Verdict**: Not optimal, but viable short-term workaround

### Alternative 2: "Accept Data Loss"
**Pros**: Zero development effort
**Cons**: Poor user experience, wastes API costs, data quality issues
**Verdict**: Unacceptable for production system

### Alternative 3: "Manual SQL Updates"
**Pros**: No code changes needed
**Cons**: Requires DB access, error-prone, doesn't scale, no retry logic
**Verdict**: Emergency-only approach

---

## Recommended Immediate Action

1. **Fix deduplication** (orchestrator.ex:669) - 5 minutes
2. **Add SQL queries to admin notes** - 10 minutes
3. **Test re-enrichment** with `force: true` on Krakow venues with partial failures
4. **Monitor results** from Phase 2 deployment (should see <5% partial failures going forward)

Then decide if full Phase 3 implementation is warranted based on:
- Frequency of partial failures after Phase 2
- Operator time spent on manual fixes
- User feedback on incomplete image galleries

---

## References

- Issue #2006: Google Places Image Rate Limiting
- Phase 1 Implementation: Enhanced Observability
- Phase 2 Implementation: Rate Limiting & Prevention
- Oban Configuration: config/config.exs:93-151
- Orchestrator Logic: lib/eventasaurus_discovery/venue_images/orchestrator.ex
