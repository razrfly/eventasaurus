# PostHog Timeout Fix Documentation

## Problem

PostHog API requests were timing out with the error:
```
[error] PostHog API request failed: :timeout
```

## Root Causes

1. **Complex HogQL queries** - The analytics query was counting multiple event types in a single query
2. **EU PostHog instance latency** - The EU instance (eu.i.posthog.com) may have higher latency
3. **Large event volume** - Queries scanning many events take longer to execute

## Solutions Implemented

### 1. Increased Timeouts
- Analytics API requests: 30 seconds (was 10 seconds)
- Event tracking requests: 10 seconds (was 5 seconds)
- GenServer call timeout: 35 seconds (was 5 seconds)

### 2. Query Optimization
- Added `LIMIT 10000` to prevent unbounded queries
- Implemented simplified fallback query that only counts page views
- Fallback executes if main query times out

### 3. Enhanced Caching
- Increased cache TTL from 5 to 15 minutes
- Added `get_cached_analytics/2` to retrieve stale cache on timeout
- Stale cache is better than no data for dashboards

### 4. Graceful Degradation
- Timeout returns default zero values instead of crashing
- Logs warnings but doesn't break the application
- Returns partial data (visitors only) if simplified query succeeds

## Configuration Options

### Disable PostHog Analytics (if timeouts persist)

In your `.env` file, you can disable analytics queries while keeping event tracking:
```bash
# Keep event tracking enabled
POSTHOG_PUBLIC_API_KEY=phc_xxxxx

# Remove or comment out to disable analytics
# POSTHOG_PRIVATE_API_KEY=phx_xxxxx
# POSTHOG_PROJECT_ID=xxxxx
```

### Environment Variables

- `POSTHOG_PUBLIC_API_KEY` - For event tracking (required)
- `POSTHOG_PRIVATE_API_KEY` - For analytics queries (optional)
- `POSTHOG_PROJECT_ID` - For analytics queries (optional)

## Testing the Fix

1. Monitor logs for timeout warnings:
   ```
   PostHog analytics timeout for event X, returning default values
   PostHog analytics timeout, trying simplified query for event X
   Found stale cached data for event X
   ```

2. Check if analytics data loads (even if slowly):
   - Event dashboard should show visitor counts
   - Registration rates may show as 0 if only simplified query works

3. Verify event tracking still works:
   - Poll events should still be tracked
   - Check PostHog dashboard for new events

## Future Improvements

1. **Pre-aggregate data** - Use PostHog's data warehouse features
2. **Batch queries** - Fetch multiple events' analytics in one request
3. **Background jobs** - Update analytics asynchronously
4. **Regional optimization** - Consider US PostHog instance if latency persists

## Rollback Plan

If issues persist, you can:
1. Remove analytics features temporarily
2. Show "Analytics unavailable" message
3. Focus on event tracking only