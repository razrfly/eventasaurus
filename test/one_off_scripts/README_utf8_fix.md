# UTF-8 Fix Summary for Ticketmaster EventProcessorJob

## Problem
The Ticketmaster EventProcessorJob was failing when processing performer names with special characters like "Rock-Serwis Piotr Kosiński". The error occurred when trying to create a slug from the name, resulting in a `FunctionClauseError` in `String.to_charlist/1`.

## Root Cause
The performer name contained invalid UTF-8 byte sequences that weren't being properly handled before normalization and slug generation.

## Solution
Implemented a three-layer UTF-8 validation approach:

### 1. Transformer Level (Prevention)
Added UTF-8 validation at the source in `EventasaurusDiscovery.Sources.Ticketmaster.Transformer`:
- `transform_event/3` - Cleans event titles
- `transform_venue/2` - Cleans venue names and addresses
- `transform_performer/1` - Cleans performer names

### 2. Processor Level (Safety)
Updated `EventasaurusDiscovery.Scraping.Processors.EventProcessor`:
- `find_or_create_performer/1` - Added UTF-8 cleaning before normalization
- Ensures clean data even if transformer validation is bypassed

### 3. PerformerStore Level (Validation)
Enhanced `EventasaurusDiscovery.Performers.PerformerStore`:
- Added name validation to reject nil/empty names
- Source-scoped fuzzy matching to prevent cross-source collisions
- Better error handling for invalid performer data

## Testing
Created `test/one_off_scripts/test_ticketmaster_utf8_fix.exs` which verifies:
- The specific failing case works correctly
- Various UTF-8 edge cases are handled properly
- The full transformation flow processes UTF-8 correctly

## Files Modified
1. `lib/eventasaurus_discovery/sources/ticketmaster/transformer.ex`
2. `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`
3. `lib/eventasaurus_discovery/performers/performer_store.ex`
4. `lib/eventasaurus_discovery/sources/processor.ex`

## Result
The Ticketmaster EventProcessorJob can now successfully process events with performers having special UTF-8 characters in their names without crashing.