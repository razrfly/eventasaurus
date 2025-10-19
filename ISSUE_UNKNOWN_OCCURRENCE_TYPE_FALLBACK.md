# Unknown Occurrence Type: Graceful Fallback for Unparseable Dates

**Issue Type**: Feature Request / Architecture Enhancement
**Priority**: HIGH
**Affects**: All event scrapers, particularly Sortiraparis
**Status**: Proposal

---

## Problem Statement

**Current Behavior**: When a scraper encounters a date format it cannot parse, the entire event fails with `{:error, :unsupported_date_format}` and is NOT saved to the database.

**Impact**:
- ~15-20% of Sortiraparis events fail due to unparseable dates
- Complete data loss - users never see these events
- Example failure: "from July 4 to 6, 2025" (Biennial Multitude festival)
- Bilingual events fail on BOTH languages even though translations work perfectly

**The Paradox**: If an event appears on a curated source like Sortiraparis, we KNOW it's a current/active event - but we throw it away because we can't parse the date string.

---

## Proposed Solution: Unknown Occurrence Type with Freshness Tracking

### Core Concept

**Instead of failing**: Save the event with `occurrence_type = :unknown` and store the raw date text for users to interpret.

**Freshness Logic**: Use `last_seen_at` timestamp to automatically hide stale events without manual cleanup.

### Four Occurrence Types

| Type | Description | Example | starts_at | Handling |
|------|-------------|---------|-----------|----------|
| **one_time** | Single specific date/time | "October 26, 2025 at 8pm" | Required | Current behavior |
| **recurring** | Pattern-based schedule | "Every Tuesday at 7pm" | First occurrence | Future enhancement |
| **exhibition** | Continuous date range | "October 15 to January 19" | Range start | Current behavior |
| **unknown** | Unparseable but current | "from July 4 to 6" | NULL | NEW - fallback |

---

## Technical Implementation

### 1. Database Schema Changes

**Add occurrence_type enum**:
```sql
-- Migration: add_occurrence_type_to_events.exs
ALTER TABLE public_events 
  ADD COLUMN occurrence_type VARCHAR(20) NOT NULL DEFAULT 'one_time';

-- Add constraint
ALTER TABLE public_events
  ADD CONSTRAINT valid_occurrence_type 
  CHECK (occurrence_type IN ('one_time', 'recurring', 'exhibition', 'unknown'));

-- Make starts_at nullable for unknown types
ALTER TABLE public_events
  ALTER COLUMN starts_at DROP NOT NULL;

-- Add constraint: starts_at required unless unknown
ALTER TABLE public_events
  ADD CONSTRAINT starts_at_required_unless_unknown
  CHECK (
    (occurrence_type = 'unknown' AND starts_at IS NULL) OR
    (occurrence_type != 'unknown' AND starts_at IS NOT NULL)
  );
```

**Keep existing fields**:
- `original_date_string` - Already exists, stores raw date text
- `last_seen_at` - Already exists on event_sources table

### 2. Transformer Fallback Logic

**Location**: `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex`

```elixir
def transform_event(raw_event) do
  # Try to parse dates normally
  case DateParser.parse_dates(raw_event["date_string"]) do
    {:ok, dates} ->
      # Success - create event(s) with specific dates
      create_events_with_dates(raw_event, dates, :one_time)

    {:error, :unsupported_date_format} ->
      # Fallback - create single event with unknown type
      Logger.info("📅 Date parsing failed, using unknown occurrence type")
      create_event_with_unknown_dates(raw_event, :unknown)
  end
end

defp create_event_with_unknown_dates(raw_event, occurrence_type) do
  event = %{
    title: raw_event["title"],
    description: raw_event["description"],
    occurrence_type: occurrence_type,
    starts_at: nil,  # NULL for unknown
    ends_at: nil,
    original_date_string: raw_event["date_string"],  # Store raw text
    # ... other fields
  }
  
  {:ok, [event]}  # Return as single-item list
end
```

### 3. Freshness Management

**Query Pattern for Active Events**:
```elixir
# In EventasaurusApp.Events context

def list_active_events(opts \\ []) do
  freshness_threshold = opts[:freshness_days] || 7
  cutoff_date = DateTime.add(DateTime.utc_now(), -freshness_threshold, :day)
  
  from(e in Event,
    left_join: es in EventSource, on: es.event_id == e.id,
    where: 
      # Known dates: check starts_at
      (e.occurrence_type != :unknown and e.starts_at >= ^DateTime.utc_now()) or
      # Unknown dates: check last_seen_at
      (e.occurrence_type == :unknown and es.last_seen_at >= ^cutoff_date)
  )
end
```

**Automatic Staleness**:
- Unknown events not seen in 7+ days automatically hidden
- No manual cleanup needed
- `last_seen_at` updated on every successful scrape
- Events "revive" automatically if seen again

### 4. Event Classification Logic

**Add to EventExtractor** (or keep in Transformer):
```elixir
def classify_occurrence_type(date_string, event_type) do
  cond do
    # Pattern-based (future enhancement)
    date_string =~ ~r/every (monday|tuesday|wednesday)/i ->
      :recurring
    
    # Date range
    date_string =~ ~r/\d{4}\s+to\s+\w+\s+\d+,\s*\d{4}/ ->
      :exhibition
    
    # Specific single date
    date_string =~ ~r/\w+\s+\d+,\s*\d{4}/ ->
      :one_time
    
    # Fallback
    true ->
      :unknown
  end
end
```

---

## UI/UX Impact

### Display Patterns

**1. Event List View**:
```html
<!-- One-time event -->
<div class="event">
  <span class="date">Oct 26, 2025 at 8pm</span>
  <h3>The Hives Concert</h3>
</div>

<!-- Unknown event -->
<div class="event event--unknown">
  <span class="badge">Ongoing</span>
  <span class="date-text">from July 4 to 6, 2025</span>
  <h3>Multitude Biennial</h3>
  <small>Last updated 2 days ago · Check venue for dates</small>
</div>
```

**2. Calendar View**:
- Place one_time and exhibition events on calendar
- Show unknown events in separate "Ongoing Events" section
- Label: "Events with flexible dates"

**3. Search/Filter Options**:
```
☑ All Events (includes unknown)
☐ Upcoming Events (excludes unknown)
☐ Ongoing/Flexible (only unknown)
```

**4. Event Detail Page**:
```
📅 Dates: from July 4 to 6, 2025
ℹ️ This event has flexible dates - check the venue website for details
🔗 [View on Sortiraparis]
```

---

## Benefits

### 1. Zero Data Loss
- **Before**: 15-20% of events completely lost
- **After**: 100% of events saved and discoverable

### 2. Graceful Degradation
- **Before**: All-or-nothing date parsing
- **After**: Store raw text when parsing fails

### 3. Automatic Cleanup
- **Before**: Manual database cleanup needed
- **After**: Events auto-hide when not seen in 7 days

### 4. Better User Experience
- **Before**: Users miss events due to parsing failures
- **After**: Users see all events, interpret dates themselves

### 5. Reduced Maintenance Burden
- **Before**: Add regex pattern for every new date format
- **After**: Unknown fallback handles anything

### 6. Scraper Reliability
- **Before**: 15-20% failure rate
- **After**: Near-zero failure rate

---

## Migration Path

### Phase 1: Schema Migration
1. Add `occurrence_type` column with default 'one_time'
2. Make `starts_at` nullable
3. Add constraints
4. Backfill existing events as 'one_time'

### Phase 2: Transformer Updates
1. Add fallback logic to Sortiraparis.Transformer
2. Test with failing event (Multitude Biennial)
3. Verify bilingual events work with unknown type

### Phase 3: Query Updates
1. Update all queries to respect occurrence_type
2. Add freshness checks for unknown events
3. Update list_active_events/1

### Phase 4: UI Updates
1. Display logic for unknown events
2. Calendar view filtering
3. Search/filter options
4. Event detail page formatting

### Phase 5: Rollout
1. Deploy to staging
2. Monitor scraper success rate (should go from ~85% to ~100%)
3. Verify unknown events display correctly
4. Deploy to production

---

## Metrics & Success Criteria

### Before Implementation
```
Scraper success rate: ~85%
Events lost: ~15-20%
Manual cleanup: Weekly
User complaints: "Missing events on Sortiraparis"
```

### After Implementation
```
Scraper success rate: ~100%
Events lost: 0%
Manual cleanup: None (automatic via last_seen_at)
User complaints: "Some events show flexible dates" (acceptable)
```

### Monitoring Queries

**Check unknown event distribution**:
```sql
SELECT 
    occurrence_type,
    COUNT(*) as event_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
FROM public_events
GROUP BY occurrence_type;
```

**Check staleness of unknown events**:
```sql
SELECT 
    COUNT(*) as unknown_events,
    COUNT(*) FILTER (WHERE es.last_seen_at > NOW() - INTERVAL '7 days') as fresh,
    COUNT(*) FILTER (WHERE es.last_seen_at <= NOW() - INTERVAL '7 days') as stale
FROM public_events e
JOIN public_event_sources es ON e.id = es.event_id
WHERE e.occurrence_type = 'unknown';
```

---

## Alternative Approaches Considered

### Alternative 1: Add More Regex Patterns
**Rejected**: Endless whack-a-mole game. Every source has different formats.

### Alternative 2: Use ML/NLP for Date Parsing
**Rejected**: Overkill. Too complex, too slow, still not 100% accurate.

### Alternative 3: Manual Review Queue
**Rejected**: Doesn't scale. Creates maintenance burden.

### Alternative 4: Skip Unknown Events
**Current behavior**: Loses ~15-20% of data. Unacceptable.

**Selected Approach**: Unknown occurrence type provides graceful fallback with automatic cleanup.

---

## Dependencies & Considerations

### Schema Changes Required
- Migration to add `occurrence_type` column
- Migration to make `starts_at` nullable
- Update constraints

### Affected Components
- All event queries (need occurrence_type awareness)
- Event list/calendar displays
- Search/filter logic
- Transformer logic (all sources, not just Sortiraparis)

### Backward Compatibility
- Existing events default to 'one_time'
- All existing queries continue to work
- New filtering logic is additive

### Future Enhancements
- **Recurring events**: Full support for "Every Tuesday at 7pm"
- **Smart classification**: ML to detect exhibition vs one-time
- **Date suggestions**: "Did you mean July 4-6, 2025?"
- **User feedback**: "Is this date correct?" button

---

## Real-World Examples

### Example 1: Multitude Biennial (Currently Failing)
```
Source: Sortiraparis
URL: .../329086-biennale-multitude-2025
Date String: "from July 4 to 6, 2025"
Current: {:error, :unsupported_date_format} - EVENT LOST
Proposed: occurrence_type: :unknown, display raw text - EVENT SAVED
```

### Example 2: Weekly Yoga Class (Future)
```
Source: Sortiraparis
Date String: "Every Tuesday at 7pm"
Current: Fails or shows one date
Proposed: occurrence_type: :recurring, pattern: {:weekly, :tuesday, "19:00"}
```

### Example 3: Museum Exhibition (Currently Works)
```
Source: Sortiraparis
Date String: "October 15, 2025 to January 19, 2026"
Current: Works - creates exhibition
Proposed: occurrence_type: :exhibition (same behavior)
```

---

## Implementation Checklist

### Database
- [ ] Create migration for occurrence_type enum
- [ ] Make starts_at nullable
- [ ] Add constraints
- [ ] Backfill existing events as 'one_time'
- [ ] Test migration on staging

### Backend
- [ ] Update Event schema with occurrence_type
- [ ] Add fallback logic to Transformer
- [ ] Update list_active_events/1 query
- [ ] Add freshness filtering for unknown type
- [ ] Update tests

### Frontend
- [ ] Display logic for unknown events
- [ ] Calendar view filtering
- [ ] Search filters (All/Upcoming/Ongoing)
- [ ] Event detail page formatting
- [ ] Badges for "Ongoing" events

### Testing
- [ ] Test with Multitude Biennial event
- [ ] Verify bilingual unknown events work
- [ ] Test freshness auto-hiding
- [ ] Test event revival when seen again
- [ ] Load testing with 100+ unknown events

### Documentation
- [ ] Update scraper README
- [ ] Document occurrence_type enum
- [ ] Add examples to transformer docs
- [ ] Update UI/UX guidelines

---

## Conclusion

The Unknown Occurrence Type provides a robust fallback mechanism that:
- ✅ Prevents data loss
- ✅ Maintains user experience
- ✅ Reduces maintenance burden
- ✅ Scales across all event sources
- ✅ Handles edge cases gracefully

**Recommendation**: Implement in Phase 3 of Sortiraparis integration, immediately after fixing critical date patterns.

---

**Related Issues**: 
- #1840 (Sortiraparis time extraction)
- Sortiraparis bilingual assessment
- Date parsing assessment

**References**:
- `SORTIRAPARIS_BILINGUAL_AND_TIME_ASSESSMENT.md`
- `PHASE_1_COMPLETE.md`
- `PHASE_2_COMPLETE.md`

**Estimated Effort**: 8-12 hours
- Schema changes: 2 hours
- Transformer logic: 2-3 hours
- Query updates: 2-3 hours
- UI/UX updates: 2-4 hours
- Testing: 2 hours

**Priority**: HIGH - Prevents 15-20% data loss
