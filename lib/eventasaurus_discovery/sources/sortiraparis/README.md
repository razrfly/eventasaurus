# Sortiraparis Event Scraper

Scraper for [Sortiraparis.com](https://www.sortiraparis.com/) - a comprehensive Paris cultural events portal.

**Status**: Phase 2 Complete (Foundation Setup) - Ready for Phase 3 (Sitemap & Discovery)

**Priority**: 65 (Regional reliable source)

**Coverage**: Paris, France

**Update Frequency**: Daily via sitemap

## Overview

Sortiraparis provides comprehensive coverage of cultural events in Paris, including concerts, exhibitions, theater performances, and shows. The site is available in 30+ languages; we use English for consistency.

### Source Configuration

- **Base URL**: `https://www.sortiraparis.com`
- **Discovery Method**: Sitemap-based (not pagination)
- **Rate Limiting**: 5 seconds between requests (conservative to avoid bot protection)
- **Timeout**: 10 seconds per request
- **Geocoding Strategy**: Multi-provider orchestrator (see [Geocoding System](../../../../docs/geocoding/GEOCODING_SYSTEM.md))

## Bot Protection Handling

Sortiraparis implements **inconsistent bot protection** that returns 401 errors on ~30% of pages even with proper headers.

### Current Mitigation (Phase 2)

✅ **Browser-like headers** (see `config.ex:headers/0`)
- User-Agent: Modern Chrome on macOS
- Accept-Language: English with French fallback
- Referer header set to base URL
- Upgrade-Insecure-Requests: Helps avoid bot detection

✅ **Conservative rate limiting** (5 seconds between requests)

✅ **Error handling** (401 detection and logging)

### Future Enhancement (Phase 3+)

⏳ **Playwright fallback** for persistent 401 errors
- Use MCP Playwright server for browser automation
- Render JavaScript-heavy pages
- Handle dynamic content loading
- Extract from rendered DOM

**Implementation**: See `client.ex:64-75` TODO comments

## Event Discovery

### Sitemap-Based Discovery

Uses XML sitemaps instead of pagination:

```elixir
Config.sitemap_urls()
# => [
#   "https://www.sortiraparis.com/sitemap-en-1.xml",
#   "https://www.sortiraparis.com/sitemap-en-2.xml",
#   "https://www.sortiraparis.com/sitemap-en-3.xml",
#   "https://www.sortiraparis.com/sitemap-en-4.xml"
# ]
```

### Event URL Classification

**90%+ accuracy** using URL pattern matching:

**Event Categories** (include):
- `concerts-music-festival` - Live music and festival events
- `exhibit-museum` - Art exhibitions and museum events
- `shows` - Performance shows and spectacles
- `theater` - Theater performances and plays

**Exclude Patterns** (non-event content):
- `guides` - Editorial guides and listicles
- `/news/` - News articles
- `where-to-eat` - Restaurant guides
- `what-to-do` - Activity guides
- `best-of` - Curated lists
- `top-` - Top lists

**Example Classification**:

```elixir
Config.is_event_url?("https://www.sortiraparis.com/concerts-music-festival/articles/319282-indochine-concert")
# => true (has event category, no exclude pattern)

Config.is_event_url?("https://www.sortiraparis.com/guides/best-restaurants-paris")
# => false (has exclude pattern)
```

## Multi-Date Event Handling

Events with multiple dates are split into **separate event instances**:

**Example**: "Indochine at Accor Arena" on February 25, 27, 28, 2026

**External IDs Generated**:
- `sortiraparis_319282_2026-02-25`
- `sortiraparis_319282_2026-02-27`
- `sortiraparis_319282_2026-02-28`

**Format**: `sortiraparis_{article_id}_{YYYY-MM-DD}`

**Why**: Each performance is a separate event occurrence with potentially different:
- Ticket availability
- Pricing
- Performers (special guests)
- Start times

**Implementation**: See `transformer.ex:196-246` (create_event function)

## Geocoding Integration

**CRITICAL**: Do NOT geocode manually. Provide full venue address and let `VenueProcessor` handle geocoding.

### Multi-Provider System

The system uses an **intelligent multi-provider orchestrator** with:

✅ **6 free providers**: Mapbox, HERE, Geoapify, LocationIQ, OpenStreetMap, Photon
✅ **Automatic failover**: Tries providers in priority order until one succeeds
✅ **Built-in rate limiting**: Respects provider quotas to stay within free tiers
✅ **Admin dashboard**: Configure provider priority at `/admin/geocoding`
✅ **Cost-effective**: Google Maps/Places APIs disabled by default

### Scraper Implementation

**Provide in venue_data**:

```elixir
venue_data: %{
  name: "Accor Arena",                          # REQUIRED
  address: "8 Boulevard de Bercy",              # RECOMMENDED (full address)
  city: "Paris",                                # REQUIRED
  country: "France",                            # RECOMMENDED (defaults to France)
  latitude: nil,                                # OPTIONAL (nil = will geocode)
  longitude: nil,                               # OPTIONAL (nil = will geocode)
  external_id: "sortiraparis_venue_12345"       # OPTIONAL (for deduplication)
}
```

**VenueProcessor will**:
1. Check if coordinates already provided → use them
2. Otherwise, call AddressGeocoder with full address
3. AddressGeocoder tries providers in priority order with failover
4. Store geocoding_metadata (provider, attempts, timestamp)
5. Handle rate limiting and retry logic automatically

**Documentation**: See [Geocoding System Guide](../../../../docs/geocoding/GEOCODING_SYSTEM.md)

## File Structure

```
lib/eventasaurus_discovery/sources/sortiraparis/
├── README.md                    # This file
├── source.ex                    # Source metadata & configuration
├── config.ex                    # Runtime configuration & helpers
├── client.ex                    # HTTP client with rate limiting & bot protection
├── transformer.ex               # Event data transformation (skeleton)
├── extractors/                  # HTML extraction modules
│   ├── event_extractor.ex      # Extract event details from HTML
│   └── venue_extractor.ex      # Extract venue information
├── helpers/                     # Helper modules
│   └── category_mapper.ex      # Map URL categories to unified format
└── jobs/                        # Oban job modules
    ├── sync_job.ex             # Sitemap discovery orchestrator (Phase 2 skeleton)
    └── event_detail_job.ex     # Event detail fetching (Phase 4)
```

## Phase Implementation Status

### ✅ Phase 1: POC & Research (Completed)

- POC document with findings: `docs/sortiraparis_poc_results.md`
- Test script: `priv/scripts/test_sortiraparis.exs`
- Bot protection analysis
- Event URL classification strategy
- Multi-date event handling approach

### ✅ Phase 2: Foundation Setup (Completed)

- ✅ Directory structure created
- ✅ `source.ex` - Source metadata with priority 65
- ✅ `config.ex` - Configuration with browser-like headers
- ✅ `client.ex` - HTTP client with bot protection handling
- ✅ `transformer.ex` - Skeleton with geocoding documentation
- ✅ `README.md` - This documentation file

### ⏳ Phase 3: Sitemap & Discovery (Next)

**Planned modules**:
- `extractors/sitemap_extractor.ex` - Parse sitemap XML
- `helpers/url_filter.ex` - Filter event URLs using `Config.is_event_url?/1`
- `helpers/category_mapper.ex` - Map URL segments to unified categories
- `jobs/sync_job.ex` - Complete sitemap orchestrator
  - Fetch sitemap URLs
  - Filter event URLs
  - Check EventFreshnessChecker (7-day window)
  - Enqueue EventDetailJob for fresh events

**Integration**: EventFreshnessChecker prevents re-processing events updated within 7 days

### ✅ Phase 4: Event Extraction (Completed)

**Implemented modules**:
- ✅ `extractors/event_extractor.ex` - Extract event data from HTML
- ✅ `extractors/venue_extractor.ex` - Extract venue information
- ✅ `transformer.ex` - Complete transformation logic with MultilingualDateParser integration
- ✅ `jobs/event_detail_job.ex` - Fetch and transform event details

**Date Parsing**:
Uses shared `MultilingualDateParser` (see `lib/eventasaurus_discovery/sources/shared/parsers/multilingual_date_parser.ex`) with language plugins:
- ✅ French plugin - Handles French date formats (primary)
- ✅ English plugin - Handles English date formats (fallback)
- ✅ Multi-language fallback - Tries French first, then English
- ✅ Unknown occurrence fallback - Creates events with `occurrence_type = "unknown"` for unparseable dates

**Supported Date Formats**:
1. **French**: "17 octobre 2025", "du 19 mars au 7 juillet 2025", "Le 1er janvier 2026"
2. **English**: "October 15, 2025", "October 15, 2025 to January 19, 2026"
3. **Multi-date**: Handled by date range extraction
4. **Unknown**: Fallback to unknown occurrence type with original date string stored

### ⏳ Phase 5: Integration & Testing (Planned)

**Test coverage**:
- End-to-end scraping tests
- Event deduplication verification
- Venue GPS deduplication (50m tight, 200m broad)
- Geocoding multi-provider validation
- Multi-date event instance creation
- Bot protection handling
- Rate limiting compliance
- Performance benchmarks

## Configuration

### Enable/Disable Source

```elixir
# config/config.exs
config :eventasaurus_discovery,
  sortiraparis_enabled: true  # Set to false to disable
```

### Access Configuration

```elixir
alias EventasaurusDiscovery.Sources.Sortiraparis.Source

Source.enabled?()           # => true/false
Source.priority()           # => 65
Source.config()             # => Full configuration map
Source.validate_config()    # => {:ok, message} or {:error, reason}
```

### Sync Job Arguments

```elixir
Source.sync_job_args()
# => %{
#   "source" => "sortiraparis",
#   "sitemap_urls" => [...],
#   "limit" => nil
# }

# Custom sitemap subset
Source.sync_job_args(sitemap_urls: ["https://www.sortiraparis.com/sitemap-en-1.xml"])

# Limit for testing
Source.sync_job_args(limit: 10)
```

## Usage Examples

### Fetch Sitemap

```elixir
alias EventasaurusDiscovery.Sources.Sortiraparis.Client

{:ok, urls} = Client.fetch_sitemap("https://www.sortiraparis.com/sitemap-en-1.xml")
# => {:ok, ["https://www.sortiraparis.com/articles/319282-indochine-concert", ...]}
```

### Fetch Event Page

```elixir
case Client.fetch_page("https://www.sortiraparis.com/articles/319282-indochine-concert") do
  {:ok, html} ->
    # Process HTML with extractors
    IO.puts("✅ Fetched #{byte_size(html)} bytes")

  {:error, :bot_protection} ->
    # 401 error - bot protection triggered
    IO.puts("⚠️  Bot protection - consider Playwright fallback")

  {:error, :not_found} ->
    # 404 error - page doesn't exist
    IO.puts("❌ Event page not found")
end
```

### Check Event URL

```elixir
alias EventasaurusDiscovery.Sources.Sortiraparis.Config

Config.is_event_url?("https://www.sortiraparis.com/concerts-music-festival/articles/319282-indochine")
# => true

Config.is_event_url?("https://www.sortiraparis.com/guides/best-restaurants")
# => false
```

### Extract Article ID

```elixir
Config.extract_article_id("/articles/319282-indochine-concert")
# => "319282"

Config.generate_external_id("319282")
# => "sortiraparis_319282"
```

## Testing

### Manual Testing

```bash
# Test sitemap fetching
iex -S mix
iex> alias EventasaurusDiscovery.Sources.Sortiraparis.Client
iex> Client.fetch_sitemap("https://www.sortiraparis.com/sitemap-en-1.xml")

# Test event page fetching (watch for 401 errors)
iex> Client.fetch_page("https://www.sortiraparis.com/articles/319282-indochine-concert")

# Test configuration validation
iex> alias EventasaurusDiscovery.Sources.Sortiraparis.Source
iex> Source.validate_config()
```

### Automated Testing (Phase 2 TODO)

```bash
# Run source-specific tests
mix test test/eventasaurus_discovery/sources/sortiraparis/

# Run all scraper tests
mix test test/eventasaurus_discovery/sources/
```

## Known Issues & Limitations

### Bot Protection (401 Errors)

**Issue**: ~30% of requests return 401 even with browser-like headers

**Current Mitigation**:
- Conservative 5-second rate limiting
- Browser-like User-Agent and headers
- Automatic retry with exponential backoff

**Future Solution**: Playwright fallback (Phase 3+)

### Multilingual Date Parsing

**Solution**: Shared `MultilingualDateParser` with language-specific plugins

**Architecture**:
- **Reusable**: Any scraper can use the same date parser
- **Language Plugins**: French and English plugins with extensible architecture
- **Fallback Chain**: French → English → Unknown occurrence fallback
- **Timezone Support**: Converts dates to UTC from specified timezone (default: Europe/Paris)

**Examples Handled**:
- French: "17 octobre 2025", "du 19 mars au 7 juillet 2025", "Le 1er janvier 2026"
- English: "October 15, 2025", "October 15, 2025 to January 19, 2026"
- Unknown: "TBA", "à définir", "sometime in spring 2025" (creates event with `occurrence_type = "unknown"`)

**Documentation**: See Phase 1-4 completion documents in project root

### Event vs Article Classification

**Accuracy**: ~90%+ with URL pattern matching

**Edge Cases**:
- Some event announcements in news section
- Festival overview pages vs. individual event pages
- Multi-event venue pages

**Refinement**: Continuous improvement during Phase 4 implementation

## Related Documentation

- **Geocoding System**: [docs/geocoding/GEOCODING_SYSTEM.md](../../../../docs/geocoding/GEOCODING_SYSTEM.md)
- **Scraper Specification**: [docs/scrapers/SCRAPER_SPECIFICATION.md](../../../../docs/scrapers/SCRAPER_SPECIFICATION.md)
- **POC Results**: [docs/sortiraparis_poc_results.md](../../../../docs/sortiraparis_poc_results.md)
- **GitHub Issue**: [#1814 - Sortiraparis Phased Implementation](https://github.com/yourusername/eventasaurus/issues/1814)

## Contact & Support

- **GitHub Issues**: Report bugs and request features
- **Implementation Questions**: See POC results and scraper specification
- **Geocoding Questions**: See geocoding system documentation
- **Testing**: See test files in `test/eventasaurus_discovery/sources/sortiraparis/`
