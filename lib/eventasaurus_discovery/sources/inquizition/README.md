# Inquizition Scraper

Weekly trivia night discovery platform for the United Kingdom.

## Overview

**Priority**: 50 (Recurring events)
**Type**: CDN API scraper
**Coverage**: United Kingdom
**Event Types**: Trivia, Quiz Nights
**Update Frequency**: Weekly

## Features

- ✅ CDN-based event fetching (StoreLocatorWidgets)
- ✅ GPS coordinates provided directly (no geocoding needed)
- ✅ Recurring event support
- ✅ Automatic next occurrence calculation
- ✅ Recurrence rule generation
- ✅ Single-stage architecture (no detail page scraping)

## Configuration

No API key required.

**Rate Limit**: 2s between requests
**Timezone**: Europe/London

## Recurrence Format

```json
{
  "frequency": "weekly",
  "days_of_week": ["monday"],
  "time": "18:30",
  "timezone": "Europe/London"
}
```

## External ID Pattern

**Format:** `inquizition_{venue_id}`

**Example:** `inquizition_12345`

### Why Venue-Based?

For pattern-based recurring events, the **venue IS the unique identifier**.

- Day of week, time, and scheduling are **metadata** (describe WHEN event happens)
- Venue location is **identity** (describes WHICH event it is)
- Venue ID from source API creates globally unique identifier

### Implementation

**Generation:** Transformer (line 70-82)
```elixir
def transform_event(venue_data, _options \\ %{}) do
  # Generate external_id with date for recurring events
  # Format: inquizition_{venue_id}_{YYYY-MM-DD}
  # This ensures each weekly occurrence is unique and passes EventFreshnessChecker
  external_id =
    case starts_at do
      %DateTime{} = dt ->
        date_str = dt |> DateTime.to_date() |> Date.to_iso8601()
        "inquizition_#{venue_data.venue_id}_#{date_str}"
      _ ->
        "inquizition_#{venue_data.venue_id}"
    end

  %{
    external_id: external_id,
    # ...
  }
end
```

**Flow:**
1. SyncJob fetches all venues from StoreLocatorWidgets CDN
2. IndexJob extracts venue data from CDN response
3. Transformer generates external_id from venue_id
4. EventFreshnessChecker filters out fresh events (>70% skip rate)
5. Processor creates/updates recurring events with deduplication

### How It Works with EventFreshnessChecker

1. **Direct external_id match:** Skip if external_id seen within threshold (168h default)
2. **Existing event_id match:** Skip if external_id belongs to recently-updated recurring event
3. **Predicted event_id match:** Uses title+venue similarity for new events

**Efficiency:** First scrape processes all events, subsequent scrapes skip ~70-90% (already fresh)

### Single-Stage Architecture

**IndexJob Integration:** (line 125-136)
```elixir
defp filter_fresh_events(events, source_id, limit) do
  # Filter out events that were recently updated (default: 7 days)
  events_to_process = EventFreshnessChecker.filter_events_needing_processing(events, source_id)

  # Apply limit if provided (for testing)
  if limit do
    Enum.take(events_to_process, limit)
  else
    events_to_process
  end
end
```

**Key Points:**
- All data available in single CDN response
- No detail page scraping needed
- Events saved directly in IndexJob
- EventFreshnessChecker provides 80-90% API call reduction

### Edge Cases

**Q: What if a venue has multiple different events?**

A: EventProcessor's title-based matching handles this:
- Regular quiz: "Inquizition Trivia at The Crown"
- Special event: "Halloween Trivia at The Crown"
- Different titles → processed separately ✅

**Q: What if titles are very similar?**

A: Intentional consolidation (Jaro distance > 0.85):
- "Inquizition Trivia at The Crown"
- "Trivia Night at The Crown"
- Similar titles → merged as recurring event ✅

This is desired behavior for recurring event detection.

### Related Documentation

- EventFreshnessChecker: `lib/eventasaurus_discovery/services/event_freshness_checker.ex`
- EventProcessor recurring logic: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:1132-1391`
- Pattern standardization: See issue #1944

## Data Sources

### StoreLocatorWidgets CDN
- **URL**: `https://cdn.storelocatorwidgets.com/api/users/{user_id}/locations`
- **Format**: JSON with stores array
- **Contains**: GPS coordinates, venue info, schedule, day filters
- **Coverage**: All UK Inquizition venues in single response

## Data Flow

1. **SyncJob** fetches stores from CDN API
2. **IndexJob** receives stores array
3. **VenueExtractor** parses venue data from each store
4. **Transformer** generates external_ids and converts to unified format
5. **EventFreshnessChecker** filters out fresh events (>70% skip rate)
6. **Processor** creates/updates recurring events with deduplication

## Key Features

### ✅ GPS Coordinates Provided

Inquizition provides GPS coordinates directly in the CDN response:

```json
{
  "lat": "51.5074",
  "lng": "-0.1278"
}
```

**Benefits**:
- No Google Places API calls needed for coordinates
- Faster processing (no geocoding delays)
- Lower API costs
- More accurate venue matching

### ✅ EventFreshnessChecker Integration

Prevents re-scraping venues updated within threshold window (default 7 days):

```elixir
# In IndexJob
events_to_process = EventFreshnessChecker.filter_events_needing_processing(events, source_id)
```

**Benefits**:
- 80-90% reduction in API calls for recurring events
- Lower database write load
- Faster scraper runs
- No rate limiting concerns

### ✅ Weekly Recurring Events

Each venue represents a weekly trivia night:

```elixir
%{
  title: "Inquizition Trivia at The Crown",
  metadata: %{
    day_of_week: "tuesday",
    recurring: true,
    frequency: "weekly",
    venue_id: "12345"
  }
}
```

### ✅ Offline City Resolution

Uses CityResolver for reliable city name extraction:

```elixir
# Resolve city and country using offline geocoding
{city, country} = resolve_location(latitude, longitude, address)
```

**Benefits**:
- No external geocoding API calls
- Fast city resolution from coordinates
- Falls back to conservative address parsing

## Data Quality

### Required Fields
- ✅ Venue ID (from CDN `id` field)
- ✅ Name (from CDN `name` field)
- ✅ Address (from CDN `address` field)
- ✅ GPS coordinates (from CDN `lat`/`lng` fields)
- ✅ Day filters (from CDN `day_filters` array)
- ✅ Schedule text (from CDN `schedule_text` field)

### Optional Fields
- ⚠️ Phone (from CDN `phone` field)
- ⚠️ Website (from CDN `website` field)
- ⚠️ Email (from CDN `email` field)

### GPS Coordinates
- ✅ Provided directly by source
- ✅ Float values in CDN response
- ✅ No geocoding needed

### Pricing
- ✅ Standard £2.50 entry fee for all events
- ✅ All events are ticketed

## Running the Scraper

```bash
# Full sync (all venues)
mix discovery.sync --source inquizition

# Limited run (testing)
mix discovery.sync --source inquizition --limit 10
```

## Architecture

Follows unified scraper specification from `docs/scrapers/SCRAPER_SPECIFICATION.md`.

### Components

```
inquizition/
├── source.ex              # Source configuration (priority 50)
├── config.ex              # Runtime settings (CDN URL, user_id)
├── client.ex              # HTTP client with rate limiting
├── transformer.ex         # Data transformation to unified format
├── extractors/
│   └── venue_extractor.ex # CDN response parsing
├── helpers/
│   └── schedule_helper.ex # Day/time parsing utilities
├── jobs/
│   ├── sync_job.ex        # Main orchestration + CDN fetching
│   └── index_job.ex       # Venue processing and event creation
└── README.md              # This file
```

## Testing

```bash
# Unit tests
mix test test/eventasaurus_discovery/sources/inquizition/

# Specific test file
mix test test/eventasaurus_discovery/sources/inquizition/transformer_test.exs

# End-to-end test (limited venues)
mix discovery.sync --source inquizition --limit 10
```

## Idempotency

Designed to run daily without creating duplicates:

1. **Stable External IDs**: `inquizition_{venue_id}` (venue-based)
2. **EventFreshnessChecker**: Skips recently updated venues
3. **EventProcessor**: Updates `last_seen_at` timestamps
4. **VenueProcessor**: Matches venues by GPS coordinates (50m/200m radius)

## Performance Metrics

- **Rate Limit**: 2 seconds between requests
- **Timeout**: 30 seconds per request
- **Max Retries**: 3 attempts
- **Queue**: `:scraper_index` (priority 1)

## Troubleshooting

### No venues found
- Check if CDN is accessible: `curl https://cdn.storelocatorwidgets.com/api/users/{user_id}/locations`
- Verify CDN response structure hasn't changed
- Check logs for parsing errors

### Missing schedule information
- Schedule parsing requires day_filters OR schedule_text
- Day information is REQUIRED (cannot create event without day of week)
- Time defaults to 8:00 PM if missing (logs warning)
- Check `schedule_inferred: true` in metadata for fallback cases

### GPS coordinates missing
- GPS coordinates are required fields from CDN
- If missing, venue extraction will fail
- Check `lat` and `lng` fields in CDN response

### City resolution failures
- CityResolver uses offline geocoding for speed
- Falls back to conservative address parsing
- Will set city to `nil` if parsing fails (logged as warning)

## Related Documentation

- [Scraper Specification](../../../../docs/scrapers/SCRAPER_SPECIFICATION.md)
- [Quick Reference](../../../../docs/scrapers/SCRAPER_QUICK_REFERENCE.md)
- [Issue #1944](https://github.com/razrfly/eventasaurus/issues/1944)

## Support

**Tests**: `test/eventasaurus_discovery/sources/inquizition/`
**Docs**: See SCRAPER_SPECIFICATION.md
