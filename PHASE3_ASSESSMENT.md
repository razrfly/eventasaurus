# Phase 3 Bilingual Fetching - Assessment Report

**Date**: 2025-10-18
**Issue**: #1835 - Add French Translation Support to Sortiraparis Scraper
**Phases Completed**: Phase 1 ✅, Phase 2 ✅, Phase 3 ⚠️

---

## Executive Summary

**Grade: B- (70/100)**

**Did we achieve the goal?** ❌ **NO** - French translations are NOT being saved to the database.

**What's working?**
- ✅ Sitemap discovery finds both English and French URLs
- ✅ URL filtering correctly identifies event URLs
- ✅ Client module can fetch both languages
- ✅ EventDetailJob has bilingual fetching logic
- ✅ Transformer handles translation merging
- ✅ Code compiles and runs without errors

**What's broken?**
- ❌ **CRITICAL**: `limit` parameter breaks article grouping logic
- ❌ **CRITICAL**: Jobs are scheduled with single language only (no `secondary_url`)
- ❌ **CRITICAL**: No French translations in database (`description_translations` only has `"en"`)
- ❌ All recent events (12 total) have ONLY English translations

---

## Database Analysis

### Query Results

**Total Events by Language** (last 10 minutes):
```sql
total_events: 12
with_french: 0
with_english: 12
with_both: 0
```

**❌ FAIL**: 0% of events have French translations (target: 90%+)

### Sample Event Data

```json
{
  "id": 2029,
  "title": "British rapper Dave in concert at Paris' Accor Arena in February 2026",
  "external_id": "sortiraparis_335288",
  "description_translations": {
    "en": "As part of his European tour entitled \"The Boy Who Played the Harp Tour\"..."
  },
  "source_lang": "en"
}
```

**❌ FAIL**: Missing French translation entirely

### Oban Job Analysis

**EventDetailJobs created** (last 10 minutes):
```sql
total_jobs: 101
with_secondary_url: 0
bilingual_jobs: 0
single_language_jobs: 101
```

**❌ FAIL**: 0% of jobs have `secondary_url` set (expected: high percentage)

**Sample Job Args**:
```json
{
  "url": "https://www.sortiraparis.com/en/what-to-see-in-paris/shows/articles/335322-...",
  "secondary_url": null,
  "event_metadata": {
    "bilingual": false,
    "languages": ["en"],
    "article_id": "335322"
  }
}
```

**❌ FAIL**: `bilingual: false`, `languages: ["en"]` only

---

## Root Cause Analysis

### Issue #1: Limit Logic Breaks Article Grouping

**Location**: `sync_job.ex:189-195`

**Problem**:
```elixir
# Apply limit if specified (limit unique URLs, not entries)
limited_entries =
  if limit do
    Enum.take(event_entries, limit)  # ❌ Takes first N URL entries
  else
    event_entries
  end
```

**What happens with `limit => 1`**:
1. Sitemap extraction finds 5,846 event URL entries (both EN and FR)
2. `Enum.take(event_entries, 1)` takes ONLY the first URL entry
3. If first entry is English, we never see the French version
4. Grouping function receives only 1 URL entry → creates 1 single-language article
5. Job scheduled with `languages: ["en"]` and `secondary_url: null`

**Expected behavior**:
- Limit should apply to UNIQUE ARTICLES, not URL entries
- If `limit => 1`, we should get 1 article with BOTH EN + FR URLs (2 URL entries)
- Jobs should have `languages: ["en", "fr"]` and `secondary_url: "https://...fr..."`

### Issue #2: URL Entries Not Paired by Article ID

**Location**: `sync_job.ex:209-245` (grouping function)

**The grouping logic is CORRECT**, but it never gets a chance to work because:
1. The limit is applied BEFORE grouping
2. Only 1 URL entry reaches the grouping function
3. Grouping creates: `%{"335322" => %{"en" => "...url..."}}`
4. No French URL to pair with

**Evidence from logs**:
```
🔗 Grouping 1 URLs by article_id
📊 Article Grouping Results:
- Unique articles: 1
- With English: 1
- With French: 0
- With both languages: 0
```

### Issue #3: Schedule Logic Expects Bilingual Data

**Location**: `sync_job.ex:265-333`

**The scheduling logic is CORRECT**, but:
```elixir
# Use English URL as primary, French as secondary
primary_url = Map.get(language_urls, "en") || Map.get(language_urls, "fr")
secondary_url = if Map.has_key?(language_urls, "en") && Map.has_key?(language_urls, "fr") do
  Map.get(language_urls, "fr")  # ✅ Logic correct
else
  nil  # ❌ But this executes every time
end
```

Since `language_urls` only has `%{"en" => "..."}`, the condition fails and `secondary_url = nil`.

---

## What We Did Right

### ✅ Phase 1: Research & Documentation
- Comprehensive research on Sortiraparis multilingual structure
- Clear implementation plan with 5 phases
- Documentation: `docs/TRANSLATION_HANDLING.md` created
- Success criteria defined for each phase

**Grade: A+ (100/100)**

### ✅ Phase 2: Sitemap Discovery
- Added French sitemap URLs to `config.ex`
- Language metadata tracked (`"en"` or `"fr"`)
- Article ID extraction working correctly
- URL grouping logic implemented correctly

**Grade: A (95/100)** - Only issue: limit logic placement

### ⚠️ Phase 3: Bilingual Content Fetching
- Client module language support ✅
- URL localization logic ✅
- EventDetailJob bilingual fetching ✅
- Translation merging in Transformer ✅
- **BUT**: Not working end-to-end due to limit logic bug ❌

**Grade: C (70/100)** - Code correct, integration broken

---

## Impact Assessment

### User Impact: HIGH
- French-speaking users still see only English descriptions
- No improvement over previous state
- Missing primary language content for Paris-based source

### Technical Debt: MEDIUM
- One critical bug to fix (limit logic)
- All code structure is correct and ready
- Fix is straightforward (see solution below)

### Testing Gap: HIGH
- No end-to-end test caught this issue
- Need integration test that validates bilingual flow
- Need test that validates `limit` works correctly with bilingual data

---

## Solution

### Fix Required in sync_job.ex

**Location**: Lines 189-200

**Current (BROKEN)**:
```elixir
# Apply limit if specified (limit unique URLs, not entries)
limited_entries =
  if limit do
    Enum.take(event_entries, limit)
  else
    event_entries
  end
```

**Fixed (CORRECT)**:
```elixir
# DON'T apply limit here - apply it AFTER grouping to limit articles, not URL entries
# The limit should restrict unique articles, not individual URLs
{:ok, event_entries}
```

**Then update `filter_fresh_events/1` to apply limit**:

**Location**: Lines 247-263

**Add after line 254**:
```elixir
# Apply limit to ARTICLES (not URL entries)
limited_articles = if limit do
  Enum.take(articles_list, limit)
else
  articles_list
end

Logger.info("""
✨ Article Processing:
- Total articles available: #{article_count}
- Articles to process: #{length(limited_articles)}
- Deduplication: Handled by database constraints
""")

{:ok, limited_articles}
```

---

## Acceptance Criteria (Revised)

### Must Fix Before Closing Issue

1. ❌ **Fix limit logic** - Apply limit to articles, not URL entries
2. ❌ **Verify bilingual jobs** - Check that `secondary_url` is set when both languages available
3. ❌ **Verify database storage** - Confirm `description_translations` has both `"en"` and `"fr"` keys
4. ❌ **Test with real data** - Run with `limit => 5` and verify all 5 events have both translations
5. ❌ **Validate translation quality** - Confirm English and French descriptions are different

### Success Metrics (Phase 5)

1. **Bilingual Coverage**: ≥90% of events have both EN and FR translations
2. **Translation Quality**: French text is actually in French (not English duplicates)
3. **No Duplicates**: Same article_id creates ONE event (not two)
4. **Performance**: Acceptable scraping time (2x requests = ~2x time)

---

## Recommendation

**Status**: ⚠️ **CANNOT CLOSE ISSUE** - Critical bug prevents bilingual fetching

**Next Steps**:
1. **Immediate**: Fix limit logic in `sync_job.ex` (lines 189-200 and 247-263)
2. **Short-term**: Add integration test for bilingual flow with `limit` parameter
3. **Medium-term**: Run full scrape without limit to validate production readiness
4. **Long-term**: Consider Phase 5 comprehensive testing plan

**Estimated Time to Fix**: 15 minutes (code change) + 30 minutes (testing)

---

## Lessons Learned

### What Went Well
- Comprehensive planning and documentation
- Modular code structure made debugging easy
- Good logging helped identify root cause quickly

### What Could Improve
- **Testing**: Should have written integration test before running production test
- **Code Review**: Should have caught limit logic issue during development
- **Validation**: Should have checked database immediately after first test run

### Best Practices Going Forward
1. Always write integration tests for multi-step workflows
2. Test with `limit` parameter to catch edge cases
3. Validate database state after each phase implementation
4. Don't assume "code compiles = code works" - verify end-to-end

---

## Final Assessment

**Can we close Issue #1835?** ❌ **NO**

**Reason**: Critical bug prevents French translations from being saved to database. Zero (0) events have French translations despite all infrastructure being in place.

**Grade Breakdown**:
- **Planning & Design**: A+ (100/100) - Excellent research and documentation
- **Code Quality**: A (95/100) - Well-structured, modular, maintainable
- **Implementation**: C (70/100) - Logic correct but integration broken
- **Testing**: F (40/100) - No integration tests caught the bug
- **Overall**: **B- (70/100)** - Good effort, needs critical fix

**Estimated completion after fix**: 95% done, one bug away from success.
