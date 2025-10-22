# Speed Quizzing Scraper

Weekly trivia night discovery platform for UK and international locations.

## Overview

**Priority**: 50 (Recurring events)
**Type**: API scraper
**Coverage**: UK (primary), International
**Event Types**: Trivia, Quiz Nights
**Update Frequency**: Weekly

## Features

- ✅ API-based event fetching
- ✅ Recurring event support
- ✅ Venue extraction with geocoding
- ✅ Automatic next occurrence calculation
- ✅ Recurrence rule generation

## Configuration

No API key required.

**Rate Limit**: 2s between requests
**Timezone**: Europe/London (default)

## Recurrence Format

```json
{
  "frequency": "weekly",
  "days_of_week": ["monday"],
  "time": "19:00",
  "timezone": "Europe/London"
}
```

## External ID Pattern

**Format:** `speed-quizzing-{event_id}`

**Example:** `speed-quizzing-12345`

### Why Venue-Based?

For pattern-based recurring events, the **venue IS the unique identifier**.

- Day of week, time, and scheduling are **metadata** (describe WHEN event happens)
- Venue location is **identity** (describes WHICH event it is)
- Event ID from source API creates globally unique identifier

### Implementation

**Generation:** Transformer (line 58)
```elixir
def transform_event(venue_data, _options \\ %{}) do
  # Generate stable external_id from event_id
  external_id = "speed-quizzing-#{venue_data.event_id}"

  %{
    external_id: external_id,
    # ...
  }
end
```

**Flow:**
1. IndexJob fetches events from Speed Quizzing API
2. Generates external_ids for each event (lines 52-56)
3. EventFreshnessChecker filters out fresh events (>70% skip rate)
4. DetailJob processes stale events only
5. Transformer reuses event_id to create external_id
6. EventProcessor creates/updates recurring event with deduplication

### How It Works with EventFreshnessChecker

1. **Direct external_id match:** Skip if external_id seen within threshold (168h default)
2. **Existing event_id match:** Skip if external_id belongs to recently-updated recurring event
3. **Predicted event_id match:** Uses title+venue similarity for new events

**Efficiency:** First scrape processes all events, subsequent scrapes skip ~70-90% (already fresh)

### IndexJob Integration

**EventFreshnessChecker integration:** IndexJob (line 50-70)
```elixir
defp filter_fresh_events(events, source_id, limit) do
  # Generate external_ids for each event (prefer event_id, fallback to id)
  events_with_external_ids = Enum.map(events, fn event ->
    id = event["event_id"] || event["id"]
    Map.put(event, "external_id", "speed-quizzing-#{id}")
  end)

  # Filter out events that were recently updated
  events_to_process = EventFreshnessChecker.filter_events_needing_processing(
    events_with_external_ids,
    source_id
  )

  # Apply limit if provided (for testing)
  if limit do
    Enum.take(events_to_process, limit)
  else
    events_to_process
  end
end
```

**Key Points:**
- Prefers `event_id` from API response, falls back to `id`
- External_id generated in both IndexJob and Transformer (must match!)
- EventFreshnessChecker called before detail processing

### Edge Cases

**Q: What if a venue has multiple different events?**

A: EventProcessor's title-based matching handles this:
- Regular quiz: "Weekly Trivia Night - Pub XYZ"
- Special event: "Halloween Special Trivia - Pub XYZ"
- Different titles → processed separately ✅

**Q: What if titles are very similar?**

A: Intentional consolidation (Jaro distance > 0.85):
- "Weekly Trivia Night - Pub ABC"
- "Trivia Night Weekly - Pub ABC"
- Similar titles → merged as recurring event ✅

This is desired behavior for recurring event detection.

### Related Documentation

- EventFreshnessChecker: `lib/eventasaurus_discovery/services/event_freshness_checker.ex`
- EventProcessor recurring logic: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:1132-1391`
- Pattern standardization: See issue #1944

## Data Flow

1. **IndexJob** fetches events from Speed Quizzing API
2. **Generate external_ids** for each event (venue-based)
3. **EventFreshnessChecker** filters out fresh events (>70% skip rate)
4. **DetailJob** processes stale events only (if needed)
5. Extract schedule and parse to recurrence_rule
6. Calculate next occurrence datetime
7. **EventProcessor** creates/updates recurring event with deduplication

## Support

**Tests**: `test/eventasaurus_discovery/sources/speed_quizzing/`
**Docs**: See SCRAPER_SPECIFICATION.md
