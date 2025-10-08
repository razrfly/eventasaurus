# Question One Scraper

Scrapes weekly trivia event data from [Question One](https://questionone.com).

## Overview

- **Type**: RSS feed + detail page scraper
- **Coverage**: UK, Ireland, and select international venues
- **Frequency**: Weekly recurring trivia events
- **Priority**: 35 (regional specialist source)
- **External ID Format**: `question_one_<venue_slug>_<day_of_week>`

## Data Sources

### 1. RSS Feed
- **URL**: `https://questionone.com/venues/feed/`
- **Pagination**: `?paged=N` parameter
- **Format**: XML/RSS
- **Contains**: List of all venue page URLs

### 2. Venue Detail Pages
- **Format**: HTML with icon-based field extraction
- **Contains**: Venue details, schedule, pricing, description, images
- **Unique Feature**: SVG icon-based extraction pattern

## Configuration

Set in `config/config.exs`:

```elixir
config :eventasaurus,
  question_one_enabled: true
```

## Running the Scraper

```bash
# Full sync (all pages)
mix discovery.sync --source question-one

# Limited run (testing)
mix discovery.sync --source question-one --limit 10
```

## Architecture

Follows unified scraper specification from `docs/scrapers/SCRAPER_SPECIFICATION.md`.

### Components

```
question_one/
├── source.ex              # Source configuration (priority 35)
├── config.ex              # Runtime settings (base_url, rate_limit)
├── client.ex              # HTTP client with rate limiting
├── transformer.ex         # Data transformation to unified format
├── extractors/
│   └── venue_extractor.ex # Icon-based HTML parsing
├── helpers/
│   └── date_parser.ex     # Time/day parsing utilities
├── jobs/
│   ├── sync_job.ex        # Main orchestration
│   ├── index_page_job.ex  # RSS feed parsing
│   └── venue_detail_job.ex # Detail page scraping
└── README.md              # This file
```

### Data Flow

```
RSS Feed → IndexPageJob → EventFreshnessChecker → VenueDetailJob → Transformer → Processor
```

1. **IndexPageJob**: Parses RSS feed pages (with pagination)
2. **EventFreshnessChecker**: Filters out fresh venues (avoids re-scraping)
3. **VenueDetailJob**: Scrapes individual venue pages
4. **VenueExtractor**: Parses HTML with icon-based extraction
5. **Transformer**: Converts to unified format
6. **Processor**: Handles geocoding and creates/updates events

## Key Features

### ✅ Icon-Based Extraction

Question One uses a unique HTML structure with SVG icons:

```html
<div class="text-with-icon">
  <svg><use href="#pin"></use></svg>
  <span class="text-with-icon__text">123 High St, London</span>
</div>
```

Supported icons:
- `pin` → Address
- `calendar` → Schedule/time
- `tag` → Fee/pricing
- `phone` → Phone number

### ✅ EventFreshnessChecker Integration

Prevents re-scraping venues updated within threshold window (default 7 days):

```elixir
# In IndexPageJob
venues_to_process = EventFreshnessChecker.filter_events_needing_processing(
  venues_with_ids,
  source_id
)
```

**Benefits**:
- 80-90% reduction in API calls for recurring events
- Lower database write load
- Faster scraper runs
- Prevents rate limiting

### ✅ VenueProcessor Geocoding

No manual Google Places API calls needed:

```elixir
venue_data: %{
  name: "The Red Lion",
  address: "123 High St, London, SW1A 1AA",
  latitude: nil,  # VenueProcessor geocodes automatically
  longitude: nil
}
```

### ✅ Weekly Recurring Events

Each venue represents a weekly trivia night:

```elixir
%{
  title: "Trivia Night at The Red Lion",
  metadata: %{
    day_of_week: "wednesday",
    recurring: true,
    frequency: "weekly"
  }
}
```

## Data Quality

### Required Fields
- ✅ Title (cleaned from RSS)
- ✅ Address (from icon: `pin`)
- ✅ Time text (from icon: `calendar`)

### Optional Fields
- ⚠️ Fee text (from icon: `tag`)
- ⚠️ Phone (from icon: `phone`)
- ⚠️ Website (from "Visit Website" link)
- ⚠️ Description (from post content area)
- ⚠️ Hero image (from WordPress uploads)

### GPS Coordinates
- ❌ Not provided by source
- ✅ Geocoded automatically by VenueProcessor

## Testing

```bash
# Unit tests
mix test test/eventasaurus_discovery/sources/question_one/

# Specific test file
mix test test/eventasaurus_discovery/sources/question_one/transformer_test.exs
```

## Idempotency

Designed to run daily without creating duplicates:

1. **Stable External IDs**: `question_one_<venue_slug>_<day_of_week>`
2. **EventFreshnessChecker**: Skips recently updated venues
3. **EventProcessor**: Updates `last_seen_at` timestamps
4. **VenueProcessor**: Matches venues by GPS/name

## Performance Metrics

- **Rate Limit**: 2 seconds between requests
- **Timeout**: 30 seconds per request
- **Max Retries**: 2 attempts
- **Queue**: `:scraper_detail` (priority 2)

## Troubleshooting

### No venues found
- Check if site is accessible: `curl https://questionone.com/venues/feed/`
- Verify RSS feed structure hasn't changed
- Check logs for parsing errors

### Geocoding failures
- Verify Google Places API key is configured
- Check API quota limits
- Review address format from source

### Missing fields
- Icon-based extraction relies on SVG `use[href]` attributes
- If HTML structure changes, update `VenueExtractor`
- Verify icon names: pin, calendar, tag, phone

## Related Documentation

- [Scraper Specification](../../../../docs/scrapers/SCRAPER_SPECIFICATION.md)
- [Quick Reference](../../../../docs/scrapers/SCRAPER_QUICK_REFERENCE.md)
- [Issue #1572](https://github.com/razrfly/eventasaurus/issues/1572)
- [Parent Issue #1513](https://github.com/razrfly/eventasaurus/issues/1513)
