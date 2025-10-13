# Venue Metadata Structure

## Overview

Venues use a **two-column approach** for storing geocoding data:

1. **`geocoding_performance`** (JSONB) - Performance metrics for scraper cost tracking dashboard
2. **`metadata`** (JSONB) - Raw provider responses for debugging

This separation follows our universal convention where `metadata` always stores raw provider data across all tables.

## Column Structures

### `venues.geocoding_performance`

**Purpose**: Cost tracking and performance analysis for geocoding dashboard

**Structure**:
```elixir
%{
  cost_per_call: 0.006,                    # Float - Cost for this geocoding call
  attempted_providers: ["mapbox", "here"], # Array - Providers tried in order
  attempts: 2,                             # Integer - Number of attempts before success
  geocoded_at: ~U[2025-01-12 10:30:00Z]   # DateTime - When geocoding occurred
}
```

**Fields**:
- `cost_per_call` - API cost for the successful provider (0.0 for free providers)
- `attempted_providers` - List of all providers attempted in fallback order
- `attempts` - Total number of provider attempts (1 = first provider succeeded)
- `geocoded_at` - Timestamp when geocoding completed

**Used By**:
- `EventasaurusDiscovery.Metrics.GeocodingStats` - Dashboard queries
- Cost reporting and budget tracking
- Provider performance analysis

### `venues.metadata`

**Purpose**: Raw provider response data for debugging and future use

**Structure**:
```elixir
%{
  captured_at: ~U[2025-01-12 10:30:00Z],  # DateTime - When data was captured
  created_by: "geocoder",                  # String - Source of this data
  raw_response: %{                         # Map - Full provider API response
    latitude: 51.5074,
    longitude: -0.1278,
    city: "London",
    country: "United Kingdom",
    # ... full API response from provider
  }
}
```

**Fields**:
- `captured_at` - Timestamp when metadata was captured
- `created_by` - Source system ("geocoder", "scraper", "user", etc.)
- `raw_response` - Complete unmodified response from geocoding provider

**Used By**:
- Debugging geocoding issues
- Extracting additional data fields later
- Auditing provider responses

## Related Columns

### `venues.source`

**Purpose**: Single source of truth for which provider geocoded this venue

**Type**: VARCHAR (column in venues table)

**Values**:
- Geocoding providers: `"mapbox"`, `"here"`, `"geoapify"`, `"locationiq"`, `"openstreetmap"`, `"photon"`, `"google_maps"`, `"google_places"`
- Manual sources: `"user"`, `"scraper"`

**Why Not in Metadata?**: Prevents duplication - this is a core database field used for queries and filtering

### `venues.place_id`

**Purpose**: External provider's unique identifier for this location

**Type**: VARCHAR (column in venues table)

**Format**:
- Google Places: `"ChIJ..."` (base64 encoded)
- Mapbox: `"mapbox-coord-{lng}-{lat}"` (coordinate-based for stability)
- Other providers: Provider-specific formats

**Deduplication**: Used as primary deduplication mechanism with unique constraint

## Data Flow

### 1. Geocoding Request
```
VenueProcessor → AddressGeocoder → Orchestrator → Provider (Mapbox, HERE, etc.)
```

### 2. Orchestrator Returns
```elixir
{:ok, %{
  latitude: 51.5074,
  longitude: -0.1278,
  city: "London",
  country: "United Kingdom",
  # Performance metrics for dashboard
  geocoding_performance: %{
    cost_per_call: 0.006,
    attempted_providers: ["mapbox"],
    attempts: 1,
    geocoded_at: ~U[2025-01-12 10:30:00Z]
  },
  # Raw data for debugging
  metadata: %{
    captured_at: ~U[2025-01-12 10:30:00Z],
    created_by: "geocoder",
    raw_response: %{...full API response...}
  }
}}
```

### 3. VenueProcessor Stores
```elixir
%Venue{
  name: "Example Venue",
  latitude: 51.5074,
  longitude: -0.1278,
  source: "mapbox",                    # From place_id detection
  place_id: "mapbox-coord-51.5074--0.1278",
  geocoding_performance: %{...},       # From orchestrator
  metadata: %{...}                     # From orchestrator
}
```

## Query Patterns

### Cost Tracking Queries

Use `geocoding_performance` column:

```elixir
# Monthly costs
from v in Venue,
  where:
    fragment("(?->>'geocoded_at')::timestamp >= ?", v.geocoding_performance, ^start_date) and
    not is_nil(v.geocoding_performance),
  select: %{
    total_cost: sum(fragment("COALESCE((?->>'cost_per_call')::numeric, 0)", v.geocoding_performance)),
    count: count(v.id)
  }

# Costs by provider
from v in Venue,
  where: not is_nil(v.geocoding_performance),
  group_by: v.source,
  select: %{
    provider: v.source,
    total_cost: sum(fragment("(?->>'cost_per_call')::numeric", v.geocoding_performance)),
    count: count(v.id)
  }
```

### Provider Performance Queries

Use `geocoding_performance` column:

```elixir
# Success rates by provider
from v in Venue,
  where: not is_nil(v.geocoding_performance),
  group_by: v.source,
  select: %{
    provider: v.source,
    success_count: count(v.id),
    avg_attempts: avg(fragment("(?->>'attempts')::integer", v.geocoding_performance))
  }

# Fallback patterns
from v in Venue,
  where: not is_nil(v.geocoding_performance),
  select: %{
    attempted_providers: fragment("?->>'attempted_providers'", v.geocoding_performance),
    successful_provider: v.source
  }
```

### Debugging Queries

Use `metadata` column:

```elixir
# Raw provider responses
from v in Venue,
  where: v.source == "mapbox",
  select: %{
    venue_name: v.name,
    raw_response: fragment("?->'raw_response'", v.metadata)
  }

# Captured metadata timestamps
from v in Venue,
  where: not is_nil(v.metadata),
  select: %{
    venue_name: v.name,
    captured_at: fragment("?->>'captured_at'", v.metadata),
    created_by: fragment("?->>'created_by'", v.metadata)
  }
```

## Migration Notes

### Old Structure (Deprecated)
```elixir
%Venue{
  metadata: %{
    geocoding: %{
      provider: "mapbox",              # ❌ REMOVED - duplicates venues.source
      cost_per_call: 0.006,
      attempted_providers: [...],
      attempts: 1,
      geocoded_at: ~U[...]
    },
    geocoding_metadata: %{             # ❌ REMOVED - moved to root metadata
      provider: "mapbox",
      raw_response: %{...}
    }
  }
}
```

### New Structure (Current)
```elixir
%Venue{
  source: "mapbox",                    # ✅ Single source of truth
  geocoding_performance: %{            # ✅ Dashboard metrics only
    cost_per_call: 0.006,
    attempted_providers: [...],
    attempts: 1,
    geocoded_at: ~U[...]
  },
  metadata: %{                         # ✅ Raw data for debugging
    captured_at: ~U[...],
    created_by: "geocoder",
    raw_response: %{...}
  }
}
```

### Why This Change?

1. **No Duplication**: Provider stored once in `venues.source`, not duplicated in metadata
2. **Universal Convention**: `metadata` means "raw provider data" across all tables in the system
3. **Clear Separation**: Performance metrics separate from raw debugging data
4. **Query Performance**: Dedicated column for dashboard queries instead of nested JSONB paths
5. **Maintainability**: Clear structure makes it obvious what goes where

## Provider-Specific Notes

### Mapbox
- Returns `place_id` as coordinate-based: `"mapbox-coord-{lng}-{lat}"`
- Ensures stable IDs (no timestamps that break deduplication)
- Raw response includes feature geometry, properties, context

### Google Places
- Returns `place_id` starting with `"ChIJ"`
- High cost ($0.034/call for Places, $0.005/call for Maps)
- Currently disabled by default

### Free Providers (OpenStreetMap, Photon, LocationIQ)
- `cost_per_call: 0.0`
- May have rate limits (handled by RateLimiter)
- Good for development and testing

## Best Practices

### When Creating Venues

1. **Always set source**: Detect from `place_id` or set to "scraper"/"user"
2. **Store performance metrics**: Include cost, attempts, attempted_providers
3. **Store raw response**: Complete API response in `metadata.raw_response`
4. **No provider duplication**: Never store provider in metadata columns

### When Querying Venues

1. **Cost tracking**: Query `geocoding_performance` column
2. **Provider filtering**: Use `venues.source` column
3. **Debugging**: Query `metadata.raw_response` for full API data
4. **Performance analysis**: Use `geocoding_performance.attempted_providers` and `attempts`

### When Adding New Providers

1. Add provider to `geocoding_providers` table (it auto-syncs to valid sources)
2. Implement provider module with `geocode/1` function
3. Return standard structure from Orchestrator (includes both columns)
4. No code changes needed in VenueProcessor (dynamic validation)

## Related Files

- **Orchestrator**: `lib/eventasaurus_discovery/geocoding/orchestrator.ex`
- **VenueProcessor**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex`
- **Venue Schema**: `lib/eventasaurus_app/venues/venue.ex`
- **Dashboard**: `lib/eventasaurus_discovery/metrics/geocoding_stats.ex`
- **Migration**: `priv/repo/migrations/20251012212618_add_geocoding_performance_to_venues.exs`

## Questions?

See GitHub issue [#1696](https://github.com/anthropics/eventasaurus/issues/1696) for the full discussion and implementation history.
