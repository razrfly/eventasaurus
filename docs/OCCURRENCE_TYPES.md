# Event Occurrence Types

**Version:** 1.0
**Last Updated:** 2025-10-18
**Purpose:** Comprehensive guide to how different event types are modeled, stored, and consolidated

---

## 🎯 Overview

Events in Eventasaurus can occur in fundamentally different ways. Rather than forcing all events into a single model, we use **occurrence types** to represent the natural patterns events follow in the real world.

**Core Philosophy:** Model events the way they actually work, not how we wish they worked.

### The Occurrence Types

| Type | Description | Examples | Storage Pattern |
|------|-------------|----------|-----------------|
| **Explicit** | Discrete dates and times | Concerts, one-time shows | List of date/time pairs |
| **Pattern** | Recurring schedule | Weekly trivia, monthly meetups | Recurrence rule |
| **Exhibition** | Continuous access during period | Museum shows, galleries | Start date + end date |
| **Movie** | Multiple showtimes | Cinema screenings | Consolidated by movie_id |
| **Recurring** | Pattern-based (Sortiraparis) | Weekly museum events | Pattern in metadata |
| **Unknown** | Can't classify | Edge cases | Description + staleness |

---

## 📐 Database Structure

All occurrence data is stored in the `public_events.occurrences` JSONB field:

```sql
-- Schema
public_events.occurrences::jsonb
```

### General Structure

```json
{
  "type": "explicit" | "pattern" | "exhibition" | "recurring" | "unknown",
  "dates": [...],        // For explicit type
  "pattern": {...},      // For pattern/recurring type
  "start_date": "...",   // For exhibition type
  "end_date": "...",     // For exhibition type
  "description": "..."   // For unknown type
}
```

---

## 1️⃣ Explicit Occurrences

**Used For:** One-time events, concerts, performances with specific dates

**Prevalence:** ~70% of all events

### How It Works

Each occurrence is stored as a discrete date/time entry. Events from the same source (e.g., VIP vs. GA tickets) are consolidated into a single event with multiple date entries.

### Database Storage

```json
{
  "type": "explicit",
  "dates": [
    {
      "date": "2025-10-25",
      "time": "19:00",
      "external_id": "bandsintown_12345_vip",
      "label": "VIP Early Entry",
      "source_id": 3
    },
    {
      "date": "2025-10-25",
      "time": "20:00",
      "external_id": "bandsintown_12345_ga",
      "label": "General Admission",
      "source_id": 3
    }
  ]
}
```

### Consolidation Logic

**Trigger:** Same title + same venue + similar time (within 4 hours)

**Location:** `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:916-1180`

**Process:**
1. Normalize title (remove dates, episode numbers, time patterns)
2. Calculate fuzzy match score using Jaro distance
3. If score ≥ threshold (0.85-0.95 depending on event type):
   - Merge into parent event
   - Add new occurrence to `dates` array
   - Update `starts_at` to earliest time
   - Update `ends_at` to latest time

**Example:**
```elixir
# Event 1: "The National @ Brooklyn Steel - VIP Experience" (7:00 PM)
# Event 2: "The National @ Brooklyn Steel" (8:00 PM)
# → Consolidated into one event with 2 occurrences
```

### Display

- "X dates available" (where X is length of `dates` array)
- Shows all date/time options as separate choices
- Labels distinguish ticket types (VIP, GA, etc.)

---

## 2️⃣ Pattern Occurrences

**Used For:** Recurring events with predictable schedules (weekly trivia, monthly book clubs)

**Prevalence:** ~5% of all events

**See Also:** [RECURRING_EVENT_PATTERNS.md](./RECURRING_EVENT_PATTERNS.md) for complete implementation guide

### How It Works

Instead of storing 50+ future dates, we store a recurrence rule. The frontend generates upcoming dates dynamically.

### Database Storage

```json
{
  "type": "pattern",
  "pattern": {
    "frequency": "weekly",
    "days_of_week": ["tuesday"],
    "time": "19:00",
    "timezone": "Europe/Warsaw"
  }
}
```

### Code Location

**Initialization:** `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:242-280`

```elixir
def initialize_occurrence_with_source(data) do
  if data.recurrence_rule do
    %{
      "type" => "pattern",
      "pattern" => data.recurrence_rule
    }
  else
    # Fall back to explicit
  end
end
```

### Sources Using Pattern Type

- **PubQuiz** (Poland trivia venues) ✅ Implemented
- **Inquizition** (UK trivia venues) 🚧 Planned
- **Geeks Who Drink** (US/Canada trivia) 🚧 Planned

### Display

- "Every Tuesday at 7:00 PM"
- Shows next 4+ upcoming dates
- Updates automatically (no stale dates)

---

## 3️⃣ Exhibition Occurrences

**Used For:** Museums, galleries, art installations with continuous access during a period

**Prevalence:** ~65% of Sortiraparis events, ~10% overall

**New:** Implemented 2025-10-18 (GitHub issue #1832)

### How It Works

Exhibitions don't have discrete showtimes - they're accessible any time during opening hours from start date to end date. We store the range, not individual dates.

### Database Storage

```json
{
  "type": "exhibition",
  "start_date": "2025-04-03",
  "end_date": "2025-12-07"
}
```

**Note:** The event's `starts_at` and `ends_at` fields are also set to match these dates.

### Metadata Storage

```json
{
  "exhibition_range": {
    "start_date": "2025-04-03",
    "end_date": "2025-12-07"
  }
}
```

### Classification Logic

**Location:** `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex:411-487`

**Triggers:**
- Date pattern is a range: "October 15, 2025 to January 19, 2026"
- Title/description contains exhibition keywords: `exhibition`, `musée`, `museum`, `gallery`, `galerie`, `exposition`, `installation`, `retrospective`

**Example:**
```
Title: "Gerhard Richter at Musée d'Art Moderne"
Date: "October 17, 2025 to March 15, 2026"
→ Classified as :exhibition
```

### Consolidation

**No consolidation** - Each exhibition is a standalone event. External ID has NO date suffix: `sortiraparis_335322`

**Code:** `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:1018-1024`

```elixir
defp find_recurring_parent(title, venue, external_id, source_id, movie_id, article_id, event_type) do
  if event_type == :exhibition do
    Logger.debug("⏭️  Skipping consolidation for exhibition event type")
    nil
  end
end
```

### Display

- "Exhibition runs: April 3 - December 7, 2025"
- Single date range, not multiple dates
- Description shows gallery/museum context

### Sources Using Exhibition Type

- **Sortiraparis** (Paris cultural events) ✅ Implemented

---

## 4️⃣ Movie Occurrences

**Used For:** Cinema showtimes for the same film

**Prevalence:** ~10% of all events (cinema-heavy cities)

### How It Works

Multiple screenings of the same movie at the same cinema are consolidated by `movie_id`. Each showtime becomes an occurrence entry.

### Database Storage

```json
{
  "type": "explicit",
  "dates": [
    {"date": "2025-10-25", "time": "14:00", "external_id": "karnet_12345_1"},
    {"date": "2025-10-25", "time": "17:00", "external_id": "karnet_12345_2"},
    {"date": "2025-10-25", "time": "20:00", "external_id": "karnet_12345_3"}
  ]
}
```

**Additional:** Event has `movie_id` field linking to `movies` table

### Consolidation Logic

**Trigger:** Same `movie_id` + same venue

**Location:** `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:1047-1088`

```elixir
defp find_movie_event_parent(movie_id, venue, external_id, source_id) do
  # Find any event at this venue with this movie_id
  # Consolidate all showtimes into one event
end
```

**Process:**
1. First showtime creates event + movie association
2. Subsequent showtimes find parent by `movie_id`
3. Add new showtime to `occurrences.dates`
4. Create source record for tracking

### External ID Format

- First showtime: `karnet_cinema-city-krakow_12345_2025-10-25T14:00:00Z`
- Pattern: `{source}_{venue_slug}_{movie_id}_{datetime}`

### Sources Using Movie Type

- **Karnet** (Krakow cinemas) ✅ Implemented
- **Kino Krakow** (Arthouse cinemas) ✅ Implemented
- **Cinema City** (Chain theaters) 🚧 Planned

### Display

- Shows movie title (not showtime-specific)
- "X showtimes available"
- User selects specific time when booking

---

## 5️⃣ Recurring Occurrences (Sortiraparis)

**Used For:** Pattern-based events detected from source text (weekly museum nights, monthly concerts)

**Prevalence:** ~18% of Sortiraparis events, ~2% overall

**New:** Implemented 2025-10-18 (GitHub issue #1832)

### How It Works

Similar to Pattern type, but pattern is extracted from event title/description rather than structured schedule data. Used when we detect recurring language but don't have full recurrence rules.

### Database Storage

```json
{
  "type": "recurring"
}
```

**Pattern stored in metadata:**
```json
{
  "recurrence_pattern": {
    "type": "weekly",
    "description": "Every Thursday evening until 10pm"
  }
}
```

### Classification Logic

**Location:** `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex:466-473`

**Triggers:**
- `every monday|tuesday|...|sunday`
- `every \w+ evening|night`
- `\d+ times per week|month`
- French: `tous les lundi|...|dimanche`
- French: `chaque lundi|...|dimanche`

**Example:**
```
Title: "Musée d'Orsay by Night"
Description: "Every Thursday evening until 10pm"
→ Classified as :recurring
```

### Pattern Extraction

**Location:** `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex:419-436`

```elixir
defp extract_recurrence_pattern(raw_event) do
  text = "#{title} #{description}" |> String.downcase()

  cond do
    text =~ ~r/every (monday|tuesday|...)/i ->
      %{type: "weekly", description: text}

    text =~ ~r/\d+ times? (per|a) (week|month)/i ->
      %{type: "custom", description: text}

    true ->
      %{type: "unknown", description: text}
  end
end
```

### Consolidation

**No consolidation** - Each recurring event is standalone. External ID has NO date suffix: `sortiraparis_335327`

**Code:** `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:1022-1024`

### Display

- Shows pattern text to user: "Every Thursday evening"
- Uses description from source (not computed dates)
- Assumes active as long as source still lists it

### Sources Using Recurring Type

- **Sortiraparis** (Paris recurring events) ✅ Implemented

---

## 6️⃣ Unknown Occurrences (Fallback)

**Used For:** Events we can't classify into any other type

**Prevalence:** <1% of events (edge cases)

**Purpose:** Graceful degradation - show user what we know, even if we can't model it perfectly

### How It Works

When we encounter an event that doesn't fit any pattern:
- Store the original description from source
- Show it directly to users
- Assume it's active if we keep seeing it during scrapes
- Remove it when it disappears (staleness checking)

### Database Storage

```json
{
  "type": "unknown",
  "description": "Original source text describing when this happens",
  "source_text": "Complex pattern we couldn't parse",
  "last_seen_at": "2025-10-18T12:00:00Z"
}
```

### When to Use

**Automatic triggers:**
- Date parsing fails completely
- Pattern too complex (e.g., "Every other Tuesday", "First and third Monday")
- Contradictory information (multiple date formats)
- Source provides description but no structured dates

**Manual override:**
- Scraper developer can explicitly set `event_type: :unknown`

### Code Pattern

```elixir
# In Transformer
case DateParser.parse_dates(date_string) do
  {:ok, dates} ->
    # Use normal classification

  {:error, :unsupported_date_format} ->
    # Fall back to unknown
    %{
      event_type: :unknown,
      metadata: %{
        occurrence_description: date_string,
        reason: "unsupported_date_format"
      }
    }
end
```

### Staleness Strategy

**Active:** Last seen within 7 days (configurable per source)
**Stale:** Not seen in recent scrape → mark for removal

**Logic:** `lib/eventasaurus_discovery/scraping/helpers/staleness_checker.ex`

```elixir
def check_staleness(event, source) do
  if event.occurrences["type"] == "unknown" do
    # For unknown types, rely purely on last_seen_at
    days_since_seen = DateTime.diff(DateTime.utc_now(), event.last_seen_at, :day)

    if days_since_seen > source.staleness_threshold do
      :stale
    else
      :active
    end
  end
end
```

### Display

- Shows source description verbatim
- "Check source for latest schedule" link
- Updates when source updates
- Disappears when source removes it

### Example

```
Event: "Summer Jazz Series"
Description from source: "Multiple dates throughout July and August, see website for details"
Occurrence type: unknown
Display: Shows description + link to source website
```

---

## 🔄 Consolidation Matrix

How different occurrence types interact when consolidating events:

| Parent Type | New Event Type | Behavior |
|-------------|---------------|----------|
| Explicit | Explicit | ✅ Merge if title/venue match |
| Explicit | Movie | ✅ Consolidate by movie_id |
| Pattern | Explicit | ❌ Keep separate (different models) |
| Exhibition | Exhibition | ❌ Keep separate (standalone) |
| Exhibition | Explicit | ❌ Keep separate (different models) |
| Recurring | Recurring | ❌ Keep separate (standalone) |
| Recurring | Explicit | ❌ Keep separate (different models) |
| Unknown | Unknown | ⚠️ Merge if external_id matches |
| Unknown | Any | ⚠️ Keep separate (can't reliably match) |

**Key Principle:** Only consolidate within the same occurrence type model.

---

## 📊 Source-Specific Patterns

### Bandsintown

- **Primary Type:** Explicit
- **Pattern:** One event per concert, sometimes with VIP/GA variants
- **Consolidation:** By title + venue + time proximity
- **External ID:** `bandsintown_{artist_id}_{venue_id}_{date}`

### Karnet (Krakow Cinemas)

- **Primary Type:** Movie (explicit dates)
- **Pattern:** Multiple showtimes per movie per cinema
- **Consolidation:** By movie_id + venue
- **External ID:** `karnet_{cinema_slug}_{movie_id}_{datetime}`

### PubQuiz (Poland Trivia)

- **Primary Type:** Pattern
- **Pattern:** Weekly recurring trivia nights
- **Consolidation:** None (one event per venue)
- **External ID:** `pubquiz_{venue_id}`

### Sortiraparis (Paris Events)

- **Primary Types:** Exhibition (65%), Recurring (18%), Explicit (17%)
- **Pattern:** Mixed - cultural events with varied schedules
- **Consolidation:** By article_id for explicit, none for exhibition/recurring
- **External ID:**
  - Explicit: `sortiraparis_{article_id}_{date}`
  - Exhibition: `sortiraparis_{article_id}`
  - Recurring: `sortiraparis_{article_id}`

### Ticketmaster

- **Primary Type:** Explicit
- **Pattern:** One-time events with specific dates
- **Consolidation:** By event_id (handles variants like VIP)
- **External ID:** `ticketmaster_{event_id}`

---

## 🔍 How to Determine Occurrence Type

### During Development (Transformer)

```elixir
def classify_event_type(raw_event) do
  cond do
    # Check for pattern indicators
    has_recurrence_rule?(raw_event) ->
      :pattern

    # Check for exhibition indicators
    is_date_range?(raw_event) && has_exhibition_keywords?(raw_event) ->
      :exhibition

    # Check for recurring language
    has_recurring_pattern?(raw_event.title, raw_event.description) ->
      :recurring

    # Check for movie events
    has_movie_id?(raw_event) ->
      :movie

    # Check for explicit dates
    has_discrete_dates?(raw_event) ->
      :explicit

    # Fallback
    true ->
      :unknown
  end
end
```

### In Production (Querying)

```sql
-- Count by occurrence type
SELECT
  occurrences->>'type' as occurrence_type,
  COUNT(*) as count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
FROM public_events
WHERE occurrences IS NOT NULL
GROUP BY occurrences->>'type'
ORDER BY count DESC;
```

**Example Output:**
```
 occurrence_type | count | percentage
-----------------+-------+------------
 explicit        | 8521  |       68.5
 pattern         |  634  |        5.1
 exhibition      | 2847  |       22.9
 movie           |  412  |        3.3
 recurring       |   24  |        0.2
 unknown         |    3  |        0.0
```

---

## 🛠️ Implementation Checklist

When adding a new source, determine occurrence type(s):

### For Explicit Events
- [ ] Parse date/time into DateTime
- [ ] Set `starts_at` and optionally `ends_at`
- [ ] Generate unique `external_id` per occurrence
- [ ] Let EventProcessor handle consolidation
- [ ] Test with multi-date events (concerts with multiple shows)

### For Pattern Events
- [ ] Implement `parse_schedule_to_recurrence/1` in Transformer
- [ ] Implement `calculate_next_occurrence/1` in Transformer
- [ ] Add `recurrence_rule` to event map
- [ ] Set `starts_at` to next upcoming occurrence
- [ ] Test timezone handling
- [ ] See [RECURRING_EVENT_PATTERNS.md](./RECURRING_EVENT_PATTERNS.md)

### For Exhibition Events
- [ ] Detect date range patterns in HTML
- [ ] Check for exhibition keywords in title/description
- [ ] Set `event_type: :exhibition` in Transformer
- [ ] Set both `starts_at` and `ends_at`
- [ ] Generate external_id WITHOUT date suffix
- [ ] Verify no consolidation happens (standalone events)

### For Movie Events
- [ ] Extract movie_id from source
- [ ] Add `movie_id` to event map
- [ ] Generate external_id with movie_id
- [ ] Let EventProcessor consolidate by movie_id
- [ ] Test multiple showtimes → single event

### For Recurring Events (Text-based)
- [ ] Detect recurring patterns in title/description
- [ ] Set `event_type: :recurring` in Transformer
- [ ] Extract pattern to metadata
- [ ] Generate external_id WITHOUT date suffix
- [ ] Set `starts_at` to anchor date
- [ ] Verify no consolidation happens

### For Unknown Events (Fallback)
- [ ] Store original source description in metadata
- [ ] Set `event_type: :unknown`
- [ ] Add `occurrence_description` to metadata
- [ ] Configure staleness threshold
- [ ] Test removal when source stops listing it

---

## 🎯 Best Practices

### 1. Choose the Right Type

**Don't force patterns where they don't exist:**
- Concert with 3 specific dates → Explicit (not Pattern)
- Exhibition running 6 months → Exhibition (not Explicit with 180 dates)
- Weekly trivia → Pattern (not 50 Explicit dates)

### 2. Preserve Source Intent

**Model events the way the source presents them:**
- If source says "Every Tuesday" → Pattern or Recurring
- If source lists discrete dates → Explicit
- If source shows date range → Exhibition

### 3. Graceful Degradation

**Unknown is better than broken:**
```elixir
case parse_complex_schedule(text) do
  {:ok, parsed} -> use_appropriate_type(parsed)
  {:error, _} ->
    Logger.warning("Could not parse schedule, using unknown type")
    %{event_type: :unknown, metadata: %{occurrence_description: text}}
end
```

### 4. Test Consolidation

**Verify events consolidate correctly:**
```elixir
# Test that these two events merge
event1 = %{title: "Concert @ Venue", starts_at: ~U[2025-10-25 19:00:00Z]}
event2 = %{title: "Concert @ Venue - VIP", starts_at: ~U[2025-10-25 19:30:00Z]}
# Should create ONE event with TWO occurrences
```

### 5. Monitor Distribution

**Check occurrence type distribution regularly:**
```sql
-- Weekly check: Are percentages reasonable?
SELECT
  occurrences->>'type' as type,
  COUNT(*),
  source.name
FROM public_events
JOIN public_event_sources ON ...
GROUP BY type, source.name;
```

---

## 📚 Related Documentation

- [RECURRING_EVENT_PATTERNS.md](./RECURRING_EVENT_PATTERNS.md) - Complete guide to Pattern type
- [ADDING_NEW_SOURCES.md](./ADDING_NEW_SOURCES.md) - How to add scrapers
- [SCRAPER_MANIFESTO.md](./SCRAPER_MANIFESTO.md) - Scraping philosophy
- [collision_handling_analysis.md](./collision_handling_analysis.md) - Event deduplication
- [ISSUE_SORTIRAPARIS_EVENT_TYPES.md](../ISSUE_SORTIRAPARIS_EVENT_TYPES.md) - Exhibition/Recurring implementation

---

## 🔗 Code References

### EventProcessor (Consolidation Logic)
- **Main processing:** `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:60-76`
- **Occurrence initialization:** Lines 242-280
- **Fuzzy matching:** Lines 916-1180
- **Movie consolidation:** Lines 1047-1088
- **Article consolidation:** Lines 1092-1129

### Sortiraparis (Exhibition/Recurring)
- **Event classification:** `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex:411-487`
- **Transformer logic:** `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex:71-436`
- **Pattern extraction:** Lines 419-436

### PubQuiz (Pattern Type)
- **Transformer:** `lib/eventasaurus_discovery/sources/pubquiz/transformer.ex`
- **Schedule parsing:** `parse_schedule_to_recurrence/1`
- **Date calculation:** `calculate_next_occurrence/1`

---

## 🎓 Key Takeaways

1. **Different events need different models** - Don't force one-size-fits-all
2. **Occurrence types enable graceful degradation** - Unknown is better than broken
3. **Consolidation is type-aware** - Only merge compatible types
4. **Source fidelity matters** - Model what sources actually provide
5. **Explicit is the default** - Use for most one-time events
6. **Pattern is powerful** - One record → infinite future dates
7. **Exhibition captures ranges** - Museums, galleries need date spans
8. **Unknown is the safety net** - Always have a fallback
9. **Test your assumptions** - Check actual distribution matches expectations
10. **Document your decisions** - Future developers will thank you

---

**Questions?** Check related docs above or review source-specific transformers in `lib/eventasaurus_discovery/sources/*/transformer.ex`
