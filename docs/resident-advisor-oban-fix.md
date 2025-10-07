# Resident Advisor Oban Job Fix

## Problem

40+ EventDetailJob instances were failing with:
```
** (KeyError) key :raw_data not found in: %EventasaurusDiscovery.PublicEvents.PublicEvent{...}
```

## Root Cause

The `check_for_container_match/1` and `calculate_association_confidence/2` functions in `PublicEventContainers` tried to access `event.raw_data["promoter_id"]`, but:

1. The `PublicEvent` schema doesn't have a `raw_data` field
2. Raw event data is stored in the `metadata` field of the associated `PublicEventSource` records
3. After events are saved to the database and loaded as Ecto structs, the sources association isn't automatically preloaded

## Solution

Modified three functions in `lib/eventasaurus_discovery/public_events/public_event_containers.ex`:

### 1. `check_for_container_match/1` (line 313)
**Before**: Tried to access non-existent `event.raw_data`
**After**:
- Preloads `sources` association
- Extracts promoter_id from first source's metadata
```elixir
# Preload sources to access metadata with promoter information
event = Repo.preload(event, :sources)

# Extract promoter_id from the first source's metadata (RA source)
event_promoter_id =
  case event.sources do
    [%{metadata: %{"promoter_id" => promoter_id}} | _] -> promoter_id
    _ -> nil
  end
```

### 2. `calculate_association_confidence/2` (line 369)
**Before**: Tried to access non-existent `event.raw_data`
**After**: Same pattern as above - preload sources and extract from metadata

### 3. `find_matching_events/1` (line 238)
**Before**: Tried to query `e.raw_data` in database (field doesn't exist)
**After**:
- Joins with `public_event_sources` table
- Queries metadata field for promoter_id match
```elixir
query
|> join(:inner, [e], s in assoc(e, :sources))
|> where([e, s], fragment("?->>'promoter_id' = ?", s.metadata, ^promoter_id))
|> distinct([e], e.id)
```

## Testing

Ran successful sync: `mix discovery.sync resident-advisor --city-id 1 --limit 10 --inline`

Results:
- ✅ Container detection: 6 festival containers detected
- ✅ Deduplication: Existing containers properly identified
- ✅ Event processing: 48 events successfully queued
- ✅ Container matching: No KeyError exceptions
- ✅ Completion: 0 failed validations

## Files Changed

- `lib/eventasaurus_discovery/public_events/public_event_containers.ex`
  - Line 313-322: `check_for_container_match/1`
  - Line 369-382: `calculate_association_confidence/2`
  - Line 238-258: `find_matching_events/1`

## Related Issues

- #1523: Multi-Signal Container Detection implementation (completed)
- #1520: Event container architecture (parent issue)
- #1522: Duplicate container bug (resolved by deduplication logic)

## Impact

- Fixes 40+ failing Oban jobs
- Enables proper container-event association
- Allows festival grouping to work correctly
- No breaking changes to existing functionality
