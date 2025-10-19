# HTML Entity Encoding Issue in Sortiraparis Event Descriptions

**Date**: October 19, 2025
**Source**: Sortiraparis scraper
**Priority**: Medium
**Impact**: User-facing display quality

---

## Problem Description

Event titles and descriptions from Sortiraparis are displaying literal HTML entity codes instead of rendered characters:

- `&#039;` appearing instead of apostrophes (')
- `&quot;` appearing instead of quotation marks (")
- Other HTML entities not being decoded

### Example

**Event**: Volbeat concert at Zénith Paris La Villette
**URL**: http://localhost:4000/activities/volbeat-in-concert-at-the-zenith-in-zenith-paris-la-villette-251101

**Current Display**:
> "Volbeat announce their return to Paris for a world tour. Join Michael Poulsen and his bandmates on stage at the Zénith de La Villette for a unique concert on Sunday, November 2, 2025. The Danish rock&#039;n&#039;roll and metal band will be presenting their new opus, &quot;God Of Angels Trust&quot;, live."

**Expected Display**:
> "Volbeat announce their return to Paris for a world tour. Join Michael Poulsen and his bandmates on stage at the Zénith de La Villette for a unique concert on Sunday, November 2, 2025. The Danish rock'n'roll and metal band will be presenting their new opus, "God Of Angels Trust", live."

---

## Root Cause Analysis

### Investigation Process

Sequential thinking analysis revealed the issue through these steps:

1. **Hypothesis**: HTML entities weren't being decoded during extraction
2. **Database Query**: Found mixed encoding in stored data - some text decoded, some not
3. **Code Review**: Located `HtmlEntities.decode()` in `clean_html/1` function
4. **Path Tracing**: Identified multiple extraction paths, discovered fallback path missing decoding

### Root Cause

**File**: `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex`
**Location**: Lines 379-384
**Function**: `extract_meta_description/1`

```elixir
defp extract_meta_description(html) do
  case Regex.run(~r{<meta\s+(?:name|property)="description"\s+content="([^"]+)"}i, html) do
    [_, desc] -> String.trim(desc)  # ❌ NO HTML entity decoding!
    _ -> nil
  end
end
```

**The Problem**:
- The `extract_description/1` function (lines 149-173) first tries to extract article paragraphs
- Paragraph extraction calls `clean_html/1` which properly decodes HTML entities ✅
- When paragraphs aren't found, it falls back to `extract_meta_description/1`
- The meta description fallback **only trims** - it never decodes HTML entities ❌
- Sortiraparis meta tags contain HTML entities that we preserve without decoding

### Evidence from Database

Query for event ID 2374 (Volbeat concert):
```sql
SELECT description_translations
FROM public_event_sources
WHERE event_id = 2374;
```

**Result shows mixed encoding**:
```json
{
  "en": "The Danish rock&#039;n&#039;roll and metal band will be presenting their new opus, &quot;God Of Angels Trust&quot;, live.",
  "fr": "Le groupe de rock'n'roll et metal danois en profitera pour présenter en live son nouvel opus, baptisé &quot;God Of Angels Trust&quot;."
}
```

Notice:
- English: `rock&#039;n&#039;roll` (ENCODED - likely from meta tag)
- French: `rock'n'roll` (DECODED - likely from article paragraphs)

This confirms different extraction paths have different decoding behaviors.

---

## Standardized Solution

### Design Principle

**ALL text extraction paths must consistently decode HTML entities.**

No hard-coded fixes. Apply the same standard decoding everywhere.

### Implementation

**Change Required**: Add HTML entity decoding to meta description fallback

**File**: `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex`
**Line**: 380

**Current Code**:
```elixir
defp extract_meta_description(html) do
  case Regex.run(~r{<meta\s+(?:name|property)="description"\s+content="([^"]+)"}i, html) do
    [_, desc] -> String.trim(desc)
    _ -> nil
  end
end
```

**Fixed Code**:
```elixir
defp extract_meta_description(html) do
  case Regex.run(~r{<meta\s+(?:name|property)="description"\s+content="([^"]+)"}i, html) do
    [_, desc] -> desc |> String.trim() |> HtmlEntities.decode()
    _ -> nil
  end
end
```

### Why This Works

1. **Consistency**: Both extraction paths (paragraphs and meta tags) now decode HTML entities
2. **Standard Library**: Uses existing `HtmlEntities.decode()` function already in use
3. **Comprehensive**: Handles ALL HTML entities (numeric, named, special chars)
4. **No Hard-Coding**: Generic solution that works for any HTML entity
5. **Future-Proof**: Will automatically handle new entities as HtmlEntities library updates

---

## Verification Steps

After implementing the fix:

1. **Re-scrape Affected Events**:
   ```bash
   # Test with Volbeat concert event
   mix run -e "EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJob.perform(%{
     url: \"https://www.sortiraparis.com/en/arts-culture/concert/articles/319282-volbeat-in-concert\"
   })"
   ```

2. **Check Database**:
   ```sql
   SELECT description_translations
   FROM public_event_sources
   WHERE event_id = 2374;
   ```

   **Expected**: Both English and French should have decoded apostrophes and quotes

3. **Verify Display**:
   - Navigate to http://localhost:4000/activities/volbeat-in-concert-at-the-zenith-in-zenith-paris-la-villette-251101
   - Description should show: `rock'n'roll` and `"God Of Angels Trust"`
   - No `&#039;` or `&quot;` should be visible

4. **Test Other Events**:
   - Check multiple Sortiraparis events
   - Verify both English and French descriptions
   - Confirm titles are also properly decoded

---

## Other Scrapers to Check

Apply the same audit to other scrapers to ensure consistency:

### Audit Checklist

For each scraper in `lib/eventasaurus_discovery/sources/`:

1. **Find all text extraction functions**:
   ```bash
   grep -r "extract_description\|extract_title\|extract_.*_text" lib/eventasaurus_discovery/sources/
   ```

2. **Check for HTML entity decoding**:
   - Look for `HtmlEntities.decode()` calls
   - Verify ALL extraction paths decode entities
   - Check meta tag fallbacks especially

3. **Test with real data**:
   - Find events with apostrophes, quotes, accented characters
   - Verify they display correctly

### Known Good Pattern

All text extraction should follow this pattern:

```elixir
defp extract_some_text(html) do
  # Extract text from HTML
  text = extract_raw_text(html)

  # Clean and decode
  text
  |> String.trim()
  |> HtmlEntities.decode()  # ✅ Always decode!
end
```

---

## Implementation Notes

### Why This Happened

1. **Incremental Development**: `clean_html/1` was created with proper decoding
2. **Fallback Added Later**: Meta description fallback added without following same pattern
3. **No Standardization**: No shared text cleaning function enforcing consistency

### Prevention for Future

**Create Shared Helper**:

Consider creating a standardized text cleaning function:

```elixir
# In lib/eventasaurus_discovery/sources/shared/text_cleaner.ex
defmodule EventasaurusDiscovery.Sources.Shared.TextCleaner do
  @doc """
  Standard text cleaning for all extracted content.
  Removes HTML tags, normalizes whitespace, decodes HTML entities.
  """
  def clean_extracted_text(text) when is_binary(text) do
    text
    |> String.replace(~r{<[^>]+>}, "")
    |> String.replace(~r{\s+}, " ")
    |> String.trim()
    |> HtmlEntities.decode()
  end

  def clean_extracted_text(nil), do: nil
end
```

Then all scrapers can use:
```elixir
alias EventasaurusDiscovery.Sources.Shared.TextCleaner

def extract_description(html) do
  raw_text = extract_raw_text(html)
  TextCleaner.clean_extracted_text(raw_text)
end
```

This ensures consistency across all scrapers and prevents similar issues.

---

## Success Criteria

- [ ] Fix implemented in `event_extractor.ex`
- [ ] Volbeat event re-scraped with correct encoding
- [ ] Database contains decoded entities (', ", etc.)
- [ ] Website displays proper characters, no HTML entities
- [ ] All Sortiraparis events verified (spot check 10+ events)
- [ ] Other scrapers audited for similar issues
- [ ] Documentation updated if shared helper created

---

## Related Files

### Files to Modify
- `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex` (line 380)

### Files to Review
- `lib/eventasaurus_discovery/sources/sortiraparis/README.md` (update if needed)
- Other scraper extractors in `lib/eventasaurus_discovery/sources/*/extractors/`

### Files for Reference
- `lib/eventasaurus_web/live/public_event_show_live.ex` (display layer - no changes needed)
- `lib/eventasaurus_discovery/sources/sortiraparis/jobs/event_detail_job.ex` (bilingual merge - no changes needed)

---

## Timeline Estimate

- **Fix Implementation**: 5 minutes (single line change)
- **Testing**: 20 minutes (re-scrape events, verify display)
- **Audit Other Scrapers**: 1 hour (check all scraper extractors)
- **Documentation**: 15 minutes (update README if needed)
- **Total**: ~2 hours

---

**Status**: 🔴 Open - Ready for Implementation
**Next Action**: Apply fix to `extract_meta_description/1` function
