# Venue Image Operations Page - Implementation Summary

## Overview

Created a new admin page for viewing and retrying venue image enrichment operations, similar to the existing geocoding operations page.

## What Was Created

### 1. LiveView Module
**File**: `lib/eventasaurus_web/live/admin/venue_image_operations_live.ex`

**Features**:
- Shows last 50 venue image enrichment jobs from Oban
- Displays job-level statistics (images discovered/uploaded/failed)
- Provider filter dropdown
- Error type filter dropdown
- Expandable job details with per-image failure information
- Individual venue retry button
- Batch retry button for all failures

**Event Handlers**:
- `filter_provider` - Filter operations by provider (Google Places, Foursquare, etc.)
- `filter_error_type` - Filter operations by error type (rate_limited, network_timeout, etc.)
- `toggle_job_details` - Expand/collapse detailed job information
- `refresh` - Reload operations from database
- `retry_all_failed` - Queue batch retry job via `CleanupScheduler.enqueue()`
- `retry_venue` - Queue individual venue retry via `FailedUploadRetryWorker.enqueue_venue(venue_id)`

### 2. Template
**File**: `lib/eventasaurus_web/live/admin/venue_image_operations_live.html.heex`

**Sections**:
1. **Summary Stats Cards**
   - Total operations
   - Images uploaded (green)
   - Images failed (red)
   - Retryable failures (orange)

2. **Operations Table**
   - Timestamp
   - Venue ID
   - Status badge (success/failed/no_images)
   - Duration
   - Results summary with expand/collapse
   - Cost
   - Retry button (only shows if has transient failures)

3. **Expanded Job Details** (when clicking "Show Details")
   - Operation summary with all metrics
   - Provider results grid (success/failed per provider)
   - Failure breakdown by error type (with retryable indicator)
   - Failed images table with:
     - Provider badge
     - Error type badge with icon
     - HTTP status code
     - Timestamp
     - Provider URL (clickable)
   - Successfully uploaded images gallery (first 8 thumbnails)
   - Raw job data (collapsible JSON)

### 3. Routes
**File**: `lib/eventasaurus_web/router.ex`

**Development Route** (line 72):
```elixir
live "/venue-images/operations", Admin.VenueImageOperationsLive
```
URL: `http://localhost:4000/admin/venue-images/operations`

**Production Route** (line 168):
```elixir
live "/venue-images/operations", EventasaurusWeb.Admin.VenueImageOperationsLive
```
URL: `/admin/venue-images/operations` (requires admin authentication)

## Data Source

Queries Oban jobs table for:
- Worker: `EventasaurusDiscovery.VenueImages.EnrichmentJob`
- State: `completed` or `discarded`
- Ordered by: `completed_at DESC`
- Limit: 50 most recent

## Metadata Used from Oban Jobs

From `job.meta` field:
- `status` - Job status (success/failed/no_images/error)
- `images_discovered` - Total images found
- `images_uploaded` - Successfully uploaded count
- `images_failed` - Failed upload count
- `failure_breakdown` - Map of error_type => count
- `failed_images` - Array of failed image details
- `providers` - Map of provider => status/details
- `total_cost_usd` - Cost in USD
- `summary` - Human-readable summary
- `imagekit_urls` - Array of uploaded image URLs
- `completed_at` - Completion timestamp

From `job.args` field:
- `venue_id` - For single venue jobs
- `venue_ids` - For batch jobs

## Error Classification

### Transient Errors (Retryable)
- `rate_limited` ⏱️ - Can retry after delay
- `network_timeout` 🌐 - Network timeout
- `network_error` 🌐 - General network issues
- `gateway_timeout` - HTTP 504
- `bad_gateway` - HTTP 502
- `service_unavailable` - HTTP 503

### Permanent Errors (Not Retryable)
- `not_found` ❓ - HTTP 404
- `forbidden` 🚫 - HTTP 403
- `auth_error` 🔐 - API authentication failed

## Retry Functionality

### Batch Retry
**Button**: "🔄 Retry All Failed" (orange, top-right)

**Action**: Calls `CleanupScheduler.enqueue()`

**What it does**:
1. Scans all venues with failed uploads
2. Classifies failures as transient/permanent/ambiguous
3. Queues `FailedUploadRetryWorker` for venues with transient failures only
4. Shows flash message: "✅ Batch retry queued - will scan all venues and retry transient failures"

### Individual Venue Retry
**Button**: "🔄 Retry" (per row, only visible if has transient failures)

**Action**: Calls `FailedUploadRetryWorker.enqueue_venue(venue_id)`

**What it does**:
1. Queues retry job for specific venue
2. Only retries images with transient error types
3. Respects max retry count (3 attempts per image)
4. Shows flash message: "✅ Retry queued for venue #[venue_id]"

## Visual Design

### Color Coding
- **Green**: Success, uploaded images
- **Red**: Failed images, permanent errors
- **Orange**: Retryable failures, warnings
- **Yellow**: Rate limited errors
- **Gray**: No images, neutral states
- **Blue**: Expanded details background

### Status Badges
- Success: Green rounded pill
- Failed: Red rounded pill
- No Images: Gray rounded pill
- Partial: Yellow rounded pill (not currently used)

### Provider Badges
- Google Places: Orange
- Foursquare: Pink
- HERE: Purple
- Mapbox: Blue
- Others: Gray

### Error Type Badges
- Rate Limited: Yellow with ⏱️
- Network Timeout/Error: Orange with 🌐
- Not Found: Red with ❓
- Forbidden: Red with 🚫
- Auth Error: Red with 🔐

## Comparison to Geocoding Operations Page

### Similar Features
- Recent operations table with expand/collapse
- Provider filter dropdown
- Refresh button
- Detailed job metadata display
- Raw JSON data viewer
- Same visual design language

### New Features (not in geocoding page)
- **Error type filter** - Filter by specific error types
- **Retry buttons** - Individual and batch retry functionality
- **Failure breakdown** - Visual error type breakdown with counts
- **Failed images table** - Detailed per-image failure information
- **Retryable indicator** - Shows which errors can be retried
- **Image gallery** - Thumbnails of successfully uploaded images
- **Summary stats cards** - Top-level metrics dashboard

### Key Differences
- **Focus**: Image enrichment instead of geocoding
- **Granularity**: Per-image failure details vs. per-venue results
- **Actionability**: Retry buttons for failed operations
- **Error classification**: Transient vs. permanent error distinction

## Usage Example

1. **Navigate** to `/admin/venue-images/operations`

2. **View recent operations** in the table

3. **Filter by provider** if debugging specific provider issues

4. **Click "Show Details"** to see:
   - Which images failed and why
   - Error types and HTTP status codes
   - Successfully uploaded images
   - Provider-level success/failure breakdown

5. **Retry individual venue** if it has transient failures:
   - Click "🔄 Retry" button in the Actions column
   - Job will be queued and processed by Oban

6. **Retry all failures** in batch:
   - Click "🔄 Retry All Failed" at top-right
   - CleanupScheduler will scan all venues and queue retries

7. **Monitor progress**:
   - Click "🔄 Refresh" to reload operations
   - Check for new successful uploads
   - Failed counts should decrease after retries

## Integration with Existing Systems

### Works With
- ✅ `CleanupScheduler` - For batch retries
- ✅ `FailedUploadRetryWorker` - For individual retries
- ✅ `EnrichmentJob` - Data source via Oban metadata
- ✅ Oban job queue - All retries queued through Oban
- ✅ Stats module - Classification logic matches
- ✅ Monitor module - Provider statistics

### Complements
- **Venue Images Stats Page** (`/admin/venue-images/stats`)
  - Stats page: Real-time provider rate limits and alerts
  - Operations page: Historical job results and retry capability

- **Discovery Stats City Detail** (`/admin/discovery/stats/city/:city_slug`)
  - City stats: Venue-level image counts and needs
  - Operations page: Job-level enrichment history

## Benefits

1. **Visibility**: See exactly what happened during each enrichment attempt
2. **Debugging**: Filter by provider or error type to identify patterns
3. **Recovery**: Retry failed uploads without manual intervention
4. **Cost Tracking**: View costs per operation and provider
5. **Audit Trail**: Complete history of enrichment attempts
6. **Confidence**: Visual confirmation of successful uploads via image gallery

## Future Enhancements

Potential improvements for future consideration:

1. **City-specific view**: Filter operations by city (like geocoding operations)
2. **Date range filter**: Filter operations by date range
3. **Export functionality**: Download operation history as CSV/JSON
4. **Success rate graph**: Visual chart of success rates over time
5. **Provider comparison**: Side-by-side provider performance metrics
6. **Auto-refresh**: Optional auto-refresh like stats page
7. **Bulk actions**: Select multiple operations for batch retry
8. **Error grouping**: Group similar errors for easier debugging
9. **Retry scheduling**: Schedule retries for off-peak hours
10. **Notification system**: Alert when high failure rates detected

---

**Status**: ✅ Implemented and ready for testing
**Compilation**: ✅ Clean compilation with no errors
**Route**: `/admin/venue-images/operations` (dev and production)
