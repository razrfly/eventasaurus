# Issue: Add French Translation Support to Sortiraparis Scraper

**Status**: Research & Planning (Phase 1)
**Priority**: Medium
**Type**: Enhancement
**Affects**: Sortiraparis scraper, translation handling system
**Related Documentation**: `ISSUE_LANGUAGE_HANDLING.md`

---

## Problem Summary

The Sortiraparis scraper currently only extracts English content from `sitemap-en-*.xml`, despite French being the primary language for this Paris-based event source. We should scrape both English and French translations to provide better localized content for our French-speaking users.

**Current State**: English-only scraping via `sitemap-en-{1,2,3,4}.xml`
**Target State**: Bilingual scraping (English + French) with merged translations

**User Impact**:
- French-speaking users only see English descriptions for Paris events
- Missing primary language content for a French source
- Competitive disadvantage vs. French event platforms
- Poor localization for target audience

---

## Research Findings

### Sortiraparis Multilingual Architecture

**Sitemap Structure** (verified in `lib/eventasaurus_discovery/sources/sortiraparis/config.ex:41-53`):
- English sitemaps: `https://www.sortiraparis.com/sitemap-en-{1,2,3,4}.xml` (currently used)
- French sitemaps: `https://www.sortiraparis.com/sitemap-fr-*.xml` (exist but not scraped)
- Comment in config explicitly mentions: "French sitemaps (sitemap-fr-*.xml) contain same events but in French"

**URL Patterns**:
- English: `https://www.sortiraparis.com/en/articles/{article_id}`
- French: `https://www.sortiraparis.com/articles/{article_id}` (default, no language prefix)
- Article IDs remain consistent across both languages

**Content Verification** (via WebFetch):
- Site has language switcher (EN/FR) on all article pages
- Same article available in both languages with consistent structure
- French is the canonical/default version (no `/fr/` prefix needed)

### Database Translation Storage

**Current Schema**:
```sql
-- Table: public_event_sources
-- Column: description_translations (JSONB)
-- Current format: {"en": "English description"}
-- Target format: {"en": "English description", "fr": "French description"}
```

**Verified in Database**:
```sql
SELECT pe.id, pe.title, pes.description_translations
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Sortiraparis'
LIMIT 3;
```

Result: All current Sortiraparis events have `{"en": "..."}` only.

**Database Constraints**:
- JSONB column supports multiple language keys
- No schema changes required
- Must respect pricing constraint: if `is_free = true`, then `min_price` and `max_price` must be `NULL`

### Reference Implementation: Karnet Bilingual Scraper

**File**: `lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex:434-535`

**Pattern**:
```elixir
defp merge_language_data(polish_data, english_data, metadata) do
  # 1. Start with primary language (Polish) as base
  base_data = merge_metadata(polish_data, metadata)

  polish_title = polish_data[:title]
  english_title = english_data[:title]

  # 2. Validate that translations match the same event
  if english_title && !validate_translation_match(polish_data, english_data) do
    Logger.warning("⚠️ English translation seems unrelated, skipping")
    # Only use Polish data if validation fails
    title_translations = %{"pl" => polish_title}
    description_translations = %{"pl" => get_description_text(polish_data)}
  else
    # 3. Merge both languages into translations map
    title_translations = %{}
    title_translations = if polish_title, do: Map.put(title_translations, "pl", polish_title), else: title_translations
    title_translations = if english_title, do: Map.put(title_translations, "en", english_title), else: title_translations

    description_translations = %{}
    polish_desc = get_description_text(polish_data)
    english_desc = get_description_text(english_data)
    description_translations = if polish_desc, do: Map.put(description_translations, "pl", polish_desc), else: description_translations
    description_translations = if english_desc, do: Map.put(description_translations, "en", english_desc), else: description_translations
  end

  # 4. Return merged data with bilingual translations
  %{
    base_data |
    title_translations: title_translations,
    description_translations: description_translations
  }
end
```

**Key Principles to Follow**:
1. Fetch both language versions of the same event
2. Validate they refer to the same event (prevent mismatches)
3. Merge translations into language-keyed map
4. Graceful fallback to single language if validation fails
5. Log warnings for translation mismatches

---

## Implementation Plan

### Phase 1: Research & Documentation ✅ (CURRENT)

**Objective**: Understand Sortiraparis multilingual structure and plan implementation.

**Tasks**:
- [x] Verify Sortiraparis has French sitemaps (sitemap-fr-*.xml)
- [x] Document URL patterns for English vs French
- [x] Confirm database schema supports multiple languages
- [x] Identify reference implementation (Karnet bilingual scraper)
- [x] Create comprehensive GitHub issue with phased plan
- [ ] Update translation handling documentation
- [ ] Define success criteria for each phase

**Deliverables**:
- This GitHub issue documenting research and plan
- Updated translation handling documentation
- Clear acceptance criteria for future phases

**Success Criteria**:
- All research questions answered with evidence
- Clear technical approach documented
- No ambiguity about how to implement

---

### Phase 2: Sitemap Discovery Enhancement

**Objective**: Update scraper configuration to include French sitemaps.

**Tasks**:
1. Update `config.ex` to include French sitemap URLs:
   ```elixir
   def sitemap_urls do
     [
       # English sitemaps
       "#{@base_url}/sitemap-en-1.xml",
       "#{@base_url}/sitemap-en-2.xml",
       "#{@base_url}/sitemap-en-3.xml",
       "#{@base_url}/sitemap-en-4.xml",
       # French sitemaps
       "#{@base_url}/sitemap-fr-1.xml",
       "#{@base_url}/sitemap-fr-2.xml",
       # Add more as discovered
     ]
   end
   ```
2. Add language metadata to sitemap processing
3. Track which language each URL belongs to
4. Handle duplicate article IDs across languages (same event, different language)

**Files to Modify**:
- `lib/eventasaurus_discovery/sources/sortiraparis/config.ex`
- `lib/eventasaurus_discovery/sources/sortiraparis.ex` (sitemap processing)

**Success Criteria**:
- Config includes both EN and FR sitemaps
- Scraper discovers both language versions of same article
- No duplicate event creation (proper consolidation)

---

### Phase 3: Bilingual Content Fetching

**Objective**: Implement logic to fetch both English and French versions of each article.

**Tasks**:
1. Add language parameter to `Client` module:
   ```elixir
   def fetch_page_with_language(url, language \\ "en") do
     localized_url = localize_url(url, language)
     fetch_page(localized_url)
   end

   defp localize_url(url, "fr") do
     # Remove /en/ prefix for French (default)
     String.replace(url, "/en/", "/")
   end

   defp localize_url(url, "en") do
     # Ensure /en/ prefix for English
     if String.contains?(url, "/en/") do
       url
     else
       String.replace(url, "/articles/", "/en/articles/")
     end
   end
   ```

2. Update scraper to fetch both language versions:
   ```elixir
   def scrape_event(url, opts \\\\ []) do
     # Fetch both language versions
     with {:ok, en_html} <- Client.fetch_page_with_language(url, "en"),
          {:ok, fr_html} <- Client.fetch_page_with_language(url, "fr"),
          {:ok, en_data} <- EventExtractor.extract(en_html, url),
          {:ok, fr_data} <- EventExtractor.extract(fr_html, url) do

       # Merge translations
       merged_data = merge_translations(en_data, fr_data)
       {:ok, merged_data}
     end
   end
   ```

3. Handle edge cases:
   - One language unavailable (404)
   - Network errors during second fetch
   - Rate limiting (add delay between language requests)

**Files to Modify**:
- `lib/eventasaurus_discovery/sources/sortiraparis/client.ex`
- `lib/eventasaurus_discovery/sources/sortiraparis.ex`

**Success Criteria**:
- Client can fetch both EN and FR versions
- Rate limiting respected (delay between requests)
- Graceful degradation if one language fails

---

### Phase 4: Translation Merging

**Objective**: Merge English and French content into unified event record following Karnet pattern.

**Tasks**:
1. Implement `merge_translations/2` function:
   ```elixir
   defp merge_translations(en_data, fr_data) do
     # Validate both versions refer to same event
     if validate_translation_match(en_data, fr_data) do
       %{
         en_data |
         description_translations: %{
           "en" => en_data["description"],
           "fr" => fr_data["description"]
         }
       }
     else
       Logger.warning("⚠️ French translation seems unrelated, using English only")
       %{
         en_data |
         description_translations: %{"en" => en_data["description"]}
       }
     end
   end

   defp validate_translation_match(en_data, fr_data) do
     # Check article IDs match
     # Check venue names are similar
     # Check dates are identical
     # Return true if confident they're same event
   end
   ```

2. Update `Transformer` to handle merged translations:
   ```elixir
   description_translations:
     case raw_event do
       %{"description_translations" => translations} when is_map(translations) ->
         translations  # Use multi-language map

       %{"description" => desc} ->
         # Fallback for single language (backward compatibility)
         %{"en" => desc}

       _ ->
         nil
     end,
   ```

3. Add comprehensive logging for translation merging:
   - Log when both languages successfully merged
   - Warn when validation fails
   - Track translation completeness metrics

**Files to Modify**:
- `lib/eventasaurus_discovery/sources/sortiraparis.ex` (add merge function)
- `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex` (lines 266-271)

**Success Criteria**:
- Translations merged into `%{"en" => "...", "fr" => "..."}`
- Validation prevents mismatched events
- Logs provide visibility into merge success/failure

---

### Phase 5: Testing & Validation

**Objective**: Verify bilingual scraping works correctly with real Sortiraparis data.

**Test Strategy**:
1. **Sample Event Testing**:
   - Select 5 representative Sortiraparis articles
   - Verify both EN and FR versions extracted
   - Confirm translations are actually different (not duplicates)
   - Check all event types (one_time, exhibition, recurring)

2. **Database Validation**:
   ```sql
   -- Verify French translations present
   SELECT
     COUNT(*) as total_events,
     COUNT(CASE WHEN pes.description_translations ? 'fr' THEN 1 END) as with_french,
     COUNT(CASE WHEN pes.description_translations ? 'en' THEN 1 END) as with_english
   FROM public_event_sources pes
   JOIN sources s ON s.id = pes.source_id
   WHERE s.name = 'Sortiraparis';
   ```

3. **Quality Checks**:
   - Translations are different (not duplicates)
   - French text is actually in French
   - English text is actually in English
   - Database constraints satisfied (especially `is_free` pricing)

4. **Performance Testing**:
   - Measure scraping time with dual-language fetching
   - Verify rate limiting works correctly
   - Ensure no memory leaks with larger datasets

**Test Cases**:
```elixir
test "sortiraparis extracts french description" do
  event = scrape_sortiraparis_event(sample_url)

  assert event.description_translations["fr"] != nil
  assert event.description_translations["en"] != nil
  assert event.description_translations["fr"] != event.description_translations["en"]
end

test "sortiraparis rate limits dual language requests" do
  start_time = System.monotonic_time(:millisecond)
  scrape_sortiraparis_event(sample_url)
  end_time = System.monotonic_time(:millisecond)
  duration = end_time - start_time

  # Should take at least rate_limit * 2 (two requests)
  assert duration >= Config.rate_limit() * 2 * 1000
end
```

**Success Criteria**:
- ≥90% of events have both EN and FR descriptions
- Translations are verified as different
- No database constraint violations
- Performance remains acceptable (2x requests = ~2x time)

---

## Documentation Updates

### 1. Translation Handling Documentation (New/Update)

**Create**: `docs/TRANSLATION_HANDLING.md` (or update existing)

**Contents**:
- How `description_translations` JSONB works
- Language code conventions (ISO 639-1: "en", "fr", "pl", etc.)
- How to implement bilingual scraping (reference Karnet pattern)
- Validation requirements (ensure translations match same event)
- Database constraints (is_free must have null prices)
- Best practices for translation merging

**Example Section**:
```markdown
## Bilingual Scraping Pattern

When implementing bilingual scraping, follow this pattern:

1. **Fetch both language versions**: Make separate HTTP requests for each language
2. **Validate match**: Ensure both versions refer to same event (check IDs, dates, venue)
3. **Merge translations**: Combine into language-keyed map
4. **Graceful fallback**: Use single language if validation fails
5. **Log warnings**: Track translation mismatches for monitoring

See `lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex:434-535` for reference implementation.
```

---

### 2. Sortiraparis Scraper README (Update)

**File**: `lib/eventasaurus_discovery/sources/sortiraparis/README.md`

**Add Section**:
```markdown
## Multilingual Support

The Sortiraparis scraper extracts both English and French translations.

### Language Structure

- **English sitemaps**: `/sitemap-en-{1,2,3,4}.xml`
- **French sitemaps**: `/sitemap-fr-*.xml`

### URL Patterns

- English: `/en/articles/{article_id}`
- French: `/articles/{article_id}` (default, no language prefix)

### Translation Storage

Translations are stored in the `description_translations` JSONB column:

```json
{
  "en": "English description text...",
  "fr": "French description text..."
}
```

### Adding Additional Languages

To add support for another language:
1. Verify Sortiraparis has sitemap for that language
2. Add sitemap URLs to `config.ex`
3. Update `localize_url/2` in client with new language pattern
4. Add language code to merge function
```

---

### 3. Cross-Reference Documentation

**Update**: `ISSUE_LANGUAGE_HANDLING.md`

Add note at top:
```markdown
> **Note**: For Sortiraparis-specific implementation, see `ISSUE_SORTIRAPARIS_FRENCH_TRANSLATIONS.md`. This document covers general language handling strategy across all sources.
```

---

## Technical Details

### Files Involved

1. **Configuration**:
   - `lib/eventasaurus_discovery/sources/sortiraparis/config.ex` (lines 41-53)
   - Add French sitemap URLs

2. **Client**:
   - `lib/eventasaurus_discovery/sources/sortiraparis/client.ex`
   - Add language parameter support

3. **Scraper**:
   - `lib/eventasaurus_discovery/sources/sortiraparis.ex`
   - Implement bilingual fetching and merging

4. **Transformer**:
   - `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex` (lines 266-271)
   - Update to handle multi-language description_translations

5. **Event Extractor**:
   - `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex`
   - May need minor updates for language-aware extraction

### Database Schema

**No schema changes required** - existing JSONB column supports multiple languages:

```sql
-- Current: {"en": "..."}
-- Target:  {"en": "...", "fr": "..."}
```

### Rate Limiting Considerations

**Current**: Single HTTP request per event
**Target**: Two HTTP requests per event (EN + FR)

**Strategy**:
- Add configurable delay between language requests (default: 1 second)
- Use exponential backoff for 429 errors
- Consider batching if performance becomes issue
- Monitor scraping duration (expect ~2x increase)

---

## Success Metrics

### Phase 1 (Research & Documentation)
- [x] Sortiraparis multilingual architecture documented
- [x] Sitemap structure verified
- [x] URL patterns documented
- [x] Reference implementation identified
- [x] Database mechanism understood
- [ ] Translation handling documentation created/updated
- [ ] GitHub issue created with phased plan

### Phase 2 (Sitemap Discovery)
- [ ] Config includes both EN and FR sitemaps
- [ ] Scraper discovers both language versions
- [ ] Proper consolidation (no duplicate events)

### Phase 3 (Bilingual Fetching)
- [ ] Client can fetch both EN and FR versions
- [ ] Rate limiting respected
- [ ] Graceful degradation on errors

### Phase 4 (Translation Merging)
- [ ] Translations merged correctly
- [ ] Validation prevents mismatches
- [ ] Comprehensive logging

### Phase 5 (Testing & Validation)
- [ ] ≥90% events have both EN and FR
- [ ] Translations verified as different
- [ ] No database constraint violations
- [ ] Performance acceptable

---

## Related Issues

- `ISSUE_LANGUAGE_HANDLING.md` - General language handling strategy
- `ISSUE_SORTIRAPARIS_ANALYSIS.md` - Event consolidation investigation

---

## Next Steps

**Immediate** (Phase 1):
1. ✅ Complete research and documentation
2. ✅ Create this GitHub issue
3. ⏳ Update translation handling documentation
4. ⏳ Define acceptance criteria for Phase 2

**Short-term** (Phase 2):
1. Update config.ex with French sitemaps
2. Test sitemap discovery
3. Verify no duplicate event creation

**Medium-term** (Phases 3-4):
1. Implement bilingual fetching in Client
2. Implement translation merging
3. Update Transformer for multi-language support

**Long-term** (Phase 5):
1. Comprehensive testing with real data
2. Performance optimization
3. Consider additional languages (Italian, Spanish)

---

## Notes

- **No code changes in Phase 1** - research and planning only
- User confirmed: "we do not care about the data on our database. We're just going to dump it" - safe to re-scrape after implementation
- French is PRIMARY language for Sortiraparis (Paris-based source)
- Follow Karnet pattern for consistency across scrapers
- Database already supports multiple languages - no schema migration needed
- Rate limiting critical to avoid being blocked by Sortiraparis

---

**Created**: 2025-10-18
**Last Updated**: 2025-10-18
**Status**: Phase 1 - Research & Documentation Complete
