# PostHog Monitoring Documentation

## Overview

The PostHog monitoring system tracks the health and performance of PostHog integration in Eventasaurus. It provides real-time metrics, alerts, and health status for both event tracking and analytics APIs.

## Components

### 1. PosthogMonitor Service (`/lib/eventasaurus/services/posthog_monitor.ex`)

A GenServer that collects and aggregates metrics:
- Request success/failure rates
- Response times (min/avg/max)
- Timeout frequency
- Cache hit rates
- Failure categorization

### 2. Health Check API

```elixir
# Get current health status
{status, message} = Eventasaurus.Services.PosthogMonitor.health_check()
# Returns: {:healthy | :degraded | :unhealthy, "message"}

# Get detailed stats
stats = Eventasaurus.Services.PosthogMonitor.get_stats()
```

### 3. PosthogHealthComponent LiveView

Visual dashboard component showing:
- Overall service health status
- Configuration status
- Real-time metrics
- Auto-refreshes every 30 seconds

## Metrics Tracked

### Analytics API Metrics
- Total requests
- Success/failure rates
- Average response time
- Cache hit rate
- Timeout rate
- Failure breakdown by type

### Event Tracking Metrics
- Total events sent
- Success/failure rates
- Failed event count
- Response times

## Health Status Thresholds

### Unhealthy
- Failure rate > 50%
- Triggers error logs and alerts

### Degraded
- Timeout rate > 30%
- Average response time > 15 seconds
- Triggers warning logs

### Healthy
- All metrics within normal ranges

## Automatic Actions

### Logging
- Summary logs every 5 minutes (if activity)
- Error logs for critical failures
- Warning logs for degraded performance

### Alerts
- Repeated timeouts (5+ in period) trigger immediate error logs
- High failure rates trigger alert logs
- Could be extended to send emails/Slack/PagerDuty

### Stats Reset
- Metrics reset every hour to prevent unbounded growth
- Provides fresh period for trend analysis

## Integration Points

### PosthogService Integration

The monitor is automatically called by PosthogService:
```elixir
# On success
PosthogMonitor.record_success(:analytics, duration_ms)

# On failure
PosthogMonitor.record_failure(:analytics, reason)

# Cache operations
PosthogMonitor.record_cache_hit(:analytics)
PosthogMonitor.record_cache_miss(:analytics)
```

### Application Supervisor

Started automatically in application.ex:
```elixir
children = [
  Eventasaurus.Services.PosthogService,
  Eventasaurus.Services.PosthogMonitor,
  # ...
]
```

## Usage Examples

### Check Health in IEx

```elixir
# Check current health
iex> Eventasaurus.Services.PosthogMonitor.health_check()
{:healthy, "All systems operational"}

# Get detailed stats
iex> stats = Eventasaurus.Services.PosthogMonitor.get_stats()
iex> stats.analytics.success_rate
0.95

# View specific metrics
iex> stats.analytics.timeout_rate
0.05
```

### Add to Admin Dashboard

```elixir
# In your admin LiveView
<.live_component
  module={EventasaurusWeb.Live.Components.PosthogHealthComponent}
  id="posthog-health"
/>
```

### Custom Alerts

Extend the monitor for custom alerting:
```elixir
defp check_and_alert(stats, type) do
  # Existing checks...
  
  # Add custom alert
  if stats.failure_rate > 0.8 do
    # Send to external monitoring
    Sentry.capture_message("PostHog #{type} critical failure rate: #{stats.failure_rate}")
    SlackNotifier.send_alert("PostHog down!")
  end
end
```

## Failure Categories

The monitor categorizes failures for better insights:

- `:timeout` - Request timeouts
- `:auth_error` - 401/403 authentication issues
- `:rate_limit` - 429 rate limiting
- `:server_error` - 5xx server errors
- `:config_error` - Missing API keys/project ID
- `:other` - Uncategorized failures

## Performance Impact

The monitoring system has minimal overhead:
- Metrics stored in GenServer state (in-memory)
- No external dependencies
- Async metric recording
- Automatic cleanup of old data

## Troubleshooting

### Monitor Not Starting
Check application.ex includes the monitor in children list

### No Stats Available
- Ensure PostHog operations are being performed
- Check monitor is running: `Process.whereis(Eventasaurus.Services.PosthogMonitor)`

### Inaccurate Metrics
- Stats reset hourly - check period_duration_minutes
- Ensure all PostHog operations use the monitor

## Future Enhancements

1. **Persistence** - Store historical metrics in database
2. **Dashboards** - Time-series graphs of metrics
3. **External Alerts** - Integration with monitoring services
4. **SLO Tracking** - Define and track service level objectives
5. **Anomaly Detection** - Alert on unusual patterns