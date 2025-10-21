# Venue Images Load Testing Guide

## Overview

This document provides guidelines and scenarios for load testing the venue image aggregation system to ensure it performs well under high load and respects provider rate limits.

## Test Scenarios

### Scenario 1: Batch Enrichment Under Normal Load

**Objective**: Test batch processing of venues with multiple providers

**Setup**:
- 100 venues with complete provider_ids
- 3 active image providers (Google Places, Foursquare, HERE)
- Rate limits: 10/sec, 100/min, 1000/hour

**Test Steps**:
```elixir
# In IEx console
alias EventasaurusDiscovery.VenueImages.EnrichmentJob
alias EventasaurusApp.Venues.Venue
alias EventasaurusApp.Repo

# Get 100 stale venues
venue_ids =
  Venue
  |> limit(100)
  |> select([v], v.id)
  |> Repo.all()

# Enqueue batch job
{:ok, job} = EnrichmentJob.enqueue_batch(venue_ids)

# Monitor progress in Oban dashboard at /admin/oban
```

**Expected Results**:
- All 100 venues enriched within 15 minutes
- No rate limit violations
- Total API cost ≤ $3.00
- Success rate ≥ 95%

**Metrics to Monitor**:
- Orchestrator.fetch_venue_images/1 response time: <5s avg
- RateLimiter alerts: 0 critical, <5 warnings
- Provider failures: <5% per provider
- Memory usage: Stable, no leaks

---

### Scenario 2: High Concurrency Stress Test

**Objective**: Test system under maximum concurrent enrichment load

**Setup**:
- 500 venues simultaneously enqueued
- All providers active
- Monitor rate limiter behavior

**Test Steps**:
```elixir
# Enqueue many individual jobs to test concurrency
venue_ids = Venue |> limit(500) |> select([v], v.id) |> Repo.all()

# Queue all individually (tests queue concurrency)
Enum.each(venue_ids, fn id ->
  EnrichmentJob.enqueue_venue(id)
end)

# Monitor Oban queue depth
# Should see queue process at max concurrency (2) without errors
```

**Expected Results**:
- Queue processes at configured concurrency (2)
- No deadlocks or timeouts
- Rate limits respected across all jobs
- Memory usage stays below 500MB

**Key Observations**:
- ETS rate limiter handles concurrent access correctly
- Task.async_stream concurrency control works (max 5)
- Provider timeout handling (15s) effective

---

### Scenario 3: Rate Limit Edge Cases

**Objective**: Verify rate limit enforcement and recovery

**Setup**:
- Configure aggressive rate limits (5/sec, 20/min)
- Enqueue 50 venues rapidly

**Test Steps**:
```elixir
alias EventasaurusDiscovery.VenueImages.RateLimiter

# Lower rate limits temporarily
# (modify provider metadata in database)

# Enqueue batch
venue_ids = Venue |> limit(50) |> select([v], v.id) |> Repo.all()
EnrichmentJob.enqueue_batch(venue_ids)

# Monitor rate limit stats
RateLimiter.get_stats("google_places")
RateLimiter.get_stats("foursquare")
```

**Expected Results**:
- Jobs slow down when limits approach
- Providers correctly skipped when rate limited
- Jobs succeed after rate limit windows reset
- No duplicate API calls

**Validation**:
```elixir
# Check logs for rate limit warnings
grep "Rate limit exceeded" log/dev.log

# Verify stats show proper throttling
EventasaurusDiscovery.VenueImages.Monitor.check_alerts()
```

---

### Scenario 4: Provider Failure Resilience

**Objective**: Test system behavior when providers fail or timeout

**Setup**:
- Temporarily disable network access for one provider
- Or modify provider to return errors

**Test Steps**:
```elixir
# Temporarily mark provider as inactive
provider = Repo.get_by(GeocodingProvider, name: "google_places")
Repo.update(Ecto.Changeset.change(provider, is_active: false))

# Enqueue batch
venue_ids = Venue |> limit(20) |> select([v], v.id) |> Repo.all()
EnrichmentJob.enqueue_batch(venue_ids)

# Verify other providers still work
```

**Expected Results**:
- Jobs complete successfully with remaining providers
- Metadata correctly reports failed providers
- Retry logic handles transient failures (max 3 retries)
- Venues get images from successful providers only

---

### Scenario 5: Image Deduplication Performance

**Objective**: Test URL-based deduplication with many duplicate images

**Setup**:
- Venues where multiple providers return same images
- Monitor deduplication performance

**Test Observations**:
- Deduplication happens in-memory efficiently
- Final image count accurate
- Position sorting preserves provider priority
- No duplicate URLs in final results

---

## Performance Benchmarks

### Target Metrics

| Metric | Target | Critical Threshold |
|--------|--------|-------------------|
| Orchestrator response time | <3s avg | >10s |
| Single venue enrichment | <5s | >15s |
| Batch enrichment (100 venues) | <10 min | >30 min |
| Memory per enrichment | <10MB | >50MB |
| API cost per venue | <$0.05 | >$0.20 |

### Rate Limit Compliance

| Provider | Limit | Test Load | Expected Behavior |
|----------|-------|-----------|-------------------|
| Google Places | 10/sec | 50 venues/min | Throttle to 9/sec |
| Foursquare | 100/min | 200 venues/hr | Smooth distribution |
| HERE | 5/sec | 30 venues/min | Queue requests |

---

## Monitoring During Load Tests

### Admin Dashboard

Access: `http://localhost:4000/admin/venue-images/stats`

Monitor:
- Real-time rate limit usage
- Provider health status
- Active alerts (warnings/critical)
- Cost accumulation

### Oban Dashboard

Access: `http://localhost:4000/admin/oban`

Monitor:
- Queue depth and processing rate
- Job failures and retries
- Processing time distribution
- Worker utilization

### IEx Monitoring

```elixir
# Real-time provider stats
alias EventasaurusDiscovery.VenueImages.Monitor
Monitor.log_health_check()

# Rate limiter stats
alias EventasaurusDiscovery.VenueImages.RateLimiter
RateLimiter.get_stats("google_places")

# Check for alerts
Monitor.check_alerts()

# Orchestrator stats for a test venue
alias EventasaurusDiscovery.VenueImages.Orchestrator
venue = Repo.get(Venue, 1)
{:ok, images, metadata} = Orchestrator.fetch_venue_images(venue)
metadata
```

---

## Troubleshooting

### High Rate Limit Violations

**Symptoms**: Many `rate_limited` errors in logs

**Solution**:
```elixir
# Reduce Oban concurrency
# In config/config.exs:
config :eventasaurus, Oban,
  queues: [
    venue_enrichment: 1  # Reduce from 2 to 1
  ]

# Or add delays between requests
# In Orchestrator:
Process.sleep(100)  # Add 100ms delay
```

### Memory Leaks

**Symptoms**: Increasing memory usage over time

**Check**:
```elixir
# Monitor ETS table size
:ets.info(:venue_images_rate_limits, :size)

# Force cleanup if needed
send(EventasaurusDiscovery.VenueImages.RateLimiter, :cleanup)
```

### Slow Enrichment

**Symptoms**: Jobs taking >30s per venue

**Debug**:
```elixir
# Check provider response times
alias EventasaurusDiscovery.Geocoding.Providers.GooglePlaces
{time, result} = :timer.tc(fn ->
  GooglePlaces.get_images("test_place_id")
end)
IO.puts("Provider response: #{time / 1_000_000}s")

# Check database query performance
{time, _} = :timer.tc(fn ->
  Orchestrator.get_enabled_image_providers()
end)
IO.puts("Provider query: #{time / 1_000}ms")
```

---

## Production Load Testing Checklist

Before production deployment:

- [ ] Test with production-like provider rate limits
- [ ] Verify cost projections for 10,000+ venues
- [ ] Test scheduled cron job (4 AM UTC) behavior
- [ ] Confirm database update performance with JSONB
- [ ] Validate image deduplication with real provider data
- [ ] Test enrichment staleness policy (30-day threshold)
- [ ] Verify retry logic handles production API failures
- [ ] Monitor memory usage over 24-hour period
- [ ] Test manual enrichment trigger from admin UI
- [ ] Validate flash messages and error handling
- [ ] Confirm rate limiter cleanup runs correctly
- [ ] Test with venues missing provider_ids gracefully

---

## Load Testing Tools

### Manual Testing (IEx)

```elixir
# Start with small batch
alias EventasaurusDiscovery.VenueImages.EnrichmentJob
{:ok, job} = EnrichmentJob.enqueue()

# Monitor in real-time
:observer.start()  # GUI monitoring tool

# Or terminal-based
:recon.proc_count(:memory, 10)  # Top 10 memory users
```

### Automated Testing (ExUnit)

```elixir
# Run load tests
mix test test/eventasaurus_discovery/venue_images/orchestrator_test.exs
mix test test/eventasaurus_discovery/venue_images/rate_limiter_test.exs
```

### External Tools

- **Apache Bench**: HTTP endpoint load testing
- **Locust**: Python-based distributed load testing
- **k6**: Modern load testing tool with JavaScript

---

## Success Criteria

Load testing is considered successful when:

1. ✅ All test scenarios complete without critical failures
2. ✅ Rate limits respected across all providers (<1% violations)
3. ✅ Cost per venue stays within budget (<$0.05)
4. ✅ Memory usage stable over 1-hour continuous operation
5. ✅ 95th percentile response time <10s
6. ✅ Zero deadlocks or database connection pool exhaustion
7. ✅ Admin dashboard shows accurate real-time stats
8. ✅ Background job queue processes without backlog

---

## Post-Testing Actions

1. **Reset Test Data**: Clear test venues and rate limiter stats
2. **Document Results**: Record actual vs. expected performance
3. **Adjust Configuration**: Update concurrency/limits based on findings
4. **Update Monitoring**: Add alerts for discovered edge cases
5. **Plan Optimizations**: Prioritize performance improvements
