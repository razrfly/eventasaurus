# week.pl Restaurant Festival Integration - Feasibility Analysis

## 🔍 Executive Summary

**Platform**: [week.pl](https://week.pl) - Restaurant festival booking platform for Poland
**Business Model**: Organizes timed dining experiences during multi-week festivals across 13 Polish cities
**Technical Stack**: Next.js + React + Apollo Client + GraphQL
**Data Type**: Restaurant reservation slots during festival periods (unique use case)
**Recommendation**: ⚠️ **Proceed with caution** - Requires GraphQL API reverse engineering or web scraping

---

## 🏢 Platform Overview

### Business Model
week.pl operates as a **restaurant festival organizer and online reservation platform** in Poland. They coordinate multi-week culinary events where restaurants offer fixed-price tasting menus with bookable time slots.

### Festival Brands
1. **RestaurantWeek®** - 3-course dining experience (63 PLN)
2. **BreakfastWeek** - Breakfast-focused festival variant
3. **FineDiningWeek®** - Premium 5-course tasting menu (161 PLN)

### Geographic Coverage
**13 Polish Cities**: Białystok, Bydgoszcz, Kraków, Łódź, Lubelskie, Poznań, Rzeszów, Śląsk, Szczecin, Trójmiasto, Warszawa, Warmia i Mazury, Wrocław

### Festival Schedule (2026 Example)
- **RestaurantWeek Spring**: March 4 - April 22 (7 weeks)
- **FineDiningWeek**: July 1 - August 13 (6 weeks)
- **RestaurantWeek Fall**: October 7 - November 22 (7 weeks)

**Key Insight**: This is a **recurring seasonal platform** with predictable festival windows, not continuous event listings.

---

## 🔧 Technical Architecture

### Frontend Stack
- **Framework**: Next.js with React
- **State Management**: Apollo Client with GraphQL
- **Styling**: CSS-in-JS (Emotion or styled-components)
- **Image Optimization**: Next.js image optimization (`/_next/image`)

### Backend Infrastructure
- **GraphQL API**: Located at `api.week.pl` (confirmed via Apollo state)
- **Data Structure**: Normalized entities with references:
  - `Restaurant:2591` - Restaurant entities with coordinates, images, tags
  - `Tag:14` - Cuisine types, dietary options, atmosphere tags
  - `Region:5` - Geographic regions (cities)
  - `FestivalEdition:70` - Specific festival time periods
  - `ImageFile:*` - CDN-hosted images

### Available Data Per Restaurant
Based on Apollo Client cache analysis:
```typescript
{
  id: number,
  name: string,
  slug: string,
  description: string,
  coordinates: { latitude: number, longitude: number },
  images: ImageFile[],
  tags: Tag[], // Cuisine, atmosphere, dietary, delivery regions
  possibleSlots: number[], // Time slots in minutes (e.g., 720 = 12:00 PM)
  festivalEdition: FestivalEdition,
  region: Region
}
```

### Reservation System
- **Time Format**: Slots stored as integer minutes from midnight (e.g., `720` = 12:00, `1140` = 19:00)
- **Filters**: Date range, guest count (2-6), reservation type (Daily/Festival)
- **Availability**: Real-time slot availability during festival periods

---

## 🚧 API Accessibility Analysis

### GraphQL Endpoint Investigation

**Attempted**: `https://api.week.pl/graphql`
**Result**: ❌ **404 Not Found**

**Possible Reasons**:
1. ✅ Different endpoint path (e.g., `/api/graphql`, `/v1/graphql`, `/graphql/v1`)
2. ✅ Requires authentication headers (API key, JWT token)
3. ✅ CORS restrictions (only accessible from `week.pl` domain)
4. ✅ Protected behind CDN/WAF (Cloudflare, etc.)

### robots.txt Analysis
**Result**: Completely permissive - no API paths revealed
```
User-agent: *
Allow: /
```

### Apollo Client State
**Finding**: Page embeds `__APOLLO_STATE__` with normalized GraphQL cache
**Implication**: GraphQL queries are executed server-side or client-side, but endpoint/auth unknown

---

## 🎯 Integration Options

### Option 1: GraphQL API Integration (Preferred but Challenging)

**Pros**:
- ✅ Structured data with clear schema
- ✅ Coordinates included (no geocoding needed)
- ✅ Rich metadata (tags, images, descriptions)
- ✅ Efficient querying with filters
- ✅ Follows existing `ResidentAdvisor` scraper pattern

**Cons**:
- ❌ Endpoint path unknown (requires network analysis)
- ❌ May require authentication/API key
- ❌ No public API documentation
- ❌ Potential legal/ToS concerns with API access

**Implementation Complexity**: **Medium-High** (API reverse engineering required)

**Reference Implementation**: `lib/eventasaurus_discovery/sources/resident_advisor/`
- Uses GraphQL client with queries
- Priority: 75 (trusted international source)
- Handles pagination, rate limiting, retries

---

### Option 2: Web Scraping (Fallback)

**Approach**: Scrape HTML/JavaScript rendered restaurant listing pages

**Pros**:
- ✅ No API authentication needed
- ✅ Publicly accessible data
- ✅ Can extract Apollo state from page source

**Cons**:
- ❌ More fragile (page structure changes break scraper)
- ❌ Requires JavaScript rendering (Puppeteer/Playwright)
- ❌ Slower than API calls
- ❌ Higher maintenance burden

**Implementation Complexity**: **Medium**

**Reference Implementation**: `lib/eventasaurus_discovery/sources/karnet/`
- HTML scraping with CSS selectors
- Multi-stage jobs (index + detail pages)
- Priority: 30 (regional source)

---

## 📊 Data Mapping Strategy

### Challenge: Restaurant Slots → Events

**Conceptual Mapping**:
```
Restaurant + Time Slot + Date + Festival → Event
```

**Example**:
```elixir
# Source Data
%{
  restaurant: "Restauracja Pod Baranami",
  festival: "RestaurantWeek Spring 2026",
  date: "2026-03-15",
  time_slot: 1140, # 19:00 (7 PM)
  price: 63.00,
  location: "Kraków"
}

# Mapped Event
%{
  title: "RestaurantWeek at Restauracja Pod Baranami",
  starts_at: ~U[2026-03-15 19:00:00Z],
  ends_at: ~U[2026-03-15 21:00:00Z], # Assume 2-hour duration
  is_ticketed: true,
  is_free: false,
  min_price: 63.00,
  max_price: 63.00,
  currency: "PLN",
  category: "food-drink", # or "dining-experience"
  venue_data: %{
    name: "Restauracja Pod Baranami",
    latitude: 50.0647,
    longitude: 19.9450,
    city: "Kraków",
    country: "Poland"
  },
  metadata: %{
    source_type: "restaurant_week",
    festival_edition: "RestaurantWeek Spring 2026",
    guest_count: 2, # or flexible
    cuisine_tags: ["Polish", "Fine Dining"],
    booking_url: "https://week.pl/restaurants/...",
    original_slot: 1140
  }
}
```

### External ID Strategy

**Pattern**: `week_pl_{restaurant_id}_{date}_{slot}`

**Example**: `week_pl_2591_20260315_1140`

**Reasoning**:
- Unique per restaurant + date + time combination
- Stable across scraper runs
- Prevents duplicate events for same slot
- Follows pattern-based scraper guidelines (SCRAPER_SPECIFICATION.md §Pattern-Based Scraper External IDs)

---

## 🏗️ Proposed Scraper Architecture

### Directory Structure
```
lib/eventasaurus_discovery/sources/week_pl/
├── source.ex                    # Source metadata & configuration
├── config.ex                    # Runtime configuration (API endpoint, rate limits)
├── client.ex                    # GraphQL client (if API accessible)
├── transformer.ex               # Restaurant slot → Event transformation
├── helpers/
│   ├── time_converter.ex        # Minute integer → DateTime conversion
│   └── festival_detector.ex     # Active festival period detection
├── jobs/
│   ├── sync_job.ex              # Main orchestration (festival period sync)
│   ├── city_sync_job.ex         # Per-city restaurant fetching
│   └── restaurant_detail_job.ex # Individual restaurant slot extraction
└── README.md                    # Setup, configuration, usage docs
```

### Job Flow

**Pattern**: Multi-stage scraper (similar to Karnet/Bandsintown)

1. **SyncJob** (Festival-aware orchestration)
   - Check if festival period is active (March 4 - April 22, etc.)
   - If active, enqueue CitySync jobs for each city
   - If inactive, skip sync (no events available)

2. **CitySyncJob** (Per-city restaurant listing)
   - Fetch restaurants for city with available slots
   - Apply EventFreshnessChecker (7-day threshold)
   - Enqueue RestaurantDetailJob for stale restaurants

3. **RestaurantDetailJob** (Individual restaurant processing)
   - Extract all time slots for restaurant
   - Generate one event per slot per day
   - Transform to unified format
   - Pass to EventProcessor for deduplication

### Priority Level

**Recommendation**: **Priority 40-50** (Regional Poland source)

**Reasoning**:
- Regional scope (Poland only)
- Niche category (restaurant experiences)
- Seasonal availability (not year-round)
- Similar to Karnet (30) but more structured data

**Priority Scale Reference**:
- 90-100: Premium APIs (Ticketmaster)
- 70-89: Trusted international (Resident Advisor, Bandsintown)
- 50-69: Regional reliable sources
- 30-49: Local/niche sources ← **week.pl fits here**

---

## ⚠️ Challenges & Considerations

### 1. API Access Uncertainty
**Issue**: GraphQL endpoint not publicly documented
**Mitigation**:
- Network traffic analysis with browser DevTools
- Check for API keys in page source/cookies
- Contact week.pl for partnership/API access
- Fall back to web scraping if API inaccessible

### 2. Seasonal Availability
**Issue**: Events only exist during festival periods (7 weeks × 3 festivals = 21 weeks/year)
**Impact**: 40% of the year has no data
**Mitigation**:
- Festival-aware sync job that checks date ranges
- Skip sync when no festival active
- Document festival schedules in README

### 3. Event Volume & Deduplication
**Issue**: High volume of events (restaurants × slots × days × cities)
**Example**: 100 restaurants × 5 slots × 49 days × 13 cities = **319,000 potential events**
**Mitigation**:
- EventFreshnessChecker with 7-day threshold (CRITICAL)
- Batch processing in detail jobs
- Rate limiting to avoid overwhelming database

### 4. Category Mapping
**Issue**: Restaurant experiences don't fit existing categories perfectly
**Options**:
- Use existing `food-drink` category
- Create new `dining-experience` category
- Tag with `restaurant-week` for filtering
**Recommendation**: Start with `food-drink`, add specific tagging via metadata

### 5. Legal & Terms of Service
**Issue**: Scraping may violate ToS
**Mitigation**:
- Review week.pl Terms of Service
- Respect robots.txt (currently permissive)
- Implement rate limiting (5-10 seconds between requests)
- Consider partnership/API access request

### 6. Data Freshness
**Issue**: Reservation slots change in real-time (availability)
**Challenge**: Showing "available" slots that are already booked
**Mitigation**:
- Treat as "event discovery" not "live booking"
- Link users to week.pl for actual reservations
- Refresh daily during festival periods

---

## 📋 Implementation Checklist

### Phase 1: API Investigation (1-2 days)
- [ ] Analyze network traffic on week.pl with browser DevTools
- [ ] Identify GraphQL queries and endpoint path
- [ ] Test API accessibility with `curl`/HTTPoison
- [ ] Check for authentication requirements
- [ ] Document API structure and query patterns
- [ ] **Decision Point**: API accessible → Phase 2A | Not accessible → Phase 2B

### Phase 2A: GraphQL Integration (if API accessible)
- [ ] Create `week_pl` directory structure
- [ ] Implement `source.ex` with configuration
- [ ] Build `client.ex` GraphQL client (follow `resident_advisor` pattern)
- [ ] Implement `transformer.ex` for data mapping
- [ ] Create multi-stage jobs (Sync → CitySync → RestaurantDetail)
- [ ] Add EventFreshnessChecker integration
- [ ] Create YAML category mappings (`priv/category_mappings/week_pl.yml`)
- [ ] Write comprehensive tests
- [ ] Document in README.md

### Phase 2B: Web Scraping (if API not accessible)
- [ ] Analyze page structure and JavaScript rendering
- [ ] Implement HTML scraper with Floki
- [ ] Extract Apollo state from `__APOLLO_STATE__` embedded JSON
- [ ] Build transformer for scraped data
- [ ] Implement multi-stage jobs
- [ ] Add EventFreshnessChecker integration
- [ ] Create category mappings
- [ ] Write tests and documentation

### Phase 3: Testing & Validation
- [ ] Test with Kraków restaurants (initial city)
- [ ] Verify deduplication works correctly
- [ ] Check EventFreshnessChecker reduces API calls by 80%+
- [ ] Run quality assessment (`mix quality.check week-pl`)
- [ ] Validate category coverage (target: >90%)
- [ ] Test during active festival period

### Phase 4: Production Deployment
- [ ] Add to `sources` table in database
- [ ] Configure Oban job scheduling
- [ ] Enable for Kraków first (pilot city)
- [ ] Monitor logs for errors/rate limiting
- [ ] Expand to all 13 cities if successful
- [ ] Document in main README.md

---

## 💡 Recommendations

### Immediate Next Steps
1. ✅ **Network Analysis**: Use Chrome DevTools to capture GraphQL requests
   - Open week.pl restaurant listing page
   - Go to Network tab → Filter: "Fetch/XHR"
   - Look for requests to `api.week.pl`
   - Copy GraphQL query and headers

2. ✅ **Test API Access**: Attempt to replicate queries with `curl`
   ```bash
   curl -X POST https://api.week.pl/[discovered-path] \
     -H "Content-Type: application/json" \
     -H "[discovered-headers]" \
     -d '{"query":"[discovered-query]","variables":{...}}'
   ```

3. ✅ **Partnership Inquiry**: Contact week.pl about official API access
   - Explain Eventasaurus use case (event discovery, not booking)
   - Request API documentation or partnership
   - May unlock structured access without reverse engineering

### Long-Term Strategy
- **Start Small**: Pilot with Kraków only (1 city)
- **Monitor Seasonality**: Only sync during active festival periods
- **Iterate**: Improve based on actual user interest in restaurant events
- **Evaluate ROI**: If low engagement, pause development

### Alternative Approach
**Consider**: Instead of scraping, **manually curate** week.pl festivals as umbrella events
- Create 3 events per year per city (RestaurantWeek Spring/Fall, FineDiningWeek)
- Link to week.pl in event description
- Avoid complex scraping for seasonal, recurring festivals
- Lower maintenance, clearer UX ("RestaurantWeek Kraków" vs. 1000s of restaurant slots)

---

## 📚 Reference Documentation

### Scraper Specification
- [SCRAPER_SPECIFICATION.md](docs/scrapers/SCRAPER_SPECIFICATION.md) - **Required Reading**
- [SCRAPER_AUDIT_REPORT.md](docs/scrapers/SCRAPER_AUDIT_REPORT.md) - Grading criteria
- [SCRAPER_QUICK_REFERENCE.md](docs/scrapers/SCRAPER_QUICK_REFERENCE.md) - Developer cheat sheet

### Reference Implementations
- **GraphQL Source**: `lib/eventasaurus_discovery/sources/resident_advisor/` (Priority 75)
- **Multi-Stage Scraper**: `lib/eventasaurus_discovery/sources/karnet/` (Priority 30)
- **Regional Poland Source**: `lib/eventasaurus_discovery/sources/kino_krakow/` (Priority 50)

### Key Patterns
- **EventFreshnessChecker**: Prevents re-processing fresh events (80-90% API reduction)
- **External ID Strategy**: Pattern-based for recurring events (SCRAPER_SPECIFICATION.md §Pattern-Based Scraper External IDs)
- **Category Mappings**: YAML-based normalization (`priv/category_mappings/{source}.yml`)

---

## 🎯 Conclusion

**Feasibility**: ✅ **Technically Feasible** (with caveats)

**Complexity**: 🟡 **Medium** (API reverse engineering) or 🟠 **Medium-High** (web scraping)

**Value**: 🟢 **Moderate** (niche category, seasonal availability, Poland-only)

**Recommendation**:
1. **Investigate API access first** - Most efficient if accessible
2. **Pilot with Kraków** - Test with 1 city before scaling
3. **Consider manual curation** - If scraping proves too complex/fragile
4. **Iterate based on user interest** - Restaurant events may be niche audience

**Priority**: Add to backlog, not urgent. Prioritize completing existing scraper improvements (Karnet tests, Bandsintown consolidation) before starting new source.

---

**Next Steps**: Assign to developer for network analysis + API investigation when bandwidth available.
