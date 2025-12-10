# Automated Source Ingestion Framework

## Abstract

This document defines a systematic framework for integrating new event data sources into the Eventasaurus platform. The goal is to establish a replicable, eventually-automated process that minimizes manual intervention while maintaining data quality and reliability.

The framework is designed to evolve: as patterns are identified and validated through manual implementations, they become candidates for automation. The ultimate objective is AI-driven source ingestion where new sources can be integrated with minimal human oversight.

---

## 1. Source Access Pattern Taxonomy

Based on analysis of 16 existing scrapers, event data sources fall into six distinct access patterns:

### 1.1 REST API Sources

**Characteristics:**
- Documented endpoints with structured JSON/XML responses
- Often require API keys or authentication
- Predictable pagination (page/size, offset/limit, cursor)
- Rate limits typically documented

**Examples:** Ticketmaster, Cinema City, Quizmeisters

**Automation Potential:** HIGH - Structured responses enable reliable parsing

**Implementation Pattern:**
```
client.ex → API calls with auth/pagination
transformer.ex → JSON field mapping
jobs/sync_job.ex → Orchestration
```

### 1.2 GraphQL Sources

**Characteristics:**
- Single endpoint with query-based data fetching
- Schema introspection possible
- Flexible field selection
- Often no authentication for public data

**Examples:** Resident Advisor, Week.pl

**Automation Potential:** HIGH - Schema introspection enables auto-discovery

**Implementation Pattern:**
```
client.ex → GraphQL queries with variables
transformer.ex → Response field mapping
jobs/sync_job.ex → Query orchestration with pagination
```

### 1.3 HTML Scraping Sources

**Characteristics:**
- No API available; parse rendered HTML
- Structure may change without notice
- May require JavaScript rendering (SPA sites)
- Bot protection possible (Cloudflare, rate limiting)

**Examples:** Karnet, Kino Kraków, Waw4Free, Sortiraparis, Pubquiz

**Automation Potential:** MEDIUM - Requires robust selector generation and change detection

**Implementation Pattern:**
```
client.ex → HTTP requests with headers/retry logic
extractor.ex → CSS/XPath selectors for data extraction
transformer.ex → Extracted data normalization
jobs/*.ex → Page hierarchy (listing → detail)
```

### 1.4 RSS/Feed Sources

**Characteristics:**
- Standardized XML format (RSS 2.0, Atom)
- Usually paginated via URL parameters
- Limited data; often requires detail page scraping
- Reliable structure

**Examples:** Question One

**Automation Potential:** HIGH - Standardized format enables reliable parsing

**Implementation Pattern:**
```
client.ex → Feed fetching with pagination
transformer.ex → XML parsing + detail page enrichment
jobs/sync_job.ex → Feed pagination orchestration
```

### 1.5 WordPress/CMS API Sources

**Characteristics:**
- WordPress REST API or AJAX endpoints
- May require nonce extraction for authentication
- Predictable endpoint patterns
- Often return HTML fragments

**Examples:** Geeks Who Drink

**Automation Potential:** MEDIUM - CMS patterns are recognizable but varied

**Implementation Pattern:**
```
client.ex → Nonce extraction + AJAX calls
transformer.ex → HTML fragment parsing
jobs/sync_job.ex → Pagination handling
```

### 1.6 Hybrid Sources

**Characteristics:**
- Combine multiple access methods
- Often CDN APIs with JSONP wrappers
- May use third-party widget services
- Require unwrapping/transformation

**Examples:** Inquizition (StoreLocatorWidgets CDN)

**Automation Potential:** LOW - Custom handling required per source

**Implementation Pattern:**
```
client.ex → Multiple endpoint handling
transformer.ex → Response unwrapping + normalization
jobs/sync_job.ex → Multi-stage orchestration
```

---

## 2. Source Ingestion Phases

### Phase 0: Source Discovery & Initial Analysis

**Objective:** Understand the source's structure, data availability, and access patterns.

**Activities:**
- [ ] Fetch and analyze homepage
- [ ] Check for robots.txt and sitemap.xml
- [ ] Identify technology stack (JavaScript framework, CMS, etc.)
- [ ] Document URL patterns for listings, details, venues
- [ ] Note any bot protection mechanisms
- [ ] Assess data quality and coverage (geography, event types)
- [ ] Determine language(s) and locale requirements

**Outputs:**
- Source profile document
- URL pattern documentation
- Technology stack assessment
- Data coverage estimate

**Automation Candidates:**
- Sitemap discovery and parsing
- Technology stack detection (Wappalyzer-style)
- URL pattern extraction from sitemaps

### Phase 1: Access Pattern Determination

**Objective:** Determine the optimal method for data extraction.

**Decision Tree:**
```
Has documented API?
├── Yes → REST API pattern
└── No → Check network requests
    ├── GraphQL endpoint found? → GraphQL pattern
    ├── AJAX/XHR JSON responses? → Hidden API pattern
    └── No structured data → HTML scraping pattern
        ├── JavaScript-rendered content? → Browser automation required
        └── Server-rendered HTML → Direct HTTP scraping
```

**Activities:**
- [ ] Analyze network requests for API endpoints
- [ ] Check for GraphQL endpoints (common: /graphql, /api/graphql)
- [ ] Look for JSON-LD or structured data in HTML
- [ ] Test if content loads without JavaScript
- [ ] Check for RSS/Atom feeds
- [ ] Identify pagination mechanisms

**Outputs:**
- Access pattern classification
- Endpoint documentation
- Authentication requirements
- Rate limit observations

**Automation Candidates:**
- Network request analysis via headless browser
- API endpoint detection
- Pagination pattern recognition

### Phase 2: Schema Mapping

**Objective:** Map source data fields to the canonical Eventasaurus schema.

**Canonical Event Schema:**
```elixir
%{
  external_id: String.t(),           # Required: {source}_{type}_{id}_{date}
  title: String.t(),                 # Required
  description: String.t() | nil,
  starts_at: DateTime.t(),           # Required
  ends_at: DateTime.t() | nil,
  url: String.t() | nil,             # Source URL
  image_url: String.t() | nil,

  # Venue (required)
  venue: %{
    name: String.t(),
    address: String.t() | nil,
    city: String.t(),
    country: String.t(),
    latitude: float() | nil,
    longitude: float() | nil
  },

  # Optional
  performers: [String.t()],
  categories: [String.t()],
  price_info: String.t() | nil,
  ticket_url: String.t() | nil
}
```

**Activities:**
- [ ] Document all available source fields
- [ ] Map each field to canonical schema
- [ ] Identify required vs optional mappings
- [ ] Note any transformations needed (date parsing, geocoding)
- [ ] Identify fields requiring enrichment (TMDB, MusicBrainz)
- [ ] Document category mapping requirements

**Outputs:**
- Field mapping table
- Transformation requirements
- Enrichment requirements
- Category mapping YAML

**Automation Candidates:**
- LLM-based field mapping suggestions
- Date format detection
- Category inference from sample data

### Phase 3: Implementation

**Objective:** Build the scraper following established patterns.

**Required Components:**
```
lib/eventasaurus_discovery/sources/{source_name}/
├── client.ex              # HTTP/API client
├── config.ex              # Source configuration
├── transformer.ex         # Data transformation
├── dedup_handler.ex       # Deduplication logic (if needed)
└── jobs/
    ├── sync_job.ex        # Main orchestration
    └── [additional jobs]  # As needed
```

**Activities:**
- [ ] Create source directory structure
- [ ] Implement client.ex with appropriate pattern
- [ ] Implement transformer.ex with schema mapping
- [ ] Create sync_job.ex with MetricsTracker integration
- [ ] Add category mapping YAML
- [ ] Implement dedup_handler.ex if needed

**Quality Gates:**
- [ ] All jobs follow `{JobType}Job` naming convention
- [ ] External IDs follow `{source}_{type}_{id}_{date}` format
- [ ] MetricsTracker integration complete
- [ ] Error handling uses standard error categories
- [ ] Rate limiting implemented appropriately

**Automation Candidates:**
- Code generation from schema mapping
- Test case generation
- Configuration file generation

### Phase 4: Testing & Validation

**Objective:** Validate scraper accuracy and reliability.

**Test Categories:**
1. **Unit Tests:** Transformer functions, date parsing, field extraction
2. **Integration Tests:** Full job execution with sample data
3. **Quality Tests:** Schema compliance, data completeness
4. **Performance Tests:** Execution time, memory usage

**Validation Metrics:**
| Metric | Threshold |
|--------|-----------|
| Schema mapping accuracy | ≥95% |
| Field extraction success | ≥98% |
| Category classification | ≥85% |
| Geocoding success | ≥90% |
| Duplicate detection precision | ≥90% |

**Activities:**
- [ ] Write unit tests for transformer
- [ ] Create integration test with sample events
- [ ] Run validation against live data sample
- [ ] Document any data quality issues
- [ ] Create performance baseline

**Outputs:**
- Test suite
- Validation report
- Performance baseline
- Known issues documentation

**Automation Candidates:**
- Automated test generation
- Quality score calculation
- Baseline comparison

### Phase 5: Production Integration

**Objective:** Deploy scraper and establish monitoring.

**Activities:**
- [ ] Add to Oban job schedule
- [ ] Configure rate limits and retry policies
- [ ] Set up monitoring alerts
- [ ] Create initial baseline
- [ ] Document operational procedures

**Monitoring Requirements:**
- Job execution tracking via MetricsTracker
- Error rate monitoring
- Performance baseline tracking
- SLO compliance (95% success, P95 <3s)

**Outputs:**
- Production configuration
- Monitoring dashboard integration
- Operational runbook
- Initial baseline report

---

## 3. Test Case: kupbilecik.pl

### 3.1 Source Profile

| Attribute | Value |
|-----------|-------|
| **Name** | KupBilecik |
| **URL** | https://www.kupbilecik.pl |
| **Type** | Ticketing Platform |
| **Language** | Polish |
| **Geography** | Poland (primary), International (secondary) |
| **Event Types** | Concerts, Theater, Sports, Cultural Events |

### 3.2 Phase 0 Analysis Results

**Sitemap Structure:**
```
sitemap.xml (index)
├── sitemap_imprezy-1.xml through sitemap_imprezy-5.xml (events)
├── sitemap_wydarzenia.xml (events/happenings)
├── sitemap_miasta.xml (cities)
├── sitemap_obiekt.xml (venues)
├── sitemap_baza.xml (base content)
├── sitemap_komentarze.xml (comments)
├── sitemap_komunikaty.xml (announcements)
├── sitemap_nowosci.xml (news)
└── sitemap_szukaj.xml (search)
```

**URL Patterns Discovered:**

| Entity | Pattern | Example |
|--------|---------|---------|
| Events | `/imprezy/{ID}/{City}/{Name}/` | `/imprezy/40000/Świnoujście/Alicja+Majewska/` |
| Cities | `/miasta/{ID}/{CityName}/{Page}/` | `/miasta/2/Kraków/` |
| Venues | `/obiekty/{ID}/{VenueName}/` | `/obiekty/81/Spodek/` |

**Technology Stack:**
- jQuery 3.2.1
- Single Page Application (SPA) architecture
- New Relic monitoring
- Google Tag Manager
- Heavy client-side JavaScript rendering

**Bot Protection:** None observed (no Cloudflare, no CAPTCHA)

**Data Volume Estimates:**
- Events: 5 sitemap files × ~400 entries = ~2,000+ events
- Cities: 700+ locations (Poland + international)
- Venues: ~1,000+ venues

### 3.3 Phase 1 Analysis Results

**Access Pattern Classification:** HTML Scraping (Sitemap-based discovery)

**Rationale:**
- No documented public API
- Heavy JavaScript rendering suggests dynamic content
- Comprehensive sitemaps provide reliable URL discovery
- Event detail pages contain structured data in HTML

**Recommended Approach:**
1. **Primary:** Sitemap-based event discovery
   - Parse `sitemap_imprezy-*.xml` for event URLs
   - Fetch event detail pages
   - Extract data from HTML (may need JavaScript rendering)

2. **Alternative:** City-based listing pages
   - Scrape `/miasta/{ID}/{City}/` pages
   - Follow pagination
   - Extract event links

**JavaScript Rendering Assessment:**
- [ ] Test if event detail content loads without JavaScript
- [ ] If JS required: Implement Playwright-based extraction
- [ ] If server-rendered: Use HTTPoison + Floki

**Rate Limiting:**
- No explicit limits observed
- Recommend: 2-3 second delay between requests
- Implement exponential backoff on errors

### 3.4 Phase 2 Schema Mapping (Pending)

**Source Fields to Map:**
| Source Field | Canonical Field | Transformation |
|--------------|-----------------|----------------|
| Event ID (URL) | external_id | `kupbilecik_event_{id}_{date}` |
| Title | title | Direct |
| Date/Time | starts_at | Parse "YYYY-MM-DD, HH:MM" |
| City (URL) | venue.city | URL decode |
| Venue ID | venue reference | Link to venue entity |
| Description | description | HTML to text |
| Image | image_url | Construct from ID pattern |

**Category Mapping Required:**
- Source categories: To be discovered from event pages
- Target: Map to Eventasaurus taxonomy
- Language: Polish → English translation needed

### 3.5 Implementation Plan (Pending)

**Proposed File Structure:**
```
lib/eventasaurus_discovery/sources/kupbilecik/
├── client.ex              # Sitemap + page fetching
├── config.ex              # Rate limits, URLs
├── sitemap_parser.ex      # XML sitemap parsing
├── extractor.ex           # HTML data extraction
├── transformer.ex         # Schema mapping
└── jobs/
    ├── sync_job.ex        # Main orchestration
    ├── sitemap_job.ex     # Sitemap processing
    └── event_detail_job.ex # Detail page processing
```

**Job Flow:**
```
SyncJob (daily)
└── SitemapJob (parse sitemaps)
    └── EventDetailJob (per event URL)
        └── Transform & Persist
```

### 3.6 Progress Log

| Date | Phase | Activity | Status | Notes |
|------|-------|----------|--------|-------|
| 2025-01-XX | 0 | Initial sitemap analysis | Complete | 5 event sitemaps found |
| 2025-01-XX | 0 | URL pattern documentation | Complete | Events, cities, venues mapped |
| 2025-01-XX | 1 | Access pattern determination | Complete | HTML scraping recommended |
| 2025-01-XX | 1 | JavaScript rendering test | Pending | Need to verify |
| 2025-01-XX | 2 | Schema mapping | Pending | |
| 2025-01-XX | 3 | Implementation | Pending | |
| 2025-01-XX | 4 | Testing | Pending | |
| 2025-01-XX | 5 | Production | Pending | |

---

## 4. Automation Roadmap

### 4.1 Current State (Manual)

All phases currently require manual execution with human decision-making.

### 4.2 Near-Term Automation (Phase 0-1)

**Candidates for automation:**
- Sitemap discovery and parsing
- Technology stack detection
- URL pattern extraction
- API endpoint detection
- Network request analysis

**Implementation approach:**
- Build reusable analysis modules
- Create standardized output formats
- Human reviews results and makes decisions

### 4.3 Mid-Term Automation (Phase 2-3)

**Candidates for automation:**
- LLM-assisted field mapping
- Code generation from templates
- Test case generation
- Category mapping suggestions

**Implementation approach:**
- LLM integration for schema inference
- Template-based code generation
- Human reviews and adjusts generated code

### 4.4 Long-Term Automation (Full Pipeline)

**Vision:** Given a source URL, the system:
1. Automatically analyzes the source
2. Determines optimal access pattern
3. Maps schema fields
4. Generates scraper code
5. Runs validation tests
6. Requests human approval
7. Deploys to production

**Requirements:**
- Robust LLM integration
- Comprehensive test framework
- Quality scoring system
- Human-in-the-loop approval gates

---

## 5. Reference: Existing Source Implementations

### 5.1 Summary Table

| Source | Category | Auth | Pagination | Rate Limit | Bot Protection |
|--------|----------|------|------------|------------|----------------|
| Bandsintown | HTML + JS | No | API endpoint | 2-3s | Zyte proxy |
| Cinema City | REST API | No | Response struct | Configurable | No |
| Geeks Who Drink | WordPress AJAX | Nonce | No | 3s backoff | No |
| Inquizition | Hybrid (CDN) | No | Single response | 3s backoff | No |
| Karnet | HTML | No | No | 4s | No |
| Kino Kraków | HTML | No | No | Configurable | No |
| Pubquiz | HTML | No | No | Configurable | No |
| Question One | RSS Feed | No | URL param | 3s backoff | No |
| Quizmeisters | REST API | No | Single response | 3s backoff | No |
| Resident Advisor | GraphQL | No | Cursor (page) | Respect-based | No |
| Sortiraparis | HTML | No | Sitemap-based | 4-5s | Cloudflare |
| Speed Quizzing | HTML | No | No | 3s backoff | No |
| Ticketmaster | REST API | API Key | page/size | 5 req/s | No |
| Waw4Free | HTML | No | No | 2s | No |
| Week.pl | GraphQL | No | Cursor | Respect-based | No |

### 5.2 Pattern Examples

**For kupbilecik.pl (HTML Scraping + Sitemap), refer to:**
- Sortiraparis: Sitemap-based discovery, Cloudflare handling
- Karnet: Polish language, HTML scraping, rate limiting
- Waw4Free: Polish language, simple HTML structure

---

## Appendix A: Source Analysis Checklist

```markdown
## Source: [Name]
**URL:** [URL]
**Date Analyzed:** [Date]

### Phase 0: Discovery
- [ ] Homepage fetched and analyzed
- [ ] robots.txt checked
- [ ] sitemap.xml checked
- [ ] Technology stack identified
- [ ] URL patterns documented
- [ ] Bot protection assessed
- [ ] Data coverage estimated
- [ ] Language(s) identified

### Phase 1: Access Pattern
- [ ] Network requests analyzed
- [ ] API endpoints checked
- [ ] GraphQL endpoint checked
- [ ] JavaScript rendering tested
- [ ] RSS/Atom feeds checked
- [ ] Pagination identified
- [ ] Rate limits observed
- [ ] **Classification:** [REST API | GraphQL | HTML | RSS | WordPress | Hybrid]

### Phase 2: Schema Mapping
- [ ] Source fields documented
- [ ] Field mapping table created
- [ ] Transformations identified
- [ ] Enrichment requirements noted
- [ ] Category mapping drafted

### Phase 3: Implementation
- [ ] Directory structure created
- [ ] client.ex implemented
- [ ] transformer.ex implemented
- [ ] sync_job.ex implemented
- [ ] Additional jobs implemented
- [ ] Category mapping YAML created
- [ ] MetricsTracker integrated

### Phase 4: Testing
- [ ] Unit tests written
- [ ] Integration tests written
- [ ] Quality validation passed
- [ ] Performance baseline created

### Phase 5: Production
- [ ] Oban schedule configured
- [ ] Monitoring set up
- [ ] Documentation complete
- [ ] Initial baseline recorded
```

---

## Appendix B: External ID Format Reference

```
{source}_{type}_{source_id}_{date}
```

**Examples:**
- `kupbilecik_event_40000_2024-11-15`
- `cinema_city_showtime_abc123_2024-11-15`
- `ticketmaster_event_G5dIZ4kM7m1nW_2024-11-15`

**Rules:**
- All lowercase with underscores
- Dates use hyphens (YYYY-MM-DD)
- `{type}`: event, movie, showtime, activity, show, etc.
- Must be globally unique and stable across re-scrapes

---

*Document Version: 1.0*
*Last Updated: 2025-01-XX*
*Next Review: After kupbilecik.pl integration complete*
