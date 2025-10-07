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

## Data Flow

1. Scrape venue listings
2. Extract schedule text
3. Parse Polish schedule to recurrence rule
4. Calculate next occurrence
5. Create recurring event

## Support

**Tests**: `test/eventasaurus_discovery/sources/pubquiz/`
**Docs**: See SCRAPER_SPECIFICATION.md
