# Repertuary Scraper

Multi-city movie aggregator platform for cinemas across Poland via repertuary.pl network.

## Overview

**Priority**: 15 (Primary movie source for Polish cities)
**Type**: Web scraper
**Coverage**: 29+ Polish cities (Kraków, Warsaw, Gdańsk, Wrocław, etc.)
**Event Types**: Movies
**Update Frequency**: Daily

## Features

- ✅ Aggregates cinemas across 29+ Polish cities
- ✅ TMDB matching for movie metadata
- ✅ Complete showtime listings
- ✅ Cinema venue data with GPS
- ✅ Multi-day schedule support
- ✅ Multi-city support with city-specific source records

## Configuration

No API key required.

**Rate Limit**: 2s between requests
**Timezone**: Europe/Warsaw

## External ID Format

`repertuary_showtime_{movie_slug}_{cinema_slug}_{datetime_iso}`

Example: `repertuary_showtime_bugonia_pod-baranami_2025-10-15T18:00:00Z`

## Data Flow

1. Scrape movie list pages (per city)
2. Extract showtime data
3. Match to TMDB
4. Transform to unified format
5. Process via VenueProcessor

## Support

**Tests**: `test/eventasaurus_discovery/sources/repertuary/`
**Docs**: See SCRAPER_SPECIFICATION.md
