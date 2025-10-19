# Issue: Sortiraparis DateParser Implementation Audit

**Status**: 🚨 CRITICAL REGRESSION IDENTIFIED  
**Date**: October 18, 2025  
**Implementation Phase**: Post-Phase 5 Integration

---

## Executive Summary

### What We Accomplished ✅
- Implemented robust Parsers.DateParser module with 47 passing tests
- Successfully integrated DateParser into EventExtractor pipeline
- Added ISO format support to Helpers.DateParser for compatibility
- Achieved working end-to-end date parsing for single dates and ranges

### Critical Issues Discovered 🚨

#### 1. **TIME REGRESSION - ALL EVENTS AT MIDNIGHT** (SEVERITY: CRITICAL)
**User's Exact Concern**: "all the events are now saying 12 a.m. Again, our main branch worked fine. So the fact that we have fucked up the time that can't all be 12 a.m. This is bullshit."

**Evidence**:
```sql
-- 100% of Sortiraparis events have midnight times
hour | event_count
-----|-------------
  22 |          34  (10pm UTC = 00:00 Paris time)
  23 |           3  (11pm UTC = 00:00 Paris time)
```

**Root Cause**: Time information is stripped during date normalization.

**Data Flow Showing Problem**:
```
BEFORE implementation:
HTML → EventExtractor → "Sunday 26 October 2025 at 8pm" (hypothetical)
                     → Helpers.DateParser → DateTime with proper time

AFTER implementation:
HTML → EventExtractor → Parsers.DateParser → "2025-10-26" (NO TIME!)
                     → Helpers.DateParser → DateTime with 00:00:00 (midnight)
```

**Technical Details**:
- `Parsers.DateParser.extract_date_components/1` only extracts `day`, `month`, `year`
- NO time extraction implemented in Phase 1-2
- ISO normalization: `"#{year}-#{month}-#{day}"` (no time component)
- `Helpers.DateParser.parse_iso_date/2` calls `create_datetime(year, month, day, 0, 0, options)`
- Hardcoded zeros for hour and minute → 00:00:00 for ALL events

**Impact**: Every single Sortiraparis event in the database shows midnight start time, which is incorrect and breaks user expectations.

#### 2. **CATEGORY DEGRADATION** (SEVERITY: HIGH)
**User's Concern**: "we're starting to get a lot of other so I don't know if we changed anything with categorization"

**Evidence**:
```sql
-- ALL events have NULL category_id
category | event_count
---------|-------------
(null)   |          40
```

**Analysis**: This is NOT related to our DateParser changes. Category assignment logic exists elsewhere in the pipeline (likely in Transformer or event creation), but categorization appears completely broken for Sortiraparis events.

#### 3. **LANGUAGE COVERAGE** (SEVERITY: MEDIUM - ACCEPTABLE)
**User's Concern**: "are we getting both languages French and English"

**Evidence**:
```sql
language | event_count
---------|-------------
English  |          28 (68%)
Unknown  |           8 (20%)
French   |           5 (12%)
```

**Analysis**:
- ✅ We ARE getting both French and English events
- ✅ DateParser handles both languages (verified in tests)
- ⚠️ French events are underrepresented (12% vs expected ~50%)
- ⚠️ 8 "Unknown" events need investigation

---

## Implementation Grade: C-

### Grades by Component

| Component | Grade | Justification |
|-----------|-------|---------------|
| **Parsers.DateParser** | A | Excellent implementation with 47 passing tests, robust multilingual support, comprehensive edge case handling |
| **Integration (EventExtractor)** | B | Clean integration, proper fallback handling, but introduced critical time regression |
| **Helpers.DateParser Update** | B+ | Successfully added ISO format support, but didn't consider time preservation |
| **Overall Impact** | D | Working date parsing but **critical time regression** affects 100% of events |

---

## Detailed Analysis

### What Works ✅

#### 1. Date Parsing Accuracy
```elixir
# Successfully handles:
parse("15 October 2025")                    → {:ok, ~D[2025-10-15]}
parse("Du 15 octobre au 19 janvier 2026")   → {:ok, %{start_date: ..., end_date: ...}}
parse("Sunday 26 October 2025")             → {:ok, ~D[2025-10-26]}
```

#### 2. Multilingual Support
- ✅ English month names: January, February, March...
- ✅ French month names: janvier, février, mars...
- ✅ Both language date formats parsed correctly
- ✅ 47/47 test cases passing

#### 3. Error Handling
- ✅ Graceful fallback to original text on parse failure
- ✅ No job crashes (improvement over pre-implementation)
- ✅ Proper error propagation with `:unsupported_date_format`

#### 4. Integration Architecture
```
HTML → EventExtractor → Parsers.DateParser → ISO format →
    → Transformer → Helpers.DateParser → UTC DateTime → Database
```

Clean separation of concerns with proper data flow.

### What's Broken 🚨

#### 1. Time Information Loss (CRITICAL)

**Problem Location**: `lib/eventasaurus_discovery/sources/sortiraparis/parsers/date_parser.ex:82-106`

```elixir
# Current implementation
defp extract_date_components(text) do
  # Only extracts day, month, year - NO TIME!
  %{
    day: extract_day(text),
    month: extract_month(text),
    year: extract_year(text)
  }
end

defp normalize_to_iso(%{day: day, month: month, year: year}) do
  # Creates date-only string: "2025-10-26"
  # No time component
  "#{year}-#{String.pad_leading(Integer.to_string(month), 2, "0")}-#{String.pad_leading(Integer.to_string(day), 2, "0")}"
end
```

**Fix Required**:
1. Add time extraction to `extract_date_components/1`
2. Modify ISO format to include time: `"2025-10-26T20:00:00"`
3. Update `Helpers.DateParser.parse_iso_date/2` to parse time component

#### 2. Category Assignment Failure (HIGH)

**Not related to DateParser**, but discovered during audit.

**Evidence**: 40/40 events have `category_id = NULL`

**Investigation Required**:
- Check `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex` category logic
- Review category mapping configuration
- Verify category lookup/assignment in event creation

#### 3. French Event Underrepresentation (MEDIUM)

**Evidence**: Only 12% French events vs expected ~50%

**Possible Causes**:
- Scraper config preferring English URLs
- Bilingual mode not properly configured
- French articles not being discovered during sync

**Investigation Required**:
- Check `lib/eventasaurus_discovery/sources/sortiraparis/client.ex` bilingual fetching
- Review sync job configuration for language balance
- Audit article discovery logic

---

## Recommendations

### Immediate Actions Required (This Sprint)

#### 1. Fix Time Regression (CRITICAL - DO FIRST)
**Estimated Effort**: 2-4 hours

**Steps**:
1. Add time extraction to `Parsers.DateParser`:
   ```elixir
   defp extract_time_components(text) do
     # Extract "8pm", "20:00", "8:30 PM", etc.
     # Return {hour, minute} or nil
   end
   ```

2. Update ISO format to ISO 8601 with time:
   ```elixir
   "2025-10-26T20:00:00"  # Instead of just "2025-10-26"
   ```

3. Update `Helpers.DateParser.parse_iso_date/2`:
   ```elixir
   # Parse: "2025-10-26T20:00:00"
   case Regex.run(~r/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}):(\d{2}))?$/, date_string) do
     [_, year, month, day, hour, minute, _] -> ...
     [_, year, month, day] -> ... # Fallback to midnight
   end
   ```

4. Add comprehensive time tests to `date_parser_test.exs`

**Verification**:
```bash
# After fix, check database:
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "
SELECT EXTRACT(HOUR FROM starts_at), COUNT(*)
FROM public_events e
JOIN public_event_sources pes ON e.id = pes.event_id
WHERE pes.source_id = 14
GROUP BY EXTRACT(HOUR FROM starts_at);"

# Should see variety of hours, not just 22/23
```

#### 2. Investigate Category Assignment (HIGH)
**Estimated Effort**: 1-2 hours

1. Review `Transformer.transform_event/1` category logic
2. Check if category mapping exists for Sortiraparis events
3. Verify category lookup in database
4. Add logging to track category assignment decisions

#### 3. Audit French Event Coverage (MEDIUM)
**Estimated Effort**: 1 hour

1. Check bilingual mode configuration in Client
2. Review sync job article discovery
3. Verify French article URLs are being processed

### Future Enhancements (Next Sprint)

#### 1. Implement Phase 3: Multi-Date Patterns
**Estimated Effort**: 3-4 hours

Currently deferred. Handle patterns like:
- "February 25, 27, 28, 2026" → Multiple separate events
- "Every Friday in October" → Recurring series

#### 2. Add Time Zone Awareness
**Estimated Effort**: 2-3 hours

- Store original timezone with events
- Handle DST transitions properly
- Support events in non-Paris timezones

#### 3. Improve Error Reporting
**Estimated Effort**: 1-2 hours

- Log unparseable date formats for analysis
- Track parsing success rate metrics
- Alert on significant parsing failures

---

## Testing Status

### Current Test Coverage
```
✅ 47/47 Parsers.DateParser tests passing
✅ Integration tests verified (manual)
✅ End-to-end pipeline working (with time issue)
```

### Missing Test Coverage
```
❌ Time extraction tests
❌ ISO 8601 with time tests
❌ Category assignment tests
❌ Bilingual scraping tests
```

---

## Decision: Can We Move On?

### Answer: **NO - MUST FIX TIME REGRESSION FIRST**

**Rationale**:
1. **Time information is critical** - Users expect accurate event times
2. **100% impact rate** - Every single event is affected
3. **User frustration** - "This is bullshit" indicates severity
4. **Data quality** - Midnight for all events is obviously wrong

**Blocking Issues**:
- 🚨 Time regression (CRITICAL - MUST FIX)
- ⚠️ Category assignment (HIGH - SHOULD FIX)

**Non-Blocking Issues**:
- ℹ️ French event coverage (MEDIUM - CAN DEFER)
- ℹ️ Phase 3 multi-date (LOW - CAN DEFER)

### Recommendation
**Fix time regression immediately** (2-4 hours), then reassess whether category issue is blocking or can be tracked separately.

---

## Comparison: Before vs After

### Before DateParser Implementation
```
✅ Times: Preserved from HTML (if present)
❌ Dates: Fragile regex patterns, many failures
❌ French: Limited support, inconsistent
❌ Ranges: Manual parsing, error-prone
```

### After DateParser Implementation
```
✅ Dates: Robust, multilingual, tested
✅ French: Full support, comprehensive
✅ Ranges: Clean handling, proper structure
❌ Times: REGRESSION - all midnight (CRITICAL)
❌ Categories: Not working (unrelated issue)
```

---

## Files Modified

### Primary Implementation
1. `lib/eventasaurus_discovery/sources/sortiraparis/parsers/date_parser.ex` (NEW - 299 lines)
2. `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex` (MODIFIED - lines 315-387)
3. `lib/eventasaurus_discovery/sources/sortiraparis/helpers/date_parser.ex` (MODIFIED - added lines 82-159)

### Test Files
4. `test/eventasaurus_discovery/sources/sortiraparis/parsers/date_parser_test.exs` (NEW - 47 tests)

### Investigation Files (Temporary)
5. `test_helpers_date_parser.exs`
6. `test_full_pipeline.exs`
7. `debug_failing_article.exs`
8. `test_date_parser_integration.exs`

---

## Conclusion

**Grade: C-**

We successfully built a **robust, well-tested date parsing system** that handles multiple languages and date formats excellently. However, we introduced a **critical regression** that affects 100% of events by stripping time information.

The implementation is **NOT production-ready** until the time regression is fixed. The fix is straightforward and estimated at 2-4 hours.

**Recommendation**: Fix time extraction immediately, verify with database audit, then reassess readiness for production deployment.

---

## Appendix: Database Audit Queries

### Time Distribution
```sql
-- Shows ALL events at midnight
SELECT
    EXTRACT(HOUR FROM e.starts_at) as hour,
    COUNT(*) as event_count
FROM public_events e
JOIN public_event_sources pes ON e.id = pes.event_id
WHERE pes.source_id = 14
GROUP BY EXTRACT(HOUR FROM e.starts_at)
ORDER BY event_count DESC;
```

### Category Distribution
```sql
-- Shows ALL events have NULL category
SELECT
    c.name as category,
    COUNT(*) as event_count
FROM public_events e
JOIN public_event_sources pes ON e.id = pes.event_id
LEFT JOIN categories c ON e.category_id = c.id
WHERE pes.source_id = 14
GROUP BY c.name
ORDER BY event_count DESC;
```

### Language Distribution
```sql
-- Shows 68% English, 12% French, 20% Unknown
SELECT
    CASE
        WHEN source_url LIKE '%/en/%' THEN 'English'
        WHEN source_url LIKE '%/scenes/%' OR source_url LIKE '%/actualites/%' THEN 'French'
        ELSE 'Unknown'
    END as language,
    COUNT(*) as event_count
FROM public_event_sources
WHERE source_id = 14
GROUP BY language
ORDER BY event_count DESC;
```

### Sample Events
```sql
-- Shows recent events with midnight times
SELECT
    e.id,
    e.title,
    e.starts_at,
    EXTRACT(HOUR FROM e.starts_at) as hour,
    e.inserted_at
FROM public_events e
JOIN public_event_sources pes ON e.id = pes.event_id
WHERE pes.source_id = 14
ORDER BY e.inserted_at DESC
LIMIT 10;
```
