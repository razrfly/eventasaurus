# UTF-8 PostgreSQL Boundary Protection - Implementation Summary

## What We Implemented (Option 1: Fix Forward)

Based on issue #1338, we implemented the "PostgreSQL Boundary Protection Strategy" by enhancing the current codebase with proper UTF-8 validation at all PostgreSQL boundaries.

## Changes Made

### 1. Enhanced UTF8 Module (`lib/eventasaurus_discovery/utils/utf8.ex`)
- Added general multi-byte UTF-8 sequence fixing (not language-specific)
- Fast-path optimization: check validity first, only fix if needed
- Handles ANY corrupt multi-byte sequences:
  - 2-byte sequences (0xC0-0xDF starters)
  - 3-byte sequences (0xE0-0xEF starters)
  - 4-byte sequences (0xF0-0xF7 starters)
  - Orphaned continuation bytes
  - Incomplete sequences at string end

### 2. PostgreSQL Boundary Validations Added

#### HTTP Clients (After JSON Decode)
- **Ticketmaster Client**: Validates both raw response AND after JSON decode
- **Bandsintown Client**: Already had validation
- **Karnet Client**: Already had validation

#### Oban Job Creation
- **Ticketmaster SyncJob**: Validates before creating EventProcessorJob
- **Ticketmaster EventProcessorJob**: Validates args when reading from DB
- **Karnet EventDetailJob**: Validates args from DB
- **Bandsintown EventDetailJob**: Validates args from DB

#### String Comparison Operations (jaro_distance)
- **EventProcessor**: Validates titles before jaro_distance calls (lines 784, 853-855)
- **VenueProcessor**: Validates venue names before jaro_distance
- **PerformerStore**: Validates performer names before jaro_distance

#### Model Changesets
- **PublicEvent**: Added `sanitize_utf8` to changeset
- **Venue**: Already had sanitization

#### Query Parameters
- **CollisionDetector**: Already validates before similarity queries

### 3. Oban Args Truncation (`lib/eventasaurus_discovery/utils/oban_helpers.ex`)
- Created helper to drastically reduce Oban Web display clutter
- Only keeps essential fields: external_id, title (50 chars), starts_at, status
- Removes all metadata, translations, and verbose fields

## Key Protection Points

1. **HTTP Response → JSON Decode**: Clean raw body, decode, clean decoded strings
2. **JSON → Oban Job**: Clean data before storing in JSONB
3. **Oban Job → Processing**: Clean args when reading from DB
4. **Database → String Operations**: Clean before any String functions that crash on invalid UTF-8
5. **User Input → Changeset**: Clean in changeset validation

## Critical Fixes for Production Errors

- **Job 7592**: VenueProcessor jaro_distance crash - Fixed
- **Job 8311**: EventProcessor jaro_distance crash - Fixed
- **Ticketmaster 0xe2 0x20 0x46**: Corrupt en-dash sequences - Fixed
- **Polish characters 0xc5 0x20**: General multi-byte handler - Fixed

## Why Option A Failed

PostgreSQL validates UTF-8 at EVERY text operation, not just inserts:
- Oban job storage (JSONB columns)
- Model inserts (text columns)
- Similarity queries (text parameters)
- Full-text search operations
- String comparison functions

Each validation protects a different PostgreSQL operation. Remove any one, and that specific operation can fail.

## Production Deployment

1. Deploy these changes
2. Monitor for UTF-8 errors in logs
3. Existing corrupt jobs in DB will be cleaned on execution
4. New jobs will be clean from the start

## Success Metrics

- Zero "invalid byte sequence for encoding UTF8" errors
- All Ticketmaster events process successfully
- jaro_distance operations no longer crash
- Oban Web displays are readable (truncated args)