# Waw4Free Warsaw Free Events Scraper

**Status**: ✅ Production-Ready (Grade: B+ 87/100)
**Priority**: 35 (local/regional source)
**Coverage**: Warsaw (Warszawa), Poland
**Language**: Polish
**All Events**: FREE

## Overview

Waw4Free (https://waw4free.pl/) is a comprehensive free events website for Warsaw, Poland. It features concerts, workshops, exhibitions, theater, sports, and family events - all completely FREE.

**Audit Status**: Comprehensive audit completed 2025-10-29. All critical functionality works correctly. See [Audit Report](https://github.com/razrfly/eventasaurus/issues/2049) for details.

## Phase 1: Project Setup (COMPLETE)

✅ Directory structure created
✅ source.ex configuration implemented
✅ config.ex with rate limiting implemented
✅ Placeholder job files created (SyncJob, EventDetailJob)
✅ Source registered in system
✅ Basic validation implemented

## Technical Details

### URL Structure
- **Homepage**: `https://waw4free.pl/`
- **Category Listing**: `/warszawa-darmowe-{category}` (e.g., `/warszawa-darmowe-koncerty`)
- **Event Detail**: `/wydarzenie-{id}-{slug}` (e.g., `/wydarzenie-144172-black-maze-4-labirynt-strachu`)

### Categories (Polish)
1. `koncerty` - concerts
2. `warsztaty` - workshops
3. `wystawy` - exhibitions
4. `teatr` - theater
5. `sport` - sports
6. `dla-dzieci` - for children
7. `festiwale` - festivals
8. `inne` - other

### External ID Format
`waw4free_{event_id}` - extracted from event URL

### Data Fields Available
- Title
- Date (Polish format: "poniedziałek, 3 listopada 2025")
- Time (24-hour format: "15:00")
- Venue name and address
- District (Warsaw neighborhoods)
- Full description (HTML)
- Event image
- Source URL (organizer website)
- Category tags
- Voluntary donation indicator

## Configuration

```elixir
# Enable/disable scraper
config :eventasaurus_discovery, waw4free_enabled: true

# Rate limiting
config :eventasaurus_discovery, waw4free_rate_limit: 2  # seconds

# Max category pages (default: 1, no pagination needed)
config :eventasaurus_discovery, waw4free_max_pages: 1
```

## Usage

```elixir
# Start sync job
{:ok, job} = EventasaurusDiscovery.Sources.Waw4free.sync()

# Check configuration
EventasaurusDiscovery.Sources.Waw4free.validate()

# Check if enabled
EventasaurusDiscovery.Sources.Waw4free.enabled?()
```

## Next Steps

### Phase 2: Polish Language Support (TODO)
- [ ] Create Polish date parser plugin
- [ ] Create Polish category mapping YAML
- [ ] Integrate with MultilingualDateParser
- [ ] Write tests for Polish language support

### Phase 3: Core Scraping Implementation (TODO)
- [ ] Implement SyncJob category listing scraper
- [ ] Implement EventDetailJob event detail scraper
- [ ] Create HTML parser utilities
- [ ] Implement rate limiting
- [ ] Write scraping tests

### Phase 4: Data Transformation (TODO)
- [ ] Implement Transformer module
- [ ] Integrate EventFreshnessChecker
- [ ] Integrate VenueProcessor (geocoding)
- [ ] Integrate EventProcessor (deduplication)
- [ ] Write integration tests

### Phase 5: Testing & QA (TODO)
- [ ] Unit tests for all modules
- [ ] Integration tests for full pipeline
- [ ] Idempotency tests
- [ ] Manual testing in development

### Phase 6: Documentation & Deployment (TODO)
- [ ] Complete this README with implementation details
- [ ] Add to main scraper documentation
- [ ] Deploy to staging
- [ ] Deploy to production
- [ ] Monitor initial runs

## Known Limitations

- Warsaw-only events
- No performer information available
- No ticket information (all events are free)
- Some events note voluntary donations: "(dobrowolna zrzutka)"
- Polish language only (no English version)

## Maintenance Notes

- **Rate Limit**: 2 seconds between requests (conservative)
- **Timeout**: 30 seconds per request
- **Retry Attempts**: 2
- **Priority**: 35 (below international sources, similar to Karnet)
- **No Pagination**: Category listings appear to be single-page

## References

- **Website**: https://waw4free.pl/
- **Reference Implementation**: Karnet (Polish source for Kraków)
- **Issue**: https://github.com/razrfly/eventasaurus/issues/2044
