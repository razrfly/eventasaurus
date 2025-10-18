# Issue: Language Handling - Wrong Languages Shown & Missing French Translations

**Status**: Enhancement - High Priority
**Severity**: Medium - Affects user experience and internationalization
**Affected Component**: Language selection, Sortiraparis scraper, UI language display
**Date Discovered**: 2025-10-18

---

## Problem Summary

Two related language issues:

1. **Wrong Language Display**: Polish language option appears for Paris/France events (from Karnet Kraków), which is incorrect
2. **Missing French Translations**: Sortiraparis scraper only downloads English content, not French translations, despite being a French source

**User Impact**:
- Users see Polish as a language option in Paris (geographically nonsensical)
- Missing French translations for events in France
- Poor localization experience for French-speaking users
- Confusing language selector with irrelevant options

---

## Evidence

### Database Analysis

**Sortiraparis Event Languages**:
```sql
SELECT
  pe.id,
  pe.title,
  (SELECT jsonb_object_keys(pes.description_translations)) as available_languages
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Sortiraparis'
LIMIT 5;
```

**Result**: All Sortiraparis events have only `"en"` (English) language.

**Expected**: Should have `"fr"` (French) and possibly `"en"` (English).

### UI Language Display

When viewing Paris events, users see language options including:
- 🇵🇱 Polish (from Karnet Kraków events in Kraków)
- 🇬🇧 English (correct)
- ❌ Missing: 🇫🇷 French (should be primary for Paris)

**Problem**: Language selector shows ALL languages from ALL events, regardless of geographic relevance.

---

## Root Cause Analysis

### Issue 1: Polish Appearing in Paris

**Cause**: UI displays all available languages from aggregated event sources without filtering by country/region.

**Event Flow**:
1. Paris page loads events from multiple sources
2. Karnet Kraków events may appear if they match search/filters
3. UI collects ALL `description_translations` keys from all events
4. Language selector shows: `["en", "pl"]`
5. User sees Polish option even though they're browsing Paris

**Files Involved**:
- Language selector component (needs geographic filtering)
- Event query logic (may be including non-Paris events)

### Issue 2: Missing French Translations

**Cause**: Sortiraparis scraper only extracts English content, doesn't check for French versions.

**Current Implementation** (transformer.ex:249-254):
```elixir
description_translations:
  case Map.get(raw_event, "description") do
    nil -> nil
    "" -> nil
    desc -> %{"en" => desc}  # ← Hardcoded "en" only
  end,
```

**Sortiraparis.com URL Structure**:
- English: `https://www.sortiraparis.com/en/articles/...`
- French: `https://www.sortiraparis.com/articles/...` (default)

**Problem**: Scraper only visits English URLs, doesn't fetch French content.

---

## Technical Details

### Issue 1: Language Filtering

#### Current Behavior

Language selector logic (likely in language helpers or LiveView):
```elixir
def available_languages(events) do
  events
  |> Enum.flat_map(fn event ->
    event.sources
    |> Enum.map(& &1.description_translations)
    |> Enum.flat_map(&Map.keys/1)
  end)
  |> Enum.uniq()
end
```

**Result**: All languages from all events, regardless of relevance.

#### Expected Behavior

Language selector should filter by:
1. **Geographic Context**: Only show languages relevant to the current city/country
2. **Event Availability**: Only show languages that have translations for displayed events
3. **Priority Order**: Show primary language(s) for the region first

```elixir
def available_languages_for_location(events, city) do
  # Get country from city
  country = city.country

  # Define relevant languages per country
  relevant_languages =
    case country.code do
      "FR" -> ["fr", "en"]  # France: French primary, English secondary
      "PL" -> ["pl", "en"]  # Poland: Polish primary, English secondary
      "US" -> ["en", "es"]  # USA: English primary, Spanish secondary
      _ -> ["en"]  # Default: English
    end

  # Filter available languages to relevant ones
  events
  |> get_all_available_languages()
  |> Enum.filter(&(&1 in relevant_languages))
  |> sort_by_relevance(country)
end
```

### Issue 2: French Translation Scraping

#### Current Scraper Behavior

**Sitemap URLs** (client.ex):
```elixir
# Currently scrapes English sitemap only
@sitemap_url "https://www.sortiraparis.com/sitemap-en-1.xml"
```

**Event Extraction** (event_extractor.ex):
- Extracts description from HTML in current language (English)
- No logic to detect/fetch alternate language versions

#### Expected Scraper Behavior

**Option A: Scrape Both Languages Simultaneously**
```elixir
# 1. Fetch English URL
english_html = fetch_page("https://www.sortiraparis.com/en/articles/#{id}")
english_desc = extract_description(english_html)

# 2. Fetch French URL (default/canonical)
french_html = fetch_page("https://www.sortiraparis.com/articles/#{id}")
french_desc = extract_description(french_html)

# 3. Build translations map
description_translations = %{
  "en" => english_desc,
  "fr" => french_desc
}
```

**Option B: Detect Available Languages from HTML**
```elixir
# Check for language switcher links in HTML
available_langs = extract_available_languages(html)
# ["en", "fr"]

# Fetch each language version
translations =
  Enum.map(available_langs, fn lang ->
    url = build_language_url(base_url, lang)
    html = fetch_page(url)
    desc = extract_description(html)
    {lang, desc}
  end)
  |> Map.new()
```

---

## Solution Options

### Issue 1: Geographic Language Filtering

#### Option 1A: City-Based Language Filtering (Recommended)

**Change**: Filter languages based on current city's country.

```elixir
# In language helper or LiveView
def available_languages_for_city(events, city) do
  country_languages = CountryLanguages.get_languages(city.country.code)

  events
  |> collect_all_languages()
  |> Enum.filter(&(&1 in country_languages))
  |> sort_by_priority(city.country.code)
end
```

**Pros**:
- Geographically relevant language options
- Better UX for users browsing specific cities
- Scalable to all cities

**Cons**:
- Requires country-to-languages mapping
- May hide valid translations in edge cases

#### Option 1B: Smart Language Detection

**Change**: Only show languages that have >50% translation coverage for visible events.

```elixir
def available_languages_with_coverage(events, min_coverage \\ 0.5) do
  total_events = length(events)

  events
  |> count_translations_per_language()
  |> Enum.filter(fn {_lang, count} -> count / total_events >= min_coverage end)
  |> Enum.map(fn {lang, _count} -> lang end)
end
```

**Pros**:
- Data-driven approach
- Works across all locations
- No hardcoded mappings

**Cons**:
- May still show irrelevant languages if coverage is high
- Complex logic

---

### Issue 2: French Translation Scraping

#### Option 2A: Dual-Language Scraping (Recommended)

**Change**: Scrape both English and French versions of each Sortiraparis event.

**Implementation**:

1. **Update Client** (`sources/sortiraparis/client.ex`):
```elixir
# Add language parameter
def fetch_page_with_language(url, language \\ "en") do
  localized_url = localize_url(url, language)
  fetch_page(localized_url)
end

defp localize_url(url, "fr") do
  # Remove /en/ from URL for French
  String.replace(url, "/en/", "/")
end

defp localize_url(url, "en") do
  # Ensure /en/ in URL for English
  if String.contains?(url, "/en/") do
    url
  else
    String.replace(url, "/articles/", "/en/articles/")
  end
end
```

2. **Update Scraper** (`sources/sortiraparis.ex`):
```elixir
def scrape_event(url, opts \\ []) do
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

defp merge_translations(en_data, fr_data) do
  %{
    en_data |
    description_translations: %{
      "en" => en_data["description"],
      "fr" => fr_data["description"]
    }
  }
end
```

3. **Update Transformer** (`sources/sortiraparis/transformer.ex`):
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

**Pros**:
- Provides both English and French content
- Better UX for French-speaking users
- Maintains English for international visitors

**Cons**:
- 2x HTTP requests per event (rate limiting concerns)
- More complex scraping logic
- Longer processing time

#### Option 2B: Language Detection from HTML

**Change**: Check HTML for language tags/switchers to detect available translations.

```elixir
def detect_available_languages(html) do
  # Look for language switcher
  case Regex.scan(~r/<a[^>]*hreflang="([^"]+)"[^>]*>/i, html) do
    [] -> ["en"]  # Default to English only
    matches -> Enum.map(matches, fn [_, lang] -> lang end)
  end
end
```

**Pros**:
- Only fetches available languages
- No wasted requests for missing translations

**Cons**:
- Depends on HTML structure
- May miss translations if no switcher present

#### Option 2C: Configuration-Based Language Scraping

**Change**: Add `languages` setting to source config.

```elixir
# In sources/sortiraparis/config.ex
def languages, do: ["en", "fr"]

# In scraper
def scrape_event(url, opts) do
  Config.languages()
  |> Enum.map(fn lang ->
    {lang, fetch_and_extract(url, lang)}
  end)
  |> merge_translations()
end
```

**Pros**:
- Explicit control over languages
- Easy to add/remove languages
- Consistent with source config pattern

**Cons**:
- Manual configuration required
- May fetch non-existent translations

---

## Recommendations

### Issue 1: Language Filtering

**Implement Option 1A**: City-based language filtering

**Implementation Steps**:
1. Create country-to-languages mapping module
2. Update language selector to filter by current city's country
3. Add tests for Paris (fr, en) and Kraków (pl, en)

**Priority**: Medium (affects UX but not critical)

### Issue 2: French Translation Scraping

**Implement Option 2A**: Dual-language scraping with rate limiting

**Implementation Steps**:
1. Update Client to support language parameter
2. Modify scraper to fetch both EN and FR versions
3. Add delay between language requests (rate limiting)
4. Update transformer to handle multi-language descriptions
5. Test with sample Sortiraparis events

**Priority**: High (missing localized content for primary audience)

---

## Testing Strategy

### Issue 1: Language Filtering

**Test Cases**:
```elixir
# Paris events should show French + English only
test "paris_events_show_french_and_english_only" do
  events = get_paris_events()
  languages = available_languages_for_city(events, paris_city)

  assert "fr" in languages
  assert "en" in languages
  refute "pl" in languages
end

# Kraków events should show Polish + English only
test "krakow_events_show_polish_and_english_only" do
  events = get_krakow_events()
  languages = available_languages_for_city(events, krakow_city)

  assert "pl" in languages
  assert "en" in languages
  refute "fr" in languages
end
```

### Issue 2: French Translation Scraping

**Test Cases**:
```elixir
test "sortiraparis_extracts_french_description" do
  event = scrape_sortiraparis_event(sample_url)

  assert event.description_translations["fr"] != nil
  assert event.description_translations["en"] != nil
  assert event.description_translations["fr"] != event.description_translations["en"]
end

test "sortiraparis_rate_limits_dual_language_requests" do
  start_time = System.monotonic_time(:millisecond)

  scrape_sortiraparis_event(sample_url)

  end_time = System.monotonic_time(:millisecond)
  duration = end_time - start_time

  # Should take at least rate_limit * 2 (two requests)
  assert duration >= Config.rate_limit() * 2 * 1000
end
```

### Verification Steps

1. **Verify French Content Availability**:
```bash
# Check Sortiraparis events have French translations
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "
SELECT
  COUNT(*) as total_events,
  COUNT(CASE WHEN pes.description_translations ? 'fr' THEN 1 END) as with_french,
  COUNT(CASE WHEN pes.description_translations ? 'en' THEN 1 END) as with_english
FROM public_event_sources pes
JOIN sources s ON s.id = pes.source_id
WHERE s.name = 'Sortiraparis';
"
```

2. **Test UI Language Selector**:
```bash
# Navigate to Paris events page
# Verify language selector shows: French, English (no Polish)
curl http://localhost:4000/c/paris
```

3. **Verify Translation Quality**:
```bash
# Manually check sample events
# Compare French and English descriptions
# Ensure they're different (not duplicates)
```

---

## Impact Analysis

### Current Impact

**Issue 1 (Polish in Paris)**:
- Confusing UX for Paris users
- Unprofessional appearance (wrong language for location)
- May indicate data quality issues to users

**Issue 2 (Missing French)**:
- French-speaking users see only English descriptions
- Missing primary language for French events
- Poor localization for target audience
- Competitive disadvantage vs. French event platforms

### User Personas Affected

1. **French-speaking Paris locals**: Need French content, confused by Polish option
2. **International tourists in Paris**: Expect French and English, not Polish
3. **Event organizers in Paris**: Want events shown in French primarily

---

## Related Issues

- Need country-to-languages mapping system
- Scraper internationalization strategy
- Language priority ordering (primary vs. secondary)
- Translation completeness tracking

---

## Next Steps

### Phase 1: Language Filtering (1 week)
1. Create country-languages mapping
2. Update language selector logic
3. Test across Paris and Kraków
4. Deploy and monitor user feedback

### Phase 2: French Translation Scraping (2 weeks)
1. Update Client with language support
2. Modify scraper for dual-language fetching
3. Add rate limiting for multi-language requests
4. Update transformer for multi-language descriptions
5. Re-scrape Sortiraparis events with French content
6. Verify translation quality

### Phase 3: Monitoring & Optimization (Ongoing)
1. Track translation coverage metrics
2. Monitor scraping performance with dual languages
3. Gather user feedback on language experience
4. Consider expanding to other languages (Italian, Spanish, etc.)

---

## Additional Context

### Why Language Matters for Discovery

**SEO Impact**:
- French keywords for Paris events improve search rankings in France
- Localized content increases organic traffic

**User Trust**:
- Seeing native language builds credibility
- Shows attention to local market

**Competitive Positioning**:
- French event platforms have native language advantage
- We need parity to compete effectively

### Sortiraparis Language Support

**Website Structure**:
- Default: French (`/articles/`)
- English: (`/en/articles/`)
- Possibly other languages (to investigate)

**Content Quality**:
- French is primary/canonical version
- English translations may be slightly different
- Both should be preserved for bilingual audience
