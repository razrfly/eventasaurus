# Add Inquizition Scraper to Eventasaurus

## Overview

Implement scraper for **Inquizition** (UK-based trivia provider) following the unified scraper specification and using Quizmeisters implementation as the architectural reference.

**Key Constraint**: Inquizition does NOT provide event images (simpler than Quizmeisters).

**Critical Requirement**: Investigate alternatives to Zyte API before implementation. Zyte should only be used as a last resort if free alternatives fail.

## Background

Inquizition is currently implemented in the `trivia_advisor` project using Zyte API for JavaScript rendering. The original implementation uses Zyte because venue data is loaded via `storelocatorwidgets.com` JavaScript widget and is not present in static HTML.

**Goal**: Port this scraper to `eventasaurus` while avoiding ongoing API costs if possible.

## Source Information

- **Website**: https://inquizition.com
- **Venue Finder**: https://inquizition.com/find-a-quiz/
- **Coverage**: United Kingdom (national coverage)
- **Event Type**: Weekly recurring trivia nights
- **Pricing**: £2.50 standard entry fee
- **Data Source**: storelocatorwidgets.com JavaScript widget (client-rendered)
- **External ID Format**: `inquizition_<venue_slug>`
- **Priority**: 35 (regional specialist source - same as Quizmeisters)

## Data Extraction Approach Investigation

### Phase 0: Prerequisites - API Investigation (REQUIRED FIRST)

**CRITICAL**: Complete this investigation phase before any implementation work.

#### How StoreLocatorWidgets Works

Inquizition embeds the StoreLocatorWidgets JavaScript widget on their venue finder page. The widget:
1. Loads from storelocatorwidgets.com CDN
2. Initializes with account UID
3. Fetches location data from StoreLocatorWidgets CDN/API
4. Exposes data via JavaScript APIs: `storeLocatorGetData()` and `storeLocatorLoad(uid)`

**Key Discovery**: StoreLocatorWidgets provides both official APIs and client-side JavaScript hooks documented at storelocatorwidgets.com.

#### Option 1: StoreLocatorWidgets CDN Endpoint (Most Preferred)
- [ ] Identify Inquizition's StoreLocatorWidgets account UID from page source
- [ ] Test direct CDN endpoint: `https://[cdn].storelocatorwidgets.com/[uid]/locations.json` (or similar)
- [ ] Document request format and authentication (if any)
- [ ] Test if endpoint is publicly accessible
- [ ] Parse JSON response structure
- [ ] **If successful**: Proceed with standard HTTP client (free, fast, reliable - like Quizmeisters)

#### Option 2: StoreLocatorWidgets Official API (Preferred Alternative)
- [ ] Research StoreLocatorWidgets Location & Search APIs
- [ ] Check if API key is publicly available or can be obtained
- [ ] Test API endpoints with Inquizition's account
- [ ] Document authentication requirements
- [ ] Evaluate API rate limits and costs (if any)
- [ ] **If successful**: Proceed with authenticated API client (potentially free or low-cost)

#### Option 3: JavaScript Hook Method (Alternative)
- [ ] Use Playwright **ONE-TIME** to extract data structure
- [ ] Inject JavaScript to call `storeLocatorGetData()` or listen to `storeLocatorListLocationsHandler()`
- [ ] Document complete data structure and UID
- [ ] Reverse-engineer the CDN endpoint from network requests
- [ ] Switch to direct HTTP client for production scraping
- [ ] **Purpose**: This is a research tool to find Option 1 endpoint, NOT for production use

#### Option 4: Zyte API (Last Resort Only)
- [ ] Document why Options 1-3 failed
- [ ] Confirm no public CDN endpoint exists
- [ ] Confirm StoreLocatorWidgets API requires paid account
- [ ] Estimate monthly Zyte costs (~$1-3/month for ~100 venues)
- [ ] Get approval for ongoing API costs
- [ ] **Only if approved**: Proceed with Zyte API implementation

### Decision Gate

**STOP**: Do not proceed past this phase until the investigation is complete and an approach is selected.

**Decision Criteria**:
1. If CDN endpoint found → Use Option 1 (HTTP client - BEST)
2. If official API accessible → Use Option 2 (authenticated API client)
3. If JavaScript hooks reveal endpoint → Use Option 3 for research, then Option 1 for production
4. If all free options fail → Use Option 4 (Zyte API - requires approval)

**Expected Outcome**: Option 1 is most likely - StoreLocatorWidgets typically serves data from a CDN endpoint that can be accessed directly once the UID is identified.

## Implementation Architecture

### Directory Structure

```
lib/eventasaurus_discovery/sources/inquizition/
├── source.ex                     # Source configuration (priority 35)
├── config.ex                     # Runtime settings (CDN URL, rate limits, timeouts)
├── client.ex                     # HTTP client with retry logic (most likely)
├── transformer.ex               # Data transformation to unified format
├── extractors/
│   └── venue_extractor.ex       # JSON parsing from CDN (most likely)
├── helpers/
│   └── time_parser.ex           # Schedule text parsing
├── jobs/
│   ├── sync_job.ex              # Main orchestration + CDN fetch
│   └── index_job.ex             # Venue processing with EventFreshnessChecker
├── README.md                    # Documentation (389+ lines)
└── (no venue_detail_job.ex - single-stage scraper)

# If Option 2-4 selected instead:
├── api_client.ex                # If StoreLocatorWidgets official API (Option 2)
├── zyte_client.ex               # If Zyte API (Option 4 - last resort)
└── extractors/venue_extractor.ex # HTML parsing (if Zyte) or JSON parsing (if API/CDN)

test/eventasaurus_discovery/sources/inquizition/
├── transformer_test.exs         # Transformation tests (NO image tests)
├── extractors/
│   └── venue_extractor_test.exs
├── helpers/
│   └── time_parser_test.exs
└── jobs/
    └── sync_job_test.exs
```

### Key Differences from Quizmeisters

1. **No Images**: Inquizition does not provide event/venue images
   - Skip `validate_image_url/1` function
   - Skip image validation tests
   - Skip image extraction from venue data

2. **No Performers**: No quizmaster/host data available
   - Skip performer extraction logic
   - Skip `PerformerStore` integration
   - Skip `PublicEventPerformer` linking

3. **Single-Stage Architecture**: No separate detail page scraping
   - Only `sync_job.ex` and `index_job.ex` (no `venue_detail_job.ex`)
   - All data extracted from venue finder page
   - Simpler data flow: Fetch → Parse → Transform → Process

4. **Standard Pricing**: £2.50 entry fee (not free)
   - `is_free: false`
   - `is_ticketed: true`
   - `min_price: 2.50`
   - `currency: "GBP"`

5. **UK Coverage**: Single country (not Australia)
   - `country: "United Kingdom"`
   - Default timezone: `"Europe/London"`
   - City resolution via `CityResolver` for UK cities

## Data Fields

### Required Fields (from venue finder)
- ✅ Venue name (from `.storelocator-storename`)
- ✅ Address (from `.storelocator-address`)
- ✅ GPS coordinates (from data attributes or geocoding)
- ✅ Schedule text (from `.storelocator-description`)
- ✅ Phone (from `.storelocator-phone a`)

### Optional Fields
- ⚠️ Website (may be in store data)
- ⚠️ Postcode (from address parsing)
- ❌ Images (not available)
- ❌ Performers (not available)
- ❌ Social media (not available)

### Standard Fields (hardcoded)
- ✅ Price: £2.50
- ✅ Currency: GBP
- ✅ Country: United Kingdom
- ✅ Category: trivia
- ✅ is_ticketed: true
- ✅ is_free: false

## Implementation Phases

### Phase 1: Core Infrastructure
Following the selected approach from Phase 0:

**Option 1 Path (StoreLocatorWidgets CDN - Most Likely)**:
- [ ] Create `source.ex` with priority 35
- [ ] Create `config.ex` with CDN URL and Inquizition's UID
- [ ] Create `client.ex` with exponential backoff retry
- [ ] Create `extractors/venue_extractor.ex` for JSON parsing
- [ ] Write unit tests for VenueExtractor (15+ tests)
- [ ] **Architecture**: Like Quizmeisters (free API, JSON response, HTTP client)

**Option 2 Path (StoreLocatorWidgets Official API)**:
- [ ] Create `source.ex` with priority 35
- [ ] Create `config.ex` with API URL and authentication
- [ ] Create `api_client.ex` with exponential backoff retry
- [ ] Create `extractors/venue_extractor.ex` for JSON parsing
- [ ] Write unit tests for VenueExtractor (15+ tests)
- [ ] **Architecture**: Similar to Quizmeisters but with API authentication

**Option 3 Path (JavaScript Hook Research → CDN Production)**:
- [ ] Use Playwright ONE-TIME to identify CDN endpoint
- [ ] Document the CDN URL and data structure
- [ ] Switch to Option 1 Path for production implementation
- [ ] **Architecture**: Research phase only, production uses standard HTTP client

**Option 4 Path (Zyte API - Last Resort)**:
- [ ] Get approval for Zyte API costs
- [ ] Create `source.ex` with priority 35
- [ ] Create `config.ex` with Zyte API settings
- [ ] Create `zyte_client.ex` with API authentication
- [ ] Create `extractors/venue_extractor.ex` for rendered HTML parsing
- [ ] Write unit tests for VenueExtractor (15+ tests)
- [ ] **Architecture**: Like trivia_advisor (paid API, HTML parsing)

### Phase 2: Time Parsing
- [ ] Create `helpers/time_parser.ex` based on Quizmeisters pattern
- [ ] Support formats: "Every Monday at 7:30pm", "Tuesdays 8pm", etc.
- [ ] Handle timezone conversion (Europe/London → UTC)
- [ ] Write comprehensive tests (29+ tests like Quizmeisters)
- [ ] Test edge cases: "first Monday", "last Tuesday", bi-weekly patterns

### Phase 3: Data Transformation
- [ ] Create `transformer.ex` following unified format
- [ ] Generate stable external IDs: `inquizition_<venue_slug>`
- [ ] Build recurrence rules for weekly events
- [ ] Integrate CityResolver for UK cities
- [ ] Set pricing: £2.50, GBP, is_ticketed=true
- [ ] Write transformer tests (18+ tests, NO image validation tests)
- [ ] Test timezone handling and recurrence rules

### Phase 4: Job Orchestration
- [ ] Create `jobs/sync_job.ex` for main coordination
- [ ] Create `jobs/index_job.ex` with EventFreshnessChecker
- [ ] Integrate EventFreshnessChecker to filter fresh venues (80-90% reduction)
- [ ] Configure Oban queue (`:scraper` queue, priority 2)
- [ ] Implement rate limiting (2s between requests)
- [ ] Add exponential backoff retry (3 attempts, 500ms → 2000ms)
- [ ] Write integration test for full pipeline

### Phase 5: Processing Integration
- [ ] Use `Processor.process_source_data/2` for unified processing
- [ ] Integrate VenueProcessor for GPS-based deduplication
- [ ] Integrate EventProcessor for external_id deduplication
- [ ] NO PerformerStore integration (no performers)
- [ ] Test end-to-end with real data (limited scraper run)
- [ ] Verify events created correctly in database
- [ ] Verify venues deduplicated by GPS coordinates

### Phase 6: Documentation & Polish
- [ ] Create comprehensive README (389+ lines like Quizmeisters)
- [ ] Document data sources and API approach (based on Phase 0 decision)
- [ ] Document architecture and data flow
- [ ] Document testing strategy
- [ ] Document troubleshooting guide
- [ ] Document idempotency mechanisms
- [ ] Document performance metrics
- [ ] Add usage examples and configuration guide

### Phase 7: Testing & Validation
- [ ] Run limited scraper: `mix discovery.sync --source inquizition --limit 5`
- [ ] Verify 5 events created with correct data
- [ ] Run full scraper: `mix discovery.sync --source inquizition`
- [ ] Verify ~100 events created (UK coverage)
- [ ] Check EventFreshnessChecker reduces subsequent runs by 80-90%
- [ ] Verify recurring patterns parse correctly
- [ ] Verify GPS coordinates accurate for UK venues
- [ ] Verify pricing set correctly (£2.50, GBP)
- [ ] Run full test suite: `mix test test/eventasaurus_discovery/sources/inquizition/`
- [ ] Aim for 60+ total tests (simpler than Quizmeisters' 83)

## Quality Checklist (Target: A+ Grade)

### 1. Data Extraction (Target: 100%)
- [ ] Venue name extracted
- [ ] GPS coordinates extracted or geocoded
- [ ] Address extracted
- [ ] Phone extracted
- [ ] Schedule text extracted
- [ ] All available fields captured

### 2. Data Transformation (Target: 100%)
- [ ] Unified format compliance
- [ ] Stable external IDs
- [ ] Recurrence rules generated
- [ ] City resolution integrated
- [ ] Timezone conversion (Europe/London → UTC)
- [ ] Pricing set correctly (£2.50, GBP)

### 3. Data Quality (Target: 98%)
- [ ] Required field validation
- [ ] GPS coordinate validation
- [ ] City name validation
- [ ] Lorem ipsum filtering (if applicable)
- [ ] Schedule text parsing robustness

### 4. Storage & Processing (Target: 100%)
- [ ] Processor integration
- [ ] VenueProcessor (GPS deduplication)
- [ ] EventProcessor (external_id deduplication)
- [ ] EventFreshnessChecker integration

### 5. Performance & Reliability (Target: 98%)
- [ ] Exponential backoff retry (3 attempts)
- [ ] Rate limiting (2s between requests)
- [ ] Timeout handling (30s per request)
- [ ] Oban configuration (`:scraper` queue, priority 2)
- [ ] EventFreshnessChecker (80-90% reduction)

### 6. Testing (Target: 100%)
- [ ] VenueExtractor tests (15+ tests)
- [ ] TimeParser tests (29+ tests)
- [ ] Transformer tests (18+ tests, NO image tests)
- [ ] SyncJob integration test
- [ ] Total: 60+ comprehensive tests

### 7. Documentation (Target: 100%)
- [ ] README length (389+ lines)
- [ ] Architecture documentation
- [ ] API/data source documentation
- [ ] Testing guide
- [ ] Troubleshooting guide
- [ ] Performance metrics
- [ ] Implementation notes

### 8. Idempotency (Target: 98%)
- [ ] Stable external IDs
- [ ] EventFreshnessChecker integration
- [ ] last_seen_at updates
- [ ] GPS venue matching
- [ ] Duplicate prevention

## Expected Outcomes

### Events Created
- **Count**: ~100 events (UK coverage)
- **Type**: Weekly recurring trivia nights
- **External ID**: `inquizition_<venue_slug>`
- **Pricing**: £2.50 entry fee (GBP)
- **Category**: trivia
- **Images**: None (not available)
- **Performers**: None (not available)

### Performance Metrics
- **Initial Run**: ~100 venues scraped
- **Subsequent Runs**: 80-90% reduction via EventFreshnessChecker
- **Rate Limit**: 2 seconds between requests
- **Timeout**: 30 seconds per request
- **Max Retries**: 3 attempts with exponential backoff

### Test Coverage
- **Total Tests**: 60+ comprehensive tests
- **VenueExtractor**: 15+ tests
- **TimeParser**: 29+ tests
- **Transformer**: 18+ tests (no image tests)
- **Integration**: 1+ end-to-end tests

### Documentation
- **README**: 389+ lines (comprehensive guide)
- **Architecture**: Complete data flow documentation
- **Testing**: Full testing strategy
- **Troubleshooting**: Common issues and solutions

## Success Criteria

1. **Phase 0 Complete**: Investigation complete, approach selected and documented
2. **Scraper Functional**: Successfully creates ~100 UK trivia events
3. **EventFreshnessChecker**: Achieves 80-90% API call reduction
4. **Test Coverage**: 60+ tests, all passing
5. **Documentation**: Comprehensive README (389+ lines)
6. **Grade Target**: A+ (98% overall score)
7. **Idempotency**: Multiple runs don't create duplicates
8. **Performance**: Rate limiting and retry logic working
9. **Data Quality**: All required fields captured and validated
10. **Cost Efficiency**: Using free alternative if possible (Options 1 or 2)

## References

- **Parent Issue**: #1513 (Quizmeisters implementation - architectural reference)
- **Architectural Template**: `lib/eventasaurus_discovery/sources/quizmeisters/`
- **Original Implementation**: `trivia_advisor` project (Zyte API approach)
- **Unified Specification**: `docs/scrapers/SCRAPER_SPECIFICATION.md`
- **Quizmeisters Audit**: `QUIZMEISTERS_AUDIT_REPORT.md` (A+ grade achievement)
- **Quizmeisters Fix Summary**: `QUIZMEISTERS_FIX_SUMMARY.md` (upgrade to A+)

## Notes

### Key Simplifications vs. Quizmeisters
1. **No images** - Skip all image handling logic and tests
2. **No performers** - Skip performer extraction and linking
3. **Single-stage** - No venue detail page scraping needed
4. **Standard pricing** - Hardcoded £2.50 fee (simpler than free events)
5. **Single country** - UK only (simpler than Australia-wide)

### Critical Success Factor
**Complete Phase 0 investigation before any implementation work.** The choice between CDN endpoint, official API, or Zyte API will determine the entire architecture and ongoing operational costs.

**Key Insight from Research**: StoreLocatorWidgets is a third-party widget service that loads location data from their CDN. The widget calls `storeLocatorLoad(uid)` to fetch data and exposes it via `storeLocatorGetData()`. This means:
1. **Most likely solution**: Direct CDN endpoint (like Quizmeisters' storerocket.io approach)
2. **Fallback solution**: StoreLocatorWidgets official API (may require API key)
3. **Research tool only**: Playwright can be used ONE-TIME to identify the CDN endpoint via JavaScript hooks
4. **Last resort**: Zyte API (avoid if possible due to ongoing costs)

The investigation should prioritize finding the CDN endpoint URL and testing direct HTTP access, which would make this implementation nearly identical to Quizmeisters (free, fast, reliable).

### Maintenance Considerations
- **If using CDN endpoint (Option 1 - most likely)**: Very low maintenance, similar to Quizmeisters
- **If using official API (Option 2)**: Monitor API rate limits and any authentication changes
- **If using Zyte API (Option 4 - last resort)**: Monitor monthly costs and usage, website structure changes
- EventFreshnessChecker reduces ongoing scraping load by 80-90%
- UK venue database relatively stable (less churn than event-based sources)
- StoreLocatorWidgets is a stable third-party service (less likely to change than custom implementations)

### Future Enhancements (Optional)
- Extended recurrence rules (bi-weekly, monthly patterns)
- Additional venue metadata extraction (if available)
- Performance monitoring and optimization
- Notification system for venue status changes
