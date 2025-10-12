# Geocoding Dashboard Redesign - Performance Focus

**Related Issue**: https://github.com/razrfly/eventasaurus/issues/1665
**Status**: Ready for implementation
**Priority**: Medium

## Overview

Redesign the geocoding dashboard at `/dev/geocoding` to focus on **provider performance and success rates** rather than cost tracking. Since most providers are now free (Mapbox, HERE, Geoapify, etc.), cost is less relevant than tracking our goal of 95%+ geocoding success rate.

## Current State ✅

**Metadata Structure**: FIXED - Recent venues have both:
- `metadata.geocoding` (backward compatibility)
- `metadata.geocoding_metadata` (new multi-provider system)

**Current Providers in Use**:
- Mapbox: 122 venues (free, primary provider)
- Previously: Google Places (paid, being phased out)

**Current Dashboard**: Cost-focused with:
- Total cost tracking
- Costs by provider
- Costs by scraper
- Failed geocoding count
- Deferred geocoding count

## Proposed Changes

### 1. Dashboard Title & Focus
- Change from "Geocoding Cost Dashboard" → "Geocoding Performance Dashboard"
- Subtitle: "Monitor geocoding success rates and provider performance"

### 2. Overview Metrics (Top 4 Cards)

Replace current metrics with:

| Current | New |
|---------|-----|
| Total Venues | Total Geocoding Attempts |
| Total Cost | Overall Success Rate (%) |
| Free Geocoding | Average Attempts per Success |
| Paid Geocoding | Failed Geocoding Count |

### 3. Provider Performance Table (Primary Section)

**Current**: Shows cost per provider
**New**: Show performance metrics

Columns:
- Provider Name
- Total Attempts (from `attempted_providers` arrays)
- Successful Geocodes (when provider was the successful one)
- Success Rate (%)
- Average Position in Fallback Chain
- Cost (keep but de-emphasize, mostly $0.00)

### 4. Fallback Chain Analysis (New Section)

Show how the multi-provider fallback system is performing:
- Most common provider sequences (e.g., "mapbox" vs "mapbox,here" vs "mapbox,here,geoapify")
- Success rate by fallback depth:
  - 1st attempt success rate
  - 2nd attempt success rate
  - 3rd+ attempt success rate
- Which providers are "rescuing" failed attempts

### 5. Scraper Performance (Enhanced)

Keep existing scraper breakdown but add:
- Geocoding success rate per scraper
- Average attempts per scraper
- Which scrapers have highest failure rates

### 6. Failure Analysis (Enhanced)

Keep failed venues list but add:
- Common failure patterns (which provider sequences failed)
- Failure reasons analysis
- Suggested actions for manual review

### 7. Cost Tracking (Secondary/Optional)

Move cost information to collapsible section at bottom:
- Keep existing cost queries for historical tracking
- De-emphasize since most providers are free
- Useful for monitoring if paid providers get accidentally enabled

## Implementation Tasks

### Phase 1: GeocodingStats Module Updates

File: `lib/eventasaurus_discovery/metrics/geocoding_stats.ex`

**New Query Functions**:

1. **`overall_success_rate/1`** - Calculate overall geocoding success percentage
   ```elixir
   # Count venues with successful geocoding vs total attempts
   # Success = has coordinates AND has geocoding_metadata.provider
   # Returns: {:ok, %{success_rate: 95.2, total: 150, successful: 143, failed: 7}}
   ```

2. **`provider_hit_rates/1`** - Show usage distribution across providers
   ```elixir
   # Extract all attempted_providers arrays and count frequency
   # Returns: {:ok, [%{provider: "mapbox", attempts: 150, successes: 143, success_rate: 95.3}]}
   ```

3. **`fallback_depth_analysis/1`** - Analyze success rates by attempt number
   ```elixir
   # Group by attempts field (1, 2, 3+) and calculate success rates
   # Returns: {:ok, [%{depth: 1, count: 120, success_rate: 94.5}, ...]}
   ```

**Updated Query Functions**:

1. **Update `success_rate_by_provider/1`** - Already exists but verify it works with current data
2. **Update `fallback_patterns/1`** - Enhance to show more detailed pattern analysis
3. **Update `summary/0`** - Include new performance metrics

### Phase 2: LiveView Updates

File: `lib/eventasaurus_web/live/admin/geocoding_dashboard_live.ex`

**Changes**:
1. Update `mount/3` to load performance metrics
2. Add new assigns:
   - `overall_success_rate`
   - `provider_hit_rates`
   - `fallback_analysis`
3. Update page title
4. Keep existing assigns for backward compatibility

### Phase 3: Template Redesign

File: `lib/eventasaurus_web/live/admin/geocoding_dashboard_live.html.heex`

**Section Order** (top to bottom):
1. Overview Metrics (4 cards - performance focused)
2. Provider Performance Table (primary focus)
3. Fallback Chain Analysis (new section)
4. Scraper Performance (enhanced)
5. Failure Analysis (enhanced)
6. Cost Tracking (collapsed/optional at bottom)

**UI Enhancements**:
- Add success rate badges with color coding:
  - Green: >95% success rate
  - Yellow: 85-95% success rate
  - Red: <85% success rate
- Add charts/visualizations (optional):
  - Provider success rate comparison
  - Fallback chain effectiveness
- Update provider badges for new providers (mapbox, here, geoapify, etc.)

### Phase 4: Testing & Validation

**Test Scenarios**:
1. ✅ Dashboard loads without errors with current data (122 mapbox venues)
2. Test with mixed provider data (after more scrapers run)
3. Test fallback chain analysis with multi-attempt scenarios
4. Verify backward compatibility with old metadata structure
5. Test performance with 1000+ venues

## Data Availability Check

Current database state (as of Oct 12, 2025):
- ✅ `metadata.geocoding_metadata` present on recent venues (122 venues)
- ✅ `metadata.geocoding` present for backward compatibility
- ✅ Provider data: Mapbox (122 venues, all successful)
- ⚠️ Limited fallback data (most succeed on first attempt with Mapbox)
- ⚠️ Need more scraper runs to see full multi-provider fallback chains

## Success Criteria

Dashboard successfully shows:
1. ✅ Overall success rate trending toward 95%+ goal
2. ✅ Which providers are most reliable
3. ✅ How often fallback chains are needed
4. ✅ Which scrapers have geocoding issues
5. ✅ Failed venues requiring manual intervention
6. ✅ Cost tracking (secondary, for monitoring)

## Technical Notes

**Query Performance**:
- Most queries use existing JSONB indexes on `metadata`
- `attempted_providers` array extraction may need optimization for large datasets
- Consider adding computed column for success rate if queries slow down

**Backward Compatibility**:
- Keep old `metadata.geocoding` queries working
- Dashboard should work with venues that only have old structure
- Prefer `metadata.geocoding_metadata` when available

**Future Enhancements** (post-implementation):
- Real-time dashboard with Phoenix PubSub updates
- Historical trend charts (success rate over time)
- Provider performance alerts (email if success rate drops below threshold)
- Automated provider priority adjustment based on performance
- Cost prediction based on current usage patterns

## Related Files

- `lib/eventasaurus_discovery/metrics/geocoding_stats.ex` - Query logic
- `lib/eventasaurus_web/live/admin/geocoding_dashboard_live.ex` - LiveView controller
- `lib/eventasaurus_web/live/admin/geocoding_dashboard_live.html.heex` - Template
- `lib/eventasaurus_discovery/geocoding/orchestrator.ex` - Multi-provider system
- `lib/eventasaurus_discovery/helpers/address_geocoder.ex` - Geocoding interface

## References

- Issue #1665: Modular multi-provider geocoding system (95%+ success rate goal)
- Current branch: `10-12-stats_for_scrapers`
- Dashboard URL: `http://localhost:4000/dev/geocoding`
