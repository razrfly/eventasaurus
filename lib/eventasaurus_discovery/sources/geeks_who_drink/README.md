# Geeks Who Drink Scraper

Scrapes weekly trivia event data from [Geeks Who Drink](https://www.geekswhodrink.com).

## Overview

- **Type**: WordPress AJAX API + detail page scraper
- **Coverage**: United States and Canada (700+ venues)
- **Frequency**: Weekly recurring trivia events
- **Priority**: 35 (regional specialist source)
- **External ID Format**: `geeks_who_drink_<venue_id>`

## Data Sources

### 1. WordPress Map API
- **Endpoint**: `/wp-admin/admin-ajax.php`
- **Action**: `mb_display_quizzes`
- **Authentication**: WordPress nonce (extracted from venues page)
- **Format**: HTML blocks (one per venue)
- **Contains**: GPS coordinates, venue info, schedule
- **Coverage**: US bounds (lat/long filters)

### 2. Venue Detail Pages
- **URL Format**: `https://www.geekswhodrink.com/venues/{venue_id}/`
- **Format**: HTML with additional venue details
- **Contains**: Website, phone, description, fee, social media links

### 3. Performer API
- **Endpoint**: `/wp-admin/admin-ajax.php`
- **Action**: `mb_display_venue_events`
- **Format**: HTML with quizmaster information
- **Contains**: Performer name, profile image

## Configuration

Set in `config/config.exs`:

```elixir
config :eventasaurus,
  geeks_who_drink_enabled: true
```

## Running the Scraper

```bash
# Full sync (all venues)
mix discovery.sync --source geeks-who-drink

# Limited run (testing)
mix discovery.sync --source geeks-who-drink --limit 3
```

## Architecture

Follows unified scraper specification from `docs/scrapers/SCRAPER_SPECIFICATION.md`.

### Components

```
geeks_who_drink/
├── source.ex                    # Source configuration (priority 35)
├── config.ex                    # Runtime settings (US bounds, rate limits)
├── client.ex                    # HTTP client with exponential backoff retry
├── transformer.ex               # Data transformation to unified format
├── extractors/
│   ├── nonce_extractor.ex      # WordPress nonce extraction
│   ├── venue_extractor.ex      # Map API HTML block parsing
│   └── venue_details_extractor.ex  # Detail page + performer API
├── helpers/
│   └── time_parser.ex          # Day/time parsing with timezone support
├── jobs/
│   ├── sync_job.ex             # Main orchestration + nonce fetching
│   ├── index_job.ex            # Map API querying
│   └── venue_detail_job.ex     # Detail scraping + performer linking
└── README.md                    # This file
```

### Data Flow

```
Nonce Extraction → Map API → EventFreshnessChecker → VenueDetailJob → Performer API → Transformer → Processor
```

1. **SyncJob**: Fetches WordPress nonce from venues page
2. **IndexJob**: Queries map API with US bounds and nonce
3. **EventFreshnessChecker**: Filters out fresh venues (avoids re-scraping)
4. **VenueDetailJob**: Scrapes individual venue pages
5. **VenueDetailsExtractor**: Fetches additional details and performer data
6. **TimeParser**: Parses schedule text (e.g., "Tuesdays at 7:00 pm")
7. **Transformer**: Converts to unified format
8. **Processor**: Creates/updates events and links performers

## Key Features

### ✅ GPS Coordinates Provided

Geeks Who Drink provides GPS coordinates directly in the map API response:

```html
<a data-lat="40.7128" data-lon="-74.0060">Venue Name</a>
```

**Benefits**:
- No Google Places API calls needed for coordinates
- Faster processing (no geocoding delays)
- Lower API costs
- More accurate venue matching

### ✅ WordPress Nonce Authentication

Map API requires WordPress nonce for authentication:

```javascript
gwdNonce: "abc123def456..."
```

**Implementation**:
- Extracted via regex from venues page
- Valid for the session
- Passed with all AJAX requests

### ✅ Performer Support

First trivia scraper with quizmaster/performer tracking:

```elixir
performer_data: %{
  name: "John Smith",
  profile_image: "https://..."
}
```

**Features**:
- Fuzzy name matching (Jaro distance ≥0.85)
- Image URL storage
- Linked via `PublicEventPerformer` join table
- Default fallback: "Geeks Who Drink Quizmaster"

### ✅ EventFreshnessChecker Integration

Prevents re-scraping venues updated within threshold window (default 7 days):

```elixir
# In IndexJob
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

### ✅ Exponential Backoff Retry

HTTP client implements robust retry logic:

```elixir
# Retry delays: 500ms → 1000ms → 2000ms
backoff_ms = 500 * 2^retries
```

**Configuration**:
- Max retries: 3 attempts
- Initial delay: 500ms
- Exponential multiplier: 2x

### ✅ Weekly Recurring Events

Each venue represents a weekly trivia night:

```elixir
%{
  title: "Geeks Who Drink Trivia at The Library Bar",
  metadata: %{
    day_of_week: "tuesday",
    recurring: true,
    frequency: "weekly",
    venue_id: "12345"
  }
}
```

## Data Quality

### Required Fields
- ✅ Venue ID (from `id="quizBlock-{id}"`)
- ✅ Title (from `<h2>` element)
- ✅ Address (from `data-address` attribute)
- ✅ GPS coordinates (from `data-lat`/`data-lon` attributes)
- ✅ Time text (from `<time>` element)

### Optional Fields
- ⚠️ Brand (from `.quizBlock__brand` element)
- ⚠️ Logo URL (from `.quizBlock__logo img[src]`)
- ⚠️ Website (from venue detail page)
- ⚠️ Phone (from venue detail page)
- ⚠️ Description (from venue detail page)
- ⚠️ Fee text (from venue detail page)
- ⚠️ Social media (Facebook, Instagram from venue detail page)
- ⚠️ Performer (name and image from AJAX API)

### GPS Coordinates
- ✅ Provided directly by source
- ✅ Float values in `data-lat` and `data-lon` attributes
- ✅ No geocoding needed

### Performer Data
- ⚠️ Name extracted from `.quiz__master p` element
- ⚠️ Profile image from `.quiz__avatar img[src]`
- ✅ Default fallback provided if missing
- ✅ 200 character name limit with truncation

## API Endpoints

### 1. Nonce Extraction
```
GET https://www.geekswhodrink.com/venues/
→ Extract: gwdNonce: "abc123..."
```

### 2. Map API (Venue List)
```
POST https://www.geekswhodrink.com/wp-admin/admin-ajax.php
Content-Type: application/x-www-form-urlencoded

action=mb_display_quizzes
&nonce={nonce}
&northLat=71.35817123219137
&southLat=-2.63233642366575
&westLong=-174.787181
&eastLong=-32.75593100000001
&week=*
&city=*
&team=*

→ Returns: HTML blocks with venue data
```

### 3. Venue Detail Page
```
GET https://www.geekswhodrink.com/venues/{venue_id}/
→ Returns: HTML with additional details
```

### 4. Performer API
```
POST https://www.geekswhodrink.com/wp-admin/admin-ajax.php
Content-Type: application/x-www-form-urlencoded

action=mb_display_venue_events
&pag=1
&venue={venue_id}
&team=*

→ Returns: HTML with quizmaster info
```

## Testing

```bash
# Unit tests
mix test test/eventasaurus_discovery/sources/geeks_who_drink/

# Specific test file
mix test test/eventasaurus_discovery/sources/geeks_who_drink/transformer_test.exs

# End-to-end test (limited venues)
mix discovery.sync --source geeks-who-drink --limit 3
```

## External ID Pattern

**Format:** `geeks_who_drink_{venue_id}`

**Example:** `geeks_who_drink_12345`

### Why Venue-Based?

For pattern-based recurring events, the **venue IS the unique identifier**.

- Day of week, time, and scheduling are **metadata** (describe WHEN event happens)
- Venue location is **identity** (describes WHICH event it is)
- Venue ID from source API creates globally unique identifier

### Implementation

**Generation:** Transformer (line 63)
```elixir
def transform_event(venue_data, _options \\ %{}) do
  # Generate stable external_id from venue_id
  external_id = "geeks_who_drink_#{venue_data.venue_id}"

  %{
    external_id: external_id,
    # ...
  }
end
```

**Flow:**
1. SyncJob extracts WordPress nonce from venues page
2. IndexJob queries map API with US bounds and nonce
3. VenueExtractor parses venue blocks from HTML response
4. Generates external_ids for each venue
5. EventFreshnessChecker filters out fresh venues (>70% skip rate)
6. VenueDetailJob scrapes stale venue detail pages only
7. Transformer regenerates same external_id from venue_id
8. EventProcessor creates/updates recurring event with deduplication

### How It Works with EventFreshnessChecker

1. **Direct external_id match:** Skip if external_id seen within threshold (168h default)
2. **Existing event_id match:** Skip if external_id belongs to recently-updated recurring event
3. **Predicted event_id match:** Uses title+venue similarity for new events

**Efficiency:** First scrape processes all venues, subsequent scrapes skip ~70-90% (already fresh)

### Edge Cases

**Q: What if a venue has multiple different events?**

A: EventProcessor's title-based matching handles this:
- Regular quiz: "Geeks Who Drink Trivia at The Library Bar"
- Special event: "Halloween Trivia at The Library Bar"
- Different titles → processed separately ✅

**Q: What if titles are very similar?**

A: Intentional consolidation (Jaro distance > 0.85):
- "Geeks Who Drink Trivia at The Library Bar"
- "Trivia Night at The Library Bar"
- Similar titles → merged as recurring event ✅

This is desired behavior for recurring event detection.

### Related Documentation

- EventFreshnessChecker: `lib/eventasaurus_discovery/services/event_freshness_checker.ex`
- EventProcessor recurring logic: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:1132-1391`
- Pattern standardization: See issue #1944

## Idempotency

Designed to run daily without creating duplicates:

1. **Stable External IDs**: `geeks_who_drink_{venue_id}` (venue-based)
2. **EventFreshnessChecker**: Skips recently updated venues
3. **EventProcessor**: Updates `last_seen_at` timestamps
4. **VenueProcessor**: Matches venues by GPS coordinates (50m/200m radius)
5. **PerformerStore**: Fuzzy matches performers (Jaro distance ≥0.85)

## Performance Metrics

- **Rate Limit**: 2 seconds between requests
- **Timeout**: 30 seconds per request
- **Max Retries**: 3 attempts with exponential backoff
- **Queue**: `:scraper_detail` (priority 2)
- **Stagger**: 3 seconds between detail job schedules

## Troubleshooting

### Nonce extraction fails
- Check if site structure changed: `curl https://www.geekswhodrink.com/venues/`
- Verify regex pattern matches: `gwdNonce["']?\s*:\s*["']([^"']+)["']`
- Check for JavaScript obfuscation or changes

### Map API returns empty response
- Verify nonce is valid and correctly extracted
- Check US bounds are correct in `config.ex`
- Verify AJAX endpoint hasn't changed
- Check for rate limiting (429 status)

### No performer data
- Performer API is optional and may return empty for some venues
- Default fallback "Geeks Who Drink Quizmaster" is used
- Check `.quiz__master` and `.quiz__avatar` selectors if structure changed

### GPS coordinates missing
- GPS coordinates are required fields from map API
- If missing, venue block parsing will fail with `:missing_required_field`
- Check `data-lat` and `data-lon` attributes in HTML response

### Time parsing errors
- TimeParser supports formats: "Tuesdays at 7:00 pm", "7pm", "19:00"
- Default fallback: Monday 7pm if parsing fails
- Check `time_text` field in map API response

### Performer linking fails
- Verify `PublicEventPerformer` table exists
- Check performer was created successfully via `PerformerStore`
- Review logs for database constraint errors

## Related Documentation

- [Scraper Specification](../../../../docs/scrapers/SCRAPER_SPECIFICATION.md)
- [Quick Reference](../../../../docs/scrapers/SCRAPER_QUICK_REFERENCE.md)
- [Issue #1616](https://github.com/razrfly/eventasaurus/issues/1616)
- [Parent Issue #1513](https://github.com/razrfly/eventasaurus/issues/1513)
