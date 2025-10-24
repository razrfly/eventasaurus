# Admin Button Implementation: Retry Failed Uploads

## Summary

Added a **"Retry Failed Uploads"** button to the Venue Images Stats admin dashboard for manual triggering of the Phase 3 cleanup scheduler.

## Location

**URL**: `/admin/venue-images/stats`

**File**: `lib/eventasaurus_web/live/admin/venue_images_stats_live.ex`

## Features Added

### 1. Retry Failed Uploads Button

- **Location**: Top right of the page, next to "Enqueue Enrichment" button
- **Color**: Orange (indicates recovery action)
- **Icon**: 🔄
- **Tooltip**: "Retry transient failed uploads without calling provider APIs"

**What it does**:
1. Triggers `CleanupScheduler.enqueue()`
2. Scans all venues with failed uploads
3. Queues `FailedUploadRetryWorker` jobs for venues with transient failures
4. Shows success/error flash message

### 2. Failed Upload Summary Dashboard

**Displays** (only shown if failures exist):
- **Venues with Failures**: Total count of venues with at least one failed image
- **Failed Images**: Total count of all failed image uploads
- **Transient Failures**: Venues with retryable errors (green, "Can be retried")
- **Permanent Failures**: Venues with permanent errors (red, "Need manual review")

**Auto-refresh**: Updates every 10 seconds along with rate limit stats

## Usage

1. Navigate to `/admin/venue-images/stats`
2. Check the **Failed Upload Summary** section (orange box)
3. Click **"Retry Failed Uploads"** button
4. Monitor Oban dashboard to see retry jobs being processed
5. Stats will refresh automatically showing progress

## Implementation Details

### Button Handler (lines 42-59)

```elixir
def handle_event("retry_failed_uploads", _params, socket) do
  case CleanupScheduler.enqueue() do
    {:ok, _job} ->
      put_flash(:info, "✅ Cleanup job enqueued - will scan venues and retry failed uploads")
    {:error, reason} ->
      put_flash(:error, "❌ Failed to enqueue cleanup job: #{inspect(reason)}")
  end
end
```

### Stats Loading (lines 199-209)

```elixir
defp load_stats(socket) do
  stats = Monitor.get_all_stats()
  alerts = Monitor.check_alerts()
  failure_summary = Stats.summary_stats()  # ← NEW

  assign(socket, :failure_summary, failure_summary)
end
```

### UI Changes

**Before**:
- Single "Enqueue Enrichment" button
- No failure visibility

**After**:
- Two buttons: "Retry Failed Uploads" (orange) + "Enqueue Enrichment" (blue)
- Failed Upload Summary section with 4 metrics
- Auto-refresh every 10 seconds

## Testing

### Manual Test Steps

1. **Verify page loads**:
   ```bash
   mix phx.server
   # Visit: http://localhost:4000/admin/venue-images/stats
   ```

2. **Verify button works**:
   - Click "Retry Failed Uploads"
   - Should see flash message: "✅ Cleanup job enqueued..."
   - Check Oban dashboard for queued job

3. **Verify stats display**:
   - If no failures exist, summary section should not display
   - If failures exist, should see orange box with 4 metrics

### Expected Workflow

```text
User clicks button
  ↓
CleanupScheduler.enqueue()
  ↓
Job queued in :maintenance queue
  ↓
CleanupScheduler.perform/1 runs
  ↓
Scans all venues with failures (Stats.venues_with_failures())
  ↓
For each venue:
  - Classify errors (transient vs permanent)
  - Queue FailedUploadRetryWorker if transient
  ↓
FailedUploadRetryWorker jobs process in :venue_enrichment queue
  ↓
Stats refresh automatically (10s interval)
  ↓
Failure counts decrease as retries succeed
```

## Integration with Phase 3

This button provides the **manual trigger** requested by the user for the Phase 3 Partial Upload Recovery System.

**Alternatives to button**:
```elixir
# IEx console
CleanupScheduler.enqueue()

# Specific venue
FailedUploadRetryWorker.enqueue_venue(123)

# Immediate retry (synchronous)
venue = Repo.get!(Venue, 123)
Orchestrator.enrich_venue(venue, retry_failed_only: true)
```

## Files Modified

1. `lib/eventasaurus_web/live/admin/venue_images_stats_live.ex`
   - Added `Stats` and `CleanupScheduler` aliases
   - Added `handle_event("retry_failed_uploads")` handler
   - Added failure summary UI section
   - Updated `load_stats/1` to load failure summary

## Dependencies

No new dependencies. Uses:
- Existing `Stats` module (Phase 3)
- Existing `CleanupScheduler` worker (Phase 3)
- Existing admin layout and styling
- Existing Phoenix LiveView infrastructure

## Benefits

✅ **One-click retry** - No need for IEx console access
✅ **Real-time visibility** - See failure counts and retry progress
✅ **Safe operation** - Only retries transient failures, skips permanent
✅ **No API waste** - Uses existing provider_urls, no new API calls
✅ **Self-service** - Admins can trigger recovery without developer help

## Future Enhancements

- Add drill-down to see specific venues with failures
- Show recent cleanup job results
- Add "Retry Single Venue" button with venue selector
- Show estimated time to completion
- Add confirmation dialog before triggering
- Display last cleanup run timestamp
