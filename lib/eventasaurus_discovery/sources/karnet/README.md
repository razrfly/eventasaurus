# Karnet Kraków Scraper

## Overview

The Karnet scraper extracts cultural events from https://karnet.krakowculture.pl/, the official cultural events portal for Kraków, Poland.

**Priority**: Low (30) - Below Ticketmaster (10) and BandsInTown (20)  
**Scope**: Kraków only  
**Type**: HTML scraper (no API available)

## Features

- ✅ Polish language support with date parsing
- ✅ Venue matching for major Kraków locations
- ✅ Basic festival detection
- ✅ Deduplication against higher-priority sources
- ✅ Rate limiting (4 seconds between requests)

## Architecture

```
Karnet Website
      ↓
  [Client] (with gzip decompression)
      ↓
  [IndexExtractor] → [SyncJob]
      ↓
  [DetailExtractor] → [EventDetailJob]
      ↓
  [DateParser] (Polish dates)
      ↓
  [VenueMatcher] (Kraków venues)
      ↓
  [DedupHandler]
      ↓
  [Processor] → Database
```

## Usage

```elixir
# Start a sync
EventasaurusDiscovery.Sources.Karnet.sync()

# Sync with options
EventasaurusDiscovery.Sources.Karnet.sync(%{
  max_pages: 3,
  force: true  # Skip deduplication
})

# Check configuration
EventasaurusDiscovery.Sources.Karnet.config()

# Validate connectivity
EventasaurusDiscovery.Sources.Karnet.validate()
```

## Polish Date Formats

The scraper handles various Polish date formats:

- Standard: `"04.09.2025, 18:00"`
- Polish month names: `"4 września 2025"`
- Date ranges: `"04.09.2025 - 06.09.2025"`
- With day names: `"czwartek, 4 września 2025"`

## Known Venues

The scraper recognizes major Kraków venues:

- Tauron Arena Kraków
- ICE Kraków (Centrum Kongresowe)
- Teatr im. J. Słowackiego
- Nowohuckie Centrum Kultury
- Opera Krakowska
- Filharmonia Krakowska
- And more...

## Deduplication Strategy

Since Karnet is lower priority:

1. Events from Ticketmaster/BandsInTown take precedence
2. Fuzzy matching on title + date + venue
3. Karnet data used to enrich existing events
4. Only unique local events are imported

## Rate Limiting

- 4 seconds between requests (conservative)
- Max 10 pages per sync by default
- Respects server response times

## Testing

```bash
# Run integration tests
mix test --only karnet

# Run with external API calls
mix test --only external --only karnet
```

## Configuration

```elixir
# config/config.exs
config :eventasaurus_discovery, :karnet_enabled, true
config :eventasaurus_discovery, :karnet_max_pages, 10
config :eventasaurus_discovery, :karnet_rate_limit, 4  # seconds
```

## Limitations

- ⚠️ Kraków events only
- ⚠️ Limited performer information
- ⚠️ No API, relies on HTML structure
- ⚠️ Simplified festival handling (no sub-events)
- ⚠️ Lower priority than international sources

## Error Handling

- Gzip/deflate decompression for compressed responses
- Graceful handling of unparseable Polish dates
- Fallback to text extraction when structure changes
- Automatic retry with exponential backoff

## Monitoring

Key metrics to monitor:

- Events extracted per page (should be ~12)
- Date parsing success rate
- Venue matching rate
- Deduplication rate (expect high overlap with other sources)
- Response times and rate limit compliance
