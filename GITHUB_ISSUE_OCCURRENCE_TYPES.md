# Fix Occurrence Type Distribution: Metadata vs. Database Field Disconnect

## Problem Summary

The occurrence type distribution on the admin discovery stats page (e.g., `/admin/discovery/stats/source/sortiraparis`) is showing **100% "explicit"** when it should show a diverse distribution of event types. This is caused by a **disconnect between where occurrence types are stored vs. where they are read from**.

### Current Incorrect Behavior
- **All sortiraparis events** show as "explicit" type in the stats dashboard
- **Actual distribution (hidden in metadata)**: 95.5% exhibition, 1.5% one_time, 1.5% recurring, 1.5% unknown

### Root Cause
1. **Sortiraparis transformer** correctly stores `occurrence_type` in `public_event_sources.metadata` JSONB field
2. **Event processor** ignores this metadata and only creates two occurrence types in `public_events.occurrences`:
   - `"pattern"` - if event has `recurrence_rule`
   - `"explicit"` - for everything else (default)
3. **Stats dashboard** reads from `public_events.occurrences->>'type'`, not from metadata
4. **Result**: All metadata occurrence types are lost when displaying stats

## Evidence from Database Analysis

```sql
-- Query showing the disconnect
SELECT
  pes.metadata->>'occurrence_type' as metadata_occurrence_type,
  pe.occurrences->>'type' as occurrences_type,
  COUNT(*) as count
FROM public_event_sources pes
JOIN public_events pe ON pe.id = pes.event_id
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis'
GROUP BY metadata_occurrence_type, occurrences_type;
```

**Result**:
| Metadata Type | Occurrences Type | Count |
|---------------|------------------|-------|
| exhibition    | explicit         | 64    |
| one_time      | explicit         | 1     |
| recurring     | explicit         | 1     |
| unknown       | explicit         | 1     |

**Total**: 67 events, all showing as "explicit" in stats despite having diverse types in metadata.

### System-Wide Analysis

Across the entire database, only 2 occurrence types exist in the `occurrences` field:
- **"explicit"**: 473 events (includes all sortiraparis events)
- **"pattern"**: 213 events (recurring events with recurrence_rule)

**Missing types**: "unknown", "exhibition", "movie", "one_time" (all defined in UI but never created)

## Related Work

- **Issue #1842**: Original plan to implement occurrence types in metadata (✅ COMPLETED in transformer)
- **Sortiraparis README**: Documents occurrence type fallback (lines 220-226, 383)
- **Implementation Status**:
  - ✅ Transformer stores occurrence_type in metadata
  - ❌ Event processor doesn't read metadata
  - ❌ Stats dashboard shows incorrect distribution

## Impact

### User-Facing Issues
1. **Misleading statistics**: Cannot distinguish between event types (exhibitions vs one-time vs unknown)
2. **Loss of semantic meaning**: "Unknown" events (unparseable dates) appear identical to confirmed date events
3. **Poor UX**: Users cannot filter or understand event type distribution
4. **Trust erosion**: Dashboard appears broken when showing 100% of one type

### Developer Issues
1. **Wasted effort**: Transformer correctly classifies events but data is ignored
2. **Maintenance confusion**: Two sources of truth (metadata vs occurrences field)
3. **Dead code**: UI defines colors/emojis for types that never appear

## Technical Details

### Files Involved

**Storing occurrence_type (Working ✅)**:
- `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex:300-306, 357-364, 423-428, 480-486`
  - Correctly stores `occurrence_type` in metadata for all event types

**Ignoring occurrence_type (Bug ❌)**:
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:343-381`
  - `initialize_occurrence_with_source/1` only checks for `recurrence_rule`
  - Never reads `occurrence_type` from metadata or `event_type` field
  - Creates only "pattern" or "explicit" types

**Reading occurrence_type (Wrong field ❌)**:
- `lib/eventasaurus_discovery/admin/source_stats_collector.ex:39-60`
  - Queries `pe.occurrences->>'type'` instead of metadata
- `lib/eventasaurus_web/live/admin/discovery_stats_live/source_detail.ex:265, 1046-1086`
  - Displays data from occurrences field, not metadata

### Occurrence Type Taxonomy

Based on code analysis and issue #1842, we have these occurrence types:

| Type | Description | Use Case | Currently Working? |
|------|-------------|----------|-------------------|
| **explicit** | Single specific date/time | Concerts, one-off performances | ✅ Yes |
| **pattern** | Recurrence rule (weekly/monthly) | Quiz nights, recurring events | ✅ Yes |
| **exhibition** | Open-ended period, continuous access | Museums, galleries | ❌ Stored in metadata only |
| **movie** | Movie showtimes (Kino Krakow pattern) | Cinema schedules | ❌ Never implemented |
| **recurring** | Recurring without strict pattern | "Every weekend", "Daily in summer" | ❌ Stored in metadata only |
| **unknown** | Unparseable/ambiguous dates | "TBA", "Coming soon", "Spring 2025" | ❌ Stored in metadata only |

## Proposed Solution

### Phase 1: Data Audit & Collection Strategy ⏱️ ~2 hours

**Objective**: Understand current state across all sources and gather enough data to validate the approach.

**Tasks**:
1. **Audit all scrapers** for occurrence_type usage:
   ```sql
   SELECT
     s.slug as source,
     pes.metadata->>'occurrence_type' as type,
     COUNT(*) as count
   FROM public_event_sources pes
   JOIN sources s ON s.id = pes.source_id
   WHERE pes.metadata->>'occurrence_type' IS NOT NULL
   GROUP BY s.slug, type
   ORDER BY source, count DESC;
   ```

2. **Identify patterns** in event_type field from extractors:
   ```sql
   SELECT
     s.slug as source,
     pes.metadata->>'event_type' as type,
     COUNT(*)
   FROM public_event_sources pes
   JOIN sources s ON s.id = pes.source_id
   GROUP BY source, type;
   ```

3. **Sample unknown events** to validate classification:
   - Get 50 events with `occurrence_type = "unknown"` in metadata
   - Manually verify date strings are indeed unparseable
   - Check if first_seen_at timestamp strategy works

4. **Document findings** in a data audit report with:
   - Current distribution across all sources
   - Validation of classification accuracy
   - Edge cases and misclassifications
   - Recommendations for phase 2

**Deliverables**:
- SQL audit script
- Data audit report (CSV/MD)
- Classification accuracy metrics
- Go/No-Go decision for phase 2

### Phase 2: Event Processor Enhancement ⏱️ ~4 hours

**Objective**: Make event processor read occurrence_type from metadata and create correct occurrences structure.

**Implementation**:

1. **Update `event_processor.ex:initialize_occurrence_with_source/1`**:
   ```elixir
   defp initialize_occurrence_with_source(data) do
     # NEW: Read occurrence_type from metadata or event_type field
     occurrence_type = get_occurrence_type(data)

     case occurrence_type do
       # Existing pattern logic (recurrence_rule)
       type when type in [:pattern, "pattern"] ->
         %{"type" => "pattern", "pattern" => data.recurrence_rule}

       # Exhibition events (museums, galleries)
       type when type in [:exhibition, "exhibition"] ->
         %{"type" => "exhibition", "dates" => [create_date_entry(data)]}

       # Movie showtimes (cinema pattern)
       type when type in [:movie, "movie"] ->
         %{"type" => "movie", "dates" => [create_date_entry(data)]}

       # Unknown/unparseable dates
       type when type in [:unknown, "unknown"] ->
         %{
           "type" => "unknown",
           "first_seen_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
           "original_date_string" => data[:original_date_string] || data["original_date_string"]
         }

       # Recurring without strict pattern
       type when type in [:recurring, "recurring"] ->
         %{
           "type" => "recurring",
           "dates" => [create_date_entry(data)],
           "pattern_description" => data[:recurrence_pattern] || "Recurring event"
         }

       # Default: explicit (one-time with specific date)
       _ ->
         %{"type" => "explicit", "dates" => [create_date_entry(data)]}
     end
   end

   # NEW: Helper to get occurrence_type from metadata or event_type field
   defp get_occurrence_type(data) do
     cond do
       # Check recurrence_rule first (highest priority)
       data.recurrence_rule -> :pattern

       # Check metadata occurrence_type (from transformer)
       data[:metadata] && data[:metadata]["occurrence_type"] ->
         data[:metadata]["occurrence_type"]

       data["metadata"] && data["metadata"]["occurrence_type"] ->
         data["metadata"]["occurrence_type"]

       # Check event_type field (from extractor)
       data[:event_type] -> data[:event_type]
       data["event_type"] -> data["event_type"]

       # Default to explicit
       true -> :explicit
     end
   end

   defp create_date_entry(data) do
     entry = %{
       "date" => format_date_only(data.start_at),
       "time" => format_time_only(data.start_at),
       "external_id" => data.external_id
     }

     # Add label if available
     if data.title && String.trim(data.title) != "" do
       Map.put(entry, "label", data.title)
     else
       entry
     end
   end
   ```

2. **Backward Compatibility**:
   - Existing events with "explicit" type remain unchanged
   - New events get correct type from metadata
   - Run data migration script (optional) to backfill existing events

3. **Testing**:
   - Unit tests for all occurrence types
   - Integration test with sortiraparis events
   - Verify stats dashboard shows correct distribution

**Deliverables**:
- Updated event_processor.ex with tests
- Data migration script (optional)
- Validation that existing events still work

### Phase 3: Stats Query Updates ⏱️ ~2 hours

**Objective**: Update stats dashboard to handle all occurrence types correctly.

**Implementation**:

1. **Update `source_stats_collector.ex:get_occurrence_type_distribution/1`**:
   - Query already correct (reads from occurrences->>'type')
   - Will automatically show new types once phase 2 completes

2. **Update `source_detail.ex:format_occurrence_pie_chart/1`**:
   ```elixir
   defp format_occurrence_pie_chart(occurrence_types) do
     colors = %{
       "explicit" => "#3B82F6",     # Blue - Specific dates
       "pattern" => "#8B5CF6",      # Purple - Strict recurrence
       "exhibition" => "#EC4899",   # Pink - Continuous access
       "movie" => "#F59E0B",        # Amber - Cinema showtimes
       "recurring" => "#10B981",    # Green - Loose recurrence
       "unknown" => "#6B7280"       # Gray - Unparseable dates
     }

     # ... rest of chart formatting
   end
   ```

3. **Update occurrence type emojis** (line 658-665):
   ```elixir
   <%= case occurrence.type do %>
     <% "explicit" -> %>🎯
     <% "pattern" -> %>🔄
     <% "exhibition" -> %>🖼️
     <% "movie" -> %>🎬
     <% "recurring" -> %>📅
     <% "unknown" -> %>❓
     <% _ -> %>❓
   <% end %>
   ```

**Deliverables**:
- Updated UI with all occurrence types
- Visual regression tests
- Screenshot showing correct distribution

### Phase 4: Documentation & Rollout ⏱️ ~2 hours

**Objective**: Update documentation and ensure all scrapers follow the pattern.

**Tasks**:

1. **Update Scraper Specification**:
   - Document occurrence_type field in metadata
   - Provide examples for each type
   - Update template transformer

2. **Update Sortiraparis README**:
   - Confirm occurrence type documentation is accurate (already exists lines 220-226)
   - Add examples showing metadata flow to occurrences field

3. **Create Scraper Checklist**:
   ```markdown
   ## Occurrence Type Implementation Checklist

   - [ ] Extractor classifies events into types (one_time, exhibition, recurring, unknown)
   - [ ] Transformer stores `occurrence_type` in metadata
   - [ ] Transformer sets `event_type` field for processor
   - [ ] Unknown events store `original_date_string` in metadata
   - [ ] Unknown events use first_seen_at as starts_at
   - [ ] Tests verify correct occurrence type in database
   - [ ] Stats dashboard shows correct distribution
   ```

4. **Update Other Scrapers**:
   - Audit Karnet (movie showtimes - should use "movie" type)
   - Audit Kino Krakow (movie showtimes - should use "movie" type)
   - Audit PubQuiz family (should already use "pattern" via recurrence_rule)

**Deliverables**:
- Updated scraper specification
- Scraper implementation checklist
- Audit report for other scrapers

## Data Migration Strategy (Optional)

If we want to backfill existing sortiraparis events:

```sql
-- Dry run: Show what would change
SELECT
  pe.id,
  pe.title,
  pe.occurrences->>'type' as current_type,
  pes.metadata->>'occurrence_type' as metadata_type
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis'
  AND pe.occurrences->>'type' != pes.metadata->>'occurrence_type'
LIMIT 10;

-- Migration: Update occurrences field from metadata
-- WARNING: Test on staging first!
UPDATE public_events pe
SET occurrences = jsonb_set(
  pe.occurrences,
  '{type}',
  to_jsonb(pes.metadata->>'occurrence_type')
)
FROM public_event_sources pes
JOIN sources s ON s.id = pes.source_id
WHERE pe.id = pes.event_id
  AND s.slug = 'sortiraparis'
  AND pes.metadata->>'occurrence_type' IS NOT NULL
  AND pe.occurrences->>'type' = 'explicit';
```

## Open Questions

1. **Terminology**: Is "unknown" the right term for unparseable dates, or should we use "flexible", "ongoing", "open_ended"?

2. **Exhibition behavior**: Should exhibitions use `starts_at` as first date or first_seen_at? Currently using first date from range.

3. **Unknown event visibility**: Should events with `occurrence_type = "unknown"` auto-hide after 7 days if not re-seen, or stay visible indefinitely?

4. **Backwards compatibility**: Should we migrate existing events or only apply to new events going forward?

5. **Movie type usage**: Should Karnet and Kino Krakow switch from article_id consolidation to movie_id consolidation with "movie" occurrence type?

6. **Recurring vs Pattern**: What's the distinction? Should "recurring" be merged into "pattern"?

## Success Metrics

### Quantitative
- ✅ Sortiraparis stats show ~95% exhibition, ~5% other types (not 100% explicit)
- ✅ All occurrence types visible in database and UI
- ✅ Zero data loss from unparseable dates (unknown type captures them)
- ✅ Stats dashboard load time <500ms (no performance regression)

### Qualitative
- ✅ Stats dashboard accurately reflects event type distribution
- ✅ Developers can distinguish event types in queries
- ✅ Users understand what each occurrence type means
- ✅ Documentation is clear and complete

## Timeline Estimate

- **Phase 1** (Data Audit): 2 hours
- **Phase 2** (Event Processor): 4 hours
- **Phase 3** (Stats Updates): 2 hours
- **Phase 4** (Documentation): 2 hours
- **Testing & QA**: 2 hours
- **Total**: ~12 hours (~1.5 days)

## Next Steps

1. **Review this proposal** and answer open questions
2. **Run Phase 1 data audit** to validate assumptions
3. **Create sub-issues** for each phase
4. **Assign to developer** for implementation
5. **Set up staging testing environment** for validation

## Related Issues

- #1842 - Original occurrence type implementation (transformer complete, processor incomplete)
- [New Issue] - Sortiraparis stats showing incorrect distribution (this issue)

---

**Labels**: `bug`, `enhancement`, `sortiraparis`, `stats-dashboard`, `occurrence-types`, `good-first-issue` (Phase 1 only)

**Priority**: High (affects data quality and user trust in stats dashboard)

**Assignee**: TBD

**Milestone**: Q1 2025 - Data Quality Improvements
