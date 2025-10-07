# Bandsintown Scraper

International concert discovery platform focused on live music events.

## Overview

**Priority**: 80 (International trusted source)
**Type**: Web scraper with Playwright
**Coverage**: International
**Event Types**: Music, Concerts
**Update Frequency**: Daily

## Features

- ✅ City-based event discovery
- ✅ GPS coordinates via JSON-LD structured data
- ✅ Comprehensive artist/performer data
- ✅ Pagination API for complete coverage
- ✅ Automatic venue geocoding fallback
- ✅ Performer extraction and linking

## Architecture

### Components

```
sources/bandsintown/
├── source.ex              # Source configuration and metadata
├── config.ex              # Configuration and URL builders
├── client.ex              # HTTP client and Playwright browser automation
├── extractor.ex           # HTML parsing and event extraction
├── detail_extractor.ex    # JSON-LD extraction for detailed event data
├── date_parser.ex         # Timezone-aware date parsing
├── transformer.ex         # Data transformation to unified format
└── jobs/
    ├── sync_job.ex           # Main coordinator job
    ├── index_page_job.ex     # City page scraping
    └── event_detail_job.ex   # Event detail page scraping
```

### Data Flow

1. **SyncJob** - Coordinator that schedules city page jobs
2. **IndexPageJob** - Scrapes city pages for event listings (requires Playwright)
3. **EventDetailJob** - Scrapes individual event pages for full details
4. **Transformer** - Converts raw data to unified event format
5. **Processor** - Handles deduplication and database operations

## Configuration

### Environment Variables

No API key required - uses web scraping.

### Rate Limiting

- **Default**: 2000ms between requests
- **Recommended**: 2-3s for production stability
- **Configurable**: Via `Config.rate_limit()`

### Target Cities

Configure target cities in `config.ex`:

```elixir
def target_cities, do: ["krakow", "warsaw", "gdansk"]
```

## Usage

### Manual Sync

```elixir
# Sync all Bandsintown events for configured cities
alias EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob

{:ok, job} = SyncJob.new(%{}) |> Oban.insert()
```

### Scheduled Sync

Configured in `config/config.exs`:

```elixir
config :eventasaurus, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       # Daily at 3 AM
       {"0 3 * * *", EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob}
     ]}
  ]
```

### Testing

```bash
# Run transformer tests
mix test test/eventasaurus_discovery/sources/bandsintown/transformer_test.exs

# Test date parsing
mix test.date_parsing
```

## Data Format

### Input (from scraper)

```elixir
%{
  "url" => "https://www.bandsintown.com/e/104563789-artist-at-venue",
  "artist_name" => "Artist Name",
  "venue_name" => "Venue Name",
  "venue_city" => "Kraków",
  "venue_country" => "Poland",
  "venue_latitude" => 50.0614,
  "venue_longitude" => 19.9372,
  "date" => "2025-10-15T20:00:00",
  "description" => "Concert description",
  "external_id" => "bandsintown_104563789"
}
```

### Output (unified format)

```elixir
%{
  title: "Artist Name",
  external_id: "bandsintown_104563789",
  starts_at: ~U[2025-10-15 20:00:00Z],
  venue_data: %{
    name: "Venue Name",
    city: "Kraków",
    country: "Poland",
    latitude: 50.0614,
    longitude: 19.9372
  },
  performer: %{
    name: "Artist Name",
    genres: [],
    image_url: nil
  },
  ticket_url: "https://www.bandsintown.com/e/104563789-artist-at-venue",
  category: "music"
}
```

## External ID Format

`bandsintown_{event_id}`

**Example**: `bandsintown_104563789`

**Stability**: Extracted from event URL, guaranteed stable across runs.

## GPS Handling

### Primary: JSON-LD Extraction

Most events include GPS coordinates in structured data:

```json
{
  "@type": "MusicEvent",
  "location": {
    "geo": {
      "latitude": 50.0614,
      "longitude": 19.9372
    }
  }
}
```

### Fallback: City Center Coordinates

When venue has no GPS data:
- Uses city center coordinates as fallback
- Logs warning for manual review
- VenueProcessor can later geocode from address

### Placeholder Venues

When no venue data is available:
- Creates placeholder venue with artist name
- Marks with `metadata.placeholder: true`
- Uses default coordinates (US: New York)

## Error Handling

### Logging Levels

```elixir
# Info - Normal operations
Logger.info("✅ Found #{count} events in #{city}")

# Warning - Recoverable issues
Logger.warning("⚠️ Missing coordinates for venue: #{venue_name}")

# Error - Failed operations
Logger.error("❌ Failed to fetch city page: #{reason}")
```

### Common Errors

#### Missing Venue Data
```
⚠️ No venue data for Bandsintown event, creating placeholder:
Event: "Artist Name"
Artist: "Artist Name"
```
**Action**: Event is processed with placeholder venue

#### Missing GPS Coordinates
```
⚠️ Missing coordinates for Bandsintown venue, using city center:
Venue: Venue Name
City: Kraków
```
**Action**: Uses city center coordinates as fallback

#### Date Parsing Failure
```
❌ Failed to parse date: invalid-date-string
```
**Action**: Event is skipped

## Troubleshooting

### No Events Found

**Symptoms**: Sync completes but finds 0 events

**Causes**:
1. City slug incorrect
2. Playwright browser not installed
3. Website structure changed

**Solutions**:
```bash
# Verify city slug is correct
mix run -e "IO.inspect EventasaurusDiscovery.Sources.Bandsintown.Config.build_city_url('krakow')"

# Install Playwright browsers
mix run -e "EventasaurusApp.Playwright.install()"

# Test with debug logging
export LOG_LEVEL=debug
mix run -e "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob.perform(%Oban.Job{args: %{}})"
```

### Duplicate Events

**Symptoms**: Same event appears multiple times

**Causes**:
1. External ID not stable
2. Processor deduplication not working

**Solutions**:
```bash
# Check external_id stability
mix test test/eventasaurus_discovery/sources/bandsintown/transformer_test.exs

# Verify no duplicates in database
psql -c "SELECT external_id, COUNT(*) FROM public_events WHERE external_id LIKE 'bandsintown_%' GROUP BY external_id HAVING COUNT(*) > 1;"
```

### Rate Limiting

**Symptoms**: 429 Too Many Requests errors

**Solutions**:
```elixir
# Increase rate limit in config.ex
@rate_limit 3  # 3 seconds between requests
```

### Playwright Timeout

**Symptoms**: Browser timeout errors

**Solutions**:
```elixir
# Increase timeout in client.ex
timeout: 30_000  # 30 seconds
```

## Performance

### Metrics

- **Average scrape time**: 3-5 minutes for Kraków (~50 events)
- **Events per city**: 30-100 typical
- **Rate limit**: 2-3s between requests
- **Playwright overhead**: 2-4s per page load

### Optimization Tips

1. **Batch processing**: Use pagination efficiently
2. **Parallel cities**: Schedule multiple cities in parallel
3. **Caching**: Cache city pages for retry logic
4. **Smart scheduling**: Run during off-peak hours

## Dependencies

### Required

- Playwright (browser automation)
- Floki (HTML parsing)
- Jason (JSON parsing)
- Oban (job processing)

### Optional

- Timex (timezone handling)

## Maintenance

### Weekly Tasks

- [ ] Check error logs for parsing failures
- [ ] Verify no duplicate events in database
- [ ] Monitor scrape completion rates

### Monthly Tasks

- [ ] Review and update city list
- [ ] Check for website structure changes
- [ ] Analyze event coverage gaps

## Known Limitations

1. **Playwright Required**: Initial city pages require JavaScript rendering
2. **Rate Limiting**: Conservative 2-3s delays needed
3. **Venue Quality**: Some events have placeholder venues
4. **Image Quality**: Some events have low-quality images
5. **International Dates**: Timezone handling can be tricky for international events

## Future Improvements

- [ ] Add artist image fetching from MusicBrainz
- [ ] Implement genre extraction
- [ ] Add ticket price scraping
- [ ] Support for tour dates extraction
- [ ] Mobile app scraping for additional data

## Support

**Documentation**: See `docs/scrapers/SCRAPER_SPECIFICATION.md`
**Issues**: https://github.com/razrfly/eventasaurus/issues
**Tests**: `test/eventasaurus_discovery/sources/bandsintown/`
