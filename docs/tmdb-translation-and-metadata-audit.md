# TMDb Translation and Metadata Audit

**Branch:** `10-02-cinema`
**Date:** 2025-10-02
**Status:** Issues Identified - No Code Changes

## Executive Summary

This audit examines how movie data from The Movie Database (TMDb) is being fetched, stored, and displayed in the Eventasaurus platform, specifically for cinema events from Kino Krakow. Several critical issues have been identified regarding translations, descriptions, metadata storage, and event naming conventions.

## Current Architecture

### Database Schema

#### Movies Table (`movies`)
```elixir
# Migration: priv/repo/migrations/20251001172821_create_movies.exs
- tmdb_id (integer, unique, required)
- title (string, required)
- original_title (string)
- slug (string, unique, required)
- overview (text)                    # Currently stores English overview only
- poster_url (string)
- backdrop_url (string)
- release_date (date)
- runtime (integer)
- metadata (map, default: %{})       # Currently stores limited data
```

#### Public Event Sources Table (`public_event_sources`)
```elixir
# Migration: priv/repo/migrations/20250913124939_create_public_event_sources.exs
- event_id (references public_events)
- source_id (references sources)
- source_url (string)
- external_id (string)
- last_seen_at (utc_datetime, required)
- metadata (map, default: %{})
- description_translations (map)     # EXISTS but NOT BEING POPULATED
- image_url (string)
- min_price, max_price, currency
- is_free (boolean)
```

### Current Data Flow

1. **Kino Krakow Scraping** (`lib/eventasaurus_discovery/sources/kino_krakow/jobs/sync_job.ex`)
   - Fetches showtimes for 7-day window
   - Extracts movie metadata (Polish title, original title, year, director, etc.)
   - Matches movies to TMDb using title similarity scoring
   - Creates/finds movie records in database
   - Creates events for each showtime

2. **TMDb Matching** (`lib/eventasaurus_discovery/sources/kino_krakow/tmdb_matcher.ex`)
   - Searches TMDb using original/international title
   - Calculates confidence score (80%+ threshold for auto-accept)
   - Creates movie record from TMDb data
   - **Issue**: Only fetches English data, no translations

3. **Movie Creation** (`create_from_tmdb/1` in `tmdb_matcher.ex:205-226`)
   ```elixir
   attrs = %{
     tmdb_id: tmdb_id,
     title: details[:title],                    # English only
     original_title: details[:title],           # Same as title (wrong?)
     overview: details[:overview],              # English only
     poster_url: build_image_url(details[:poster_path]),
     backdrop_url: build_image_url(details[:backdrop_path]),
     release_date: parse_release_date(details[:release_date]),
     runtime: details[:runtime],
     metadata: %{
       vote_average: details[:vote_average],
       vote_count: details[:vote_count],
       genres: details[:genres],
       production_countries: details[:production_countries]
       # Missing: Full TMDb response, translations, credits, etc.
     }
   }
   ```

4. **Event Title Construction** (`build_title/1` in `transformer.ex:100-106`)
   ```elixir
   movie_title = event[:movie_title] || event[:original_title] || "Unknown Movie"
   cinema_name = event.cinema_data[:name] || "Unknown Cinema"
   "#{movie_title} at #{cinema_name}"
   ```

   **Issue**: `movie_title` comes from Kino Krakow Polish title, creating inconsistent naming:
   ```elixir
   # sync_job.ex:272
   movie_title: movie_info.movie_data.polish_title || movie.title
   ```

## Issues Identified

### 1. ❌ TMDb Translation Data Not Being Fetched

**Location:** `lib/eventasaurus_web/services/tmdb_service.ex`

**Problem:**
- TMDb API calls are hardcoded with `language=en-US`
- No calls to TMDb's `/movie/{id}/translations` endpoint
- Polish translations are available from TMDb but ignored

**Current Implementation:**
```elixir
# Line 293, 347
url = "#{@base_url}/movie/popular?api_key=#{api_key}&page=#{page}&language=en-US"
url = "#{@base_url}/movie/#{movie_id}?api_key=#{api_key}&append_to_response=#{append_to_response}&include_image_language=en,null"
```

**TMDb API Available Endpoints (NOT USED):**
```
GET /movie/{movie_id}/translations
GET /movie/{movie_id}?language=pl-PL
```

**Example TMDb Translations Response:**
```json
{
  "translations": [
    {
      "iso_3166_1": "PL",
      "iso_639_1": "pl",
      "name": "Polski",
      "english_name": "Polish",
      "data": {
        "title": "Polska Nazwa Filmu",
        "overview": "Polski opis filmu...",
        "homepage": ""
      }
    },
    {
      "iso_3166_1": "US",
      "iso_639_1": "en",
      "name": "English",
      "english_name": "English",
      "data": {
        "title": "English Movie Title",
        "overview": "English movie description...",
        "homepage": ""
      }
    }
  ]
}
```

### 2. ❌ Event Naming Inconsistency

**Location:** `lib/eventasaurus_discovery/sources/kino_krakow/jobs/sync_job.ex:272`

**Problem:**
- Event titles use `polish_title` from Kino Krakow website scraping
- Should use TMDb English title + Polish translation for bilingual display
- Fallback logic `polish_title || movie.title` is unreliable

**Current Behavior:**
```elixir
# sync_job.ex:272
movie_title: movie_info.movie_data.polish_title || movie.title
```

**Result:** Inconsistent event names
- Sometimes Polish from Kino Krakow
- Sometimes English from TMDb (as fallback)
- No structured bilingual naming

**Expected Behavior:**
- Primary: English title from TMDb
- Secondary: Polish title from TMDb translations
- Display: "English Title (Polska Nazwa)" or locale-based switching

### 3. ❌ Description Translations Field Not Populated

**Location:** `lib/eventasaurus_discovery/public_events/public_event_source.ex`

**Problem:**
- `description_translations` field exists in schema (line 10)
- Field is defined in changeset (line 33)
- **BUT**: Never populated with movie overview/description data

**Current State:**
```elixir
# Schema has the field
field(:description_translations, :map)

# Changeset allows it
|> cast(attrs, [..., :description_translations, ...])

# But it's never set anywhere in the codebase
```

**Expected Data Structure:**
```elixir
%{
  "en" => "English movie description from TMDb...",
  "pl" => "Polski opis filmu z TMDb..."
}
```

**Current Event Source Creation:**
- Transformer doesn't populate description field
- TMDb overview is stored in `movies.overview` (English only)
- `public_event_sources.description_translations` remains empty

### 4. ❌ Incomplete Metadata Storage

**Location:** `lib/eventasaurus_discovery/sources/kino_krakow/tmdb_matcher.ex:216-222`

**Problem:**
- `movies.metadata` field stores only 4 data points
- TMDb provides 50+ fields in movie details response
- Valuable data being discarded

**Currently Stored:**
```elixir
metadata: %{
  vote_average: details[:vote_average],
  vote_count: details[:vote_count],
  genres: details[:genres],
  production_countries: details[:production_countries]
}
```

**Available from TMDb but NOT Stored:**
```elixir
# From fetch_movie_details response (tmdb_service.ex:417-453)
- tagline
- budget
- revenue
- status
- original_language
- production_companies
- spoken_languages
- director (extracted from credits)
- cast (top 10)
- crew (key roles)
- images (backdrops, posters)
- videos (trailers, teasers)
- external_links (IMDB, Facebook, Twitter, Instagram)
- popularity
- adult
```

**Impact:**
- Cannot display rich movie information
- Missing data for filtering/sorting
- No access to credits, trailers, external links
- Redundant API calls if data needed later

### 5. ⚠️ Original Title Assignment Issue

**Location:** `lib/eventasaurus_discovery/sources/kino_krakow/tmdb_matcher.ex:210`

**Problem:**
```elixir
title: details[:title],           # English title from TMDb
original_title: details[:title],  # SAME as title - should be details[:original_title]
```

**TMDb Distinction:**
- `title`: Localized title (based on language parameter)
- `original_title`: Original title in movie's native language

**Example:**
- Title: "Spirited Away" (English)
- Original Title: "千と千尋の神隠し" (Japanese)

**Current Code:** Both fields get English title, losing original language information.

## TMDb API Reference

### Available Endpoints

1. **Get Movie Details** (Currently Used)
   ```
   GET /movie/{movie_id}?api_key={key}&language={lang}
   ```
   - Returns movie data in specified language
   - Currently hardcoded to `en-US`

2. **Get Translations** (NOT Used)
   ```
   GET /movie/{movie_id}/translations?api_key={key}
   ```
   - Returns all available translations
   - Includes title and overview in each language

3. **Append to Response** (Partially Used)
   ```
   GET /movie/{movie_id}?api_key={key}&append_to_response=credits,images,videos,translations
   ```
   - Can request multiple data sets in one call
   - Currently uses: `credits,images,videos,external_ids`
   - Missing: `translations`

### Language Support

TMDb supports:
- `language=en-US` - English (currently used)
- `language=pl-PL` - Polish (NOT used)
- Multiple languages can be fetched via translations endpoint

## Recommendations

### 1. Fetch TMDb Translations

**Implementation Location:** `lib/eventasaurus_web/services/tmdb_service.ex`

**Add to `append_to_response`:**
```elixir
# Line 345
append_to_response = "credits,images,videos,external_ids,translations"
```

**Process Translations:**
```elixir
defp extract_translations(tmdb_data) do
  translations = tmdb_data["translations"]["translations"] || []

  # Extract English and Polish
  en_trans = Enum.find(translations, &(&1["iso_639_1"] == "en"))
  pl_trans = Enum.find(translations, &(&1["iso_639_1"] == "pl"))

  %{
    "en" => %{
      "title" => en_trans["data"]["title"],
      "overview" => en_trans["data"]["overview"]
    },
    "pl" => %{
      "title" => pl_trans["data"]["title"],
      "overview" => pl_trans["data"]["overview"]
    }
  }
end
```

### 2. Store Translations in Movies Table

**Option A:** Add translation fields to movies table
```elixir
# New migration
add :title_translations, :map
add :overview_translations, :map
```

**Option B:** Store in existing metadata field
```elixir
metadata: %{
  vote_average: details[:vote_average],
  # ... existing fields ...
  translations: %{
    "en" => %{title: "...", overview: "..."},
    "pl" => %{title: "...", overview: "..."}
  }
}
```

### 3. Populate Event Source Descriptions

**Location:** `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex`

```elixir
# In transform_event/1, add:
description_translations: build_description_translations(raw_event),

defp build_description_translations(event) do
  %{
    "en" => event[:overview_en] || event[:overview],
    "pl" => event[:overview_pl]
  }
end
```

### 4. Fix Event Title Construction

**Location:** `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex:100-106`

```elixir
defp build_title(event) do
  # Use TMDb English title as primary
  english_title = event[:title_en] || event[:original_title]
  polish_title = event[:title_pl]
  cinema_name = event.cinema_data[:name]

  # Format: "English Title (Polski Tytuł) at Cinema"
  title = if polish_title && polish_title != english_title do
    "#{english_title} (#{polish_title})"
  else
    english_title
  end

  "#{title} at #{cinema_name}"
end
```

### 5. Store Complete TMDb Metadata

**Location:** `lib/eventasaurus_discovery/sources/kino_krakow/tmdb_matcher.ex:216-222`

```elixir
metadata: %{
  # Core metadata
  vote_average: details[:vote_average],
  vote_count: details[:vote_count],
  popularity: details[:popularity],

  # Movie details
  tagline: details[:tagline],
  budget: details[:budget],
  revenue: details[:revenue],
  status: details[:status],
  original_language: details[:original_language],

  # Classifications
  genres: details[:genres],
  production_companies: details[:production_companies],
  production_countries: details[:production_countries],
  spoken_languages: details[:spoken_languages],

  # Credits
  director: details[:director],
  cast: details[:cast],
  crew: details[:crew],

  # Media
  images: details[:images],
  videos: details[:videos],

  # Links
  external_links: details[:external_links],

  # Translations
  translations: extract_translations(tmdb_full_response)
}
```

### 6. Fix Original Title Assignment

**Location:** `lib/eventasaurus_discovery/sources/kino_krakow/tmdb_matcher.ex:210`

```elixir
attrs = %{
  tmdb_id: tmdb_id,
  title: details[:title],                          # English title
  original_title: details[:original_title],        # Original language title (NOT same as title)
  overview: details[:overview],
  # ... rest
}
```

## Impact Assessment

### User Experience Impact
- **High**: Event names are confusing (mixed Polish/English)
- **High**: Missing movie descriptions in preferred language
- **Medium**: Cannot display rich movie information (cast, crew, trailers)

### Data Quality Impact
- **High**: Translations available but unused
- **High**: Metadata field underutilized (4 fields vs 50+ available)
- **Medium**: `description_translations` field defined but empty

### Performance Impact
- **Low**: Current implementation efficient (single API call per movie)
- **Potential**: Fetching translations adds minimal overhead (included in append_to_response)

## Testing Recommendations

1. **Verify TMDb Translation Availability**
   - Check if Polish translations exist for popular movies
   - Test with movies that have/don't have Polish translations

2. **Test Title Display**
   - Verify bilingual title format renders correctly
   - Test with long titles (truncation)
   - Test with special characters in Polish

3. **Validate Metadata Storage**
   - Confirm all TMDb fields stored correctly
   - Test metadata field size limits
   - Verify JSON serialization works

## Files Requiring Changes

### Core Changes
1. `lib/eventasaurus_web/services/tmdb_service.ex`
   - Add `translations` to `append_to_response`
   - Add `extract_translations/1` function
   - Update `format_detailed_movie_data/1`

2. `lib/eventasaurus_discovery/sources/kino_krakow/tmdb_matcher.ex`
   - Fix `original_title` assignment (line 210)
   - Expand `metadata` to include full TMDb response (line 216-222)
   - Include translations in movie creation

3. `lib/eventasaurus_discovery/sources/kino_krakow/jobs/sync_job.ex`
   - Update `enrich_showtime/3` to include translation data (line 272)
   - Pass English and Polish titles to transformer

4. `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex`
   - Rewrite `build_title/1` for bilingual naming (line 100-106)
   - Add `description_translations` field (line 45)
   - Include translations in event data

### Schema Updates (Optional)
5. Consider migration to add explicit translation fields:
   ```elixir
   alter table(:movies) do
     add :title_translations, :map
     add :overview_translations, :map
   end
   ```

## Conclusion

The current implementation successfully fetches and stores basic movie data from TMDb, but misses significant opportunities for better internationalization and richer metadata. The infrastructure is in place (`description_translations` field exists, `metadata` map supports expansion), but requires implementation to populate these fields with TMDb's available translation and metadata.

**Priority:** High - Affects user experience for Polish market
**Complexity:** Medium - Requires TMDb API changes and data flow updates
**Risk:** Low - Additive changes, minimal breaking changes

## Next Steps

1. Review this audit with team
2. Prioritize which issues to address first
3. Create implementation tasks for approved changes
4. Implement and test translations feature
5. Monitor user feedback on bilingual naming
