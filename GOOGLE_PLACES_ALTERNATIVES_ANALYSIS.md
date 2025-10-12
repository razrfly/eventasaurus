# Google Places API Alternatives - Comprehensive Analysis

**Date**: 2025-01-12
**Purpose**: Evaluate feasibility of replacing Google Places API with free alternatives

---

## Executive Summary

**Current State**:
- Backend geocoding (scrapers): ✅ Already using OSM → Google fallback
- Frontend autocomplete (private events): ❌ Still uses Google Places JavaScript
- Monthly cost: ~$10-25 (mostly private event autocomplete)
- Annual cost: ~$120-300

**Recommendation**: Wait and See (Option C) - Only proceed if growth trajectory exceeds 500 events/month or strategic value justifies $2,000-$5,000 development investment.

**ROI at Current Scale**: 36+ years (not economically viable)
**ROI at 2,000 events/month**: 2-5 years (acceptable)

---

## Current Implementation

### Backend Geocoding (Scrapers)

#### QuestionOne Scraper
- **Method**: AddressGeocoder with OSM → Google Maps fallback
- **File**: `lib/eventasaurus_discovery/helpers/address_geocoder.ex`
- **Cost**: $0.00-$0.005 per venue (mostly OSM, rare Google fallback)
- **Status**: ✅ Working well, no changes needed

#### Cinema City Scraper
- **Method**: CityResolver (offline reverse geocoding)
- **Cost**: $0.00 (completely free)
- **Status**: ✅ Working well, no changes needed

#### Kino Krakow & Resident Advisor Scrapers
- **Method**: Google Places API (Text Search + Details)
- **Cost**: $0.037 per venue
- **Volume**: ~120-230 venues/month
- **Monthly Cost**: $4.44-$8.51
- **Status**: Could be optimized but low priority

**Backend Conclusion**: Already mostly free via OSM. Total scraper cost: ~$5-10/month.

---

### Frontend Autocomplete (Private Events)

#### Current Implementation
- **File**: `assets/js/hooks/places-search.js` (~580 lines)
- **Method**: Google Places Autocomplete JavaScript widget
- **Features Used**:
  - Real-time autocomplete dropdown (instant suggestions)
  - Rich place data: ratings, price_level, photos, phone, website
  - Location biasing (center + radius)
  - Type filtering (restaurant, entertainment, city, etc.)
  - Address component parsing

#### Current Costs
- **Autocomplete Session**: $0.017 per session
- **Estimated Volume**: 100 private events/month × 3 searches = 300 sessions
- **Monthly Cost**: 300 × $0.017 = **$5.10**
- **Annual Cost**: **$61.20**
- **5-Year Cost**: **$306.00**

#### What Google Places Provides
✅ **Core Geocoding** (available in free alternatives):
- Place name
- Formatted address
- Coordinates (lat/lng)
- City, state, country
- Basic categories/types

❌ **Rich Metadata** (unique to Google Places):
- ⭐ Ratings and review counts
- 💰 Price level indicators
- 📸 Photos (up to 10 per venue)
- 📞 Phone numbers
- 🌐 Website URLs

#### Where It's Used
- **Private Event Creation**: `lib/eventasaurus_web/live/event_live/new.ex`
  - Lines 1067-1103: venue_selected handler
  - Lines 1129-1163: location_selected handler
  - Stores full Google Places data including place_id, metadata

- **Private Event Editing**: `lib/eventasaurus_web/live/event_live/edit.ex`
  - Lines 1166-1200: location_selected handler
  - Similar integration to new.ex

**Frontend Conclusion**: This is the primary opportunity for cost reduction, but requires significant development.

---

## Free Alternative Options

### Option 1: Photon (OpenStreetMap)

**API**: https://photon.komoot.io

**Pros**:
- ✅ Completely free, no API key required
- ✅ Fast autocomplete responses (built on Elasticsearch)
- ✅ Multilingual support
- ✅ More permissive rate limits than Nominatim (~10-50 req/sec)
- ✅ Global coverage via OSM data

**Cons**:
- ❌ No ratings, photos, phone, website
- ❌ Data quality varies by region (excellent in US/Europe, spotty elsewhere)
- ❌ "Fair use" policy - no hard limits but can be restricted
- ❌ No official JavaScript widget (need to build custom autocomplete)

**Best For**: Primary autocomplete for basic venue lookup

---

### Option 2: Nominatim (OpenStreetMap)

**API**: https://nominatim.org/release-docs/latest/api/Search/

**Pros**:
- ✅ Completely free, no API key required
- ✅ Official OSM geocoding service
- ✅ Already used successfully in backend (AddressGeocoder)

**Cons**:
- ❌ Strict rate limit: 1 request/second
- ❌ Not suitable for real-time autocomplete
- ❌ No ratings, photos, phone, website
- ❌ Slower responses than Photon

**Best For**: Backend geocoding fallback (already in use), not frontend autocomplete

---

### Option 3: Geoapify

**API**: https://apidocs.geoapify.com

**Pros**:
- ✅ Free tier: 3,000 requests/day (~100/day sustained)
- ✅ Drop-in replacement for Google Places
- ✅ JavaScript widget provided
- ✅ Good data quality
- ✅ Fast responses

**Cons**:
- ⚠️ Requires API key
- ⚠️ Free tier may be insufficient (300 sessions/month = 10/day average, but spiky traffic)
- ⚠️ Eventual cost after free tier ($0.001 per request = $0.30/300 requests)
- ❌ No ratings, photos from free tier

**Best For**: Quick migration with minimal code changes, good for low-traffic sites

---

### Option 4: Mapbox Geocoding API

**API**: https://docs.mapbox.com/api/search/geocoding/

**Pros**:
- ✅ Free tier: 100,000 requests/month (very generous)
- ✅ Commercial-grade quality
- ✅ JavaScript library available (@mapbox/mapbox-gl-geocoder)
- ✅ Fast, reliable responses
- ✅ Good global coverage

**Cons**:
- ⚠️ Requires API key and Mapbox account
- ⚠️ Eventual cost after free tier ($0.50 per 1,000 requests)
- ❌ No ratings, photos

**Best For**: Fallback option for high-quality results when Photon fails

---

### Option 5: Custom Implementation (Photon + Downshift)

**Stack**: Photon API + Downshift.js (autocomplete UI library)

**Pros**:
- ✅ Completely free at any scale
- ✅ Full control over UX
- ✅ No rate limit concerns with proper debouncing
- ✅ Open source aligned

**Cons**:
- ❌ Most development work (40-50 hours)
- ❌ Need to build/maintain custom autocomplete UI
- ❌ No official support

**Best For**: Long-term strategic investment, full vendor independence

---

## Recommended Approach

### Option A: Do Nothing ⏸️

**When to Choose**:
- Current costs are acceptable (~$60-180/year)
- No plans to scale beyond 200 events/month
- Development resources needed for higher priorities
- Cannot accept any UX trade-offs (ratings/photos are critical)

**Pros**:
- Zero development cost
- Zero risk
- Proven UX
- No data quality concerns

**Cons**:
- Vendor lock-in
- Exposed to future price increases
- Missed strategic opportunity for independence

---

### Option B: Hybrid Implementation 🚀

**Proposed Stack**: Photon (primary) + Mapbox (fallback) + Google (emergency)

**When to Choose**:
- Planning to scale beyond 500 events/month within 24 months
- Strategic value (vendor independence, privacy) is important
- Development capacity available (3-5 weeks)
- Can accept UX trade-offs (no ratings/photos in standard flow)

**Architecture**:
```
User Types Query
    ↓
Debounce 300ms → Check Local Cache
    ↓
Query Photon API (free, fast)
    ↓ (if fails or poor results)
Fallback to Mapbox (100K free/month)
    ↓ (if fails)
Emergency fallback to Google Places
```

**Development Effort**:
- Phase 1: Proof of concept (1-2 days)
- Phase 2: JavaScript hook implementation (3-5 days)
- Phase 3: UI/UX updates (2-3 days)
- Phase 4: Backend integration (1-2 days)
- Phase 5: Testing (2-3 days)
- Phase 6: Gradual rollout (1-2 weeks)
- **Total**: 3-5 weeks (~40-50 hours)

**Cost Analysis**:
- Development: $2,000-$5,000 (one-time)
- Ongoing: ~$0.51/month (10% Google fallback)
- Savings: ~$4.59/month = $55/year
- ROI at current volume: 36-90 years ⚠️
- ROI at 500 events/month: 7-18 years ⚠️
- ROI at 2,000 events/month: 2-5 years ✅

**Strategic Value** (non-financial):
- Vendor independence: ~$500-1,000/year
- Privacy/brand value: ~$200-500/year
- Team learning: ~$500-1,000 value
- Open source alignment: ~$100-200/year
- **Total Strategic Value**: ~$1,300-$2,700/year

**Adjusted ROI with Strategic Value**: 1-2 years (acceptable)

**Pros**:
- 90% cost reduction
- Vendor independence
- Scalable to high volume
- Privacy-friendly
- Open source aligned

**Cons**:
- Significant development investment
- No ratings, photos, phone numbers in standard flow
- Potential data quality issues (especially non-US/Europe)
- Custom code to maintain
- UX changes may confuse existing users

**UX Changes Required**:
- Remove star ratings from venue cards
- Remove price level indicators ($, $$, $$$)
- Remove photo carousels
- Remove phone number display
- Remove website links
- Add "Limited information available" messaging
- Add optional "Enhance with Google Places" button for users who need full details

**Risk Mitigation**:
- Feature flag for instant rollback to Google Places
- Gradual rollout: 10% → 50% → 100% over 2-4 weeks
- Keep Google Places code for 3 months post-rollout
- Monitor error rates (<10% increase threshold for rollback)
- Geographic routing (OSM for US/EU, Google for low-coverage regions)

---

### Option C: Wait and See 🕐 (RECOMMENDED)

**When to Choose**:
- Current volume <200 events/month
- Costs are acceptable
- Growth trajectory unclear
- Want to defer decision until necessary

**Strategy**:
- Monitor growth for 6 months
- Set threshold: Re-evaluate when monthly cost exceeds $25 (500 events/month)
- Or: Re-evaluate when strategic concerns (vendor lock-in) become priority

**Pros**:
- Zero immediate investment
- Defer decision until economics improve
- More time to evaluate free alternatives
- Let open source ecosystem mature (better tools may emerge)

**Cons**:
- Exposed to price increases
- Harder to migrate later (more Google Places usage to replace)
- Miss timing for strategic vendor independence

---

## Implementation Details (If Proceeding with Option B)

### Phase 1: Proof of Concept (1-2 days)

**Goal**: Validate Photon integration and data quality

**Tasks**:
- Create minimal HTML page with autocomplete using Photon API
- Test with 20-30 real venue queries (restaurants, bars, venues, cities)
- Measure response times (target: <300ms p95)
- Compare results side-by-side with Google Places
- Document quality gaps and edge cases

**Success Criteria**:
- Response time <300ms for 95% of queries
- Address accuracy ≥90% for US/Europe queries
- Can extract city, state, country from responses

---

### Phase 2: JavaScript Hook Implementation (3-5 days)

**Goal**: Build production-ready autocomplete component

**Tasks**:
1. Create new hook: `OSMPlacesSearch` in `assets/js/hooks/places-search.js`
2. Implement debouncing (300ms delay after user stops typing)
3. Add local caching (sessionStorage for recent searches)
4. Build response normalizer to convert Photon/Mapbox → Google Places format
5. Add configuration for primary/fallback providers via data attributes
6. Implement fallback chain with error handling
7. Add minimum query length threshold (3 characters)

**Code Structure**:
```javascript
export const OSMPlacesSearch = {
  mounted() {
    this.providers = ['photon', 'mapbox', 'google'];
    this.debounceDelay = 300;
    this.cache = new Map();
    this.initAutocomplete();
  },

  async search(query) {
    // Check cache
    // Try Photon
    // Fallback to Mapbox
    // Emergency fallback to Google
  },

  normalizeResponse(provider, response) {
    // Convert to common format
  }
};
```

**Success Criteria**:
- Autocomplete dropdown appears within 500ms
- Fallback chain works correctly
- Maintains API compatibility with existing LiveView handlers

---

### Phase 3: UI/UX Updates (2-3 days)

**Goal**: Redesign venue cards for OSM data (no ratings/photos)

**Tasks**:
1. Update venue selection display in `places-search.js` (lines 410-458)
2. Remove rating stars display
3. Remove price level indicators
4. Remove photo carousel
5. Remove phone/website display
6. Add "Powered by OpenStreetMap" attribution
7. Add optional "Enhance with Google Places" button
8. Update CSS for simplified venue cards
9. Add "Limited information available" tooltip

**UI Mockup**:
```
┌─────────────────────────────────────┐
│ 📍 Blue Note Jazz Club              │
│ 131 W 3rd St, New York, NY 10012    │
│                                     │
│ ℹ️ Limited info • OSM               │
│ [Enhance with Google Places]       │
└─────────────────────────────────────┘
```

**Success Criteria**:
- Professional appearance without ratings/photos
- Clear messaging about limited information
- Optional enhancement path available

---

### Phase 4: Backend Integration (1-2 days)

**Goal**: Update LiveView handlers to accept OSM place format

**Files to Update**:
- `lib/eventasaurus_web/live/event_live/new.ex`
- `lib/eventasaurus_web/live/event_live/edit.ex`
- `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex`

**Tasks**:
1. Update `handle_event("location_selected", ...)` to accept OSM format
2. Map OSM IDs to internal venue system (store as `osm_id` in metadata)
3. Update VenueProcessor to handle OSM metadata
4. Ensure geocoding metadata tracks provider used (`osm`, `mapbox`, `google`)
5. Add validation for required fields (name, coordinates, formatted_address)

**Success Criteria**:
- Form submissions work correctly
- Venue data stored properly in database
- Provider attribution tracked in metadata

---

### Phase 5: Testing & QA (2-3 days)

**Goal**: Verify autocomplete works across all scenarios

**Test Cases**:
- Real venue searches (restaurants, bars, clubs, theaters)
- City searches (New York, Los Angeles, Chicago)
- International searches (London, Paris, Tokyo)
- Partial/misspelled queries
- Fast typing (debouncing test)
- Network failures (fallback test)
- Rate limiting simulation
- Mobile responsive
- Cross-browser (Chrome, Firefox, Safari, Edge)

**Performance Tests**:
- Response time <500ms p95
- Debouncing reduces requests by 70-80%
- Local caching works correctly
- No memory leaks

**Success Criteria**:
- >95% test pass rate
- No regression in core flows
- Performance meets targets

---

### Phase 6: Gradual Rollout (1-2 weeks)

**Goal**: Deploy safely with monitoring and rollback capability

**Rollout Plan**:
1. Add feature flag in runtime config
2. Deploy to staging with 100% OSM
3. Test manually and run automated tests
4. Deploy to production with 10% OSM (A/B test)
5. Monitor for 3 days:
   - Error rates
   - Venue selection success rate
   - Response times
   - User feedback
6. Increase to 50% if no issues
7. Monitor for 1 week
8. Increase to 100% if no issues
9. Keep Google Places code for 3 months
10. Remove Google Places code after monitoring period

**Monitoring Metrics**:
- Autocomplete error rate (target: <5%)
- Venue selection success rate (target: >90%)
- Response time p95 (target: <500ms)
- API fallback frequency (should be <10% Mapbox, <1% Google)
- User-reported issues

**Rollback Criteria**:
- Error rate >10% increase
- Venue success rate <85%
- Response time >1s p95
- >50% of sessions use Google fallback

---

## Risk Analysis

### High Risk 🔴

**1. Data Quality Degradation**
- **Problem**: OSM data less complete/accurate than Google Places
- **Impact**: Users frustrated with incorrect or missing venues
- **Likelihood**: Medium-High (OSM quality varies by region)
- **Mitigation**:
  - Keep "Enhance with Google Places" button
  - Monitor venue selection error rates
  - Maintain Google Places fallback in code
  - Focus rollout on regions with good OSM coverage (US, Europe first)
  - Add geographic routing (OSM for well-covered regions, Google elsewhere)

**2. Missing Rich Metadata**
- **Problem**: No ratings, photos, phone, website from OSM
- **Impact**: Less informative venue cards, potential user confusion
- **Likelihood**: High (certain - this is a known limitation)
- **Mitigation**:
  - Redesign UI to not emphasize missing data
  - Add "Limited information available" messaging
  - Offer Google Places opt-in for full details
  - Survey users to understand if metadata is actually used
  - Consider scraping/augmenting OSM with public data sources

**3. Geographic Coverage Gaps**
- **Problem**: OSM data sparse in some regions (Asia, Africa, South America)
- **Impact**: Poor experience for users in those regions
- **Likelihood**: High for specific regions
- **Mitigation**:
  - Analyze current user base by geography
  - Rollout to well-covered regions first (US, Canada, Europe)
  - Keep Google Places for low-coverage regions
  - Add geographic routing logic based on user location

---

### Medium Risk 🟡

**4. Performance Regression**
- **Problem**: Custom autocomplete slower than Google's widget
- **Impact**: Poor UX, increased load times
- **Likelihood**: Medium
- **Mitigation**:
  - Performance testing before rollout
  - Use Photon (known for fast responses)
  - Implement local caching
  - Monitor response times in production
  - Set SLA: <500ms p95, rollback if breached

**5. Development Time Overrun**
- **Problem**: Implementation takes longer than estimated
- **Impact**: Delayed rollout, increased dev costs, opportunity cost
- **Likelihood**: Medium-High (new territory, unknowns)
- **Mitigation**:
  - Use phased approach with clear milestones
  - Build MVP first (Photon only, basic UI)
  - Defer nice-to-have features to later phases
  - Set hard deadline: if >4 weeks, reassess ROI
  - Time-box each phase strictly

**6. User Resistance to Change**
- **Problem**: Users accustomed to Google Places behavior
- **Impact**: Support requests, negative feedback, adoption resistance
- **Likelihood**: Low-Medium
- **Mitigation**:
  - Gradual rollout (10% → 50% → 100%)
  - Clear messaging about why change is being made
  - Easy rollback mechanism via feature flag
  - Collect feedback and iterate quickly
  - Provide opt-in for Google Places if needed

---

### Low Risk 🟢

**7. Rate Limiting on Free Tier**
- **Problem**: Free APIs may throttle under heavy load
- **Impact**: Autocomplete becomes slow or fails
- **Likelihood**: Low (with debouncing and caching)
- **Mitigation**:
  - Implement aggressive debouncing (300ms)
  - Add request caching in sessionStorage
  - Use Mapbox free tier (100K/month) as fallback
  - Monitor request volumes and upgrade if needed
  - Keep Google Places as emergency fallback

**8. Breaking Changes in External APIs**
- **Problem**: Photon/Mapbox change API format or shut down
- **Impact**: Broken autocomplete functionality
- **Likelihood**: Low (established services, active maintenance)
- **Mitigation**:
  - Use multiple providers in fallback chain
  - Abstract API integration behind adapter layer
  - Monitor provider status and announcements
  - Keep Google Places as ultimate fallback
  - Contribute to/support open source projects

---

## Cost Analysis

### Current State (Google Places Only)

**Private Events** (100/month):
- Autocomplete sessions: 100 × 3 searches = 300/month
- Cost per session: $0.017
- Monthly: $5.10
- Annual: $61.20
- 5-year: $306.00

**Scrapers** (250 venues/month):
- Mostly OSM (free)
- Occasional Google fallback: ~$5-10/month
- Annual: $60-120

**Total Annual (Current)**: $120-180

---

### Hybrid OSM Implementation

**Development Cost** (one-time):
- 40-50 hours @ $50-100/hr
- Total: $2,000-$5,000

**Ongoing Costs**:
- 90% successful with OSM: 270 sessions × $0 = $0
- 10% fallback to Mapbox: 0 sessions × $0 = $0 (under 100K free tier)
- 1% fallback to Google: 3 sessions × $0.017 = $0.05/month
- Monthly: **$0.05**
- Annual: **$0.60**

**Savings**: $60.60/year at current volume

**ROI** (pure cost basis):
- $2,000 / $60.60/year = 33 years ⚠️
- $5,000 / $60.60/year = 82 years ⚠️

---

### Growth Scenarios

**At 500 Events/Month**:
- Current (Google): $25.50/month = $306/year
- Hybrid (OSM): $2.55/month = $30.60/year
- Savings: $275.40/year
- ROI: 7-18 years ⚠️

**At 2,000 Events/Month**:
- Current (Google): $102/month = $1,224/year
- Hybrid (OSM): $10.20/month = $122.40/year
- Savings: $1,101.60/year
- ROI: 2-5 years ✅

**At 5,000 Events/Month**:
- Current (Google): $255/month = $3,060/year
- Hybrid (OSM): $25.50/month = $306/year
- Savings: $2,754/year
- ROI: <1 year ✅✅

---

### Strategic Value (Non-Financial)

**Vendor Independence**: $500-1,000/year
- Avoid future Google price increases
- Negotiating power with providers
- Control over critical infrastructure

**Privacy & Brand**: $200-500/year
- No user data sent to Google
- Open source alignment
- Community contribution

**Team Learning**: $500-1,000 one-time
- Custom component development skills
- Multi-provider integration patterns
- Open source contribution experience

**Total Strategic Value**: $1,300-$2,700/year

---

### Adjusted ROI (With Strategic Value)

**Current Volume** (100 events/month):
- Savings: $60.60/year + $1,800/year strategic = $1,860.60/year
- ROI: 1-3 years ✅

**500 Events/Month**:
- Savings: $275.40/year + $1,800/year strategic = $2,075.40/year
- ROI: <1 year ✅✅

**Conclusion**: If strategic value is important, ROI is acceptable even at current volume.

---

## Decision Framework

### Proceed with Option B (Hybrid) if ALL of:
- ✅ Planning to scale beyond 500 events/month within 24 months, OR
- ✅ Vendor independence is strategic priority, OR
- ✅ Have 3-5 weeks of development capacity available
- ✅ Can accept UX trade-offs (no ratings/photos in standard flow)
- ✅ Team has JavaScript/API integration skills

### Proceed with Option C (Wait and See) if ANY of:
- ✅ Current costs are acceptable (<$25/month)
- ✅ No clear growth trajectory
- ✅ Development resources needed for higher priorities
- ✅ Cannot accept any data quality trade-offs
- ✅ Ratings/photos are critical to UX

### Proceed with Option A (Do Nothing) if ALL of:
- ✅ Current costs are acceptable indefinitely
- ✅ No strategic concerns about vendor lock-in
- ✅ Google Places UX is non-negotiable
- ✅ No plans to scale significantly

---

## Success Metrics (If Implementing Option B)

### Technical Metrics

**Performance**:
- Response time p50: <200ms
- Response time p95: <500ms
- Response time p99: <1s
- Cache hit rate: >30%
- Debounce effectiveness: >70% request reduction

**Reliability**:
- Autocomplete error rate: <5%
- Venue selection success rate: >90%
- API fallback frequency: <10% Mapbox, <1% Google
- Uptime: >99.9%

### Business Metrics

**Cost**:
- Monthly API costs: <$1 (target: $0.05-$0.50)
- Cost reduction: >80% vs. Google Places
- ROI timeline: <5 years at projected growth

**User Experience**:
- Venue selection time: No increase (maintain <30 seconds)
- User-reported issues: <5% increase
- Support tickets: <10% increase
- User satisfaction: Maintain current baseline

### Strategic Metrics

**Vendor Independence**:
- % of events using non-Google providers: >90%
- Number of provider options: ≥3 (Photon, Mapbox, Google)
- Fallback chain resilience: 100% (all providers working)

**Data Quality**:
- Venue accuracy rate: >90%
- Address accuracy rate: >95%
- Coordinate accuracy: >99%

---

## Next Steps

### If Choosing Option A (Do Nothing)
1. Close this issue
2. Continue monitoring costs monthly
3. Re-evaluate if costs exceed $50/month

### If Choosing Option C (Wait and See)
1. Set calendar reminder for 6-month review
2. Monitor monthly costs and event volume
3. Set alert: Re-evaluate if costs exceed $25/month or volume exceeds 500 events/month
4. Track Google Places API pricing changes

### If Choosing Option B (Hybrid Implementation)
1. Get stakeholder approval for $2,000-$5,000 development investment
2. Create feature flag in runtime config
3. Start Phase 1: Proof of Concept
4. Weekly progress reviews
5. Go/No-Go decision after PoC (commit or abort)

---

## References

### Documentation
- Current geocoding state: `docs/GEOCODING_CURRENT_STATE.md`
- AddressGeocoder implementation: `lib/eventasaurus_discovery/helpers/address_geocoder.ex`
- Google Places JavaScript: `assets/js/hooks/places-search.js`
- Event creation LiveView: `lib/eventasaurus_web/live/event_live/new.ex`

### External APIs
- Photon: https://photon.komoot.io
- Nominatim: https://nominatim.org/release-docs/latest/api/Search/
- Geoapify: https://apidocs.geoapify.com
- Mapbox Geocoding: https://docs.mapbox.com/api/search/geocoding/
- Google Places Pricing: https://developers.google.com/maps/billing-and-pricing/pricing

### Related Issues
- #1655: Geocoding cost tracking implementation
- #1653: Geocoding audit report
- #1652: Original geocoding cost concern

---

**Decision Required**: Choose Option A, B, or C based on strategic priorities and growth trajectory.

**Recommended**: Option C (Wait and See) unless strategic value justifies immediate investment.
