# Issue: Sortiraparis Event Type Classification & Handling Strategy

**Date**: 2025-10-18
**Status**: Investigation Complete - Architectural Decision Required
**Priority**: High - Affects 83% of Sortiraparis events (24/29)
**Category**: Feature Design / Data Modeling

---

## Problem Statement

Sortiraparis provides events that fall into **fundamentally different categories** with different temporal characteristics:

1. **One-time events with specific dates** (concerts, shows)
2. **Ongoing exhibitions with run dates** (museums, galleries)
3. **Recurring patterns** (weekly museum nights, comedy shows)

Currently, we treat ALL of these as "events with specific dates", which leads to:
- Exhibitions showing "2 dates available" (opening + closing dates treated as showtimes)
- Recurring events being consolidated into date ranges instead of patterns
- User confusion about whether an event happens once, multiple times, or is ongoing

**Core Issue**: We're forcing diverse event types into a single "specific date" model that doesn't fit the source data reality.

---

## Evidence from Source Data

### Pattern 1: Date Ranges (Exhibitions - 83% of events)

**Database Evidence**:
```
Title: "Treasures saved from Gaza"
Original String: "April 3, 2025 to December 7, 2025"
Stored As: 2 separate dates (2025-04-02, 2025-12-06)
Display: "2 dates available"
Reality: Exhibition runs continuously from April to December
```

**More Examples**:
- Gaza Exhibition: April 3 - December 7, 2025 (8 months)
- Gerhard Richter: October 17, 2025 - March 2, 2026 (5 months)
- Nutcracker Show: December 23, 2025 - January 3, 2026 (2 weeks)
- Musée d'Orsay Nocturne: September 30, 2025 - January 11, 2026 (3+ months)

**Characteristics**:
- Have explicit start and end dates
- Run continuously or on regular schedule during the period
- Typically museums, galleries, exhibitions
- Users can visit anytime during the run (subject to opening hours)
- Tickets are often for "any day during run" not specific dates

### Pattern 2: Recurring Events (Weekly/Monthly)

**Web Fetch Evidence**:

**Example 1: Lyoom Comedy Souk**
- Original String: "January 1, 2025 to December 31, 2025"
- Web Page: "Every Wednesday at 7.30pm"
- Reality: Weekly recurring event, not 2 specific dates
- Ticket Type: Advance reservation for specific Wednesday

**Example 2: Musée d'Orsay Nocturne**
- Original String: "September 30, 2025 to January 11, 2026"
- Web Page: "Every Thursday evening, until 9:45pm"
- Reality: Weekly museum access, not 2 specific dates
- Ticket Type: Museum admission for any Thursday evening

**Example 3: Musée de Cluny**
- Title: "Musée de Cluny at night: discover the Middle Ages two Thursday evenings a month"
- Original String: "October 7, 2025 to January 11, 2026"
- Reality: Happens 2 times per month on Thursdays
- Pattern: Not every week, but twice monthly

**Characteristics**:
- Have patterns like "Every Wednesday", "Every Thursday evening"
- Run for extended periods (months/year)
- Require advance tickets for specific occurrences
- Similar to our PubQuiz/trivia pattern

### Pattern 3: One-Time Events with Specific Dates (17% of events)

**Database Evidence**:
```
Title: "British rapper Dave in concert"
Original String: "October 17, 2025"
Stored As: 1 date (2025-10-16)
Display: No "dates available" label
Reality: Single concert on one specific date
```

**More Examples**:
- Concerts: Dave, Offspring, Luke Combs, Star Academy
- One-time shows: Manga Mega Show, Hip Hop Symphonique
- Film screenings: Voice is Back (Frank Sinatra)

**Characteristics**:
- Single specific date
- Tickets for that exact performance
- Traditional "event with date" model
- This is our current default assumption (but minority of Sortiraparis events!)

---

## Current System Behavior

### Date Parser (date_parser.ex)

**What it does**:
```elixir
# Pattern: "October 15, 2025 to January 19, 2026"
def parse_date_range(date_string, options) do
  # Returns: [start_date, end_date]
  # Example: [~U[2025-10-15 00:00:00Z], ~U[2026-01-19 00:00:00Z]]
end
```

**Result**: Date ranges are converted to 2 discrete dates (opening + closing)

### Transformer (transformer.ex:78-82)

**What it does**:
```elixir
# Create separate event for each date
events =
  Enum.map(dates, fn date ->
    create_event(article_id, title, date, venue_data, raw_event, options)
  end)
```

**Result**:
- Exhibition with "April 3 to December 7" → 2 separate events
- Event 1: external_id `sortiraparis_323158_2025-04-02`
- Event 2: external_id `sortiraparis_323158_2025-12-06`

### EventProcessor Consolidation

**What it does**:
```elixir
# Find parent by article_id and consolidate
article_id ->
  find_article_event_parent(article_id, venue, external_id, source_id)
```

**Result**:
- Finds the 2 events from same article
- Merges into 1 event with `occurrences.dates = [date1, date2]`
- UI displays "2 dates available"

### Why This is Wrong

**For Exhibitions**:
- User sees "2 dates available"
- Expects: 2 specific showtimes
- Reality: Exhibition runs continuously for months
- User experience: Confusing, misleading

**For Recurring Events**:
- User sees "2 dates available"
- Expects: 2 specific showtimes
- Reality: Happens every week for months
- User experience: Completely wrong - they miss 90% of occurrences

**For One-Time Events**:
- Works correctly (minority case)

---

## Comparison to Existing Event Types

### PubQuiz/Trivia Pattern (We handle this correctly!)

**How we handle it**:
```json
{
  "occurrences": {
    "type": "pattern",
    "pattern": {
      "frequency": "weekly",
      "day_of_week": "wednesday",
      "time": "19:30"
    }
  }
}
```

**Display**:
- Shows as "Weekly on Wednesdays"
- Doesn't show specific dates
- Users understand it's recurring

**Why it works**:
- We recognize it's a pattern, not discrete dates
- Store the recurrence rule, not individual dates
- UI adapts to show pattern instead of date list

### Movie Showtimes (Karnet)

**How we handle it**:
```json
{
  "occurrences": {
    "type": "explicit",
    "dates": [
      {"date": "2025-10-15", "time": "14:00"},
      {"date": "2025-10-15", "time": "19:30"},
      {"date": "2025-10-16", "time": "21:00"}
    ]
  }
}
```

**Display**:
- "3 showtimes available" or "Daily event"
- Shows specific times user can attend
- Clear that these are discrete showtimes

**Why it works**:
- Movies DO have specific showtimes
- Each date is a real screening
- Explicit list matches reality

---

## Proposed Solution: Event Type Classification

### Step 1: Classify Event Types During Scraping

Add event type classification to Sortiraparis transformer:

```elixir
# Detect event type from date string + title + content
event_type = classify_event_type(raw_event)

# Types:
# - :one_time - Single specific date (concerts)
# - :exhibition - Date range, continuous access (museums, galleries)
# - :recurring - Pattern-based (weekly shows, monthly events)
```

### Step 2: Handle Each Type Differently

#### Type 1: One-Time Events (Current behavior - KEEP)

**Input**: "October 17, 2025"
**Processing**:
- Parse as single date
- Create one event
- Store as explicit date

**Display**: Event card with single date

#### Type 2: Exhibitions (NEW behavior needed)

**Input**: "April 3, 2025 to December 7, 2025"
**Processing**:
- Parse as date range
- Create ONE event (not two)
- Store run period:
```json
{
  "occurrences": {
    "type": "exhibition",
    "start_date": "2025-04-03",
    "end_date": "2025-12-07"
  }
}
```

**Display**:
- "On view: April 3 - December 7, 2025"
- OR: "Runs through December 7, 2025"
- NO "X dates available" label
- Clicking shows: "Visit anytime during run"

**Freshness**:
- Keep showing event as long as end_date hasn't passed
- Update when re-scraped (if dates extend)
- Remove when end_date passes without being re-scraped

#### Type 3: Recurring Events (NEW behavior needed)

**Input**: "January 1, 2025 to December 31, 2025" + title/content contains "every Wednesday"
**Processing**:
- Detect recurring pattern from title/HTML
- Create ONE event
- Store pattern:
```json
{
  "occurrences": {
    "type": "pattern",
    "pattern": {
      "frequency": "weekly",
      "day_of_week": "wednesday",
      "time": "19:30",
      "valid_from": "2025-01-01",
      "valid_until": "2025-12-31"
    }
  }
}
```

**Display**:
- "Every Wednesday at 7:30pm"
- "Through December 31, 2025"
- Clicking shows: Next 5-10 upcoming dates

**Freshness**:
- Keep showing as long as within valid period
- Generate upcoming dates dynamically
- Update pattern if re-scraped with new info

---

## Classification Logic

### Step 1: Detect from Date String Pattern

```elixir
def classify_by_date_pattern(date_string) do
  cond do
    # "October 15, 2025 to January 19, 2026" → likely exhibition
    Regex.match?(~r/\w+ \d+, \d{4} to \w+ \d+, \d{4}/, date_string) ->
      :potential_exhibition

    # "October 17, 2025" → likely one-time
    Regex.match?(~r/^\w+ \d+, \d{4}$/, date_string) ->
      :one_time

    # Other patterns
    true ->
      :unknown
  end
end
```

### Step 2: Refine with Title/Content Analysis

```elixir
def classify_event_type(raw_event) do
  date_pattern = classify_by_date_pattern(raw_event["date_string"])
  title = raw_event["title"]
  description = raw_event["description"]

  cond do
    # Recurring indicators
    recurring_pattern?(title) || recurring_pattern?(description) ->
      :recurring

    # Exhibition indicators
    date_pattern == :potential_exhibition && exhibition_keywords?(title) ->
      :exhibition

    # One-time default
    date_pattern == :one_time ->
      :one_time

    # Ambiguous - default to exhibition (safer than creating duplicates)
    true ->
      :exhibition
  end
end

defp recurring_pattern?(text) do
  text =~ ~r/every (monday|tuesday|wednesday|thursday|friday|saturday|sunday)/i ||
  text =~ ~r/every \w+ evening/i ||
  text =~ ~r/\d+ times? (per|a) (week|month)/i
end

defp exhibition_keywords?(text) do
  text =~ ~r/exhibition/i ||
  text =~ ~r/musée|museum/i ||
  text =~ ~r/gallery|galerie/i ||
  text =~ ~r/exposition/i
end
```

### Step 3: Extract Pattern Details (for recurring)

```elixir
def extract_recurring_pattern(title, description) do
  cond do
    # "Every Wednesday at 7:30pm"
    match = Regex.run(~r/every (monday|tuesday|wednesday|thursday|friday|saturday|sunday) at (\d+):(\d+)\s*(am|pm)?/i, text) ->
      [_, day, hour, minute, meridiem] = match
      %{
        frequency: "weekly",
        day_of_week: String.downcase(day),
        time: parse_time(hour, minute, meridiem)
      }

    # "Every Thursday evening"
    match = Regex.run(~r/every (monday|tuesday|wednesday|thursday|friday|saturday|sunday) evening/i, text) ->
      [_, day] = match
      %{
        frequency: "weekly",
        day_of_week: String.downcase(day),
        time: nil  # Time not specified
      }

    # More patterns...
    true ->
      nil
  end
end
```

---

## Database Schema Implications

### Current Schema (occurrences JSONB field)

Already supports multiple types:

```json
// Type 1: Explicit dates (current)
{
  "type": "explicit",
  "dates": [{"date": "2025-10-15", "time": "19:00"}]
}

// Type 2: Pattern (PubQuiz uses this)
{
  "type": "pattern",
  "pattern": {"frequency": "weekly", "day_of_week": "wednesday"}
}

// Type 3: Exhibition (NEW - add this)
{
  "type": "exhibition",
  "start_date": "2025-04-03",
  "end_date": "2025-12-07"
}
```

**No schema changes needed!** The JSONB field is flexible enough.

---

## Implementation Strategy

### Phase 1: Add Type Classification (Week 1)

**Files to modify**:
1. `lib/eventasaurus_discovery/sources/sortiraparis/event_extractor.ex`
   - Add classification logic
   - Detect recurring patterns from HTML

2. `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex`
   - Add `event_type` field to transformed data
   - Modify date handling based on type

3. `lib/eventasaurus_discovery/sources/sortiraparis/helpers/date_parser.ex`
   - Add `parse_exhibition_range/2` (returns start+end as map, not list)
   - Keep `parse_date_range/2` for backward compatibility

**Testing**:
- Test classification on sample URLs
- Verify type detection accuracy
- Edge case testing

### Phase 2: Update EventProcessor (Week 2)

**Files to modify**:
1. `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`
   - Handle exhibition-type events (don't create 2 instances)
   - Handle recurring-type events (extract pattern)
   - Keep one-time handling as-is

**Logic changes**:
```elixir
case event_type do
  :exhibition ->
    # Create ONE event with exhibition occurrences
    # Don't consolidate (nothing to consolidate)

  :recurring ->
    # Create ONE event with pattern occurrences
    # Similar to PubQuiz handling

  :one_time ->
    # Current behavior (works fine)
end
```

### Phase 3: UI Updates (Week 3)

**Files to modify**:
1. `lib/eventasaurus_discovery/public_events/public_event.ex`
   - Update `frequency_label/1` to handle exhibition type
   - Show "On view: [dates]" instead of "2 dates available"

2. Event card component
   - Display logic for exhibition vs explicit vs pattern

**Display examples**:
- Exhibition: "On view April 3 - December 7"
- Recurring: "Every Wednesday at 7:30pm"
- One-time: "October 17, 2025"

### Phase 4: Freshness & Scraping (Week 4)

**Files to modify**:
1. `lib/eventasaurus_discovery/services/event_freshness_checker.ex`
   - Exhibition events: fresh until end_date
   - Recurring events: fresh until valid_until

2. Re-scrape logic
   - Update exhibition end dates if extended
   - Update recurring patterns if changed

---

## Decision Matrix: When to Use Each Type

| Characteristic | One-Time | Exhibition | Recurring |
|----------------|----------|------------|-----------|
| **Date Pattern** | Single date | Date range | Date range + pattern |
| **Temporal** | Point in time | Continuous period | Repeated pattern |
| **Access** | Specific time only | Anytime during run | Specific recurring times |
| **Tickets** | For specific date | For any date | For specific occurrence |
| **Examples** | Concerts, films | Museums, galleries | Weekly shows, classes |
| **Title Keywords** | Artist names, "concert" | "exhibition", "musée" | "every", "weekly" |
| **Sortiraparis %** | ~17% | ~65% | ~18% |

---

## Benefits of This Approach

### For Users

1. **Accurate Information**:
   - Exhibitions show run dates, not fake "2 dates"
   - Recurring events show pattern, not misleading date count

2. **Better Discovery**:
   - Users can see what's available now vs. upcoming
   - Clear distinction between one-time and ongoing

3. **Proper Expectations**:
   - No confusion about tickets
   - Understand if they can "drop in" vs. need advance booking

### For System

1. **Cleaner Data Model**:
   - One event per actual event (not artificial splitting)
   - Occurrences field used appropriately

2. **Better Freshness**:
   - Don't remove exhibitions just because opening date passed
   - Keep recurring events active during entire run

3. **Scalability**:
   - Works for other cultural event sources
   - Handles similar patterns from future sources

### For Performance

1. **Fewer Database Records**:
   - One exhibition event instead of 2+ instances
   - Reduced consolidation overhead

2. **Less Confusion**:
   - No more "every event has 2 dates" problem
   - Consolidation logic only for actual duplicates

---

## Risks & Mitigation

### Risk 1: Misclassification

**Risk**: Some events classified as exhibition are actually one-time
**Impact**: User expects ongoing access, but it's one specific date
**Mitigation**:
- Conservative classification (prefer one-time when ambiguous)
- Test on large sample of URLs
- Monitor user feedback after launch

### Risk 2: Pattern Extraction Failures

**Risk**: Can't extract recurring pattern from title
**Impact**: Falls back to exhibition or one-time (possibly wrong)
**Mitigation**:
- Build robust regex library
- Log unmatched patterns for review
- Manual classification for tricky cases

### Risk 3: Breaking Existing Events

**Risk**: Re-scraping changes event types
**Impact**: Users' saved events might behave differently
**Mitigation**:
- Phase migration (don't change existing events immediately)
- Only apply to newly scraped events initially
- Gradual migration of old events

---

## Success Metrics

### Before (Current State)

- 24/29 events (83%) show "2 dates available"
- User confusion about what "2 dates" means
- Exhibitions treated as 2 discrete showtimes

### After (Goal)

- 0 exhibitions showing "X dates available"
- Exhibitions showing "On view: [date range]"
- Recurring events showing "Every [day] at [time]"
- One-time events showing single date
- User feedback: "Much clearer what kind of event this is"

### Metrics to Track

1. **Classification Accuracy**: % of events correctly classified (goal: >95%)
2. **User Engagement**: Click-through rate on event cards (expect increase)
3. **Error Reduction**: Fewer user reports of "wrong dates"
4. **Data Quality**: % of events with appropriate occurrences type

---

## Open Questions

### Question 1: What if exhibition has specific tour times?

**Example**: "Museum exhibition, with guided tours every Tuesday at 2pm"

**Options**:
A. Treat as exhibition (show run dates)
B. Treat as recurring (show tour pattern)
C. Hybrid: exhibition with optional recurring tours

**Recommendation**: Start with (A), add (C) in future if needed

### Question 2: How to handle "extended until" dates?

**Example**: Exhibition originally "April - June", extended to "April - December"

**Current Problem**: Creates new external_id with new end date, gets consolidated

**Options**:
A. Update end_date on existing event (preferable)
B. Create new event with consolidated dates
C. Track extension history in metadata

**Recommendation**: (A) for cleaner data

### Question 3: Should we scrape French pages for more pattern details?

**Context**: English pages may have less detail than French originals

**Tradeoff**:
- More accurate patterns (French has more detail)
- 2x scraping time (fetch both EN and FR)

**Recommendation**: Phase 2 enhancement, not initial implementation

---

## Next Steps

### Immediate (This Week)

1. **Validate classification approach**:
   - Sample 50 random Sortiraparis URLs
   - Manually classify each event type
   - Test classification algorithm accuracy

2. **Design decision on edge cases**:
   - Resolve open questions above
   - Document classification rules
   - Create test fixtures

3. **Prototype pattern extraction**:
   - Test regex patterns on real titles/descriptions
   - Build pattern library
   - Validate against web-fetched content

### Short Term (Next 2 Weeks)

1. Implement Phase 1 (classification)
2. Test on staging with real scraping
3. Review classification accuracy
4. Iterate on patterns

### Medium Term (Next Month)

1. Implement Phases 2-3 (processing + UI)
2. Internal testing and validation
3. Deploy to production with monitoring
4. Gather user feedback

---

## Related Issues

- ISSUE_SORTIRAPARIS_AGGREGATION.md - Original consolidation investigation
- ISSUE_SORTIRAPARIS_ANALYSIS.md - Root cause analysis
- ISSUE_LANGUAGE_HANDLING.md - French/English content scraping

---

## Conclusion

The "2 dates available" problem is not a bug in consolidation logic, but a **fundamental mismatch between event types and our data model**.

Sortiraparis provides 3 distinct event types:
1. One-time events (17%) - we handle correctly
2. Exhibitions (65%) - we mishandle as 2 discrete dates
3. Recurring events (18%) - we mishandle as date ranges

**Solution**: Classify events during scraping and handle each type appropriately using existing occurrences schema flexibility.

**Priority**: High - affects user experience for 83% of Sortiraparis events
**Effort**: Medium - 3-4 weeks across scraper, processor, and UI
**Risk**: Low-Medium - classification accuracy is key risk factor
