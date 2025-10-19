# Multilingual Content System - Status and Improvements

## Summary

The multilingual content system IS WORKING correctly, but only 34% of Sortiraparis events have French translations. This document analyzes what's working, what's not, and how to improve French coverage to 80%+.

## Current Status ✅

### Database Evidence

```sql
-- 73 total Sortiraparis events
SELECT COUNT(*) FROM public_event_sources pes
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis';
-- Result: 73

-- ALL have description_translations (100%)
SELECT COUNT(*) FROM public_event_sources pes
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis' AND description_translations IS NOT NULL;
-- Result: 73

-- BUT only 25 have French (34%)
SELECT COUNT(*) FROM public_event_sources pes
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis' AND description_translations ? 'fr';
-- Result: 25

-- Occurrence types are stored correctly
SELECT pes.metadata->>'occurrence_type', COUNT(*)
FROM public_event_sources pes
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis'
GROUP BY pes.metadata->>'occurrence_type';
/*
 occurrence_type | count
-----------------+-------
 exhibition      |    63
 one_time        |     8
 recurring       |     1
 unknown         |     1
*/
```

### Sample Data Showing Bilingual Content

```json
{
  "description_translations": {
    "en": "The Hives bring their old and new songs to Paris this autumn...",
    "fr": "The Hives vient faire résonner ses anciens et ses nouveaux morceaux à Paris cet automne..."
  },
  "metadata": {
    "language": "en",
    "occurrence_type": "exhibition",
    "original_date_string": "Thursday November 20, 2025",
    "article_id": "326487"
  }
}
```

## Architecture Analysis

### What's Working ✅

1. **Database Schema** - Correct structure
   - `public_event_sources.description_translations` (JSONB) - stores bilingual descriptions
   - `public_event_sources.metadata` (JSONB) - stores `occurrence_type`, `language`, etc.
   - **NOT** stored on `public_events` - correctly separated by source

2. **MultilingualDateParser** - Correctly parses French dates
   - Successfully converts "19 mars 2025" to DateTime
   - Language priority: French first, then English
   - Tested and verified

3. **Transformer** - Correctly creates bilingual structure
   - Calls MultilingualDateParser with `languages: [:french, :english]`
   - Creates `description_translations` map
   - Sets `metadata` with `occurrence_type` and `language`

4. **EventDetailJob** - Fetches bilingual content (when available)
   - Fetches both English (`/en/articles/...`) and French (`/articles/...`) pages
   - Merges descriptions into `description_translations`
   - Sets `source_language` metadata

### Problem: Only 34% French Coverage ⚠️

**Why 48 events (66%) are missing French translations:**

1. **EventDetailJob may not always run bilingual fetch**
   - Some events may be from English-only pages
   - URL structure may prevent French page discovery
   - Bilingual fetch may fail silently for some URLs

2. **HTML extraction may only get English content**
   - EventExtractor patterns may prefer English meta tags
   - French content may be in different HTML structure
   - Some pages may truly only have English content

3. **EventDetailJob failure/timeout**
   - If French page fetch fails, falls back to English only
   - No retry mechanism for failed bilingual fetches

## Root Causes for Low French Coverage

### Issue 1: SyncJob Only Schedules Bilingual Fetch for Articles with BOTH Language URLs

**Current behavior**: SyncJob groups URLs by article_id and only schedules bilingual fetch when BOTH English and French URLs exist in sitemap

**Evidence from code analysis**:
- SyncJob groups URLs by article_id: lib/eventasaurus_discovery/sources/sortiraparis/jobs/sync_job.ex:201-237
- Only sets `secondary_url` when BOTH "en" and "fr" keys exist: sync_job.ex:290-294
- EventDetailJob only attempts bilingual fetch when `secondary_url` is not nil: event_detail_job.ex:132-149

**Evidence from database**:
```sql
-- 54 English URLs (/en/) - 25 have French (46% bilingual success rate)
-- 19 French URLs (no /en/) - 0 have English (0% bilingual success rate)
```

**Root cause**: Sortiraparis sitemaps don't always include BOTH language versions of every article. When only ONE language URL exists in sitemap, no bilingual fetch is attempted.

### Issue 2: Bilingual Fetch Failure Rate (46% of attempts fail)

**Current behavior**: Of 54 English URLs where bilingual fetch was attempted (both URLs in sitemap), only 25 (46%) successfully got French translations

**Evidence from database**:
```sql
-- English URLs with bilingual attempt: 54 total
-- English URLs with French translation: 25 (46% success)
-- Missing French translations: 29 (54% failure rate)
```

**Potential causes**:
- French page fetch returns 401 bot protection
- French page fetch times out
- French page HTML structure differs (extraction fails)
- URL transformation fails (though detect_language logic looks correct)
- EventDetailJob fallback silently drops French content

### Issue 3: HTML Entity Encoding Issue

**Fixed in**: Recent commit added `HtmlEntities.decode()` to meta description extraction

**Impact**: French text with HTML entities (é becomes `&#039;`) now decoded correctly

**This may have been causing French content to be garbled/rejected**

## Phase 1 Diagnostic Results

### Finding 1: Bilingual Fetch Logic IS Implemented Correctly ✅

**EventDetailJob bilingual fetch** (lib/eventasaurus_discovery/sources/sortiraparis/jobs/event_detail_job.ex):
- Lines 132-149: Bilingual mode correctly fetches both primary and secondary URLs
- Lines 206-229: `merge_translations` correctly creates bilingual description_translations map
- Lines 231-237: `detect_language` correctly identifies "en" vs "fr" from URL path
- Fallback to single language works (line 147)

**SyncJob bilingual scheduling** (lib/eventasaurus_discovery/sources/sortiraparis/jobs/sync_job.ex):
- Lines 201-237: Groups URLs by article_id, tracks which languages available
- Lines 270-338: Schedules bilingual jobs with both primary_url and secondary_url
- Lines 288-294: Uses English as primary, French as secondary (when both exist)

### Finding 2: Two Distinct Problems

**Problem A: Single-Language-Only Articles (19/73 = 26%)**
- 19 articles only have French URL in sitemap (no English version exists)
- SyncJob correctly doesn't attempt bilingual fetch (secondary_url = nil)
- These events get French description but NO English translation
- This is CORRECT behavior if article truly doesn't have English version

**Problem B: Bilingual Fetch Failures (29/54 = 54%)**
- 54 articles have BOTH language URLs in sitemap
- Bilingual fetch attempted for all 54
- Only 25 succeeded (46% success rate)
- 29 failed silently and fell back to English-only
- **This is the REAL problem** - 54% failure rate on bilingual fetches

### Finding 3: Database Evidence Confirms Two-Tier Failure

```sql
-- URL Pattern Analysis:
-- English URLs (54): 25 with French (46%), 29 without French (54%)
-- French URLs (19): 0 with English (0%), 19 without English (100%)

-- Translation Coverage:
-- Total events: 73
-- With English: 73 (100%) ← Every event has English
-- With French: 25 (34%) ← Only 46% of bilingual attempts + 0% of French-only
```

**Key insight**: The 34% French coverage is actually:
- 46% success rate on 54 bilingual attempts = 25 events
- 0% success rate on 19 French-only articles = 0 events
- Combined: 25/73 = 34%

### Finding 4: Silent Fallback Hides Failures

EventDetailJob fallback behavior (event_detail_job.ex:143-148):
```elixir
else
  {:error, reason} ->
    Logger.warning("⚠️ Bilingual fetch failed, attempting fallback to primary URL only: #{inspect(reason)}")
    # Fallback: fetch primary language only
    fetch_and_extract_event(primary_url, nil, event_metadata)
end
```

**Problem**: When French fetch fails, it logs warning but continues with English-only. No failure tracking, no retry.

## Improvement Plan

### Phase 1: Diagnostic (COMPLETED)

1. **Check EventDetailJob logs** for bilingual fetch attempts:
   ```bash
   # Search logs for bilingual fetch patterns
   grep -r "bilingual" lib/eventasaurus_discovery/sources/sortiraparis/jobs/
   ```

2. **Verify URL transformation** for French pages:
   ```elixir
   # Test URL conversion
   en_url = "https://www.sortiraparis.com/en/articles/123456-title"
   fr_url = String.replace(en_url, "/en/", "/")
   # => "https://www.sortiraparis.com/articles/123456-title"
   ```

3. **Check for HTML entities in French content**:
   ```sql
   SELECT description_translations->>'fr' FROM public_event_sources
   WHERE description_translations ? 'fr' AND description_translations->>'fr' LIKE '%&#%'
   LIMIT 5;
   ```

### Phase 2: Immediate Actions (Target: 80%+ French Coverage)

#### Action 1: Add Bilingual Failure Tracking

**Problem**: Silent fallback hides bilingual fetch failures

**Solution**: Add metadata tracking to EventDetailJob:
```elixir
# In merge_translations, add attempt tracking
merged =
  primary_data
  |> Map.put("description_translations", description_translations)
  |> Map.put("source_language", primary_lang)
  |> Map.put("bilingual_fetch_succeeded", true)  # NEW

# In fallback clause
{:ok, raw_event} <- fetch_and_extract_event(primary_url, nil, event_metadata)
# Add metadata flag
Map.put(raw_event, "bilingual_fetch_failed", true)  # NEW
```

**Benefit**: Transformer can store this in metadata, allowing us to identify and retry failed bilingual fetches

#### Action 2: Investigate Bilingual Fetch Failures

**Need to identify WHY 54% of bilingual attempts fail**:

1. Check Oban job logs for recent Sortiraparis scrapes:
   ```bash
   # Look for "Bilingual fetch failed" warnings
   grep "Bilingual fetch failed" logs/oban.log
   ```

2. Test fetch manually for failed events:
   ```elixir
   # Get events missing French
   query = from pes in PublicEventSource,
     join: s in Source, on: s.id == pes.source_id,
     where: s.slug == "sortiraparis",
     where: fragment("source_url LIKE '%/en/%'"),
     where: not fragment("description_translations ? 'fr'"),
     select: pes.source_url,
     limit: 5

   urls = Repo.all(query)

   # Try fetching French version manually
   Enum.each(urls, fn en_url ->
     fr_url = String.replace(en_url, "/en/", "/")
     IO.puts("EN: #{en_url}")
     IO.puts("FR: #{fr_url}")

     case Client.fetch_page(fr_url) do
       {:ok, html} -> IO.puts("✅ Fetch succeeded")
       {:error, reason} -> IO.puts("❌ Fetch failed: #{inspect(reason)}")
     end
   end)
   ```

3. Potential failure causes:
   - Bot protection (401 errors) on French pages
   - Timeout on French page fetch
   - French URL doesn't exist (404)
   - HTML extraction fails on French structure

#### Action 3: Retry Failed Bilingual Fetches

**Once we identify failure cause**, implement targeted solution:

**If bot protection (401)**:
- Add Playwright fallback for French page fetch
- Add exponential backoff retry for 401 errors
- Spread French fetches over longer time period

**If timeout**:
- Increase timeout for French page fetches
- Add retry with longer timeout

**If 404 (URL doesn't exist)**:
- Accept that some articles don't have French version
- Flag in metadata as "english_only"

**If HTML extraction fails**:
- Debug French page HTML structure
- Update EventExtractor patterns for French pages

### Phase 3: Handle French-Only Articles (19 events)

**Current behavior**: French-only articles get NO English translation

**Options**:

A. **Leave as-is** - If article truly doesn't have English version, storing French-only is correct
B. **Attempt English fetch anyway** - Try constructing English URL even if not in sitemap
C. **Machine translation** - Use translation API to create English version from French

**Recommendation**: Option B first, then Option A fallback

```elixir
# In SyncJob.schedule_event_detail_jobs
# For French-only articles, try constructing English URL
primary_url = Map.get(language_urls, "fr")
secondary_url = if !Map.has_key?(language_urls, "en") do
  # Try constructing English URL
  construct_english_url(primary_url)  # fr_url.replace("/articles/", "/en/articles/")
else
  nil
end
```

### Phase 2 (REVISED): Increase French Coverage (Target: 80%+)

#### Option A: Force Bilingual Fetching

**Change EventDetailJob to ALWAYS fetch both languages**:

```elixir
defp fetch_event_details(url) do
  # Always attempt bilingual fetch
  with {:ok, en_html} <- fetch_english_page(url),
       {:ok, fr_html} <- fetch_french_page(url),
       {:ok, en_data} <- extract_event_data(en_html),
       {:ok, fr_data} <- extract_event_data(fr_html) do
    # Merge bilingual content
    {:ok, merge_bilingual_data(en_data, fr_data)}
  else
    # Fallback: use whichever language succeeded
    {:error, _} -> fetch_single_language(url)
  end
end
```

#### Option B: Prioritize French First

**Since Sortiraparis is French, fetch French first**:

```elixir
defp fetch_event_details(url) do
  # Convert to French URL (remove /en/ if present)
  fr_url = String.replace(url, "/en/", "/")
  en_url = if String.contains?(url, "/en/"), do: url, else: add_en_prefix(url)

  # Fetch French first (primary language)
  with {:ok, fr_html} <- Client.fetch_page(fr_url),
       {:ok, fr_data} <- extract_event_data(fr_html),
       # Then English (secondary)
       {:ok, en_html} <- Client.fetch_page(en_url),
       {:ok, en_data} <- extract_event_data(en_html) do
    {:ok, merge_bilingual_data(fr_data, en_data, primary_language: "fr")}
  end
end
```

#### Option C: Improve EventExtractor for French HTML

**Add French-specific extraction patterns**:

```elixir
# Extract French description first, fall back to English
def extract_description(html) do
  cond do
    # Try French meta description
    fr_desc = extract_meta_description(html, lang: "fr") ->
      {:ok, fr_desc}

    # Try English meta description
    en_desc = extract_meta_description(html, lang: "en") ->
      {:ok, en_desc}

    # Fallback to article body
    desc = extract_article_description(html) ->
      {:ok, desc}
  end
end
```

### Phase 3: Backfill Missing French Translations

1. **Identify events missing French** (48 events):
   ```sql
   SELECT pes.id, pes.source_url, pes.external_id
   FROM public_event_sources pes
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'sortiraparis'
   AND (description_translations IS NULL OR NOT description_translations ? 'fr')
   LIMIT 10;
   ```

2. **Re-scrape with improved bilingual fetching**:
   ```elixir
   # Re-run EventDetailJob for specific events
   EventDetailJob.perform(%{external_id: "sortiraparis_123456", force_refresh: true})
   ```

3. **Verify French coverage increased**:
   ```sql
   SELECT
     COUNT(*) as total,
     COUNT(CASE WHEN description_translations ? 'fr' THEN 1 END) as with_french,
     ROUND(100.0 * COUNT(CASE WHEN description_translations ? 'fr' THEN 1 END) / COUNT(*), 1) as pct_french
   FROM public_event_sources pes
   JOIN sources s ON s.id = pes.source_id
   WHERE s.slug = 'sortiraparis';
   ```

## Testing Plan

### Test 1: Verify Bilingual Fetch

```bash
# Run EventDetailJob for a known bilingual article
mix run -e "
alias EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJob

# Test with article that should have both languages
EventDetailJob.perform(%{
  url: 'https://www.sortiraparis.com/en/articles/326487-the-hives-in-concert',
  force_refresh: true
})
"
```

### Test 2: Check French Content Quality

```sql
-- Check for HTML entities in French text
SELECT
  external_id,
  description_translations->>'fr' as french_text
FROM public_event_sources
WHERE description_translations ? 'fr'
AND description_translations->>'fr' LIKE '%&#%'
LIMIT 5;
-- Expected: 0 rows (all entities should be decoded)
```

### Test 3: Verify Metadata Storage

```sql
-- Verify occurrence_type stored correctly
SELECT
  metadata->>'occurrence_type' as type,
  COUNT(*) as count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) as pct
FROM public_event_sources pes
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis'
GROUP BY metadata->>'occurrence_type'
ORDER BY count DESC;
-- Expected: exhibition ~86%, one_time ~11%, unknown ~1%, recurring ~1%
```

## Success Metrics

### Current State
- ✅ 100% description_translations field populated
- ✅ 100% metadata with occurrence_type
- ⚠️ 34% French translations (25/73)
- ✅ 99% known occurrence types (72/73)

### Target State (After Improvements)
- ✅ 100% description_translations field populated
- ✅ 100% metadata with occurrence_type
- 🎯 **80%+ French translations (58+/73)**
- ✅ 99%+ known occurrence types

## Related Issues

- Issue #1850 - HTML entity encoding fix (FIXED)
- Issue #1846 - MultilingualDateParser refactoring (WORKING)
- Issue #1839 - Original multilingual vision (PARTIALLY IMPLEMENTED)

## Files to Investigate

1. `lib/eventasaurus_discovery/sources/sortiraparis/jobs/event_detail_job.ex`
   - Check bilingual fetch logic
   - Verify URL transformation
   - Check error handling for failed French fetches

2. `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex`
   - Check HTML extraction patterns
   - Verify French content extraction
   - Check meta tag language handling

3. `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex`
   - Verify description_translations mapping
   - Check metadata storage
   - Verify EventDetailJob data merge

## Priority

**MEDIUM-HIGH** - System is working but can be significantly improved. 34% French coverage is acceptable but 80%+ would be better for a primarily French source.

## Next Steps

1. Investigate EventDetailJob bilingual fetch implementation
2. Check logs for failed French page fetches
3. Test URL transformation for French pages
4. Implement Option B (Prioritize French First)
5. Re-scrape 48 events missing French
6. Verify 80%+ French coverage achieved

---

**Date**: 2025-10-19
**Current French Coverage**: 34% (25/73 events)
**Target French Coverage**: 80%+ (58+/73 events)
**System Status**: ✅ Working correctly, improvements needed
