# Issue: Country-wide/Regional Sources Failing with "City not found" Error

## Problem

When attempting to queue Question One or Geeks Who Drink scrapers from the discovery dashboard, the system returns:

```
Error! Import failed: City not found (id: )
```

This occurs even though these sources are **country-wide/regional sources** that don't require a city_id parameter.

## Root Cause Analysis

### Architecture Overview

The system uses a scope-based approach to determine whether sources require a city_id:

1. **SourceRegistry.requires_city_id?(source_slug)** - Checks if source needs city_id
2. **SourceRegistry.get_scope(source_slug)** - Reads `metadata["scope"]` from sources table
3. **Scope values**:
   - `"city"` - Requires specific city (Ticketmaster, Bandsintown, etc.)
   - `"country"` - Country-wide (PubQuiz Poland)
   - `"regional"` - Multi-country region (Question One: UK/Ireland, Geeks Who Drink: US/Canada)

### The Bug

**Seeds file location**: `priv/repo/seeds/sources.exs`

The seeds file is **missing the `"scope"` field** in metadata for all sources. Example:

```elixir
%{
  name: "Question One",
  slug: "question-one",
  website_url: "https://www.questionone.co.uk",
  priority: 35,
  domains: ["trivia"],
  aggregate_on_index: true,
  aggregation_type: "trivia",
  metadata: %{
    "rate_limit_seconds" => 2,
    "max_requests_per_hour" => 300,
    "language" => "en",
    "supports_recurring_events" => true
    # ❌ MISSING: "scope" => "regional"
  }
}
```

### Failure Chain

1. User tries to queue Question One from dashboard
2. DiscoveryDashboardLive calls DiscoverySyncJob with `city_id: nil`
3. DiscoverySyncJob.perform() calls `SourceRegistry.requires_city_id?("question-one")`
4. SourceRegistry.get_scope() queries sources table, finds metadata WITHOUT "scope" field
5. **Defaults to `"city"` scope** (line 120 in source_registry.ex)
6. requires_city_id?() returns `true`
7. Job checks for city with `city_id: nil`, fails with "City not found (id: )"

### Code References

**source_registry.ex:105-130** - get_scope() defaults to :city when scope is nil:
```elixir
scope =
  case metadata["scope"] do
    "city" -> :city
    "country" -> :country
    "regional" -> :regional
    nil -> :city  # ❌ BAD DEFAULT
    other -> :city
  end
```

**source_registry.ex:147-153** - requires_city_id?() returns true for city scope:
```elixir
def requires_city_id?(source_slug) do
  case get_scope(source_slug) do
    {:ok, :city} -> true
    {:ok, _} -> false
    {:error, _} -> true  # Default to requiring city for safety
  end
end
```

**discovery_sync_job.ex:50-55** - Fails when city is required but missing:
```elixir
if requires_city && (!city_id || !city) do
  error_msg = "City not found (id: #{city_id})"
  Logger.error("❌ #{error_msg} for #{source} sync")
  broadcast_progress(:error, %{message: error_msg})
  {:error, error_msg}
end
```

## Solution

Add `"scope"` field to metadata in `priv/repo/seeds/sources.exs`:

### City-scoped sources (scope: "city")
- Ticketmaster
- Bandsintown
- Resident Advisor
- Karnet Kraków
- Cinema City
- Kino Krakow

### Country-scoped sources (scope: "country")
- PubQuiz Poland (Poland-wide)

### Regional-scoped sources (scope: "regional")
- Question One (UK/Ireland)
- Geeks Who Drink (US/Canada)

## Implementation

Update each source in seeds file to include scope:

```elixir
%{
  name: "Question One",
  slug: "question-one",
  website_url: "https://www.questionone.co.uk",
  priority: 35,
  domains: ["trivia"],
  aggregate_on_index: true,
  aggregation_type: "trivia",
  metadata: %{
    "rate_limit_seconds" => 2,
    "max_requests_per_hour" => 300,
    "language" => "en",
    "supports_recurring_events" => true,
    "scope" => "regional"  # ✅ FIXED
  }
}
```

## Alternative Considered

### Option 1: Auto-create cities during scraping
**Pros**: No manual city management needed
**Cons**:
- Complex: Need geocoding for every venue
- Performance: Geocoding API calls slow down scraping
- Data quality: Auto-created cities may have inconsistent names/boundaries

### Option 2: Manual city creation UI
**Pros**: Clean data, admin control
**Cons**:
- Painful UX: Admin must manually add every city before scraping
- Scalability: Question One alone covers 100+ UK/Ireland cities

### **Option 3: Scope-based routing (CHOSEN)**
**Pros**:
- Clean architecture: Sources declare their requirements
- No geocoding overhead: Only needed for venue storage, not job routing
- Works NOW: System already has scope infrastructure
**Cons**:
- Seeds must be updated with scope field

## Testing

After updating seeds:

1. Drop and reseed database:
   ```bash
   mix ecto.drop && mix ecto.create && mix ecto.migrate && mix run priv/repo/seeds.exs
   ```

2. Navigate to discovery dashboard: http://localhost:4000/admin/imports

3. Queue Question One:
   - Select "Question One" from source dropdown
   - Should show "Coverage: UK & Ireland (Unbounded)" instead of city selector
   - Click "Start Import"
   - Should succeed without "City not found" error

4. Verify city auto-creation:
   - Question One will discover venues in various UK/Ireland cities
   - VenueProcessor will geocode addresses and auto-create cities as needed
   - Check `/admin/discovery/config` to see new cities appear

## Files to Update

- `priv/repo/seeds/sources.exs` - Add "scope" to all source metadata
- After seeds update, drop/reseed database to apply changes

## Related Code

- `lib/eventasaurus_discovery/sources/source_registry.ex:105-153` - Scope detection
- `lib/eventasaurus_discovery/admin/discovery_sync_job.ex:38-55` - City requirement check
- `lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex:26-31` - UI source classification
