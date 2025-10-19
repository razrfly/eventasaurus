# Translation Handling System

**Status**: Active
**Last Updated**: 2025-10-18
**Applies To**: All event scrapers with multilingual content

---

## Overview

Eventasaurus stores multilingual event content in JSONB columns, allowing flexible storage of descriptions, titles, and other text fields in multiple languages. This approach provides:

- **Flexible Language Support**: Add new languages without schema changes
- **Fallback Chains**: Display content in user's preferred language or fallback to English
- **Source Fidelity**: Preserve original language content from event sources
- **Future-Proof**: Easily extend to support additional languages

---

## Database Schema

### Primary Translation Column

**Table**: `public_event_sources`
**Column**: `description_translations` (JSONB)

**Format**:
```json
{
  "en": "English description text...",
  "fr": "French description text...",
  "pl": "Polish description text...",
  "es": "Spanish description text..."
}
```

### Language Codes

Use **ISO 639-1** (two-letter) language codes:

| Code | Language | Example Sources |
|------|----------|----------------|
| `en` | English | Sortiraparis (EN), Karnet (EN), Most international sources |
| `fr` | French | Sortiraparis (FR) |
| `pl` | Polish | Karnet (PL) |
| `es` | Spanish | Future sources |
| `de` | German | Future sources |
| `it` | Italian | Future sources |

**Reference**: [ISO 639-1 Language Codes](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)

### Database Constraints

**IMPORTANT**: When storing translations, respect existing database constraints:

1. **Pricing Constraint**: If `is_free = true`, then `min_price` and `max_price` must be `NULL`
2. **Required Fields**: `title`, `starts_at`, `external_id` are required regardless of language
3. **JSONB Format**: Must be valid JSON object with string keys and string values

---

## Bilingual Scraping Pattern

When implementing scrapers that extract content in multiple languages, follow this established pattern:

### 1. Fetch Both Language Versions

Make separate HTTP requests for each language version of the same event:

```elixir
defp scrape_bilingual_event(base_url, event_id, opts \\ []) do
  # Fetch primary language
  with {:ok, primary_html} <- Client.fetch_page(build_url(base_url, event_id, :primary)),
       {:ok, primary_data} <- Extractor.extract(primary_html),

       # Fetch secondary language
       {:ok, secondary_html} <- Client.fetch_page(build_url(base_url, event_id, :secondary)),
       {:ok, secondary_data} <- Extractor.extract(secondary_html) do

    # Merge translations
    merge_translations(primary_data, secondary_data)
  else
    {:error, reason} ->
      Logger.warning("Failed to fetch bilingual data: #{inspect(reason)}")
      {:error, reason}
  end
end
```

### 2. Validate Translation Match

Before merging, verify both versions refer to the same event:

```elixir
defp validate_translation_match(primary_data, secondary_data) do
  # Compare stable identifiers
  same_id? = primary_data.event_id == secondary_data.event_id

  # Compare structural data (dates should match exactly)
  same_dates? = DateTime.compare(primary_data.starts_at, secondary_data.starts_at) == :eq

  # Venue names should be similar (allow for translation differences)
  venue_similarity = String.jaro_distance(
    String.downcase(primary_data.venue_name),
    String.downcase(secondary_data.venue_name)
  )
  similar_venue? = venue_similarity > 0.7

  # All validation checks must pass
  same_id? && same_dates? && similar_venue?
end
```

**Key Validation Points**:
- Event IDs must match exactly
- Dates and times must be identical (same UTC DateTime)
- Venue names should be similar (>70% string similarity)
- Pricing information should be consistent

### 3. Merge Translations

If validation passes, merge language content into translation maps:

```elixir
defp merge_translations(primary_data, secondary_data) do
  if validate_translation_match(primary_data, secondary_data) do
    %{
      primary_data |
      description_translations: %{
        "en" => primary_data.description,    # Primary language
        "fr" => secondary_data.description   # Secondary language
      },
      title_translations: %{
        "en" => primary_data.title,
        "fr" => secondary_data.title
      }
    }
  else
    Logger.warning("⚠️ Translation validation failed, using primary language only")

    # Fallback to single language
    %{
      primary_data |
      description_translations: %{"en" => primary_data.description}
    }
  end
end
```

### 4. Graceful Fallback

Handle cases where one language is unavailable:

```elixir
defp scrape_bilingual_event(base_url, event_id, opts) do
  # Always try both languages, but don't fail if one is missing
  primary_result = fetch_and_extract(base_url, event_id, :primary)
  secondary_result = fetch_and_extract(base_url, event_id, :secondary)

  case {primary_result, secondary_result} do
    {{:ok, primary}, {:ok, secondary}} ->
      # Both available - merge
      {:ok, merge_translations(primary, secondary)}

    {{:ok, primary}, {:error, _reason}} ->
      # Only primary available
      Logger.info("Secondary language unavailable, using primary only")
      {:ok, add_single_translation(primary, "en")}

    {{:error, _reason}, {:ok, secondary}} ->
      # Only secondary available (rare)
      Logger.info("Primary language unavailable, using secondary only")
      {:ok, add_single_translation(secondary, "fr")}

    {{:error, _}, {:error, _}} ->
      # Both failed
      {:error, :no_translations_available}
  end
end
```

### 5. Logging and Monitoring

Add comprehensive logging for translation operations:

```elixir
defp merge_translations(primary_data, secondary_data) do
  if validate_translation_match(primary_data, secondary_data) do
    Logger.info("✅ Successfully merged translations for event: #{primary_data.external_id}")
    Logger.debug("Languages: #{inspect(Map.keys(merged.description_translations))}")

    # Merge logic...
  else
    Logger.warning("⚠️ Translation mismatch for event: #{primary_data.external_id}")
    Logger.debug("Primary: #{inspect(primary_data)}")
    Logger.debug("Secondary: #{inspect(secondary_data)}")

    # Fallback logic...
  end
end
```

**Logging Recommendations**:
- ✅ `info`: Successful translation merges
- ⚠️ `warning`: Validation failures, translation mismatches
- 🐛 `debug`: Detailed comparison data for troubleshooting
- 🚨 `error`: Complete translation failures

---

## Reference Implementation: Karnet

The **Karnet** scraper provides the canonical example of bilingual scraping (Polish + English).

**File**: `lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex:434-535`

### Key Implementation Details

```elixir
defp merge_language_data(polish_data, english_data, metadata) do
  # 1. Start with primary language (Polish) as base
  base_data = merge_metadata(polish_data, metadata)

  polish_title = polish_data[:title]
  english_title = english_data[:title]

  # 2. Validate both versions refer to same event
  if english_title && !validate_translation_match(polish_data, english_data) do
    Logger.warning("⚠️ English translation seems unrelated, skipping")

    # Only use Polish data if validation fails
    title_translations = %{"pl" => polish_title}
    description_translations = %{"pl" => get_description_text(polish_data)}
  else
    # 3. Merge both languages into translations map
    title_translations = %{}
    title_translations =
      if polish_title,
        do: Map.put(title_translations, "pl", polish_title),
        else: title_translations
    title_translations =
      if english_title,
        do: Map.put(title_translations, "en", english_title),
        else: title_translations

    description_translations = %{}
    polish_desc = get_description_text(polish_data)
    english_desc = get_description_text(english_data)

    description_translations =
      if polish_desc,
        do: Map.put(description_translations, "pl", polish_desc),
        else: description_translations
    description_translations =
      if english_desc,
        do: Map.put(description_translations, "en", english_desc),
        else: description_translations
  end

  # 4. Return merged data with bilingual translations
  %{
    base_data |
    title_translations: title_translations,
    description_translations: description_translations
  }
end
```

### Karnet Pattern Summary

1. **Fetch Strategy**:
   - Polish URL: `/pl/{slug}` (primary language)
   - English URL: `/en/{slug}` (secondary language)

2. **Validation Approach**:
   - Checks title similarity
   - Compares event dates
   - Verifies venue consistency

3. **Merge Strategy**:
   - Polish as base (primary language for source)
   - English added if validation passes
   - Graceful degradation to single language

4. **Error Handling**:
   - Logs validation failures
   - Falls back to primary language
   - Never fails completely due to missing translations

---

## Sortiraparis Implementation Plan

For detailed implementation of French translations in the Sortiraparis scraper, see:

**GitHub Issue**: #1835 - Add French Translation Support to Sortiraparis Scraper
**Documentation**: `ISSUE_SORTIRAPARIS_FRENCH_TRANSLATIONS.md`

### Sortiraparis Language Structure

- **English sitemaps**: `/sitemap-en-{1,2,3,4}.xml`
- **French sitemaps**: `/sitemap-fr-*.xml`
- **English URLs**: `/en/articles/{article_id}`
- **French URLs**: `/articles/{article_id}` (default, no language prefix)

### Implementation Status

- **Phase 1**: Research & Documentation ✅ (Complete)
- **Phase 2**: Sitemap Discovery Enhancement 🔄 (Planned)
- **Phase 3**: Bilingual Content Fetching 🔄 (Planned)
- **Phase 4**: Translation Merging 🔄 (Planned)
- **Phase 5**: Testing & Validation 🔄 (Planned)

---

## Rate Limiting Considerations

**Important**: Bilingual scraping doubles HTTP requests per event.

### Rate Limiting Strategy

```elixir
defp fetch_with_rate_limit(url, language, opts) do
  # Get rate limit from config (default: 1 second between requests)
  rate_limit_ms = Keyword.get(opts, :rate_limit_ms, 1000)

  # Fetch content
  result = Client.fetch_page(url)

  # Wait before next request (respects rate limiting)
  Process.sleep(rate_limit_ms)

  result
end

defp scrape_bilingual_event(base_url, event_id, opts) do
  # First language - no delay needed (first request)
  {:ok, primary} = fetch_with_rate_limit(
    build_url(base_url, event_id, :primary),
    "en",
    opts
  )

  # Second language - rate limit applied automatically
  {:ok, secondary} = fetch_with_rate_limit(
    build_url(base_url, event_id, :secondary),
    "fr",
    opts
  )

  merge_translations(primary, secondary)
end
```

### Performance Impact

| Strategy | Requests per Event | Expected Time | Notes |
|----------|-------------------|---------------|-------|
| Single Language | 1 | 1x baseline | Current approach |
| Bilingual (Sequential) | 2 | ~2x baseline | Add rate limit delay between requests |
| Bilingual (Parallel) | 2 | ~1x baseline | Risk of rate limiting, not recommended |

**Recommendation**: Use sequential fetching with configurable delay to respect rate limits.

### Error Handling for Rate Limits

```elixir
defp fetch_with_retry(url, language, retries \\ 3) do
  case Client.fetch_page(url) do
    {:ok, content} ->
      {:ok, content}

    {:error, %{status: 429}} when retries > 0 ->
      # Rate limited - exponential backoff
      backoff_ms = :math.pow(2, 4 - retries) * 1000
      Logger.warning("Rate limited, retrying in #{backoff_ms}ms (#{retries} retries left)")
      Process.sleep(trunc(backoff_ms))
      fetch_with_retry(url, language, retries - 1)

    {:error, reason} ->
      {:error, reason}
  end
end
```

---

## Testing Translation Implementation

### Unit Tests

```elixir
defmodule MySource.TransformerTest do
  use ExUnit.Case

  describe "bilingual translation extraction" do
    test "extracts both English and French descriptions" do
      event = scrape_event(sample_bilingual_url())

      assert event.description_translations["en"] != nil
      assert event.description_translations["fr"] != nil
      assert event.description_translations["en"] != event.description_translations["fr"]
    end

    test "validates translations refer to same event" do
      primary = %{event_id: "123", title: "Concert", starts_at: ~U[2025-12-01 20:00:00Z]}
      secondary = %{event_id: "456", title: "Concert", starts_at: ~U[2025-12-01 20:00:00Z]}

      refute validate_translation_match(primary, secondary)
    end

    test "falls back to single language on validation failure" do
      event = scrape_event_with_mismatched_translation()

      # Should only have one language
      assert map_size(event.description_translations) == 1
    end
  end
end
```

### Integration Tests

```elixir
defmodule MySource.IntegrationTest do
  use EventasaurusDiscovery.DataCase

  test "bilingual event stored correctly in database" do
    event_data = %{
      description_translations: %{
        "en" => "English description",
        "fr" => "Description française"
      }
    }

    {:ok, event} = EventProcessor.process_event(event_data)

    # Verify database storage
    event = Repo.get(PublicEvent, event.id) |> Repo.preload(:public_event_sources)
    source = List.first(event.public_event_sources)

    assert source.description_translations["en"] == "English description"
    assert source.description_translations["fr"] == "Description française"
  end
end
```

### Database Validation Queries

```sql
-- Check translation completeness
SELECT
  s.name as source,
  COUNT(*) as total_events,
  COUNT(CASE WHEN pes.description_translations ? 'en' THEN 1 END) as with_english,
  COUNT(CASE WHEN pes.description_translations ? 'fr' THEN 1 END) as with_french,
  ROUND(
    100.0 * COUNT(CASE WHEN pes.description_translations ? 'fr' THEN 1 END) / COUNT(*),
    2
  ) as french_percentage
FROM public_event_sources pes
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Sortiraparis'
GROUP BY s.name;

-- Find events missing translations
SELECT
  pe.id,
  pe.title,
  pe.slug,
  pes.description_translations
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Sortiraparis'
  AND (
    NOT (pes.description_translations ? 'fr')
    OR pes.description_translations->'fr' IS NULL
  )
LIMIT 10;

-- Verify translations are actually different (not duplicates)
SELECT
  pe.id,
  pe.title,
  pes.description_translations->'en' = pes.description_translations->'fr' as is_duplicate
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Sortiraparis'
  AND pes.description_translations ? 'en'
  AND pes.description_translations ? 'fr'
  AND pes.description_translations->'en' = pes.description_translations->'fr';
-- Should return 0 rows (no duplicates)
```

---

## Best Practices

### DO ✅

1. **Use ISO 639-1 language codes** (two-letter: "en", "fr", "pl")
2. **Validate translations match** before merging (event ID, dates, venue)
3. **Log validation failures** with detailed context for debugging
4. **Gracefully fallback** to single language if second language unavailable
5. **Respect rate limits** when fetching multiple language versions
6. **Test translation completeness** with database queries
7. **Verify translations differ** (not duplicates due to bugs)
8. **Document language structure** in scraper README

### DON'T ❌

1. **Don't hardcode language assumptions** - verify language with actual content
2. **Don't skip validation** - mismatched translations cause data quality issues
3. **Don't fail completely** if one translation missing - use available language(s)
4. **Don't ignore rate limiting** - bilingual scraping doubles requests
5. **Don't duplicate content** - ensure translations are actually different
6. **Don't use three-letter codes** - stick to ISO 639-1 (two-letter)
7. **Don't modify schema** for new languages - JSONB supports arbitrary keys
8. **Don't store empty translations** - omit language key if content unavailable

---

## Adding New Languages

### Process

1. **Research Source Language Support**:
   - Verify source website has content in target language
   - Identify URL patterns for language-specific pages
   - Check sitemap structure (language-specific sitemaps?)

2. **Update Scraper Configuration**:
   ```elixir
   # Add language-specific URLs to config
   def sitemap_urls(language \\ :all) do
     case language do
       :en -> ["#{@base_url}/sitemap-en-*.xml"]
       :fr -> ["#{@base_url}/sitemap-fr-*.xml"]
       :es -> ["#{@base_url}/sitemap-es-*.xml"]  # New language
       :all -> sitemap_urls(:en) ++ sitemap_urls(:fr) ++ sitemap_urls(:es)
     end
   end
   ```

3. **Implement Language Parameter**:
   ```elixir
   def fetch_page_with_language(url, language) do
     localized_url = localize_url(url, language)
     Client.fetch_page(localized_url)
   end

   defp localize_url(url, "es") do
     # Add Spanish URL pattern
     String.replace(url, "/articles/", "/es/articles/")
   end
   ```

4. **Update Merge Function**:
   ```elixir
   defp merge_translations(en_data, fr_data, es_data) do
     %{
       description_translations: %{
         "en" => en_data.description,
         "fr" => fr_data.description,
         "es" => es_data.description  # Add new language
       }
     }
   end
   ```

5. **Add Tests**:
   ```elixir
   test "extracts Spanish translations" do
     event = scrape_event(sample_spanish_url())
     assert event.description_translations["es"] != nil
   end
   ```

6. **Update Documentation**:
   - Add language to scraper README
   - Update this document with language code
   - Document URL patterns and sitemap structure

**No schema changes required** - JSONB column supports arbitrary language keys.

---

## Troubleshooting

### Issue: Translations are duplicates (same text in both languages)

**Symptoms**:
```json
{
  "en": "Description française de l'événement",
  "fr": "Description française de l'événement"
}
```

**Causes**:
- Scraper fetching same language URL twice
- Language detection logic incorrect
- Source website serving same content regardless of URL

**Solution**:
```elixir
# Add language verification after extraction
defp verify_language(content, expected_language) do
  detected_language = LanguageDetector.detect(content)

  if detected_language != expected_language do
    Logger.warning("Expected #{expected_language}, got #{detected_language}")
    {:error, :language_mismatch}
  else
    {:ok, content}
  end
end
```

### Issue: Validation always fails (translations never merge)

**Symptoms**: All events only have single language despite source having both

**Causes**:
- Validation logic too strict (e.g., venue names differ significantly)
- Dates not normalized to UTC
- Event IDs different across languages

**Solution**:
```elixir
# Relax validation for venue names (allow translation differences)
defp validate_translation_match(primary, secondary) do
  # RELAXED: Only check event ID and dates, not venue
  same_id? = primary.event_id == secondary.event_id
  same_dates? = DateTime.compare(primary.starts_at, secondary.starts_at) == :eq

  if same_id? && same_dates? do
    true
  else
    Logger.debug("Validation failed: id=#{same_id?}, dates=#{same_dates?}")
    false
  end
end
```

### Issue: Rate limiting (429 errors)

**Symptoms**: Frequent 429 errors when scraping with multiple languages

**Solution**:
```elixir
# Increase delay between requests
config :eventasaurus_discovery, MySource,
  rate_limit_ms: 2000  # Increase from 1000ms to 2000ms

# Add exponential backoff for retries
defp fetch_with_backoff(url, retry \\ 0) do
  case Client.fetch_page(url) do
    {:error, %{status: 429}} when retry < 3 ->
      wait_ms = :math.pow(2, retry) * 1000
      Process.sleep(trunc(wait_ms))
      fetch_with_backoff(url, retry + 1)

    result -> result
  end
end
```

---

## Related Documentation

- **Sortiraparis French Translation Implementation**: `ISSUE_SORTIRAPARIS_FRENCH_TRANSLATIONS.md` (GitHub #1835)
- **General Language Handling Strategy**: `ISSUE_LANGUAGE_HANDLING.md`
- **Karnet Bilingual Implementation**: `lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex`
- **Scraper Development Guide**: `docs/ADDING_NEW_SOURCES.md`
- **Database Schema**: View `public_event_sources` table with `\d public_event_sources`

---

## Future Improvements

### Planned Enhancements

1. **Automatic Language Detection**:
   - Use NLP library to verify extracted content is in expected language
   - Warn if language mismatch detected

2. **Translation Quality Scoring**:
   - Track completeness (% of events with each language)
   - Monitor for duplicate translations (same text in multiple languages)
   - Alert on quality degradation

3. **Title Translations**:
   - Add `title_translations` JSONB column
   - Currently only descriptions are translated
   - Useful for displaying localized event titles

4. **Additional Language Support**:
   - Spanish (es) - for Spanish event sources
   - German (de) - for German event sources
   - Italian (it) - for Italian event sources

5. **Performance Optimization**:
   - Batch processing for multiple language requests
   - Parallel fetching with smart rate limiting
   - Caching translation mappings across scrapes

---

**Maintained By**: Eventasaurus Engineering Team
**Questions**: See related documentation or GitHub issues
**Last Reviewed**: 2025-10-18
