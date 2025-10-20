# CRITICAL: Multilingual Content Not Being Persisted

## Summary

We built a comprehensive multilingual date parser (MultilingualDateParser) and transformation pipeline for Sortiraparis events, BUT zero French content is actually being stored in the database. 73 Sortiraparis events exist with NULL `title_translations` - we're only storing English content.

## Evidence

```sql
-- 73 Sortiraparis events in database
SELECT COUNT(*) FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis';
-- Result: 73

-- ZERO events with translations
SELECT COUNT(*) FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis' AND pe.title_translations IS NOT NULL;
-- Result: 0

-- Sample data - all English, no translations
SELECT pe.title, pe.title_translations FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
JOIN sources s ON s.id = pes.source_id
WHERE s.slug = 'sortiraparis' LIMIT 5;
/*
title                                           | title_translations
------------------------------------------------+--------------------
The Hives in concert at the Zenith in Paris ... | (NULL)
Chris Isaak in concert at Salle Pleyel...      | (NULL)
Et tout le Monde s'en Fout...                  | (NULL)
Kate Barry: a retrospective exhibition...      | (NULL)
50 years of Rubik's Cube...                    | (NULL)
*/
```

## Architecture Analysis

### What's Working ✅

1. **EventExtractor** - Correctly extracts raw French date strings from HTML
   - Patterns include both English and French months
   - Example: `"(?:January|February|...|janvier|février|mars|avril|...)"`

2. **MultilingualDateParser** - Correctly parses French dates
   - Language plugins for French and English
   - Successfully converts "19 mars 2025" to DateTime objects
   - Tested and verified in test scripts

3. **Transformer** - Correctly CALLS MultilingualDateParser
   - Line 553-555: `MultilingualDateParser.extract_and_parse(date_string, languages: [:french, :english], timezone: timezone)`
   - Tries French first, then English (correct priority)
   - Creates `description_translations` map (line 521-538)
   - Sets metadata `language` field (line 364, 428, 485, 305)

4. **Database Schema** - Correctly HAS multilingual fields
   - `public_events.title_translations` (JSONB)
   - PublicEvent schema includes `:title_translations` field (line 336, 389, 414)

### What's Broken ❌

**The Disconnect**: Transformer creates `description_translations` and sets `language` metadata, but this data is **never persisted to the database**.

## Root Causes

### 1. Missing Schema Field Mapping

**Issue**: Transformer creates `description_translations` (line 285, 342, 409) but:
- Database has `title_translations` (exists)
- Database does NOT have `description_translations` column
- PublicEvent schema doesn't cast/validate `description_translations`

**Evidence**:
```sql
-- Check schema
\d public_events
-- Only has: title_translations (JSONB)
-- Missing: description_translations
```

### 2. EventDetailJob Not Running Bilingual Fetches

**Issue**: Transformer code shows it expects bilingual content from EventDetailJob:

```elixir
# Line 522-524
case Map.get(raw_event, "description_translations") do
  nil ->
    # No translations map, check for single language description
```

But EventDetailJob is not fetching both English AND French versions of pages.

**Expected Flow**:
1. EventDetailJob fetches English page: `/en/articles/123456`
2. EventDetailJob fetches French page: `/articles/123456` (or `/fr/articles/123456`)
3. EventDetailJob merges: `{"en" => "English desc", "fr" => "French desc"}`
4. Transformer receives merged `description_translations`
5. PublicEvent stores in `title_translations` JSONB

**Current Flow**:
1. EventDetailJob fetches ONE page (English only)
2. Transformer gets single language `description`
3. Transformer creates `description_translations: %{"en" => desc}`
4. PublicEvent schema doesn't map `description_translations` → data lost
5. Database stores NULL in `title_translations`

### 3. Metadata Language Field Not Persisted

**Issue**: Transformer sets `metadata: %{language: "en"}` but `public_events` table doesn't have a `metadata` column.

```sql
-- Check for metadata column
\d public_events
-- Result: NO metadata column exists
```

The `metadata` field in Transformer output is completely ignored.

## Impact

- **0% multilingual coverage** despite Sortiraparis being primarily French
- **Data loss**: French titles, descriptions, cultural context all missing
- **User experience**: French users see English-only content from French source
- **Wasted effort**: Spent hours building MultilingualDateParser that isn't being used for its primary purpose

## The Crimes

### Crime 1: Field Name Mismatch
- **Transformer** creates: `description_translations`
- **Database** has: `title_translations`
- **Result**: Translations dropped

### Crime 2: EventDetailJob Not Bilingual
- EventDetailJob fetches ONE language only
- No bilingual page fetching implemented
- Transformer expects merged translations but never receives them

### Crime 3: Schema Missing Metadata Column
- Transformer sets: `metadata: %{language: "en", occurrence_type: "one_time", ...}`
- Database has: NO metadata column in `public_events`
- **Note**: There IS a `metadata` column planned/exists elsewhere but not in `public_events`

### Crime 4: No Title Translation Extraction
- We extract descriptions but not titles in multiple languages
- EventExtractor doesn't have bilingual title extraction
- HTML probably has both `<h1>` and `<meta property="og:title">` but we only grab one

## Solution Path

### Phase 1: Database Schema (CRITICAL)

1. **Add description_translations column**
   ```sql
   ALTER TABLE public_events ADD COLUMN description_translations JSONB;
   ```

2. **Add metadata column** (if truly needed)
   ```sql
   ALTER TABLE public_events ADD COLUMN metadata JSONB DEFAULT '{}'::jsonb;
   ```

### Phase 2: EventDetailJob Bilingual Fetching

1. **Implement bilingual fetch** in EventDetailJob:
   ```elixir
   defp fetch_bilingual_content(url) do
     en_url = String.replace(url, "/articles/", "/en/articles/")
     fr_url = url  # Original URL is French

     with {:ok, en_html} <- Client.fetch_page(en_url),
          {:ok, fr_html} <- Client.fetch_page(fr_url),
          {:ok, en_desc} <- extract_description(en_html),
          {:ok, fr_desc} <- extract_description(fr_html) do
       {:ok, %{"en" => en_desc, "fr" => fr_desc}}
     end
   end
   ```

2. **Merge translations** before passing to Transformer

### Phase 3: Transformer Field Mapping

1. **Update Transformer** to set `title_translations` AND `description_translations`:
   ```elixir
   %{
     title: title,  # English default for backwards compat
     title_translations: %{"en" => en_title, "fr" => fr_title},
     description_translations: %{"en" => en_desc, "fr" => fr_desc},
     metadata: %{
       language: "fr",  # Source language
       occurrence_type: "one_time",
       ...
     }
   }
   ```

2. **Update PublicEvent schema** to cast new fields:
   ```elixir
   def changeset(event, attrs) do
     event
     |> cast(attrs, [..., :title_translations, :description_translations, :metadata])
     |> ...
   end
   ```

### Phase 4: Backfill Existing Data

1. Re-scrape Sortiraparis events with bilingual fetching enabled
2. Update existing 73 events with French translations
3. Verify `title_translations` populated

## Testing

```bash
# After fixes, verify translations are stored
mix run -e "
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.PublicEvents.PublicEvent

# Check a Sortiraparis event
event = Repo.one(
  from pe in PublicEvent,
  join: pes in assoc(pe, :sources),
  join: s in assoc(pes, :source),
  where: s.slug == \"sortiraparis\",
  limit: 1,
  preload: [:sources]
)

IO.inspect(event.title_translations, label: \"Translations\")
# Expected: %{\"en\" => \"...\", \"fr\" => \"...\"}
# Currently: nil
"
```

## Files to Modify

1. `priv/repo/migrations/YYYYMMDDHHMMSS_add_multilingual_fields_to_public_events.exs`
2. `lib/eventasaurus_discovery/public_events/public_event.ex` (schema + changeset)
3. `lib/eventasaurus_discovery/sources/sortiraparis/jobs/event_detail_job.ex` (bilingual fetch)
4. `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex` (field mapping)

## Priority

**CRITICAL** - This represents a fundamental architecture failure where we built multilingual support but aren't using it. All 73 existing Sortiraparis events lack French content they should have.

## Related Issues

- Issue #1846 - MultilingualDateParser refactoring (WORKING CORRECTLY)
- Issue #1839 - Original multilingual vision (NOT IMPLEMENTED)
- Potential issue: EventExtractor may only extract English titles/descriptions even when French available

## Next Steps

1. Create migration for `description_translations` and `metadata` columns
2. Update PublicEvent schema and changesets
3. Implement bilingual fetching in EventDetailJob
4. Update Transformer field mapping
5. Test with single event
6. Re-scrape all Sortiraparis events
7. Verify French content persisted

---

**Date Discovered**: 2025-10-19
**Discovered By**: Code review analysis
**Affected Records**: 73 Sortiraparis events (100% of source)
**Data Loss**: 100% of French translations
