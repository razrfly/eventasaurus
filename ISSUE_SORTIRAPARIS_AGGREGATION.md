# Issue: Sortiraparis Events Incorrectly Aggregated - "2 Dates Available" Display Bug

**Status**: Bug - High Priority
**Severity**: Medium - Affects user experience and event discovery
**Affected Component**: EventProcessor, Event Consolidation System
**Source**: Sortiraparis scraper
**Date Discovered**: 2025-10-18

---

## Problem Summary

Sortiraparis events are being incorrectly aggregated despite having `aggregate_on_index: false` in the source configuration. This causes the UI to display "2 dates available" for events that should appear as separate individual events.

**User Impact**:
- Users see "2 dates available" for most Sortiraparis events when only 1 date exists
- Event browsing experience is confusing and misleading
- Individual event instances are merged when they should remain separate

**Expected Behavior**: Each Sortiraparis event instance should display individually with its own date, not aggregated with an "X dates available" label.

---

## Evidence

### Database Analysis

Query showing aggregated events:
```sql
SELECT
  pe.id,
  pe.title,
  pe.starts_at,
  pe.occurrences,
  pes.external_id
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Sortiraparis'
  AND pe.occurrences IS NOT NULL
LIMIT 5;
```

**Result**: 5+ events have `occurrences` field populated with 2 dates each.

### Example Event (ID: 1716)

```json
{
  "id": 1716,
  "title": "Flops?! Dare, fail, innovate: the funny exhibition unveiled at the Musée des Arts et Métiers",
  "starts_at": "2025-10-13 22:00:00",
  "external_id": "sortiraparis_223291_2025-10-13",
  "occurrences": {
    "type": "explicit",
    "dates": [
      {
        "date": "2025-10-13",
        "time": "22:00",
        "label": "Flops?! Dare, fail, innovate: the funny exhibition unveiled at the Musée des Arts et Métiers",
        "external_id": "sortiraparis_332484_2025-10-13"
      },
      {
        "date": "2026-05-16",
        "time": "22:00",
        "label": "Flops?! Dare, fail, innovate: the funny exhibition unveiled at the Musée des Arts et Métiers",
        "source_id": 14,
        "external_id": "sortiraparis_332484_2026-05-16"
      }
    ]
  }
}
```

**Problem**: This event shows "2 dates available" because `occurrences.dates` has 2 entries, but these should be separate events.

### Distribution Analysis

```sql
SELECT
  substring(pes.external_id from 'sortiraparis_([0-9]+)') as article_id,
  COUNT(*) as event_count,
  COUNT(DISTINCT pe.starts_at) as unique_dates
FROM public_event_sources pes
JOIN public_events pe ON pe.id = pes.event_id
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Sortiraparis'
GROUP BY substring(pes.external_id from 'sortiraparis_([0-9]+)')
ORDER BY event_count DESC
LIMIT 20;
```

**Result**:
- 3 articles have 2 event instances each (legitimate multi-date events in source)
- 85% of events have only 1 instance
- Yet UI shows "2 dates available" for most events

---

## Root Cause Analysis

### Event Flow

1. **Sortiraparis Transformer** (transformer.ex:78-85):
   ```elixir
   # Create separate event for each date
   events =
     Enum.map(dates, fn date ->
       create_event(article_id, title, date, venue_data, raw_event, options)
     end)

   Logger.info("✅ Transformed into #{length(events)} event instance(s): #{title}")
   {:ok, events}
   ```
   - ✅ Creates individual event instances (CORRECT)
   - ✅ Each has unique external_id with date suffix (CORRECT)

2. **EventProcessor** (event_processor.ex:1079-1180):
   - ❌ **BUG LOCATION**: `find_non_movie_recurring_parent` uses fuzzy string matching to find "similar" events
   - ❌ Consolidates events with similar titles at same venue, ignoring `aggregate_on_index: false`
   - ❌ Calls `consolidate_into_parent` which merges events into `occurrences` field
   - **Root Cause**: No check for source's `aggregate_on_index` setting before consolidation

3. **PublicEventsEnhanced** (public_events_enhanced.ex:1085-1091):
   - ✅ Actually **respects** `aggregate_on_index` setting (NOT the bug)
   - ✅ Only aggregates events where `source.aggregate_on_index == true`
   - Note: This was initially suspected but is working correctly

4. **UI Display** (public_event.ex:457-468):
   ```elixir
   def frequency_label(%__MODULE__{} = event) do
     count = occurrence_count(event)

     cond do
       count == 0 -> nil
       count == 1 -> nil
       count <= 7 -> "#{count} dates available"  # ← Shows "2 dates available"
       count <= 30 -> "Multiple dates"
       count <= 60 -> "Daily event"
       true -> "#{count} dates available"
     end
   end
   ```
   - Reads `occurrences.dates` length
   - Shows "2 dates available" when count = 2

### Configuration

**Sortiraparis Config** (sources/sortiraparis/config.ex):
```elixir
aggregate_on_index: false  # ← Should prevent aggregation
```

**Expected Behavior**: Events should NOT be consolidated during processing, should display individually.

**Actual Behavior**: Events ARE being consolidated by EventProcessor during scraping, ignoring this setting.

---

## Technical Details

### Event Consolidation Logic Issue

**The Bug is in EventProcessor, NOT PublicEventsEnhanced**

The `EventProcessor.find_non_movie_recurring_parent/4` function (lines 1079-1180):
1. Uses fuzzy string matching (Jaro distance) to find "similar" events at same venue
2. Consolidates events with similarity > threshold into one event with multiple `occurrences`
3. **Does NOT check** the source's `aggregate_on_index` setting before consolidation
4. This happens during **scraping/processing**, not during display aggregation

**File**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`

### Key Files Involved

1. **Transformer** (`lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex`)
   - Lines 78-85: Creates individual event instances ✅

2. **Config** (`lib/eventasaurus_discovery/sources/sortiraparis/config.ex`)
   - `aggregate_on_index: false` setting (not being respected) ❌

3. **EventProcessor** (`lib/eventasaurus_discovery/scraping/processors/event_processor.ex`) **← BUG LOCATION**
   - Lines 1079-1180: `find_non_movie_recurring_parent/4` - Fuzzy matching consolidation (needs fixing) ❌
   - Lines 1273-1284: `consolidate_into_parent/3` - Merges events into occurrences
   - Lines 1286-1375: `add_occurrence_to_event/2` - Populates occurrences field

4. **PublicEventsEnhanced** (`lib/eventasaurus_discovery/public_events_enhanced.ex`)
   - Lines 1085-1091: `event_aggregatable?/1` - Correctly respects aggregate_on_index ✅

5. **PublicEvent** (`lib/eventasaurus_discovery/public_events/public_event.ex`)
   - Lines 457-468: `frequency_label/1` - Displays "X dates available" based on occurrences
   - Lines 441-445: `occurrence_count/1` - Counts occurrences

---

## Expected vs. Actual Behavior

### Expected (aggregate_on_index: false)

**Database**:
```
Event 1: "Exhibition at Museum" - 2025-10-13 - external_id: sortiraparis_332484_2025-10-13
Event 2: "Exhibition at Museum" - 2026-05-16 - external_id: sortiraparis_332484_2026-05-16
```

**UI Display**:
- Two separate event cards
- Each shows its own single date
- No "dates available" label

### Actual (Bug)

**Database**:
```
Event 1: "Exhibition at Museum" - 2025-10-13 - occurrences: {dates: [2025-10-13, 2026-05-16]}
```

**UI Display**:
- One event card
- Shows "2 dates available" label
- Confusing for users expecting individual events

---

## Solution Options

### Option 1: Check aggregate_on_index in EventProcessor (Recommended)

**Change**: Modify `EventProcessor.find_non_movie_recurring_parent/4` to respect source configuration.

```elixir
defp find_non_movie_recurring_parent(title, venue, external_id, source_id) do
  # Get source configuration
  source = Repo.get(Source, source_id)

  # Skip fuzzy matching consolidation for sources with aggregate_on_index: false
  if source && source.aggregate_on_index == false do
    Logger.debug("⏭️  Skipping consolidation for non-aggregatable source: #{source.name}")
    nil
  else
    # Existing fuzzy matching logic
    clean_title = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(title)
    normalized_title = normalize_for_matching(clean_title)
    # ... continue with fuzzy matching
  end
end
```

**Pros**:
- Fixes the root cause at the source (event processing time)
- Prevents `occurrences` field from being populated incorrectly
- Respects source configuration properly
- Scalable to all sources with `aggregate_on_index: false`

**Cons**:
- Requires database query for source lookup (already happens in processing)
- Need to re-scrape existing events to fix already-consolidated data

---

### Option 2: Pass aggregate_on_index Flag Through Processing

**Change**: Add source configuration to event processing context.

```elixir
# In EventProcessor.process_event/3
defp process_event(event_data, source, venue) do
  # Pass source config to consolidation check
  context = %{
    source_id: source.id,
    aggregate_on_index: source.aggregate_on_index
  }

  parent = find_non_movie_recurring_parent(
    event_data.title,
    venue,
    event_data.external_id,
    context
  )
  # ...
end

# In find_non_movie_recurring_parent/4
defp find_non_movie_recurring_parent(title, venue, external_id, context) do
  if context.aggregate_on_index == false do
    nil  # Skip consolidation
  else
    # Existing fuzzy matching logic
  end
end
```

**Pros**:
- Explicit context passing, no hidden lookups
- Clear data flow through processing pipeline
- Easy to test and reason about

**Cons**:
- More refactoring required across processing functions
- Need to update function signatures

---

### Option 3: Filter by Source in consolidate_into_parent

**Change**: Check source config before consolidation.

```elixir
defp consolidate_into_parent(existing_event, parent_event, data) do
  # Get source for the event being consolidated
  source = Repo.get(Source, data.source_id)

  # Don't consolidate for non-aggregatable sources
  if source && source.aggregate_on_index == false do
    Logger.debug("⏭️  Skipping consolidation for non-aggregatable source")
    {:error, :non_aggregatable_source}
  else
    # Existing consolidation logic
    with {:ok, updated_parent} <- add_occurrence_to_event(parent_event, data),
         {:ok, _source} <- create_occurrence_source_record(parent_event, data) do
      Logger.info("🔄 Consolidated event ##{existing_event.id} into parent ##{parent_event.id}")
      {:ok, updated_parent}
    end
  end
end
```

**Pros**:
- Minimal changes to existing logic flow
- Last-line-of-defense approach

**Cons**:
- Still performs fuzzy matching unnecessarily
- Less efficient (does matching work then discards result)
- Not as clean as preventing consolidation earlier

---

## Recommendations

### Immediate Fix (This Week)

**Option 1**: Add `aggregate_on_index` check to EventProcessor.

**Implementation Steps**:
1. Modify `EventProcessor.find_non_movie_recurring_parent/4` to check source's `aggregate_on_index` setting
2. Skip fuzzy matching consolidation when `aggregate_on_index == false`
3. Add unit tests for the new conditional logic
4. Re-scrape Sortiraparis events to fix existing consolidated data
5. Verify "dates available" label no longer appears for Sortiraparis events

### Long-term Improvement (Next Sprint)

Consider adding more granular aggregation controls:
- Per-source aggregation rules
- Category-based aggregation (e.g., "Exhibitions" aggregate, "Concerts" don't)
- Time-based aggregation rules (e.g., events >30 days apart don't aggregate)

---

## Testing Strategy

### Verification Steps

1. **Check Current State**:
```bash
# Count aggregated Sortiraparis events
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "
SELECT COUNT(*) as aggregated_events
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Sortiraparis'
  AND pe.occurrences IS NOT NULL
  AND jsonb_array_length(pe.occurrences->'dates') > 1;
"
```

2. **After Fix - Verify Separation**:
```bash
# Should return 0 aggregated events
# All Sortiraparis events should have occurrences = null OR single date
```

3. **Test UI Display**:
```bash
# Navigate to Paris events page
# Verify NO "2 dates available" labels appear on Sortiraparis events
curl http://localhost:4000/c/paris
```

### Regression Testing

After implementing fix:
1. Verify other sources (Karnet, Question One) still aggregate correctly
2. Check that `aggregate_on_index: true` sources still show "X dates available"
3. Test that multi-date events from aggregated sources still work
4. Verify no duplicate events appear for Sortiraparis

---

## Impact Analysis

### Current Impact

- **90 Sortiraparis events** in production
- **~20% show "2 dates available"** incorrectly (5+ events with aggregated occurrences)
- **User confusion** about event dates and availability
- **Poor UX** for browsing Paris cultural events

### User Experience Issues

1. **Misleading Labels**: Users see "2 dates available" when only 1 date actually exists for that specific event
2. **Duplicate Confusion**: Same exhibition/event appears to have multiple dates when they're actually different instances
3. **Navigation Issues**: Users may struggle to find the specific date they want

### Similar Sources at Risk

Any future sources with `aggregate_on_index: false` will encounter the same issue:
- Individual event series (like recurring workshops)
- Time-sensitive promotions
- Pop-up events
- Single-showing performances

---

## Related Issues

- Event aggregation system doesn't respect source-level configuration
- No documentation on when/how aggregation should be applied
- UI shows aggregation labels even for non-aggregated sources

---

## Next Steps

1. **Implement**: Add `aggregate_on_index` check to EventProcessor (find_non_movie_recurring_parent function)
2. **Re-scrape**: Re-run Sortiraparis scraper to fix existing consolidated events
3. **Test**: Verify Sortiraparis events display individually without "X dates available" labels
4. **Validate**: Check other sources (Karnet, Question One) still consolidate correctly
5. **Document**: Update EventProcessor documentation about aggregate_on_index handling
6. **Monitor**: Track user feedback on event display and verify data quality improvements

---

## Additional Context

### Why aggregate_on_index Matters

Sources like **Karnet Kraków** (movies) want aggregation:
- Movie "Inception" plays 50 times → Show as "1 movie, 50 showtimes"
- UI: "Daily event" or "Multiple dates"

Sources like **Sortiraparis** (exhibitions/events) want individual display:
- Each exhibition instance is unique → Show each separately
- UI: Individual event cards with single dates

### Configuration Intent

The `aggregate_on_index: false` setting was specifically added to prevent this exact issue, but the aggregation system is not respecting it.
