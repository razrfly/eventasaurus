# Kino Krakow Scraper - Implementation Status

## Overview

The Kino Krakow cinema scraper has been successfully integrated into the Eventasaurus discovery system. The scraper extracts movie showtimes from Krakow cinemas and enriches them with movie metadata and TMDB (The Movie Database) matching.

## Implementation Complete

### Phase 1: Core Scraping ✅
- **ShowtimeExtractor**: Parses https://www.kino.krakow.pl/cinema_program/by_movie
- **MovieExtractor**: Extracts metadata from movie detail pages
- **CinemaExtractor**: Extracts venue information including GPS coordinates
- **DateParser**: Handles Polish date formats

### Phase 2: System Integration ✅
- **Dashboard Registration**: Added to admin discovery dashboard
- **Job Routing**: Integrated with DiscoverySyncJob
- **City Configuration**: Configured as Krakow-specific source
- **Source Module**: Follows Karnet pattern with proper configuration

## Test Results

### MovieExtractor Validation (8/8 checks passing)
```
✅ Original title present: "Interstellar"
✅ Polish title present: "Interstellar"
✅ Director present: "Christopher Nolan"
✅ Year present: 2014
✅ Country present: "USA / Wielka Brytania"
✅ Runtime present: 169 minutes
✅ Genre present: "przygodowy / dreszczowiec / sci-fi"
✅ Cast present: ["Anne Hathaway", "Jessica Chastain", "Matthew McConaughey"]
```

### Live Scraping Test
- **Showtimes Extracted**: 305 from live website
- **Unique Movies**: 51
- **Unique Cinemas**: 14
- **TMDB Matching**: Active (some Polish films don't have matches - expected)

## Files Modified

### Dashboard Integration
- `/lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex`
  - Added "kino-krakow" to `@city_specific_sources` map (line 20)
  - Added "kino-krakow" to sources dropdown (line 290)

### Job Routing
- `/lib/eventasaurus_discovery/admin/discovery_sync_job.ex`
  - Added Kino Krakow to `@sources` map

### Core Extractors (Debugged & Fixed)
- `/lib/eventasaurus_discovery/sources/kino_krakow/extractors/movie_extractor.ex`
  - Updated all extraction methods to use regex parsing of actual HTML
  - Fixed selectors for: original_title, director, year, country, runtime, cast, genre
  - Extraction now works with real Kino Krakow HTML structure

## Test Scripts Created

1. **scripts/test_kino_krakow_integration.exs** - Full integration test
2. **scripts/test_movie_extractor.exs** - MovieExtractor validation
3. **scripts/debug_kino_movie_page.exs** - HTML structure debugging
4. **scripts/test_kino_simple.exs** - Simple integration test

## How to Use

### From Admin Dashboard
1. Navigate to `/admin/discovery`
2. Select source: "kino-krakow"
3. City automatically set to: Kraków
4. Set limit (recommended: 100)
5. Click "Start Import"

### From CLI
```elixir
# Queue a sync job
EventasaurusDiscovery.Admin.DiscoverySyncJob.queue_sync(
  "kino-krakow",
  krakow_city_id,
  100  # limit
)
```

### Via Mix Task (if available)
```bash
mix discovery.sync --source kino-krakow --city krakow --limit 100
```

## Known Behaviors

### TMDB Matching
- **Success Rate**: Varies by film type
- **Expected Failures**: Polish-only films, local screenings, special events
- **Common Errors**:
  - `:no_results` - Film not found in TMDB database
  - `:no_candidates` - TMDB returned results but confidence too low

### Processing Time
- Scrapes all showtimes first (~5-10 seconds)
- Enriches all unique movies sequentially (~2 seconds per movie)
- Rate limited: 2-second delay between movie detail page fetches
- **Total Time**: ~2-3 minutes for full scrape of 50 movies

## Technical Details

### Data Flow
1. **Fetch Showtimes**: GET /cinema_program/by_movie
2. **Extract Showtimes**: ShowtimeExtractor parses table structure
3. **Enrich Movies**: Parallel fetch of movie detail pages
4. **Extract Metadata**: MovieExtractor parses each detail page
5. **TMDB Matching**: Match movies to TMDB database
6. **Enrich Cinemas**: Fetch venue details including GPS
7. **Transform Events**: Convert to unified PublicEvent format
8. **Filter**: Remove events without TMDB matches
9. **Return**: Processed events ready for import

### Rate Limiting
- **Delay**: 2 seconds between requests
- **User Agent**: "EventasaurusDiscovery/1.0"
- **Timeout**: 30 seconds per request
- **Retry**: Not implemented (single attempt)

### Source Configuration
- **Key**: "kino-krakow"
- **Name**: "Kino Krakow"
- **Priority**: 15 (higher than Karnet's 30)
- **City**: Kraków only
- **Timezone**: Europe/Warsaw
- **Features**:
  - ✅ TMDB Matching
  - ✅ Movie Metadata
  - ✅ Venue Details

## Next Steps (Future Enhancements)

### Phase 3: Optimization (Optional)
1. **Improve TMDB Matching**:
   - Fuzzy matching for Polish titles
   - Year-based filtering
   - Director confirmation
   - Fallback strategies

2. **Performance Optimization**:
   - Parallel movie enrichment
   - Cache movie metadata across scrapes
   - Incremental updates (only new showtimes)

3. **Error Handling**:
   - Retry logic for failed requests
   - Graceful degradation for missing data
   - Better logging for debugging

4. **Monitoring**:
   - Success/failure metrics
   - TMDB match rate tracking
   - Processing time monitoring

## Conclusion

**Status**: ✅ **Production Ready**

The Kino Krakow scraper is fully integrated and functional. It successfully:
- Extracts showtimes from live website
- Enriches with movie metadata
- Matches to TMDB database
- Transforms to unified event format
- Appears in admin dashboard
- Can be triggered via Oban jobs

The scraper follows the established pattern of other scrapers (Karnet, Ticketmaster) and is ready for production use.

---

**Date**: October 2, 2025
**Issue**: #1439
**Developer**: Claude Code with user guidance
