# Insufficient Venue Context in Image Enrichment Job Metadata

## Problem Statement

When venue image enrichment jobs fail with `:no_place_id`, the Oban job metadata provides no context about the venue itself, making it impossible to diagnose WHY the venue doesn't have a provider ID.

### Current Metadata (Insufficient)

```elixir
Args: %{"force" => true, "providers" => ["google_places"], "venue_id" => 70}

Meta: %{
  "providers" => %{
    "google_places" => %{"reason" => ":no_place_id", "status" => "failed"}
  },
  "status" => "no_images",
  "summary" => "No images found - venue has no available photos"
}
```

**Questions We Can't Answer:**
- ❌ What is the venue name?
- ❌ Does this venue have coordinates?
- ❌ Does it have a city_id?
- ❌ Does it have ANY provider IDs (maybe different providers)?
- ❌ Was geocoding ever attempted?
- ❌ Is this a data quality issue or expected behavior?

## Root Cause Analysis

### Data Flow Trace

```
1. Job starts with venue_id: 70
   ↓
2. Loads venue via Repo.get(Venue, venue_id)
   - HAS ACCESS TO: name, address, lat/lng, provider_ids, city_id
   ↓
3. Calls Orchestrator.fetch_venue_images(venue, ["google_places"])
   ↓
4. Orchestrator.fetch_from_provider checks get_place_id(venue, "google_places")
   - Checks: venue.provider_ids["google_places"]
   ↓
5. Returns {:error, "google_places", :no_place_id}
   ↓
6. Error stored in metadata.error_details["google_places"] = :no_place_id
   ↓
7. Job calls build_success_metadata(enriched_venue, start_time)
   - ✅ HAS FULL VENUE OBJECT
   - ❌ DOESN'T EXTRACT VENUE CONTEXT
```

### Code Locations

**Where venue data is available:**
- `enrichment_job.ex:173` - Venue loaded from DB
- `enrichment_job.ex:187` - Passed to `build_success_metadata(enriched_venue, start_time)`
- `enrichment_job.ex:856` - `build_success_metadata` function receives full venue

**Where error occurs:**
- `orchestrator.ex:295-300` - `get_place_id/2` checks `venue.provider_ids`
- Returns `:no_place_id` if key not found

**Venue schema fields available** (`venues/venue.ex:153-173`):
```elixir
field(:name, :string)
field(:address, :string)
field(:latitude, :float)
field(:longitude, :float)
field(:provider_ids, :map, default: %{})  # ← THE KEY FIELD
belongs_to(:city_ref, EventasaurusDiscovery.Locations.City, foreign_key: :city_id)
```

## Recommended Metadata Additions

### New "venue_context" Section

Add to `build_success_metadata/2` function:

```elixir
venue_context: %{
  venue_id: enriched_venue.id,
  venue_name: enriched_venue.name,
  venue_address: enriched_venue.address,
  has_coordinates: !is_nil(enriched_venue.latitude) and !is_nil(enriched_venue.longitude),
  coordinates: if(enriched_venue.latitude, do: "#{enriched_venue.latitude},#{enriched_venue.longitude}", else: nil),
  city_id: enriched_venue.city_id,
  provider_ids_available: Map.keys(enriched_venue.provider_ids || %{}),
  provider_ids_count: map_size(enriched_venue.provider_ids || %{}),
  requested_providers: extract_requested_providers(enriched_venue)
}
```

### Example: What You'd See

**Scenario 1: Venue Needs Geocoding**
```elixir
Meta: %{
  "venue_context" => %{
    "venue_id" => 70,
    "venue_name" => "Blue Note Jazz Club",
    "venue_address" => "131 W 3rd St, New York, NY 10012",
    "has_coordinates" => true,
    "coordinates" => "40.7308,-74.0007",
    "city_id" => 5,
    "provider_ids_available" => [],           # ← EMPTY! Needs geocoding
    "provider_ids_count" => 0,
    "requested_providers" => ["google_places"]
  },
  "providers" => %{
    "google_places" => %{"reason" => ":no_place_id", "status" => "failed"}
  }
}
```

**Diagnosis:** ✅ Clear! Venue has address + coordinates but no provider_ids → **Needs geocoding first**

**Scenario 2: Wrong Provider Requested**
```elixir
Meta: %{
  "venue_context" => %{
    "venue_id" => 70,
    "venue_name" => "Blue Note Jazz Club",
    "provider_ids_available" => ["foursquare", "here"],  # ← Has IDs, wrong provider
    "provider_ids_count" => 2,
    "requested_providers" => ["google_places"]           # ← Requested wrong one
  },
  "providers" => %{
    "google_places" => %{"reason" => ":no_place_id", "status" => "failed"}
  }
}
```

**Diagnosis:** ✅ Clear! Venue has provider_ids but for different providers → **Either use existing providers or geocode for google_places**

**Scenario 3: Data Quality Issue**
```elixir
Meta: %{
  "venue_context" => %{
    "venue_id" => 70,
    "venue_name" => "Unknown Venue",
    "venue_address" => nil,
    "has_coordinates" => false,               # ← No coordinates!
    "city_id" => nil,                        # ← No city!
    "provider_ids_available" => [],
    "provider_ids_count" => 0
  }
}
```

**Diagnosis:** ✅ Clear! Venue missing critical data → **Data quality issue, fix venue data first**

## Implementation Recommendations

### 1. Update `build_success_metadata/2`

**File:** `lib/eventasaurus_discovery/venue_images/enrichment_job.ex:856`

Add venue context section:

```elixir
defp build_success_metadata(enriched_venue, start_time) do
  # ... existing code ...

  # NEW: Extract venue context for debugging
  venue_context = build_venue_context(enriched_venue)

  %{
    # Existing fields...
    status: status,
    images_discovered: length(all_images),
    # ... etc ...

    # NEW FIELD
    venue_context: venue_context,

    # Existing fields...
    execution_time_ms: execution_time,
    completed_at: DateTime.to_iso8601(DateTime.utc_now())
  }
end
```

### 2. Add Helper Function

```elixir
defp build_venue_context(venue) do
  provider_ids = venue.provider_ids || %{}

  %{
    venue_id: venue.id,
    venue_name: venue.name,
    venue_address: venue.address,
    has_coordinates: !is_nil(venue.latitude) and !is_nil(venue.longitude),
    coordinates:
      if venue.latitude and venue.longitude do
        "#{venue.latitude},#{venue.longitude}"
      else
        nil
      end,
    city_id: venue.city_id,
    provider_ids_available: Map.keys(provider_ids) |> Enum.map(&to_string/1),
    provider_ids_count: map_size(provider_ids)
  }
end
```

### 3. Optional: Add to Error Metadata Too

**File:** `lib/eventasaurus_discovery/venue_images/enrichment_job.ex:924`

Update `build_error_metadata/2` to accept venue:

```elixir
defp build_error_metadata(reason, start_time, venue) do
  execution_time = DateTime.diff(DateTime.utc_now(), start_time, :millisecond)

  %{
    status: "error",
    error: inspect(reason),
    venue_context: build_venue_context(venue),  # NEW
    images_found: 0,
    execution_time_ms: execution_time,
    failed_at: DateTime.to_iso8601(DateTime.utc_now())
  }
end
```

## Benefits

### Immediate Diagnosis
- See venue name instead of just ID
- Know if venue needs geocoding vs has wrong provider
- Identify data quality issues at a glance

### Pattern Recognition
- Spot systematic issues (e.g., "all venues from source X lack provider_ids")
- Identify geographic patterns (e.g., "venues in city Y don't have google_places IDs")

### Reduced Investigation Time
- No need to query database manually
- No need to correlate job timestamps with application logs
- All context in one place in Oban UI

### Better Monitoring/Alerting
- Alert on specific conditions: "venues with coordinates but no provider_ids"
- Track geocoding coverage by city/region
- Measure data quality metrics

## Alternative: Minimal Addition

If full context is too much, at minimum add:

```elixir
%{
  # Existing metadata...
  venue_name: enriched_venue.name,  # Just the name!
  venue_provider_ids: Map.keys(enriched_venue.provider_ids || %{})  # What we have
}
```

Even this minimal addition would dramatically improve debuggability.

## Testing Recommendations

After implementation:

1. **Trigger `:no_place_id` error** (venue without geocoding)
   - Verify metadata shows empty provider_ids_available
   - Verify venue name is displayed

2. **Trigger with partial provider_ids** (venue has foursquare, request google_places)
   - Verify metadata shows ["foursquare"] in provider_ids_available
   - Verify clearly shows mismatch

3. **Check success cases**
   - Verify venue_context doesn't bloat metadata excessively
   - Verify coordinates display correctly

## Priority

**High** - This is blocking your ability to diagnose production issues. You're seeing systematic `:no_place_id` failures but can't tell:
- If venues need geocoding
- If this is a data migration issue
- If specific venue sources are problematic

Without this context, every failure requires manual database queries to understand what's happening.

## Related Issues

- See: `.github/ISSUE_GOOGLE_PLACES_ERROR_MESSAGES.md` - Similar issue with insufficient error context
