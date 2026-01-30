# PubQuiz Scraper

Weekly trivia night discovery platform for Poland.

## Overview

**Priority**: 50 (Recurring events)
**Type**: Web scraper
**Coverage**: Poland (focus: Kraków, Warsaw)
**Event Types**: Trivia, Quiz Nights
**Update Frequency**: Weekly

## Features

- ✅ Recurring event support (first implementation!)
- ✅ Polish schedule parsing
- ✅ Venue extraction with geocoding
- ✅ Automatic next occurrence calculation
- ✅ Recurrence rule generation

## Configuration

No API key required.

**Rate Limit**: 2s between requests
**Timezone**: Europe/Warsaw

## Recurrence Format

```json
{
  "frequency": "weekly",
  "days_of_week": ["monday"],
  "time": "19:00",
  "timezone": "Europe/Warsaw"
}
```

## Schedule Parsing

Supports Polish day names:
- poniedziałek → monday
- wtorek → tuesday
- środa → wednesday
- czwartek → thursday
- piątek → friday
- sobota → saturday
- niedziela → sunday

## External ID Pattern

**Format:** `pubquiz-pl_{city}_{venue_slug}_{YYYY-MM-DD}`

**Example:** `pubquiz-pl_warszawa_centrum_2025-01-07`

### Why Date-Based?

For recurring events, each weekly occurrence needs a unique identifier to pass EventFreshnessChecker:

- Base venue slug: `pubquiz-pl_{city}_{venue_slug}` - identifies the venue
- Date suffix: `_{YYYY-MM-DD}` - identifies the specific occurrence
- This ensures each weekly trivia night is treated as a unique event

### Implementation

**Base ID Generation:** CityJob (line 148-158)
```elixir
defp generate_external_id(url) do
  url
  |> String.trim_trailing("/")
  |> String.split("/")
  |> Enum.take(-2)  # Last 2 URL segments: city/venue
  |> Enum.join("_")
  |> String.replace("-", "_")
  |> then(&"pubquiz-pl_#{&1}")
end
```

**Date Suffix Added:** VenueDetailJob (line 144-154)
```elixir
# After parsing schedule and calculating next_occurrence
date_str = next_occurrence |> DateTime.to_date() |> Date.to_iso8601()
dated_external_id = "#{external_id}_#{date_str}"
```

**Flow:**
1. CityJob generates base external_id from venue URL
2. Passes base external_id to VenueDetailJob in job args
3. VenueDetailJob parses schedule and calculates next_occurrence
4. Date is appended to external_id for the specific occurrence
5. EventFreshnessChecker allows new weekly occurrences through

### How It Works with EventFreshnessChecker

1. **Direct external_id match:** Skip if external_id seen within threshold (168h default)
2. **Existing event_id match:** Skip if external_id belongs to recently-updated recurring event
3. **Predicted event_id match:** Uses title+venue similarity for new events

**Efficiency:** First scrape processes all venues, subsequent scrapes skip ~70-90% (already fresh)

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

1. **CityJob** scrapes venue listings from city page
2. **Generate external_ids** for each venue (venue-based)
3. **EventFreshnessChecker** filters out fresh venues (>70% skip rate)
4. **VenueDetailJob** processes stale venues only
5. Extract schedule text and parse to recurrence_rule
6. Calculate next occurrence datetime
7. **EventProcessor** creates/updates recurring event with deduplication

## Support

**Tests**: `test/eventasaurus_discovery/sources/pubquiz/`
**Docs**: See SCRAPER_SPECIFICATION.md
