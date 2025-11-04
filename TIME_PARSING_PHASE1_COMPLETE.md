# Phase 1 Complete: Time Parsing Consolidation

## Summary

Successfully migrated GeeksWhoDrink and QuestionOne scrapers to use the shared `RecurringEventParser`, eliminating ~400 lines of duplicate code and improving maintainability.

## Changes Made

### 1. GeeksWhoDrink Migration

**Files Modified:**
- `lib/eventasaurus_discovery/sources/geeks_who_drink/transformer.ex`
  - Updated to use `RecurringEventParser` with `America/New_York` timezone
  - Modified `parse_schedule_to_recurrence/3` to extract day/time from starts_at DateTime
  - Updated `fallback_parse_time_text/2` to use separate `parse_day_of_week` and `parse_time` functions

- `lib/eventasaurus_discovery/sources/geeks_who_drink/jobs/venue_detail_job.ex`
  - Removed `TimeParser` alias
  - Updated `calculate_next_occurrence/2` to use `RecurringEventParser.next_occurrence/3`

**Files Deleted:**
- `lib/eventasaurus_discovery/sources/geeks_who_drink/helpers/time_parser.ex` (~208 lines)

**Tests Fixed:**
- `test/eventasaurus_discovery/sources/geeks_who_drink/transformer_test.exs`
  - Added `timezone: "America/New_York"` to all test cases
  - Fixed date/time alignment (changed to October 14, 2025 which is actually a Tuesday)
  - Fixed UTC time conversion (23:00 UTC = 19:00 EDT)
  - **Result: 10 tests passing, 0 failures ✅**

### 2. QuestionOne Migration

**Files Modified:**
- `lib/eventasaurus_discovery/sources/question_one/transformer.ex`
  - Updated to use `RecurringEventParser` with `Europe/London` timezone
  - Modified `parse_schedule_to_recurrence/1` to use separate parsing functions
  - Updated `parse_time_data/1` to use `RecurringEventParser` API
  - Added default country "United Kingdom" for UK-specific source

**Files Deleted:**
- `lib/eventasaurus_discovery/sources/question_one/helpers/date_parser.ex` (~208 lines)

**Tests Fixed:**
- `test/eventasaurus_discovery/sources/question_one/transformer_test.exs`
  - **Result: 4 tests passing, 0 failures ✅**

## Code Reduction

- **Total Lines Eliminated**: ~416 lines
- **Duplicate Functions Removed**:
  - `parse_time_text/1` (duplicated across both scrapers)
  - `parse_day_of_week/1` (duplicated across both scrapers)
  - `parse_time/1` (duplicated across both scrapers)
  - `next_occurrence/3` (duplicated across both scrapers)

## Benefits

1. **Single Source of Truth**: All recurring event time parsing now uses `RecurringEventParser`
2. **Maintainability**: Bug fixes and improvements only need to be made in one place
3. **Consistency**: Both scrapers now follow the same parsing patterns
4. **Timezone Support**: Proper timezone handling with parameterized timezone values
5. **Test Coverage**: Shared helper has comprehensive tests that benefit all scrapers

## API Changes

The `RecurringEventParser` uses a different API than the old duplicate parsers:

**Old API (TimeParser/DateParser):**
```elixir
{:ok, {day, time}} = TimeParser.parse_time_text("Tuesdays at 7pm")
```

**New API (RecurringEventParser):**
```elixir
{:ok, day} = RecurringEventParser.parse_day_of_week("Tuesdays at 7pm")
{:ok, time} = RecurringEventParser.parse_time("Tuesdays at 7pm")
```

This change required updating all callsites to use the separate functions rather than the combined one.

## Timezone Handling

Both scrapers now properly handle timezones:

- **GeeksWhoDrink**: Uses `America/New_York` timezone (dynamic timezone detection via TzWorld in VenueDetailJob)
- **QuestionOne**: Uses `Europe/London` timezone (UK-specific source)

The `RecurringEventParser.next_occurrence/3` function accepts a timezone parameter and returns a DateTime in UTC that represents the next occurrence in that timezone.

## Related Issue

See GitHub Issue #2151 for the original analysis that led to this refactoring.

## Next Steps (Phase 2 - Optional)

Phase 2 will focus on Polish date parsing consolidation:

1. Evaluate migrating Karnet to use `MultilingualDateParser`
2. Evaluate migrating KinoKrakow to use `MultilingualDateParser`
3. Potential code reduction: ~200-300 lines
4. Risk: MEDIUM (Polish parsing has more complexity than recurring events)

---

**Status**: ✅ Phase 1 Complete
**Tests**: ✅ All passing (14 tests, 0 failures)
**Code Quality**: ✅ No regressions
**Ready for**: Phase 2 or other work
