# Karnet Scraper Bug: Incorrect Translation Extraction from 404 Pages

## 🐛 Bug Description

The Karnet event detail scraper is incorrectly extracting and storing wrong event titles as translations when attempting to fetch English versions of Polish-only events. When an English URL returns a 404 error, the scraper still attempts to extract content from the error page, resulting in completely unrelated event titles being saved as translations.

## 🔴 Severity: High

This bug corrupts event data with incorrect translations, causing users to see completely unrelated event titles when switching languages.

## 📊 Impact

### Affected Events (Sample)
- **Event ID 87**: "Cała prawda o teoriach spiskowych..." → Polish translation shows "O „Obywatelce" Claudii Rankine..." (completely different event)
- **Event ID 129**: "Trójkącik, czyli trzech na próbę" → "Synchronizacja w Birkenwald. Premiera w Kinie Kijów"
- **Event ID 104**: "Magiczna rana" → "Masażystka (MOS Underground)"
- **Event ID 125**: "Śpiewoterapia" → "Biuroza"
- **Event ID 2**: "Old Metropolitan Band" → "Old Metropolitan Band w Globusie"
- **Event ID 3**: "Chuck Frazier Trio" → "Chuck Frazier Trio w Globusie"

At least 6 events confirmed with wrong translations, potentially more.

## 🔍 Root Cause Analysis

### Location of Bug
`/lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex`

### The Problem Flow

1. **URL Construction** (Lines 266-281):
   ```elixir
   defp build_bilingual_urls(original_url, _event_id) do
     %{
       polish: "https://karnet.krakowculture.pl/pl/#{slug}",
       english: "https://karnet.krakowculture.pl/en/#{slug}"
     }
   end
   ```

2. **Content Fetching** (Lines 283-310):
   - The code fetches both Polish and English versions
   - When English returns 404, it logs a warning but **continues processing**
   - The error is caught but treated as "English version not available" with `{:ok, nil}`

3. **The Critical Bug** (Lines 297-306):
   ```elixir
   english_result = case Client.fetch_page(urls.english) do
     {:ok, html} ->
       Logger.debug("✅ English content fetched successfully")
       DetailExtractor.extract_event_details(html, urls.english)  # BUG: Extracts from 404 page!
     {:error, :not_found} ->
       Logger.info("ℹ️ English version not available: #{urls.english}")
       {:ok, nil}
   ```

   **The issue**: When `Client.fetch_page` returns `{:ok, html}` for a 404 page (because the HTTP request succeeds even though it's a 404), the code passes that 404 error page HTML to `DetailExtractor.extract_event_details`.

4. **Data Extraction from Wrong Page**:
   - `DetailExtractor` blindly looks for `<h1>` tags and other content
   - On a 404 page, this might extract:
     - "Error 404" as the title
     - Or worse, if the 404 page shows "recommended events", it extracts those titles
     - Could also extract from redirect pages or event listing pages

5. **Incorrect Data Merge** (Lines 335-357):
   ```elixir
   defp merge_language_data(polish_data, english_data, metadata) do
     # Merges whatever was extracted, even if it's from wrong pages
     title_translations = %{
       "pl" => polish_data[:title],
       "en" => english_data[:title]  # This could be from a 404 page!
     }
   ```

## 🎯 How to Reproduce

1. Find a Karnet event that exists only in Polish (no English version)
2. Run the Karnet sync job
3. Check the database - the `title_translations` will contain wrong data

Example URL that triggers the bug:
- Polish (works): `https://karnet.krakowculture.pl/pl/60924-krakow-oslizgle-macki-wiadome-sily-historia-ameryki-w-teoriach-spiskowych-spotkanie-z-piotrem-tarczynskim`
- English (404): `https://karnet.krakowculture.pl/en/60924-krakow-oslizgle-macki-wiadome-sily-historia-ameryki-w-teoriach-spiskowych-spotkanie-z-piotrem-tarczynskim`

## ✅ Proposed Solution

### 1. Check HTTP Status Code
The `Client.fetch_page` function needs to return an error for 404 responses, not `{:ok, html}`.

### 2. Validate Response Before Extraction
Before passing HTML to `DetailExtractor`, verify:
- HTTP status is 200
- The page is actually an event detail page (not an error page)
- The content relates to the same event

### 3. Skip Translation on Error
When English version returns 404 or any error:
```elixir
english_result = case Client.fetch_page(urls.english) do
  {:ok, html} when status_code == 200 ->
    # Only extract if we got a successful response
    DetailExtractor.extract_event_details(html, urls.english)
  _ ->
    # Any error or non-200 status means no English version
    {:ok, nil}
end
```

### 4. Add Content Validation
Implement a validation check to ensure extracted content is related:
```elixir
defp validate_translation_match(polish_data, english_data) do
  # Check if event IDs match or titles are similar
  # Return false if they appear to be different events
end
```

### 5. Better Error Page Detection
In `DetailExtractor`, detect common error page patterns:
```elixir
defp is_error_page?(html) do
  html =~ "Error 404" ||
  html =~ "Page not found" ||
  html =~ "Nie znaleziono strony"
end
```

## 🔧 Files to Modify

1. `/lib/eventasaurus_discovery/sources/karnet/client.ex` - Return proper error for 404s
2. `/lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex` - Handle 404s correctly
3. `/lib/eventasaurus_discovery/sources/karnet/detail_extractor.ex` - Add error page detection

## 🧪 Testing Requirements

1. Test with events that have both Polish and English versions
2. Test with Polish-only events (should not create false English translations)
3. Test with various error scenarios (404, 500, timeout)
4. Verify that only legitimate translations are stored

## 📝 Additional Notes

- This bug affects data integrity and user experience
- The language switcher feature will display these incorrect translations to users
- A data cleanup will be needed after the fix is deployed
- Consider adding monitoring/alerts for translation mismatches