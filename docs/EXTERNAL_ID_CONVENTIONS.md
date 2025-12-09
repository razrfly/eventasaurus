# External ID Conventions

This document defines the conventions for `external_id` generation across all scrapers in Eventasaurus. The `external_id` is a critical field used for deduplication, idempotency, and event tracking.

## Overview

### Purpose of external_id

1. **Deduplication**: Prevent reimporting the same event from the same source
2. **Idempotency**: Re-running a scraper updates existing records instead of creating duplicates
3. **Freshness Tracking**: `public_event_sources.last_seen_at` is updated each time an event is seen
4. **Cross-Source Matching**: Events from different sources can be linked (via fuzzy matching, not external_id)

### Database Constraint

```sql
UNIQUE(source_id, external_id) ON public_event_sources
```

This means:
- The same `external_id` CAN exist for different sources
- Each source can only have ONE record per `external_id`

## Event Type Classification

| Event Type | Pattern | Date in ID? | DB Records | Use Case |
|------------|---------|-------------|------------|----------|
| **Single-occurrence** | `{source}_{api_id}` | No | 1 per event | Concerts, shows |
| **Multi-date** | `{source}_{id}_{date}` | Yes | 1 per date | Festival dates |
| **Multi-showtime** | `{source}_showtime_{ids}` | Yes (in time) | 1 per screening | Movie showtimes |
| **Recurring** | `{source}_{venue_id}` | **No** | 1 total | Weekly trivia |
| **Date-range** | `{source}_{id}` | No | 1 with start/end | Exhibitions |

## Pattern Specifications

### 1. Single-Occurrence Events

**Pattern**: `{source}_{api_id}`

**Examples**:
- `bandsintown_12345`
- `resident_advisor_67890`
- `ticketmaster_url_11111`
- `karnet_event_54321`

**When to use**: Events that happen once at a specific date/time (concerts, one-off shows)

**Implementation**:
```elixir
# From URL (preferred for stability)
case Regex.run(~r/\/e\/(\d+)-/, url) do
  [_, id] -> "bandsintown_#{id}"
  _ -> "bandsintown_#{hash(url)}"  # Fallback
end

# From API response
external_id = "resident_advisor_#{event["id"]}"
```

### 2. Multi-Date Events

**Pattern**: `{source}_{article_id}_{YYYY-MM-DD}`

**Examples**:
- `sortiraparis_12345_2024-01-15`
- `sortiraparis_12345_2024-01-16`
- `week_pl_restaurant123_2024-01-15_19:00`

**When to use**: Same event repeating on multiple distinct dates (festivals, markets)

**Why date is included**: Each date creates a separate database record

**Implementation**:
```elixir
external_id = "sortiraparis_#{article_id}_#{Date.to_iso8601(date)}"
```

**Special Case - Date Range Events** (exhibitions):
```elixir
# NO date suffix - store range in starts_at/ends_at
external_id = "sortiraparis_#{article_id}"
```

### 3. Movie Showtimes

**Pattern (API IDs)**: `{source}_showtime_{cinema_id}_{film_id}_{event_id}`

**Pattern (Slugs)**: `{source}_showtime_{movie}_{cinema}_{date}_{time}`

**Examples**:
- `cinema_city_showtime_1099_12345_67890`
- `kino_krakow_showtime_the-matrix_kino-pod-baranami_2024-01-15_19_30`

**When to use**: Cinema screenings with multiple showtimes per day

**Why time is included**: Same movie can play multiple times per day at same cinema

**Implementation**:
```elixir
# Cinema City (API IDs available)
external_id = "cinema_city_showtime_#{cinema_id}_#{film_id}_#{event_id}"

# Kino Krakow (slug-based)
external_id = "kino_krakow_showtime_#{movie}_#{cinema}_#{date}_#{time}"
            |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
```

### 4. Recurring Events

**Pattern**: `{source}_{venue_id}` or `{source}_{venue_slug}`

**Examples**:
- `inquizition_abc123`
- `question_one_the-pub-name`
- `geeks_who_drink_xyz789`
- `speed_quizzing_event456`

**When to use**: Weekly/regular events that use `recurrence_rule`

**CRITICAL**: Do NOT include date in external_id for recurring events!

**Why no date**: ONE database record represents ALL future occurrences. The frontend generates specific dates from `recurrence_rule`.

**Implementation**:
```elixir
venue_slug = TextHelper.slugify(venue_name)
external_id = "question_one_#{venue_slug}"
```

**recurrence_rule example**:
```json
{
  "frequency": "weekly",
  "days_of_week": ["wednesday"],
  "time": "20:00",
  "timezone": "Europe/London"
}
```

## Decision Tree

```
Is this a recurring event (weekly trivia, etc.)?
├── YES → Use venue-based ID (NO date): {source}_{venue_id}
└── NO
    └── Is this a movie/cinema showtime?
        ├── YES → Include time: {source}_showtime_{movie}_{cinema}_{datetime}
        └── NO
            └── Does the same "event" repeat on multiple dates?
                ├── YES → Include date: {source}_{id}_{date}
                └── NO
                    └── Is it a date-range event (exhibition)?
                        ├── YES → No date suffix: {source}_{id}
                        └── NO → Single occurrence: {source}_{api_id}
```

## Current Implementation by Source

| Source | Pattern | Example |
|--------|---------|---------|
| **Bandsintown** | `bandsintown_{api_id}` | `bandsintown_12345` |
| **Ticketmaster** | `tm_url_{numeric_id}` | `tm_url_98765` |
| **Resident Advisor** | `resident_advisor_{api_id}` | `resident_advisor_54321` |
| **Karnet** | `karnet_{url_id}` | `karnet_11111` |
| **Cinema City** | `cinema_city_showtime_{cinema}_{film}_{event}` | `cinema_city_showtime_1099_123_456` |
| **Kino Krakow** | `kino_krakow_showtime_{movie}_{cinema}_{date}_{time}` | `kino_krakow_showtime_matrix_kino-pod-baranami_2024-01-15_19_30` |
| **Sortiraparis** | `sortiraparis_{article_id}_{date}` | `sortiraparis_12345_2024-01-15` |
| **Week.pl** | `week_pl_{restaurant}_{date}_{slot}` | `week_pl_rest123_2024-01-15_19:00` |
| **Inquizition** | `inquizition_{venue_id}` | `inquizition_abc123` |
| **Question One** | `question_one_{venue_slug}` | `question_one_the-pub-name` |
| **Geeks Who Drink** | `geeks_who_drink_{venue_id}` | `geeks_who_drink_xyz789` |
| **Speed Quizzing** | `speed_quizzing_{event_id}` | `speed_quizzing_456` |
| **Waw4Free** | Pass-through from extractor | Varies |

## Historical Changes

### Migration: Fix External ID Conventions (2024-12)

**Migration**: `20251209123303_fix_external_id_conventions.exs`
**Related**: GitHub issue #2602

Fixed two inconsistencies to standardize external_id formats:

1. **Speed Quizzing**: Changed delimiter from hyphens to underscores
   - Before: `speed-quizzing-{id}`
   - After: `speed_quizzing_{id}`

2. **Karnet**: Removed redundant `_event_` type component
   - Before: `karnet_event_{id}`
   - After: `karnet_{id}`

The migration updates existing database records, and code changes ensure
new records use the standardized format going forward.

## Job Tracking vs Event external_ids

**Important**: Jobs use separate external_ids for metrics tracking!

| Purpose | Pattern | Example |
|---------|---------|---------|
| **Event dedup** | `{source}_{identifier}` | `bandsintown_12345` |
| **SyncJob tracking** | `{source}_sync_{date}` | `cinema_city_sync_2024-01-15` |
| **IndexJob tracking** | `{source}_{cinema}_{date}` | `cinema_city_1099_2024-01-15` |
| **DayJob tracking** | `{source}_day_{offset}_{date}` | `kino_krakow_day_0_2024-01-15` |

These serve different purposes:
- **Event external_ids**: Stored in `public_event_sources`, used for deduplication
- **Job external_ids**: Used by `MetricsTracker` for job execution monitoring

## Best Practices

1. **Stability over readability**: Prefer API IDs over slugs when available
2. **Generate early**: Create external_id as early as possible in the pipeline
3. **Pass through**: Don't regenerate external_id in later jobs (causes drift)
4. **Lowercase**: Always use lowercase for consistency
5. **No special characters**: Replace with underscores or remove
6. **Test idempotency**: Verify re-running scraper updates, not duplicates

## Related Documentation

- `docs/source-implementation-guide.md` - Full scraper implementation guide
- `docs/RECURRING_EVENT_PATTERNS.md` - Recurring event specification
- `docs/scraper-monitoring-guide.md` - MetricsTracker integration
