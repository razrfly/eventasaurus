# Kino Kraków Scraper

Movie aggregator platform for cinemas in Kraków, Poland.

## Overview

**Priority**: 15 (Primary movie source for Kraków)
**Type**: Web scraper
**Coverage**: Kraków (all cinemas including Cinema City, Multikino, etc.)
**Event Types**: Movies
**Update Frequency**: Daily

## Features

- ✅ Aggregates all Kraków cinemas
- ✅ TMDB matching for movie metadata
- ✅ Complete showtime listings
- ✅ Cinema venue data with GPS
- ✅ Multi-day schedule support

## Configuration

No API key required.

**Rate Limit**: 2s between requests
**Timezone**: Europe/Warsaw

## External ID Format

`{movie_slug}-{cinema_slug}-{datetime_iso}`

Example: `test-movie-kino-plaza-2025-10-15T18:00:00Z`

## Data Flow

1. Scrape movie list pages
2. Extract showtime data
3. Match to TMDB
4. Transform to unified format
5. Process via VenueProcessor

## Support

**Tests**: `test/eventasaurus_discovery/sources/kino_krakow/`
**Docs**: See SCRAPER_SPECIFICATION.md
