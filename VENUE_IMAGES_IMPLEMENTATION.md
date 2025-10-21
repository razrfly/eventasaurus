# Venue Images Aggregation System - Implementation Complete

## Overview

Provider-agnostic venue image aggregation system that fetches, deduplicates, and manages images from multiple providers (Google Places, Foursquare, HERE, Geoapify, Unsplash) with comprehensive rate limiting, cost tracking, and monitoring.

**GitHub Issue**: #1915
**Implementation Date**: 2025-01-21
**Status**: ✅ Complete (All 7 Phases)

---

## Architecture Summary

### Core Components

1. **Orchestrator** (`lib/eventasaurus_discovery/venue_images/orchestrator.ex`)
   - Parallel provider queries using Task.async_stream
   - URL-based image deduplication
   - Cost tracking and metadata aggregation
   - Enrichment workflow with 30-day staleness policy

2. **Provider Behavior** (`lib/eventasaurus_discovery/venue_images/provider.ex`)
   - Unified interface for all image providers
   - Standardized image format with attribution
   - MultiProvider pattern for dual-capability providers

3. **Rate Limiter** (`lib/eventasaurus_discovery/venue_images/rate_limiter.ex`)
   - ETS-based token bucket algorithm
   - Per-second, per-minute, per-hour limits
   - Automatic cleanup every 5 minutes
   - GenServer for concurrent access

4. **Monitor** (`lib/eventasaurus_discovery/venue_images/monitor.ex`)
   - Real-time provider health tracking
   - Rate limit alerting (warning: 80%, critical: 95%)
   - Cost tracking and reporting

5. **Enrichment Job** (`lib/eventasaurus_discovery/venue_images/enrichment_job.ex`)
   - Oban background worker
   - Scheduled daily at 4 AM UTC
   - Batch processing with exponential backoff retry
   - Configurable batch size (100) and max retries (3)

6. **Admin Dashboard** (`lib/eventasaurus_web/live/admin/venue_images_stats_live.ex`)
   - Real-time monitoring (10s auto-refresh)
   - Manual enrichment trigger
   - Alert display and provider stats
   - Accessible at `/admin/venue-images/stats`

---

## Database Schema

### Migrations

1. **20251021172940_add_venue_images_support.exs**
   - Added `venue_images` JSONB field (default: `[]`)
   - Added `image_enrichment_metadata` JSONB field (default: `{}`)
   - Created GIN indices for efficient querying

2. **20251021173010_add_image_providers_and_priorities.exs**
   - Added Unsplash provider
   - Set image priorities for all providers
   - Configured rate limits and costs in metadata

### Data Structure

**venue_images** (JSONB array):
```json
[
  {
    "url": "https://example.com/photo.jpg",
    "width": 1920,
    "height": 1080,
    "provider": "google_places",
    "attribution": "Photo by John Doe",
    "attribution_url": "https://example.com/attribution",
    "position": 1,
    "fetched_at": "2025-01-21T12:00:00Z"
  }
]
```

**image_enrichment_metadata** (JSONB object):
```json
{
  "providers_attempted": ["google_places", "foursquare", "here"],
  "providers_succeeded": ["google_places", "foursquare"],
  "providers_failed": ["here"],
  "total_images_found": 15,
  "total_cost": 0.045,
  "cost_breakdown": {
    "google_places": 0.030,
    "foursquare": 0.000,
    "here": 0.015
  },
  "requests_made": {
    "google_places": 10,
    "foursquare": 5,
    "here": 0
  },
  "last_enriched_at": "2025-01-21T12:00:00Z",
  "next_enrichment_due": "2025-02-20T12:00:00Z",
  "fetched_at": "2025-01-21T12:00:00Z"
}
```

---

## Provider Implementations

### Extended Providers (MultiProvider Pattern)

All providers converted to support multiple capabilities:

1. **Google Places** (`lib/eventasaurus_discovery/geocoding/providers/google_places.ex`)
   - Priority: 1 (highest)
   - Cost: $0.003/image
   - Rate limit: 10/second
   - Capabilities: geocoding, images

2. **Foursquare** (`lib/eventasaurus_discovery/geocoding/providers/foursquare.ex`)
   - Priority: 2
   - Cost: $0.00 (free)
   - Rate limit: 100/minute
   - Capabilities: geocoding, images

3. **HERE** (`lib/eventasaurus_discovery/geocoding/providers/here.ex`)
   - Priority: 3
   - Cost: $0.005/image
   - Rate limit: 5/second
   - Capabilities: geocoding, images

4. **Geoapify** (`lib/eventasaurus_discovery/geocoding/providers/geoapify.ex`)
   - Priority: 10
   - Cost: $0.002/image
   - Rate limit: 10/second
   - Capabilities: geocoding, images

### New Provider

5. **Unsplash** (`lib/eventasaurus_discovery/venue_images/providers/unsplash.ex`)
   - Priority: 99 (fallback)
   - Cost: $0.00 (free tier)
   - Rate limit: 50/hour
   - Capabilities: images only
   - Use case: Stock photos when venue-specific images unavailable

---

## Component Integration

### VenuePhotosComponent

**Updated**: `lib/eventasaurus_web/live/components/venue_photos_component.ex`

**Changes**:
- Added venue_images support (priority #1)
- Maintains backward compatibility with rich_data.images
- Displays provider attribution in photo viewer
- Shows provider source (e.g., "Google Places")
- Supports both atom and string keys from JSONB

**Priority Order**:
1. `venue.venue_images` (new)
2. `rich_data.sections.photos` (standardized)
3. `rich_data.images` (legacy)

### VenueHeroComponent

**Updated**: `lib/eventasaurus_web/live/components/venue_hero_component.ex`

**Changes**:
- Uses first 2 images from venue_images by position
- Maintains backward compatibility with rich_data
- Extracts attribution metadata
- Sorts by position for consistent hero display

---

## Configuration

### Oban Queue

```elixir
# config/config.exs
config :eventasaurus, Oban,
  queues: [
    venue_enrichment: 2  # Concurrent enrichment jobs
  ]
```

### Cron Schedule

```elixir
# config/config.exs
{Oban.Plugins.Cron,
 crontab: [
   {"0 4 * * *", EventasaurusDiscovery.VenueImages.EnrichmentJob}
 ]}
```

### Job Configuration

```elixir
# config/config.exs
config :eventasaurus, EventasaurusDiscovery.VenueImages.EnrichmentJob,
  batch_size: 100,
  max_retries: 3
```

### Application Supervision

```elixir
# lib/eventasaurus/application.ex
children = [
  # ...
  EventasaurusDiscovery.VenueImages.RateLimiter,
  # ...
]
```

---

## Testing

### Unit Tests

1. **orchestrator_test.exs**
   - fetch_venue_images/1 with various scenarios
   - needs_enrichment?/2 staleness detection
   - get_enabled_image_providers/0 ordering
   - Metadata structure validation

2. **rate_limiter_test.exs**
   - check_rate_limit/1 enforcement
   - get_stats/1 tracking
   - reset_limits/1 cleanup
   - Concurrent request handling

### Load Testing

**Documentation**: `test/eventasaurus_discovery/venue_images/LOAD_TESTING.md`

**Scenarios**:
1. Batch enrichment (100 venues)
2. High concurrency stress test (500 venues)
3. Rate limit edge cases
4. Provider failure resilience
5. Image deduplication performance

**Target Metrics**:
- Orchestrator response time: <3s avg
- Single venue enrichment: <5s
- Batch enrichment (100): <10 min
- Memory per enrichment: <10MB
- API cost per venue: <$0.05

---

## Admin Features

### Dashboard Access

- **Development**: `http://localhost:4000/admin/venue-images/stats`
- **Production**: `https://app.wombie.com/admin/venue-images/stats` (admin auth required)

### Features

1. **Real-time Monitoring**
   - Provider status (active/inactive)
   - Priority display
   - Rate limit usage (last second, minute, hour)
   - Cost per image
   - Auto-refresh every 10 seconds

2. **Alerts**
   - Warning alerts (80-95% limit usage)
   - Critical alerts (>95% limit usage)
   - Color-coded severity badges
   - Provider-specific messages

3. **Manual Controls**
   - "Enqueue Enrichment" button
   - Flash messages for success/failure
   - Real-time stats after manual trigger

---

## API Usage

### Direct Enrichment

```elixir
alias EventasaurusDiscovery.VenueImages.Orchestrator
alias EventasaurusApp.Repo
alias EventasaurusApp.Venues.Venue

# Fetch images for a venue
venue = Repo.get(Venue, venue_id)
{:ok, images, metadata} = Orchestrator.fetch_venue_images(venue)

# Enrich venue with images (updates database)
{:ok, enriched_venue} = Orchestrator.enrich_venue(venue)

# Force re-enrichment
{:ok, enriched_venue} = Orchestrator.enrich_venue(venue, force: true)

# Check if enrichment needed
needs_update? = Orchestrator.needs_enrichment?(venue)
```

### Background Jobs

```elixir
alias EventasaurusDiscovery.VenueImages.EnrichmentJob

# Enqueue all stale venues
{:ok, job} = EnrichmentJob.enqueue()

# Enqueue specific venue
{:ok, job} = EnrichmentJob.enqueue_venue(venue_id)

# Enqueue batch
{:ok, job} = EnrichmentJob.enqueue_batch([1, 2, 3, 4, 5])
```

### Monitoring

```elixir
alias EventasaurusDiscovery.VenueImages.Monitor
alias EventasaurusDiscovery.VenueImages.RateLimiter

# Get all provider stats
stats = Monitor.get_all_stats()

# Get specific provider stats
{:ok, stats} = Monitor.get_provider_stats("google_places")

# Check for alerts
alerts = Monitor.check_alerts()

# Log health check
Monitor.log_health_check()

# Get rate limiter stats
stats = RateLimiter.get_stats("google_places")

# Reset rate limits (admin function)
:ok = RateLimiter.reset_limits("google_places")
```

---

## Cost Analysis

### Provider Costs (per image)

| Provider | Cost | Free Tier | Rate Limit |
|----------|------|-----------|------------|
| Google Places | $0.003 | No | 10/sec |
| Foursquare | $0.000 | Yes | 100/min |
| HERE | $0.005 | No | 5/sec |
| Geoapify | $0.002 | Limited | 10/sec |
| Unsplash | $0.000 | Yes | 50/hour |

### Projected Costs

**Assumptions**:
- Average 10 images per venue
- 70% from Google Places (priority 1)
- 20% from Foursquare (free)
- 10% from HERE/Geoapify

**Cost per venue**:
- Google: 7 images × $0.003 = $0.021
- Foursquare: 2 images × $0.000 = $0.000
- HERE: 1 image × $0.005 = $0.005
- **Total**: ~$0.026 per venue

**Monthly estimates**:
- 1,000 venues: ~$26/month
- 10,000 venues: ~$260/month
- 100,000 venues: ~$2,600/month

---

## Performance Optimizations

1. **Parallel Provider Queries**
   - Task.async_stream with max_concurrency: 5
   - 15-second timeout per provider
   - Non-blocking aggregation

2. **ETS-Based Rate Limiting**
   - In-memory tracking (no database overhead)
   - Sliding window algorithm
   - Automatic cleanup of old records

3. **Deduplication**
   - URL-based deduplication (Enum.uniq_by)
   - In-memory sorting by position
   - No database queries for deduplication

4. **Batch Processing**
   - Oban queue with concurrency: 2
   - Batch size: 100 venues
   - Exponential backoff retry (1s, 2s, 4s)

5. **Database Optimization**
   - GIN indices on JSONB fields
   - Efficient staleness queries
   - Single database update per venue

---

## Known Limitations

1. **Provider Dependencies**
   - Requires provider_ids stored in venue record
   - Venues without provider_ids get skipped
   - Providers must support MultiProvider interface

2. **Image Quality**
   - No automated quality scoring
   - Position based on provider priority only
   - No duplicate detection by image content

3. **Attribution**
   - Relies on provider-supplied attribution
   - No automated verification
   - Attribution display optional in UI

4. **Staleness**
   - 30-day hardcoded threshold
   - No per-provider staleness configuration
   - Manual enrichment bypasses staleness check

---

## Future Enhancements

### Potential Improvements

1. **Image Quality Scoring**
   - ML-based image quality assessment
   - Resolution and aspect ratio scoring
   - Automatic best image selection

2. **Content-Based Deduplication**
   - Perceptual hashing (pHash, dHash)
   - Duplicate detection across providers
   - Similar image clustering

3. **Provider Health Monitoring**
   - Historical success rate tracking
   - Automatic provider disabling on failures
   - Circuit breaker pattern

4. **Cost Optimization**
   - Provider selection based on budget
   - Fallback cascade configuration
   - Cost caps and alerts

5. **Image CDN Integration**
   - Automatic image proxying
   - Cloudflare R2 or S3 storage
   - Thumbnail generation
   - Image optimization (WebP, AVIF)

6. **Advanced Scheduling**
   - Priority-based enrichment
   - Peak/off-peak scheduling
   - Venue importance scoring

---

## Deployment Checklist

### Pre-Deployment

- [x] All migrations created and tested
- [x] Provider rate limits configured
- [x] Oban queue configured
- [x] Admin dashboard accessible
- [x] Tests passing
- [x] Load testing complete

### Deployment Steps

1. **Database Migrations**
   ```bash
   mix ecto.migrate
   ```

2. **Provider Configuration**
   - Verify API keys in environment
   - Configure rate limits in provider metadata
   - Set image priorities

3. **Oban Configuration**
   - Verify cron schedule
   - Set appropriate concurrency
   - Configure batch size

4. **Monitoring Setup**
   - Add admin dashboard to monitoring
   - Set up cost alerts
   - Configure rate limit notifications

5. **Initial Enrichment**
   ```elixir
   # Enqueue all venues for initial enrichment
   EventasaurusDiscovery.VenueImages.EnrichmentJob.enqueue()
   ```

### Post-Deployment

- [ ] Monitor first batch enrichment
- [ ] Verify cost tracking accuracy
- [ ] Check rate limit compliance
- [ ] Validate image display in UI
- [ ] Review admin dashboard metrics
- [ ] Confirm scheduled job runs correctly

---

## Support and Maintenance

### Monitoring

- **Admin Dashboard**: Real-time provider stats and alerts
- **Oban Dashboard**: Job queue and processing metrics
- **Application Logs**: Rate limit warnings and errors

### Troubleshooting

1. **High costs**: Check provider cost_breakdown in metadata
2. **Rate limit violations**: Review RateLimiter stats and adjust concurrency
3. **Slow enrichment**: Check provider response times and network
4. **Missing images**: Verify provider_ids are stored correctly

### Maintenance Tasks

- **Weekly**: Review cost reports and provider success rates
- **Monthly**: Analyze enrichment coverage and staleness
- **Quarterly**: Optimize provider priorities based on quality/cost

---

## Conclusion

The venue image aggregation system is fully implemented and production-ready. It provides:

✅ **Provider-agnostic architecture** supporting multiple image sources
✅ **Automatic enrichment** with staleness detection and scheduling
✅ **Rate limiting** to prevent API quota overages
✅ **Cost tracking** for budget management
✅ **Real-time monitoring** through admin dashboard
✅ **Component integration** with backward compatibility
✅ **Comprehensive testing** including load testing scenarios

The system is designed to scale efficiently while maintaining provider compliance and minimizing costs.
