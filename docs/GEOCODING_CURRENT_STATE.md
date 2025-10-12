# Geocoding Current State Documentation

**Date**: 2025-01-11
**Purpose**: Document current geocoding implementation before cost tracking system implementation

---

## Overview

Currently, 5 scrapers use geocoding services to obtain venue coordinates. This document maps each scraper's geocoding strategy and identifies which services incur costs.

---

## Geocoding Patterns by Scraper

### 1. QuestionOne (Quiz Events)

**File**: `lib/eventasaurus_discovery/sources/question_one/jobs/venue_detail_job.ex`

**Geocoding Method**: AddressGeocoder with OSM → Google Maps fallback

**Flow**:
```
Address → AddressGeocoder.geocode_address(address)
  ↓
Try OpenStreetMap (up to 3 retries)
  ↓ (if fails)
Fallback to Google Maps Geocoding API
```

**Code Location**: Line 72
```elixir
case AddressGeocoder.geocode_address(address) do
  {:ok, {city_name, country_name, {lat, lng}}} ->
```

**Costs**:
- OpenStreetMap: **$0.00** (free, used first)
- Google Maps Geocoding: **$0.005 per venue** (only when OSM fails)

**Current State**: No cost tracking

---

### 2. Kino Krakow (Cinema Events)

**File**: `lib/eventasaurus_discovery/sources/kino_krakow/extractors/cinema_extractor.ex`

**Geocoding Method**: Google Places API (Text Search + Details) via VenueProcessor

**Flow**:
```
Cinema Name (no coordinates provided)
  ↓
VenueProcessor.lookup_venue_from_google_places()
  ↓
Google Places Text Search ($0.032)
  ↓
Google Places Details ($0.005)
  ↓
Returns: {lat, lng, name, place_id, full_metadata}
```

**Code Location**: Cinema extractor line 5-8
```elixir
# Since Kino Krakow does not provide individual cinema info pages or GPS coordinates,
# this module returns cinema name formatted from the slug along with city and country.
# VenueProcessor automatically looks up venues using Google Places API (TextSearch + Details).
```

**Costs**:
- Google Places: **$0.037 per venue** (Text Search + Details)

**Current State**: No cost tracking, metadata stored but not analyzed

---

### 3. Resident Advisor (Electronic Music Events)

**File**: `lib/eventasaurus_discovery/sources/resident_advisor/venue_enricher.ex`

**Geocoding Method**: Google Places API (Text Search + Details) via VenueProcessor

**Flow**:
```
RA Venue (no coordinates provided)
  ↓
VenueEnricher.get_coordinates() → returns {nil, nil, false}
  ↓
VenueProcessor.lookup_venue_from_google_places()
  ↓
Google Places Text Search ($0.032)
  ↓
Google Places Details ($0.005)
  ↓
Returns: {lat, lng, name, place_id, full_metadata}
```

**Code Location**: venue_enricher.ex line 48-54
```elixir
# RA doesn't provide coordinates
# Return nil and let VenueProcessor handle Google Places lookup
Logger.debug("RA doesn't provide coordinates for #{venue_name}, deferring to VenueProcessor")
{nil, nil, false}
```

**Costs**:
- Google Places: **$0.037 per venue** (Text Search + Details)

**Current State**: No cost tracking, metadata stored but not analyzed

---

### 4. Karnet (Krakow Cultural Events)

**File**: `lib/eventasaurus_discovery/sources/karnet/transformer.ex`

**Geocoding Method**: Deferred (uses default Krakow coordinates, flags for later geocoding)

**Flow**:
```
Venue (no coordinates provided)
  ↓
Use default Krakow center coordinates
  ↓
Set needs_geocoding: true flag
  ↓
(Later) Manual or automated geocoding process
```

**Code Location**: Line 202-220
```elixir
# Karnet doesn't provide coordinates, so we need to geocode
default_krakow_lat = 50.0647
default_krakow_lng = 19.9450

# Flag for geocoding if we used defaults
needs_geocoding: is_nil(venue_data[:latitude]) || is_nil(venue_data[:longitude])
```

**Costs**:
- Initial: **$0.00** (uses default coordinates)
- Later geocoding: **Unknown** (depends on geocoding method used)

**Current State**: No tracking of when/how deferred geocoding happens

---

### 5. Cinema City (Cinema Events)

**File**: `lib/eventasaurus_discovery/sources/cinema_city/transformer.ex`

**Geocoding Method**: CityResolver (offline reverse geocoding from provided coordinates)

**Flow**:
```
Cinema API provides {lat, lng}
  ↓
CityResolver.resolve_city(lat, lng)
  ↓
Offline lookup using local geodata
  ↓
Returns: city_name
```

**Code Location**: Line 216-232
```elixir
@doc """
Resolves city and country from GPS coordinates using offline geocoding.
Uses CityResolver for reliable city name extraction from coordinates.
Falls back to conservative validation of API-provided city name if geocoding fails.
"""
def resolve_location(latitude, longitude, api_city, known_country) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} -> {city_name, known_country}
```

**Costs**:
- CityResolver: **$0.00** (free, uses offline data)

**Current State**: Free method, no cost tracking needed

---

## Summary Table

| Scraper | Geocoding Method | Provider | Cost per Venue | Tracking Status |
|---------|-----------------|----------|----------------|-----------------|
| QuestionOne | AddressGeocoder (OSM → Google) | OSM (primary) + Google Maps (fallback) | $0.00 - $0.005 | ❌ Not tracked |
| Kino Krakow | Google Places (via VenueProcessor) | Google Places API | $0.037 | ❌ Not tracked |
| Resident Advisor | Google Places (via VenueProcessor) | Google Places API | $0.037 | ❌ Not tracked |
| Karnet | Deferred (default coords + flag) | TBD (later) | Unknown | ❌ Not tracked |
| Cinema City | CityResolver (offline) | Local geodata | $0.00 | N/A (free) |

---

## Cost Impact Analysis

### Current Monthly Volume (Estimates)
- QuestionOne: ~50-100 venues/month
- Kino Krakow: ~20-30 venues/month
- Resident Advisor: ~100-200 venues/month
- Karnet: ~50-100 venues/month (deferred)
- Cinema City: ~30-50 venues/month (free)

### Estimated Monthly Costs (After 10K free tier)
- QuestionOne: $0.25 - $0.50 (assuming 50% OSM success rate)
- Kino Krakow: $0.74 - $1.11
- Resident Advisor: $3.70 - $7.40
- **Total**: ~$4.69 - $9.01 per month

**Note**: First 10,000 requests/month are free across all Google APIs, so actual costs may be lower.

---

## Current Metadata Storage

### VenueProcessor (line 620)
```elixir
metadata: google_metadata
```

**What's Stored**: Full Google Places response (place_id, formatted_address, geometry, etc.)

**What's Missing**:
- Which scraper created the venue
- Which geocoding provider was used
- Cost per geocoding operation
- Timestamp of geocoding
- Retry attempts
- Failure tracking

---

## Gaps in Current Implementation

### 1. No Cost Visibility
- Cannot answer: "How much did geocoding cost last month?"
- Cannot answer: "How many venues per scraper use paid APIs?"
- Cannot answer: "What's our geocoding budget forecast?"

### 2. No Provider Attribution
- Cannot determine which venues used OSM vs Google Maps
- Cannot identify optimization opportunities
- Cannot track Google API usage against quotas

### 3. No Failure Tracking
- Geocoding failures are logged but not persisted
- Cannot analyze failure patterns
- Cannot identify venues needing manual review

### 4. Deferred Geocoding Opacity
- Karnet's `needs_geocoding` flag is not tracked in metadata
- Cannot identify venues pending geocoding
- Cannot estimate future geocoding costs

---

## Proposed Solution Overview

See issue #1655 for full phased implementation plan.

**Key Changes**:
1. Add `venues.metadata.geocoding` structure with provider, cost, scraper, timestamp
2. Update AddressGeocoder to return metadata (non-breaking)
3. Update VenueProcessor to merge geocoding metadata
4. Update all scrapers to pass scraper name
5. Create GeocodingStats query module for cost reporting
6. Create Oban worker for monthly cost reports

**Target State**: Complete visibility into geocoding costs with minimal performance overhead.

---

## Files Requiring Changes

### Phase 1 (Core Infrastructure)
- [ ] `lib/eventasaurus_discovery/geocoding/pricing.ex` (NEW - ✅ Created)
- [ ] `lib/eventasaurus_discovery/geocoding/metadata_builder.ex` (NEW)
- [ ] `lib/eventasaurus_discovery/helpers/address_geocoder.ex` (ADD new function)
- [ ] `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex` (UPDATE)

### Phase 2 (Scrapers)
- [ ] `lib/eventasaurus_discovery/sources/question_one/jobs/venue_detail_job.ex`
- [ ] `lib/eventasaurus_discovery/sources/kino_krakow.ex`
- [ ] `lib/eventasaurus_discovery/sources/resident_advisor.ex`
- [ ] `lib/eventasaurus_discovery/sources/processor.ex`

### Phase 3 (Edge Cases)
- [ ] `lib/eventasaurus_discovery/sources/karnet/transformer.ex`
- [ ] `lib/eventasaurus_discovery/sources/cinema_city/transformer.ex`

### Phase 4 (Monitoring)
- [ ] `lib/eventasaurus_discovery/metrics/geocoding_stats.ex` (NEW)
- [ ] `lib/eventasaurus_discovery/workers/geocoding_cost_report_worker.ex` (NEW)
- [ ] `config/config.exs` (ADD Oban cron job)

---

## Next Steps

1. ✅ **Phase 0 Complete**: Pricing verified, constants created, current state documented
2. **Phase 1**: Begin core infrastructure implementation
3. **Phase 2**: Integrate with primary scrapers
4. **Phase 3**: Handle edge cases
5. **Phase 4**: Add monitoring and reporting
6. **Phase 5**: Testing
7. **Phase 6**: Production deployment

---

**References**:
- Issue #1652: Original proposal
- Issue #1653: Audit report
- Issue #1655: Phased implementation plan
- Google Pricing: https://developers.google.com/maps/billing-and-pricing/pricing
