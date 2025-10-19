# Issue: Robust Multilingual Date Parsing for Sortiraparis

**Status**: 📋 **PROPOSED**
**Priority**: High
**Created**: 2025-10-18
**Branch**: TBD
**GitHub Issue**: TBD

---

## Executive Summary

The current regex-based date extraction for Sortiraparis is failing with `:unsupported_date_format` errors on hundreds of articles. After investigating multilingual date parsing libraries and Sortiraparis HTML structure, we need to implement a robust, maintainable solution that handles French and English dates systematically.

**Root Cause**: Manual regex patterns don't scale and miss many date format variations.

**Solution**: Create a dedicated DateParser module that normalizes multilingual dates to ISO format before parsing with Timex.

---

## Problem Analysis

### Current Issues

1. **Hundreds of `:unsupported_date_format` errors** - Current regex patterns miss many valid dates
2. **Fragile regex approach** - Hard to maintain, doesn't scale to new patterns
3. **No JSON-LD fallback** - Sortiraparis uses `@type: "Article"` not `@type: "Event"`, so no structured `startDate`
4. **Language mixing** - Articles can have dates in either French or English

### Evidence from Sequential Thinking Research

**Library Investigation Results:**
- ✅ **Timex**: Already installed (~> 3.7), but only supports formatting with locales, NOT parsing
- ✅ **ex_cldr**: Formatting only, no parsing capability
- ❌ **No Elixir equivalent** to Ruby's Chronic or JavaScript's date-fns with i18n

**Sortiraparis HTML Analysis:**
- JSON-LD uses `@type: "Article"` with `datePublished`/`dateModified` (article metadata)
- NO `@type: "Event"` with `startDate`/`endDate` (event metadata)
- Dates only in natural language text (French/English)
- Example failing URL: `https://www.sortiraparis.com/loisirs/cinema/articles/335280-film-un-fantome-dans-la-bataille-2025`

**Date Format Examples Found:**
```
English:
- "October 15, 2025"
- "Friday, October 31, 2025"
- "February 25, 27, 28, 2026"
- "October 15, 2025 to January 19, 2026"

French:
- "17 octobre 2025"
- "vendredi 31 octobre 2025"
- "Du 1er janvier au 15 février 2026"
- "Le 19 avril 2025"
```

---

## Proposed Solution: Multilingual DateParser Module

### Architecture

Create a new module: `EventasaurusDiscovery.Sources.Sortiraparis.Parsers.DateParser`

**Three-Stage Pipeline:**

1. **Extract** - Find date strings in HTML using broad patterns
2. **Normalize** - Convert multilingual components to ISO format
3. **Parse** - Use Timex to parse normalized ISO strings

### Key Components

#### 1. Month Name Normalization Map

```elixir
@month_names %{
  # English
  "january" => 1, "february" => 2, "march" => 3, "april" => 4,
  "may" => 5, "june" => 6, "july" => 7, "august" => 8,
  "september" => 9, "october" => 10, "november" => 11, "december" => 12,

  # French
  "janvier" => 1, "février" => 2, "mars" => 3, "avril" => 4,
  "mai" => 5, "juin" => 6, "juillet" => 7, "août" => 8,
  "septembre" => 9, "octobre" => 10, "novembre" => 11, "décembre" => 12,

  # Abbreviated forms
  "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4,
  "jun" => 6, "jul" => 7, "aug" => 8, "sep" => 9,
  "oct" => 10, "nov" => 11, "dec" => 12,

  "janv" => 1, "févr" => 2, "avr" => 4,
  "juil" => 7, "sept" => 9, "déc" => 12
}
```

#### 2. Component Extraction

Instead of trying to match complete date strings, extract components:

```elixir
defp extract_date_components(text) do
  %{
    day: extract_day_number(text),
    month: extract_month(text),      # Returns month number
    year: extract_year(text),
    ordinal: extract_ordinal(text)   # "er", "st", "nd", etc.
  }
end
```

#### 3. Normalization to ISO Format

Convert extracted components to `YYYY-MM-DD` format:

```elixir
defp normalize_to_iso(%{day: day, month: month, year: year}) do
  "#{year}-#{String.pad_leading(to_string(month), 2, "0")}-#{String.pad_leading(to_string(day), 2, "0")}"
end
```

#### 4. Timex Parsing

Use Timex to parse the normalized ISO string:

```elixir
defp parse_with_timex(iso_string) do
  case Timex.parse(iso_string, "{YYYY}-{0M}-{0D}") do
    {:ok, date} -> {:ok, date}
    {:error, reason} -> {:error, {:timex_parse_failed, reason}}
  end
end
```

### Benefits

✅ **Maintainable** - Add new languages by extending month map
✅ **Scalable** - Component-based approach handles variations
✅ **Leverages Timex** - Uses existing dependency correctly
✅ **Testable** - Each stage can be tested independently
✅ **Debuggable** - Clear intermediate representations
✅ **Language-agnostic intermediate format** - ISO strings work everywhere

---

## Implementation Phases

### Phase 1: Create DateParser Module (2-3 hours)

**Goal**: Extract basic single dates in French and English

**Tasks**:
1. Create `lib/eventasaurus_discovery/sources/sortiraparis/parsers/date_parser.ex`
2. Implement month name normalization map
3. Implement component extraction for single dates
4. Implement ISO normalization
5. Implement Timex parsing
6. Write unit tests for common patterns

**Success Criteria**:
- ✅ Parses "17 octobre 2025" → `~D[2025-10-17]`
- ✅ Parses "October 15, 2025" → `~D[2025-10-15]`
- ✅ Parses "Le 19 avril 2025" → `~D[2025-04-19]`
- ✅ Unit tests pass

### Phase 2: Handle Date Ranges (1-2 hours)

**Goal**: Support date range patterns

**Tasks**:
1. Extract start and end components from ranges
2. Handle "to" and "au" connectors
3. Handle "Du...au" patterns
4. Return `%{start_date: date1, end_date: date2}`

**Success Criteria**:
- ✅ Parses "Du 1er janvier au 15 février 2026"
- ✅ Parses "October 15, 2025 to January 19, 2026"

### Phase 3: Handle Multi-Date Patterns (1 hour)

**Goal**: Support patterns like "February 25, 27, 28, 2026"

**Tasks**:
1. Extract base month and year
2. Extract all day numbers
3. Return list of dates

**Success Criteria**:
- ✅ Parses "February 25, 27, 28, 2026" → `[~D[2026-02-25], ~D[2026-02-27], ~D[2026-02-28]]`

### Phase 4: Handle Day Names (30 min)

**Goal**: Support patterns with day names

**Tasks**:
1. Strip day names before processing
2. Support both English and French day names

**Success Criteria**:
- ✅ Parses "vendredi 31 octobre 2025"
- ✅ Parses "Friday, October 31, 2025"

### Phase 5: Integration with EventExtractor (1 hour)

**Goal**: Replace current regex approach

**Tasks**:
1. Update `extract_date_from_text/1` to use DateParser
2. Handle all return types (single date, range, multi-date)
3. Update error handling
4. Remove old regex patterns

**Success Criteria**:
- ✅ All existing tests pass
- ✅ No `:unsupported_date_format` errors on test corpus

### Phase 6: Comprehensive Testing (2 hours)

**Goal**: Validate against real Sortiraparis pages

**Tasks**:
1. Run scraper on 200+ mixed French/English articles
2. Collect and fix any remaining edge cases
3. Add edge cases to test suite
4. Document supported formats

**Success Criteria**:
- ✅ >95% success rate on test corpus
- ✅ Clear error messages for truly unparseable dates

---

## Error Handling Strategy

### Graceful Degradation

1. **Unknown month name** → Try as-is, might be abbreviated form
2. **Missing components** → Return `:incomplete_date_data`
3. **Invalid date** → Return `:invalid_date` (e.g., Feb 31)
4. **Timex parse error** → Return `:timex_parse_failed` with reason

### Logging

```elixir
Logger.debug("📅 Extracted components: #{inspect(components)}")
Logger.debug("🔄 Normalized to ISO: #{iso_string}")
Logger.debug("✅ Parsed date: #{inspect(date)}")
```

---

## Testing Strategy

### Unit Tests (date_parser_test.exs)

```elixir
describe "single dates" do
  test "parses English dates" do
    assert DateParser.parse("October 15, 2025") == {:ok, ~D[2025-10-15]}
  end

  test "parses French dates" do
    assert DateParser.parse("17 octobre 2025") == {:ok, ~D[2025-10-17]}
  end

  test "parses with day names" do
    assert DateParser.parse("vendredi 31 octobre 2025") == {:ok, ~D[2025-10-31]}
  end
end

describe "date ranges" do
  test "parses Du...au pattern" do
    assert DateParser.parse("Du 1er janvier au 15 février 2026") ==
      {:ok, %{start: ~D[2026-01-01], end: ~D[2026-02-15]}}
  end
end
```

### Integration Tests (event_extractor_test.exs)

```elixir
test "extracts dates from real French article" do
  html = File.read!("test/fixtures/sortiraparis_french_article.html")
  assert {:ok, %{"date_string" => _}} = EventExtractor.extract(html, url)
end
```

---

## Alternative Approaches Considered

### ❌ Option 1: Expand Current Regex

**Why Rejected**: Doesn't scale, becomes unmaintainable, still misses edge cases

### ❌ Option 2: Use Timex Custom Parser Behavior

**Why Rejected**: Still requires pattern matching logic, more complex than normalization approach

### ❌ Option 3: Call External Service

**Why Rejected**: Adds network dependency, slower, costs money

### ✅ Option 4: Normalization Pipeline (CHOSEN)

**Why Chosen**: Maintainable, scalable, leverages existing dependencies, testable

---

## Future Enhancements

1. **Add more languages** - Spanish, German, Italian (just extend month map)
2. **Fuzzy matching** - Handle typos in month names
3. **Relative dates** - "next Friday", "in 3 days" (requires NLP)
4. **Time extraction** - "19:00", "7pm" (currently not needed)
5. **Caching** - Memoize parsed dates for performance

---

## Dependencies

- ✅ Timex (~> 3.7) - Already installed
- ✅ Jason - Already installed (for testing JSON fixtures)

**No new dependencies required!**

---

## Risk Assessment

**Low Risk**:
- Self-contained module
- Can be tested independently
- Gradual rollout (phase by phase)
- Existing functionality preserved until final integration

**Rollback Strategy**:
- Keep old regex patterns commented out
- Feature flag for new parser
- Easy to revert if issues found

---

## Success Metrics

1. **Error Rate** - Reduce `:unsupported_date_format` errors from ~30% to <5%
2. **Test Coverage** - >90% code coverage for DateParser module
3. **Performance** - Parse times <10ms per date
4. **Maintainability** - Adding new language takes <30 minutes

---

## Related Documentation

- **ISSUE_SORTIRAPARIS_FRENCH_TRANSLATIONS.md** - Previous date extraction fixes
- **Timex Documentation** - https://hexdocs.pm/timex/
- **Schema.org Event** - https://schema.org/Event (not used by Sortiraparis)

---

## Next Steps

1. ✅ **Create this issue document**
2. ⏳ **Get user approval** for approach
3. ⏳ **Create GitHub issue** with link to this document
4. ⏳ **Implement Phase 1** - Basic DateParser module
5. ⏳ **Iterate through remaining phases**

---

## Notes

- Sortiraparis is not the only source - this DateParser can be reused for other sources with similar needs
- The normalization approach is a standard pattern in multilingual systems
- ISO 8601 format is the gold standard for date interchange
- Timex is battle-tested and reliable for the final parsing step
