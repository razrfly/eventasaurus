# Phase 2 Complete: Polish Date Parsing Consolidation

## Summary

Successfully migrated KinoKrakow scraper to use the shared `MultilingualDateParser`, eliminating ~175 lines of duplicate Polish date parsing code. Karnet scraper was evaluated but excluded from Phase 2 due to format incompatibility requiring enhancements to MultilingualDateParser.

## Changes Made

### 1. KinoKrakow Migration ✅

**Files Modified:**
- `lib/eventasaurus_discovery/sources/kino_krakow/extractors/showtime_extractor.ex`
  - Updated alias from `KinoKrakow.DateParser` to `MultilingualDateParser`
  - Modified `parse_datetime/2` to combine date and time strings
  - Delegated to `MultilingualDateParser.extract_and_parse/2` with Polish language support
  - Uses `Europe/Warsaw` timezone for proper UTC conversion

**Files Deleted:**
- `lib/eventasaurus_discovery/sources/kino_krakow/date_parser.ex` (~175 lines)
- `test/eventasaurus_discovery/sources/kino_krakow/date_parser_test.exs` (~50 lines)

**Tests Verified:**
- `test/eventasaurus_discovery/sources/kino_krakow/`
  - **Result: 10 tests passing, 0 failures ✅**

### 2. Karnet Evaluation (Not Migrated) ⚠️

**Analysis Results:**
- Karnet uses **DD.MM.YYYY format** (e.g., "04.09.2025, 18:00")
- This format is **NOT supported** by MultilingualDateParser's Polish plugin
- MultilingualDateParser expects textual Polish dates (e.g., "4 września 2025")

**Decision Rationale:**
- **Risk Level**: MEDIUM-HIGH
- **Required Work**: Would need to enhance MultilingualDateParser first to support DD.MM.YYYY format
- **Recommendation**: Keep Karnet using its custom parser OR enhance MultilingualDateParser in a future phase
- **Benefit**: Low (Karnet is one specialized source, format handling is already stable)

**Karnet-Specific Features Not in MultilingualDateParser:**
- DD.MM.YYYY numeric date format
- Date range parsing for this format (e.g., "04.09.2025 - 09.10.2025")
- Mixed format support (both numeric and textual dates)

## Code Reduction

- **Total Lines Eliminated**: ~225 lines
  - KinoKrakow DateParser: ~175 lines
  - KinoKrakow DateParser tests: ~50 lines

## Benefits

1. **Reduced Duplication**: KinoKrakow now shares Polish date parsing logic with MultilingualDateParser
2. **Maintainability**: Bug fixes to Polish date parsing benefit all sources using MultilingualDateParser
3. **Consistency**: KinoKrakow now follows the same parsing patterns as other sources
4. **Test Coverage**: Leverages comprehensive tests in MultilingualDateParser's Polish plugin
5. **Risk Mitigation**: Avoided high-risk Karnet migration that would require parser enhancements

## Implementation Details

### KinoKrakow Migration Pattern

**Old API (KinoKrakow.DateParser):**
```elixir
case DateParser.parse_datetime(date_str, time_str) do
  %DateTime{} = datetime -> datetime
  nil -> nil
end
```

**New API (MultilingualDateParser):**
```elixir
defp parse_datetime(date_str, time_str) when is_binary(date_str) and is_binary(time_str) do
  # Combine date and time into single string
  # E.g., "środa, 1 października" + "15:30" -> "środa, 1 października 15:30"
  combined_text = "#{date_str} #{time_str}"

  case MultilingualDateParser.extract_and_parse(combined_text,
         languages: [:polish],
         timezone: "Europe/Warsaw"
       ) do
    {:ok, %{starts_at: datetime}} ->
      datetime

    {:error, reason} ->
      Logger.debug("MultilingualDateParser failed for '#{combined_text}': #{inspect(reason)}")
      nil
  end
end

defp parse_datetime(_date_str, _time_str), do: nil
```

### Supported Date Formats

**KinoKrakow (now via MultilingualDateParser):**
- Polish day names: "poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota", "niedziela"
- Polish month names: "stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca", "lipca", "sierpnia", "września", "października", "listopada", "grudnia"
- Date format: "czwartek, 2 października" + "15:30"
- Timezone: Europe/Warsaw → UTC

**Karnet (remains custom parser):**
- DD.MM.YYYY format: "04.09.2025, 18:00"
- Date ranges: "04.09.2025 - 09.10.2025"
- Polish text dates: "czwartek, 4 września 2025"
- Timezone: Europe/Warsaw → UTC

## Comparison with Phase 1

| Metric | Phase 1 (Recurring Events) | Phase 2 (Polish Dates) |
|--------|---------------------------|------------------------|
| **Lines Eliminated** | ~416 lines | ~225 lines |
| **Sources Migrated** | 2/2 (GeeksWhoDrink, QuestionOne) | 1/2 (KinoKrakow only) |
| **Risk Level** | LOW | LOW (KinoKrakow), MEDIUM-HIGH (Karnet) |
| **Tests Passing** | 14 tests, 0 failures | 10 tests, 0 failures |
| **Files Deleted** | 2 parsers | 1 parser + 1 test file |

## Related Issues

- GitHub Issue #2151: Analysis that led to this refactoring
- Phase 1 Completion: TIME_PARSING_PHASE1_COMPLETE.md

## Future Enhancements (Optional)

### Phase 3: Karnet Migration (If Needed)

**Requirements:**
1. Enhance MultilingualDateParser to support DD.MM.YYYY format
2. Add DD.MM.YYYY pattern to Polish plugin's date extraction
3. Support date ranges in DD.MM.YYYY format
4. Maintain backward compatibility with existing sources

**Estimated Effort:**
- Risk: MEDIUM
- Code Changes: ~50-100 lines in MultilingualDateParser
- Testing: Comprehensive tests for new format
- Benefit: Additional ~370 lines eliminated from Karnet parser

**Decision:** Defer to future phase only if Karnet's custom parser becomes a maintenance burden OR if multiple sources need DD.MM.YYYY support.

---

**Status**: ✅ Phase 2 Complete (1/2 sources migrated)
**Tests**: ✅ All passing (10 tests, 0 failures)
**Code Quality**: ✅ No regressions
**Decision**: ✅ Karnet excluded due to format incompatibility (appropriate risk management)
**Ready for**: Phase 3 (optional) or other work
