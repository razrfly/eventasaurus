# ISSUE: Geocoding Metrics & Monitoring Dashboard

**Priority**: 🟡 Medium
**Status**: 📋 Planning
**Created**: 2025-10-11
**Category**: Infrastructure, Monitoring, Discovery System

---

## Problem Statement

After implementing the robust three-stage geocoding system (OSM → Google Maps fallback) for QuestionOne scraper with 100% success rate, we now need **visibility into geocoding operations across all scrapers** to:

1. **Track Success/Failure Rates**: Monitor geocoding performance per scraper and provider
2. **Identify Performance Issues**: Detect API timeouts, rate limiting, and slow responses
3. **Monitor API Costs**: Track Google Maps API usage to optimize costs
4. **Validate Data Quality**: Monitor city creation, fake city detection, and validation failures
5. **Enable Proactive Debugging**: Real-time alerts for geocoding failures before they accumulate

**Current Blind Spots**:
- ❌ No visibility into OSM vs Google Maps usage patterns
- ❌ Can't track which scrapers are causing most geocoding load
- ❌ No real-time alerts for geocoding failures
- ❌ Can't measure API response times or rate limiting frequency
- ❌ No historical trends for geocoding success rates
- ❌ Can't identify which addresses are consistently failing

---

## Current State Analysis

### Scraper Geocoding Patterns

| Scraper | Data Source | Geocoding Method | Uses AddressGeocoder? |
|---------|-------------|------------------|----------------------|
| **QuestionOne** | Address strings only | AddressGeocoder (OSM → Google) | ✅ Yes |
| **Bandsintown** | GPS coordinates | Direct coordinates | ❌ No |
| **Ticketmaster** | GPS coordinates | Direct coordinates | ❌ No |
| **Geeks Who Drink** | GPS coordinates | Direct coordinates | ❌ No |
| **Cinema City** | Address strings | VenueProcessor → Google Places | ⚠️ Indirect |
| **Kino Krakow** | Address strings | VenueProcessor → Google Places | ⚠️ Indirect |
| **Resident Advisor** | Mixed (GPS + address) | VenueProcessor → Google Places | ⚠️ Indirect |
| **Karnet** | Address strings | VenueProcessor → Google Places | ⚠️ Indirect |
| **PubQuiz** | Address strings | VenueProcessor → Google Places | ⚠️ Indirect |

### Geocoding Architecture

**Three Distinct Geocoding Paths**:

1. **AddressGeocoder (QuestionOne only)**:
   - Input: Address string only
   - Flow: OSM (free, 1 req/sec) → Google Maps ($5/1000) → Fail
   - Retry: Exponential backoff (1s, 2s) on timeout/rate limit
   - Validation: City name validation, rejects street addresses
   - Output: City name, country, coordinates

2. **Direct Coordinates (Bandsintown, Ticketmaster, Geeks Who Drink)**:
   - Input: GPS coordinates from API
   - Flow: Use coordinates directly → VenueProcessor validates
   - No geocoding: Already have lat/lng
   - City Resolution: CityResolver uses coordinates for city lookup

3. **VenueProcessor Google Places (Cinema City, Kino Krakow, etc.)**:
   - Input: Address string or partial venue data
   - Flow: Google Places Text Search → Details API → Extract coordinates
   - Fallback: If no coordinates, venue creation fails
   - Output: Coordinates, place_id, verified venue name

### Current Tracking Capabilities

**What We Can Track** (via Oban):
- ✅ Total jobs per scraper (completed, discarded, retryable)
- ✅ Job failure reasons (from `errors` field)
- ✅ Job retry counts and timing

**What We Can't Track**:
- ❌ AddressGeocoder provider usage (OSM vs Google)
- ❌ Geocoding response times per provider
- ❌ Rate limiting frequency
- ❌ City validation rejections (fake city attempts)
- ❌ VenueProcessor Google Places lookup metrics
- ❌ Per-scraper geocoding success rates
- ❌ API cost breakdown
- ❌ Geographic distribution of geocoding requests

---

## Proposed Solution: Comprehensive Geocoding Metrics System

### Architecture Overview

**Three-Tier Metrics System**:

1. **Telemetry Events** (Real-time)
   - Low overhead event emission
   - Capture all geocoding operations
   - No database writes (in-memory aggregation)

2. **Metrics Database** (Historical)
   - Aggregate telemetry into time-series data
   - Store for analysis and trending
   - Support for complex queries

3. **LiveDashboard Integration** (Visualization)
   - Real-time metrics display
   - Historical charts and trends
   - Per-scraper breakdowns
   - Cost estimation

### Telemetry Event Structure

**Event Naming Convention**: `[:eventasaurus_discovery, :geocoding, <operation>]`

#### AddressGeocoder Events

```elixir
# Event: [:eventasaurus_discovery, :geocoding, :address_attempt]
# When: Start of geocoding attempt
%{
  address: "20 Britannia Road, Poole England BH14 8BB",
  source_scraper: "question_one",
  job_id: 123,
  timestamp: ~U[2025-10-11 13:00:00Z]
}

# Event: [:eventasaurus_discovery, :geocoding, :osm_success]
# When: OpenStreetMap returns valid result
%{
  address: "20 Britannia Road, Poole...",
  source_scraper: "question_one",
  city_extracted: "Parkstone",
  country: "United Kingdom",
  coordinates: {50.7229055, -1.9538458},
  response_time_ms: 234,
  attempt_number: 1,
  timestamp: ~U[2025-10-11 13:00:00.234Z]
}

# Event: [:eventasaurus_discovery, :geocoding, :osm_timeout]
# When: OpenStreetMap times out (>5s)
%{
  address: "...",
  source_scraper: "question_one",
  response_time_ms: 5000,
  attempt_number: 1,
  will_retry: true,
  timestamp: ~U[2025-10-11 13:00:05Z]
}

# Event: [:eventasaurus_discovery, :geocoding, :osm_rate_limited]
# When: OpenStreetMap returns HTML (rate limit)
%{
  address: "...",
  source_scraper: "question_one",
  attempt_number: 2,
  will_retry: true,
  backoff_ms: 2000,
  timestamp: ~U[2025-10-11 13:00:06Z]
}

# Event: [:eventasaurus_discovery, :geocoding, :google_fallback]
# When: Falling back to Google Maps after OSM failure
%{
  address: "...",
  source_scraper: "question_one",
  osm_failure_reason: :timeout,
  osm_attempts: 3,
  timestamp: ~U[2025-10-11 13:00:08Z]
}

# Event: [:eventasaurus_discovery, :geocoding, :google_success]
# When: Google Maps returns valid result
%{
  address: "...",
  source_scraper: "question_one",
  city_extracted: "Parkstone",
  country: "United Kingdom",
  coordinates: {50.7229055, -1.9538458},
  response_time_ms: 156,
  api_cost_usd: 0.005,
  timestamp: ~U[2025-10-11 13:00:08.156Z]
}

# Event: [:eventasaurus_discovery, :geocoding, :validation_rejected]
# When: City name validation rejects fake city
%{
  address: "...",
  source_scraper: "question_one",
  rejected_value: "3-4 Moulsham St",
  rejection_reason: :street_address_pattern,
  provider: "google",
  timestamp: ~U[2025-10-11 13:00:08.200Z]
}

# Event: [:eventasaurus_discovery, :geocoding, :complete_success]
# When: Geocoding completes successfully with valid city
%{
  address: "...",
  source_scraper: "question_one",
  city_name: "Parkstone",
  country: "United Kingdom",
  coordinates: {50.7229055, -1.9538458},
  provider_used: "osm",  # or "google"
  total_time_ms: 234,
  osm_attempts: 1,
  google_attempts: 0,
  timestamp: ~U[2025-10-11 13:00:08.234Z]
}

# Event: [:eventasaurus_discovery, :geocoding, :complete_failure]
# When: All geocoding attempts exhausted
%{
  address: "...",
  source_scraper: "question_one",
  failure_reason: :all_providers_failed,
  osm_attempts: 3,
  google_attempts: 1,
  total_time_ms: 8456,
  timestamp: ~U[2025-10-11 13:00:16.456Z]
}
```

#### VenueProcessor Events

```elixir
# Event: [:eventasaurus_discovery, :venue_processor, :google_places_lookup]
# When: VenueProcessor calls Google Places API
%{
  venue_name: "The Boot",
  address: "45 Trinity Gardens",
  city_name: "London",
  source_scraper: "cinema_city",
  lookup_type: :missing_coordinates,
  timestamp: ~U[2025-10-11 13:00:00Z]
}

# Event: [:eventasaurus_discovery, :venue_processor, :google_places_success]
# When: Google Places returns valid result
%{
  venue_name: "The Boot",
  coordinates: {51.46, -0.12},
  place_id: "ChIJdd4hrwug2EcRmSrV3Vo6llI",
  verified_name: "The Boot Pub",
  response_time_ms: 345,
  api_cost_usd: 0.017,  # Text Search ($0.017/1000) + Details ($0.017/1000)
  source_scraper: "cinema_city",
  timestamp: ~U[2025-10-11 13:00:00.345Z]
}

# Event: [:eventasaurus_discovery, :venue_processor, :google_places_failure]
# When: Google Places lookup fails
%{
  venue_name: "Unknown Venue",
  failure_reason: :no_results,
  response_time_ms: 234,
  source_scraper: "cinema_city",
  timestamp: ~U[2025-10-11 13:00:00.234Z]
}
```

#### City Events

```elixir
# Event: [:eventasaurus_discovery, :city, :validation_success]
# When: City name passes validation
%{
  city_name: "Parkstone",
  country: "United Kingdom",
  source_scraper: "question_one",
  validation_checks_passed: [:length, :pattern, :no_street_suffix],
  timestamp: ~U[2025-10-11 13:00:00Z]
}

# Event: [:eventasaurus_discovery, :city, :created]
# When: New city created in database
%{
  city_name: "Parkstone",
  country: "United Kingdom",
  source_scraper: "question_one",
  coordinates: {50.7229055, -1.9538458},
  provider_used: "osm",
  timestamp: ~U[2025-10-11 13:00:00Z]
}

# Event: [:eventasaurus_discovery, :city, :reused]
# When: Existing city reused for new venue
%{
  city_name: "London",
  country: "United Kingdom",
  source_scraper: "bandsintown",
  city_id: 1,
  venue_count: 78,
  timestamp: ~U[2025-10-11 13:00:00Z]
}
```

---

## Database Schema Design

### Table: `geocoding_metrics`

**Purpose**: Time-series aggregated metrics for dashboard queries

```sql
CREATE TABLE geocoding_metrics (
  id BIGSERIAL PRIMARY KEY,

  -- Time bucket (aggregated per hour)
  time_bucket TIMESTAMP NOT NULL,

  -- Scraper identification
  source_scraper VARCHAR(255) NOT NULL,

  -- Provider metrics
  provider VARCHAR(50) NOT NULL, -- 'osm', 'google_maps', 'google_places'

  -- Success/Failure counts
  attempts INTEGER NOT NULL DEFAULT 0,
  successes INTEGER NOT NULL DEFAULT 0,
  failures INTEGER NOT NULL DEFAULT 0,
  timeouts INTEGER NOT NULL DEFAULT 0,
  rate_limited INTEGER NOT NULL DEFAULT 0,

  -- Performance metrics
  avg_response_time_ms INTEGER,
  max_response_time_ms INTEGER,
  min_response_time_ms INTEGER,
  p95_response_time_ms INTEGER,

  -- Cost tracking (Google only)
  total_api_calls INTEGER NOT NULL DEFAULT 0,
  estimated_cost_usd DECIMAL(10, 6),

  -- City metrics
  cities_created INTEGER NOT NULL DEFAULT 0,
  cities_reused INTEGER NOT NULL DEFAULT 0,
  validation_rejections INTEGER NOT NULL DEFAULT 0,

  -- Timestamps
  inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),

  -- Indexes
  CONSTRAINT geocoding_metrics_unique_bucket
    UNIQUE (time_bucket, source_scraper, provider)
);

CREATE INDEX geocoding_metrics_time_bucket_idx
  ON geocoding_metrics (time_bucket DESC);

CREATE INDEX geocoding_metrics_scraper_time_idx
  ON geocoding_metrics (source_scraper, time_bucket DESC);

CREATE INDEX geocoding_metrics_provider_time_idx
  ON geocoding_metrics (provider, time_bucket DESC);
```

### Table: `geocoding_events`

**Purpose**: Detailed event log for debugging and analysis

```sql
CREATE TABLE geocoding_events (
  id BIGSERIAL PRIMARY KEY,

  -- Event identification
  event_type VARCHAR(100) NOT NULL, -- 'osm_success', 'google_fallback', etc.
  source_scraper VARCHAR(255) NOT NULL,

  -- Geocoding details
  address TEXT,
  city_extracted VARCHAR(255),
  country VARCHAR(255),
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),

  -- Provider details
  provider VARCHAR(50), -- 'osm', 'google_maps', 'google_places'
  response_time_ms INTEGER,
  attempt_number INTEGER,

  -- Results
  success BOOLEAN NOT NULL,
  failure_reason VARCHAR(255),

  -- Validation
  validation_rejected BOOLEAN DEFAULT FALSE,
  rejection_reason VARCHAR(255),

  -- Costs (Google only)
  api_cost_usd DECIMAL(10, 6),

  -- Oban job tracking
  oban_job_id BIGINT,

  -- Metadata (JSONB for flexibility)
  metadata JSONB DEFAULT '{}'::jsonb,

  -- Timestamp
  occurred_at TIMESTAMP NOT NULL DEFAULT NOW(),
  inserted_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX geocoding_events_occurred_at_idx
  ON geocoding_events (occurred_at DESC);

CREATE INDEX geocoding_events_scraper_occurred_idx
  ON geocoding_events (source_scraper, occurred_at DESC);

CREATE INDEX geocoding_events_event_type_idx
  ON geocoding_events (event_type, occurred_at DESC);

CREATE INDEX geocoding_events_success_idx
  ON geocoding_events (success, occurred_at DESC)
  WHERE success = FALSE;

CREATE INDEX geocoding_events_oban_job_idx
  ON geocoding_events (oban_job_id)
  WHERE oban_job_id IS NOT NULL;
```

---

## LiveDashboard Integration Design

### Dashboard Page: "Geocoding Monitor"

**URL**: `/admin/dashboard/geocoding`

**Layout**: Three main sections

#### Section 1: Real-Time Overview (Top Cards)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 🌍 Geocoding Overview (Last 24 Hours)                                      │
├──────────────┬──────────────┬──────────────┬──────────────┬───────────────┤
│ Total        │ Success Rate │ OSM Success  │ Google Usage │ Avg Response  │
│ 1,234        │ 98.4%        │ 89.2%        │ 10.8%        │ 234ms         │
│ attempts     │              │ (1,101)      │ (133)        │               │
└──────────────┴──────────────┴──────────────┴──────────────┴───────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ 💰 Cost Estimate (Last 24 Hours)                                           │
├──────────────┬──────────────┬──────────────┬──────────────┬───────────────┤
│ Google Maps  │ Google Places│ Total API    │ Daily Rate   │ Monthly Est.  │
│ $0.67        │ $2.34        │ $3.01        │ 2,341 req/day│ ~$90/month    │
│ (133 calls)  │ (137 calls)  │              │              │               │
└──────────────┴──────────────┴──────────────┴──────────────┴───────────────┘
```

#### Section 2: Per-Scraper Breakdown (Table)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 📊 Per-Scraper Metrics (Last 24 Hours)                                     │
├──────────────────┬─────────┬──────────┬───────────┬──────────┬────────────┤
│ Scraper          │ Events  │ Success  │ OSM %     │ Google % │ Avg Time   │
├──────────────────┼─────────┼──────────┼───────────┼──────────┼────────────┤
│ QuestionOne      │ 145     │ 96.6%    │ 89.2%     │ 10.8%    │ 234ms      │
│ Cinema City      │ 234     │ 100%     │ N/A       │ 100%     │ 345ms      │
│ Kino Krakow      │ 156     │ 98.1%    │ N/A       │ 100%     │ 312ms      │
│ Resident Advisor │ 89      │ 100%     │ N/A       │ N/A      │ N/A (GPS)  │
│ Bandsintown      │ 678     │ 100%     │ N/A       │ N/A      │ N/A (GPS)  │
│ Ticketmaster     │ 445     │ 100%     │ N/A       │ N/A      │ N/A (GPS)  │
├──────────────────┼─────────┼──────────┼───────────┼──────────┼────────────┤
│ TOTAL            │ 1,747   │ 98.9%    │ 89.2%     │ 10.8%    │ 267ms      │
└──────────────────┴─────────┴──────────┴───────────┴──────────┴────────────┘
```

#### Section 3: Historical Charts

**Chart 1: Success Rate Over Time (7 days)**
```
Success Rate %
100% ┤                                      ╭───────────────
 95% ┤                        ╭─────────────╯
 90% ┤              ╭─────────╯
 85% ┤        ╭─────╯
 80% ┤  ╭─────╯
     └──┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴──>
       Day1  Day2  Day3  Day4  Day5  Day6  Day7  Today
```

**Chart 2: Provider Usage (7 days stacked bar)**
```
Requests
1500 ┤     █████              ██████
1000 ┤     █████    ████      ██████     ██████
 500 ┤     █████    ████      ██████     ██████     ████
     └──────────────────────────────────────────────────────>
           Day1     Day2      Day3       Day4       Day5

Legend: █ OpenStreetMap  █ Google Maps  █ Google Places
```

**Chart 3: Response Times (7 days box plot)**
```
Response Time (ms)
1000 ┤                                           ○
 800 ┤                                  ╭────╮
 600 ┤                     ╭────╮      │    │
 400 ┤        ╭────╮       │    │      │    │
 200 ┤        │    │       │    │      │    │
     └────────────────────────────────────────────>
           Day1         Day2         Day3

Legend: ╭────╮ p25-p75  ─── median  ○ outliers
```

#### Section 4: Recent Failures (Live Feed)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 🚨 Recent Failures (Last 100)                                              │
├─────────────┬────────────────────────────────┬─────────────┬───────────────┤
│ Time        │ Address                        │ Scraper     │ Reason        │
├─────────────┼────────────────────────────────┼─────────────┼───────────────┤
│ 13:14:05    │ Unknown Street, London         │ QuestionOne │ OSM timeout   │
│ 13:12:44    │ Missing Address                │ Cinema City │ No results    │
│ 13:10:23    │ Invalid Postcode Format        │ QuestionOne │ Validation    │
└─────────────┴────────────────────────────────┴─────────────┴───────────────┘
```

#### Section 5: City Quality Metrics

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 🏙️ City Quality (Last 24 Hours)                                            │
├──────────────────┬──────────────┬──────────────────┬─────────────────────────┤
│ New Cities       │ Reused       │ Validation Rejects│ Top Rejection Reason    │
│ 12               │ 1,735        │ 23                │ Street address pattern  │
│                  │              │                   │ (18 occurrences)        │
└──────────────────┴──────────────┴──────────────────┴─────────────────────────┘

Recent Cities Created:
• Parkstone, United Kingdom (via OSM) - 13:00:00
• Gravel Hill, United Kingdom (via Google) - 12:45:23
• Clewer New Town, United Kingdom (via OSM) - 12:30:15
```

---

## Implementation Phases

### Phase 1: Infrastructure Setup (Week 1)

**Goal**: Build telemetry and database foundation

#### Tasks:

1. **Create Database Migrations**
   - `geocoding_metrics` table
   - `geocoding_events` table
   - Indexes and constraints

2. **Create Ecto Schemas**
   - `EventasaurusDiscovery.Metrics.GeocodingMetric`
   - `EventasaurusDiscovery.Metrics.GeocodingEvent`

3. **Create Telemetry Handler**
   - `EventasaurusDiscovery.Telemetry.GeocodingHandler`
   - Listen to all geocoding events
   - Aggregate into hourly buckets
   - Write to `geocoding_metrics` table

4. **Create Event Logger**
   - `EventasaurusDiscovery.Metrics.EventLogger`
   - Write detailed events to `geocoding_events` table
   - Async writes (via background task)

5. **Testing**
   - Unit tests for telemetry handler
   - Unit tests for event logger
   - Integration tests for database writes

**Success Criteria**:
- ✅ Telemetry events captured and aggregated
- ✅ Events written to database
- ✅ No performance degradation (<5ms overhead)

---

### Phase 2: AddressGeocoder Instrumentation (Week 2)

**Goal**: Instrument QuestionOne scraper's AddressGeocoder

#### Tasks:

1. **Instrument AddressGeocoder.geocode_address/1**
   - Emit `:address_attempt` event at start
   - Measure total execution time

2. **Instrument try_openstreetmaps_with_retry/2**
   - Emit `:osm_success` on success
   - Emit `:osm_timeout` on timeout
   - Emit `:osm_rate_limited` on rate limit
   - Track attempt numbers and retry delays

3. **Instrument try_google_maps/1**
   - Emit `:google_fallback` when called
   - Emit `:google_success` on success
   - Track API costs ($5 per 1000 requests)

4. **Instrument validate_city_name/1**
   - Emit `:validation_rejected` on rejection
   - Track rejection reasons

5. **Emit Final Events**
   - `:complete_success` on successful geocoding
   - `:complete_failure` on all failures

6. **Testing**
   - Test all event emissions
   - Verify cost calculations
   - Test with real addresses

**Success Criteria**:
- ✅ All AddressGeocoder operations emit telemetry
- ✅ QuestionOne scraper metrics visible in database
- ✅ No breaking changes to existing functionality

---

### Phase 3: VenueProcessor Instrumentation (Week 3)

**Goal**: Instrument Google Places lookups in VenueProcessor

#### Tasks:

1. **Instrument lookup_venue_from_google_places/2**
   - Emit `:google_places_lookup` at start
   - Emit `:google_places_success` on success
   - Emit `:google_places_failure` on failure
   - Track API costs (Text Search $17/1000 + Details $17/1000)

2. **Track Scraper Context**
   - Pass `source_scraper` through call chain
   - Associate metrics with correct scraper

3. **Testing**
   - Test Google Places event emissions
   - Verify cost calculations
   - Test with multiple scrapers

**Success Criteria**:
- ✅ VenueProcessor metrics tracked
- ✅ Cinema City, Kino Krakow, Karnet metrics visible
- ✅ Google Places costs accurately tracked

---

### Phase 4: City Creation Instrumentation (Week 3)

**Goal**: Track city creation and validation

#### Tasks:

1. **Instrument CityResolver.validate_city_name/1**
   - Emit `:validation_success` on pass
   - Already emits `:validation_rejected` on fail

2. **Instrument VenueProcessor City Creation**
   - Emit `:city_created` when new city created
   - Emit `:city_reused` when existing city used
   - Track which scraper created which cities

3. **Testing**
   - Test city event emissions
   - Verify scraper attribution

**Success Criteria**:
- ✅ City metrics tracked per scraper
- ✅ Fake city attempts visible in metrics

---

### Phase 5: LiveDashboard Integration (Week 4)

**Goal**: Build real-time dashboard

#### Tasks:

1. **Create Dashboard Module**
   - `EventasaurusWeb.Telemetry.GeocodingDashboard`
   - Implement LiveDashboard page behavior

2. **Build Overview Cards**
   - Query `geocoding_metrics` for 24h data
   - Calculate aggregate statistics
   - Display real-time cards

3. **Build Per-Scraper Table**
   - Query metrics grouped by scraper
   - Display sortable table
   - Click to drill down into scraper details

4. **Build Historical Charts**
   - Success rate chart (7 days)
   - Provider usage chart (7 days)
   - Response time chart (7 days)
   - Use Chart.js or similar

5. **Build Recent Failures Feed**
   - Query `geocoding_events` WHERE success = FALSE
   - Live-updating list
   - Click to see event details

6. **Build City Quality Section**
   - Recent cities created
   - Validation rejection counts
   - Top rejection reasons

7. **Add to LiveDashboard Routes**
   - Update `router.ex` to include geocoding page
   - Require admin authentication

8. **Testing**
   - Manual testing of dashboard
   - Performance testing with large datasets
   - Mobile responsive testing

**Success Criteria**:
- ✅ Dashboard accessible at `/admin/dashboard/geocoding`
- ✅ Real-time metrics displayed
- ✅ Charts rendering correctly
- ✅ No performance issues with large datasets

---

### Phase 6: Alerts & Monitoring (Week 5)

**Goal**: Proactive alerts for issues

#### Tasks:

1. **Create Alert Rules**
   - Success rate drops below 95%
   - Google API costs exceed $10/day
   - Response times exceed 2s p95
   - More than 10 validation rejections per hour

2. **Integrate with Existing Alerting**
   - Slack notifications (if configured)
   - Email alerts (if configured)
   - Dashboard warnings

3. **Create Scheduled Job**
   - Hourly check of metrics
   - Compare against thresholds
   - Send alerts if breached

4. **Testing**
   - Test alert trigger conditions
   - Verify notification delivery

**Success Criteria**:
- ✅ Alerts trigger on threshold breaches
- ✅ Notifications delivered promptly
- ✅ No false positives

---

## Rollout Strategy

### Stage 1: QuestionOne Only (Week 2)

**Scope**: Only AddressGeocoder instrumented

**Why First**:
- Already has comprehensive error handling
- Known success baseline (96.6%)
- Single scraper = easy to validate metrics

**Validation**:
- Compare dashboard metrics to Oban job statistics
- Verify 96.6% success rate matches
- Confirm OSM vs Google split matches logs

### Stage 2: VenueProcessor Scrapers (Week 3)

**Scope**: Cinema City, Kino Krakow, Karnet, PubQuiz, Resident Advisor

**Why Second**:
- Uses different geocoding method (Google Places)
- Higher volume than QuestionOne
- Will reveal API cost patterns

**Validation**:
- Compare total events to database event counts
- Verify venue creation matches geocoding attempts
- Confirm Google Places costs are accurate

### Stage 3: All Scrapers Visible (Week 4)

**Scope**: Dashboard shows all scrapers including GPS-based ones

**Why Last**:
- Complete picture of all event creation
- Can compare GPS-based vs geocoding-based success rates
- Enables per-scraper optimization decisions

**Validation**:
- Dashboard shows accurate data for all 9 scrapers
- Metrics match Oban statistics
- No performance degradation

---

## Success Metrics

### Immediate Metrics (Phase 1-2)

- ✅ Telemetry overhead <5ms per geocoding attempt
- ✅ Database writes async (no blocking)
- ✅ QuestionOne metrics matching Oban statistics
- ✅ 100% event capture rate

### Short-Term Metrics (Phase 3-5)

- ✅ Dashboard loads in <2s
- ✅ All scrapers visible in dashboard
- ✅ Historical trends showing correct data
- ✅ API cost estimates within 10% of actual

### Long-Term Metrics (Phase 6+)

- ✅ Proactive issue detection (alerts before failures accumulate)
- ✅ Cost optimization (identify expensive scrapers)
- ✅ Performance optimization (identify slow geocoding)
- ✅ Data quality improvement (track fake city attempts)

---

## Cost Analysis

### Implementation Costs

| Phase | Engineer Time | Database Storage | API Costs |
|-------|--------------|------------------|-----------|
| Phase 1-2 | 3 days | ~10MB/month | No change |
| Phase 3-4 | 2 days | ~5MB/month | No change |
| Phase 5 | 5 days | - | No change |
| Phase 6 | 2 days | - | No change |
| **Total** | **12 days** | **~15MB/month** | **No change** |

### Operational Costs

**Database Storage**:
- `geocoding_events`: ~1KB per event × 2,000 events/day = 2MB/day = 60MB/month
- `geocoding_metrics`: ~200 bytes per hour per scraper × 9 scrapers × 24h = 43KB/day = 1.3MB/month
- **Total**: ~61MB/month (negligible)

**Compute Overhead**:
- Telemetry emission: <1ms per event (negligible)
- Async database writes: <5ms per event (non-blocking)
- Dashboard queries: <500ms per page load
- **Total**: <10ms overhead per geocoding operation

**No Additional API Costs**: We're tracking existing API usage, not adding new calls

---

## Alternative Approaches Considered

### Alternative 1: Oban Job Metadata Only

**Approach**: Store all metrics in Oban's `meta` field

**Pros**:
- No new tables needed
- Tightly coupled with jobs

**Cons**:
- ❌ No aggregation support
- ❌ Difficult to query across jobs
- ❌ Limited to Oban-based scrapers
- ❌ No real-time visibility
- ❌ Oban cleanup removes historical data

**Decision**: Rejected - too limited for comprehensive monitoring

### Alternative 2: External Monitoring (DataDog, New Relic)

**Approach**: Send metrics to external service

**Pros**:
- Professional dashboards
- Advanced alerting
- No maintenance

**Cons**:
- ❌ Additional monthly costs ($50-200/month)
- ❌ Data leaves our infrastructure
- ❌ Less customization
- ❌ Requires integration work

**Decision**: Rejected - prefer internal solution first, can integrate later if needed

### Alternative 3: Log-Based Metrics

**Approach**: Parse logs to extract metrics

**Pros**:
- No code changes needed
- Uses existing logs

**Cons**:
- ❌ Parsing overhead
- ❌ Fragile (log format changes break metrics)
- ❌ No structured data
- ❌ Difficult to aggregate

**Decision**: Rejected - structured events are better

---

## Open Questions

### Q1: Data Retention Policy?

**Question**: How long should we keep `geocoding_events`?

**Options**:
- A: 30 days (debugging recent issues)
- B: 90 days (trend analysis)
- C: 1 year (long-term trends)

**Recommendation**: 90 days with automatic archival to S3 for older data

### Q2: Sampling Rate?

**Question**: Should we sample events to reduce storage?

**Current Volume**: ~2,000 events/day × 365 days = 730K events/year = ~730MB

**Options**:
- A: No sampling (full fidelity)
- B: Sample 10% of successes, 100% of failures
- C: Sample everything at 10%

**Recommendation**: No sampling - volume is manageable and full data is valuable

### Q3: Real-Time vs Batch Processing?

**Question**: Should metrics be updated in real-time or batched?

**Options**:
- A: Real-time (every event writes to DB immediately)
- B: Batch (aggregate events in memory, write every 1 minute)
- C: Hybrid (failures immediate, successes batched)

**Recommendation**: Hybrid - failures immediate for alerts, successes batched for performance

### Q4: Dashboard Access Control?

**Question**: Who should access the dashboard?

**Options**:
- A: Admin only (most secure)
- B: All developers (easier debugging)
- C: Public (full transparency)

**Recommendation**: Admin only initially, expand to developers after Phase 5

---

## Next Steps

### Immediate (This Week)

1. **Review this issue** with team for feedback
2. **Decide on data retention policy** (Q1)
3. **Decide on sampling strategy** (Q2)
4. **Create database migration** for Phase 1

### Short-Term (Weeks 2-3)

1. **Implement Phase 1** (Infrastructure)
2. **Implement Phase 2** (AddressGeocoder)
3. **Validate QuestionOne metrics**

### Medium-Term (Weeks 4-5)

1. **Implement Phase 3-4** (VenueProcessor + City)
2. **Implement Phase 5** (LiveDashboard)
3. **Deploy to production**

### Long-Term (Week 6+)

1. **Implement Phase 6** (Alerts)
2. **Monitor and iterate**
3. **Expand to other scrapers** as needed

---

## Related Issues

- **ISSUE_GEOCODING_PHASE1_FAILURES.md**: Original geocoding problems that led to this
- **PHASE_2B_COMPLETION_SUMMARY.md**: Successful Phase 2 completion showing need for monitoring
- **GEOCODING_PHASES_1_2_AUDIT.md**: Audit showing 100% success but lack of visibility

---

## References

- Phoenix LiveDashboard: https://hexdocs.pm/phoenix_live_dashboard
- Telemetry: https://hexdocs.pm/telemetry
- Oban Telemetry: https://hexdocs.pm/oban/Oban.Telemetry.html
- Google Maps Pricing: https://developers.google.com/maps/billing-and-pricing/pricing

---

**Created**: 2025-10-11
**Last Updated**: 2025-10-11
**Status**: 📋 Planning - Awaiting team review and Q1-Q4 decisions
**Next Action**: Team review meeting to finalize architecture decisions
