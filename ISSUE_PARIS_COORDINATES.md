# Issue: Paris City Missing Coordinates - Arrondissement Granularity Problem

**Status**: Critical Bug
**Severity**: High - Blocks access to `/c/paris` URL
**Affected Component**: City coordinate calculation, Sortiraparis scraper, URL routing
**Date Discovered**: 2025-10-17

---

## Problem Summary

The main "Paris" city (ID: 371, slug: `paris`) exists in the database but has **no latitude/longitude coordinates**, causing the `ValidateCity` plug to fail when users try to access `/c/paris`. This happens because all Sortiraparis venues are linked to **arrondissement-level cities** (Paris 1, Paris 2, Paris 5, etc.) instead of the main Paris city.

**Error Message**:
```
RuntimeError at GET /c/paris
City 'Paris' (slug: paris) exists but has no coordinates.
Run coordinate calculation job or add coordinates manually.
```

**User Impact**: The Sortiraparis source shows 84 events in the dashboard, but the `/c/paris` URL doesn't work, preventing users from browsing Paris events.

---

## Root Cause Analysis

### Data Flow

1. **Sortiraparis Scraper** extracts venue addresses from HTML:
   - Address format: `"8 Boulevard de Bercy, 75012 Paris 12"`
   - VenueExtractor uses regex: `/Paris(?:\s+\d{1,2})?/`
   - Extracts city as: `"Paris 12"`, `"Paris 5"`, etc. (with arrondissement number)

2. **VenueProcessor** receives venue data with `city_name: "Paris 12"`:
   - Looks up city by exact name match
   - No match found for "Paris 12"
   - Creates NEW city record with `name: "Paris 12"`, `slug: "paris-12"`

3. **Venue Creation**:
   - Venue linked to arrondissement city (e.g., `city_id: 377` for Paris 12)
   - Main Paris city (ID: 371) receives NO venues

4. **Coordinate Calculation**:
   - `CityCoordinateCalculationJob` calculates coordinates from venue averages
   - Arrondissement cities get coordinates (they have venues)
   - Main Paris city remains empty (no venues to average)

5. **URL Routing Failure**:
   - User accesses `/c/paris`
   - `ValidateCity` plug looks up city by slug `"paris"`
   - Finds Paris city but `latitude` and `longitude` are NULL
   - Raises error in dev, returns 503 in production

### Current State (Database Evidence)

```elixir
# Main Paris city - NO VENUES, NO COORDINATES
%{id: 371, name: "Paris", slug: "paris", latitude: nil, longitude: nil}

# Arrondissement cities - HAVE VENUES AND COORDINATES
%{id: 372, name: "Paris 5", slug: "paris-5", lat: 48.850483, lng: 2.344081}
%{id: 373, name: "Paris 9", slug: "paris-9", lat: 48.872070, lng: 2.341245}
%{id: 375, name: "Paris 8", slug: "paris-8", lat: 48.867195, lng: 2.311650}
# ... 17 more arrondissement cities with coordinates
```

**Venue Distribution**:
- Paris 1-19 arrondissements: 64 venues across 84 events
- Main "Paris" city: **0 venues**
- Surrounding suburbs (Versailles, Nanterre, etc.): ~10 venues

---

## Why This Happens

### Design Intent vs. Reality

The system was **designed** with these assumptions:
1. Cities are flat entities (no parent-child hierarchy)
2. Venues belong to one city
3. City coordinates = average of venue locations
4. URL routing uses exact slug matching

**The Reality**:
- Geocoding providers return granular city names (arrondissements for Paris, boroughs for London, etc.)
- Sortiraparis HTML includes arrondissement numbers in addresses
- Users expect `/c/paris` to work for all Paris events
- No normalization layer exists between granular cities and canonical cities

### The Mismatch

| Layer | Expected Behavior | Actual Behavior |
|-------|------------------|-----------------|
| **Scraper** | Extract "Paris" | Extracts "Paris 5", "Paris 9" |
| **Geocoding** | Return "Paris" | Returns arrondissement-level names |
| **Database** | One "Paris" city | 20+ Paris cities (arrondissements + suburbs) |
| **URL** | `/c/paris` works | 404 - Paris has no coordinates |
| **User Intent** | See all Paris events | Blocked by missing coordinates |

---

## Why Coordinate Calculation Job Doesn't Help

The `CityCoordinateCalculationJob` works correctly - it calculates coordinates from venue averages. But for the main Paris city:

```elixir
# Job logic:
SELECT avg(v.latitude), avg(v.longitude), count(v.id)
FROM venues v
WHERE v.city_id = 371  -- Main Paris city
AND v.latitude IS NOT NULL
AND v.longitude IS NOT NULL
```

**Result**: `0 venues` → `NO coordinates` → `Job returns {:error, :no_venues}`

The job **cannot** calculate coordinates for Paris because Paris has no venues. All venues belong to the arrondissement cities.

---

## File References

### Key Files Involved

1. **VenueExtractor** (`lib/eventasaurus_discovery/sources/sortiraparis/extractors/venue_extractor.ex`)
   - Line 417-421: `parse_address/1` - Extracts "Paris 5", "Paris 9" with regex
   - Line 64: Fallback to "Paris" only if no city found

2. **VenueProcessor** (`lib/eventasaurus_discovery/scraping/processors/venue_processor.ex`)
   - Line 298-316: `ensure_city/1` - Exact name matching, creates new cities
   - No normalization of arrondissement names

3. **CityCoordinateCalculationJob** (`lib/eventasaurus_discovery/jobs/city_coordinate_calculation_job.ex`)
   - Line 91-112: `calculate_coordinates/1` - Averages venue locations
   - Returns `{:error, :no_venues}` when no venues exist

4. **ValidateCity Plug** (`lib/eventasaurus_web/plugs/validate_city.ex`)
   - Line 18: Direct slug lookup via `Locations.get_city_by_slug/1`
   - Line 37-54: Requires coordinates, fails if missing

5. **City Schema** (`lib/eventasaurus_discovery/locations/city.ex`)
   - No parent_id or hierarchy fields
   - Flat structure: id, name, slug, latitude, longitude, country_id

---

## Solution Options

### Option 1: Normalize Arrondissements to "Paris" (Quick Fix)

**Change**: Modify `VenueExtractor.parse_address/1` to strip arrondissement numbers.

```elixir
# Current (line 417-421):
city = case Regex.run(~r/Paris(?:\s+\d{1,2})?/, address_string) do
  [match] -> match  # Returns "Paris 5"
  _ -> "Paris"
end

# Proposed:
city = case Regex.run(~r/Paris(?:\s+\d{1,2})?/, address_string) do
  [_match] -> "Paris"  # Always return "Paris"
  _ -> "Paris"
end
```

**Pros**:
- Simplest fix
- All new venues go to main Paris city
- Coordinates calculate automatically

**Cons**:
- Loses arrondissement granularity (might be useful for local events)
- Need to migrate existing 64 venues to main Paris city
- Doesn't solve the general problem (London boroughs, NYC boroughs, etc.)

---

### Option 2: Add City Hierarchy (Architectural Change)

**Change**: Add `parent_id` field to cities table, create parent-child relationships.

```elixir
# Migration:
alter table(:cities) do
  add :parent_id, references(:cities, on_delete: :nilify_all)
end

# Schema:
schema "cities" do
  field :name, :string
  field :parent_id, :id
  belongs_to :parent, City
  has_many :children, City, foreign_key: :parent_id
end

# Data structure:
Paris (parent, has coordinates from child average)
  ├── Paris 1 (child, coordinates from venues)
  ├── Paris 5 (child, coordinates from venues)
  └── Paris 9 (child, coordinates from venues)
```

**Implementation**:
1. Add parent_id column
2. Link arrondissements to main Paris
3. Update coordinate job to aggregate child cities
4. Update routing to handle parent lookups

**Pros**:
- Preserves granularity
- Scalable to other cities (London, NYC, Tokyo)
- Clean data model

**Cons**:
- Significant schema change
- Need migration for existing data
- More complex coordinate calculation
- Routing logic needs enhancement

---

### Option 3: Aggregate Coordinates for Parent Cities

**Change**: Update `CityCoordinateCalculationJob` to handle city aggregation.

```elixir
# Add special handling for known parent cities:
defp calculate_coordinates(%City{slug: "paris"}) do
  # Find all Paris arrondissements
  child_cities = from(c in City,
    where: fragment("? LIKE 'paris-%' OR ? LIKE '% paris %'", c.slug, c.name))
    |> Repo.all()

  # Calculate average from all child city coordinates
  aggregate_child_coordinates(child_cities)
end
```

**Pros**:
- No schema changes
- Preserves existing data
- Solves immediate problem

**Cons**:
- Hardcoded logic for specific cities
- Doesn't scale well
- Fragile (depends on naming patterns)

---

### Option 4: Slug Aliases/Normalization (Routing Layer)

**Change**: Add slug normalization in `ValidateCity` plug or `Locations` module.

```elixir
# Add lookup fallback:
case Locations.get_city_by_slug(city_slug) do
  nil ->
    # Try pattern matching for arrondissements
    case Locations.find_parent_city(city_slug) do
      nil -> not_found()
      parent_city -> assign(conn, :current_city, parent_city)
    end

  city -> validate_coordinates(city)
end
```

**Pros**:
- No data migration needed
- Flexible routing
- Can handle multiple patterns

**Cons**:
- Doesn't fix underlying data issue
- Complex routing logic
- Paris still has no actual coordinates

---

### Option 5: Virtual City Views (Recommended)

**Change**: Create a database view or computed city system.

```sql
-- Create view that aggregates arrondissements:
CREATE VIEW city_with_aggregates AS
SELECT
  c.id,
  c.name,
  c.slug,
  COALESCE(c.latitude, child_avg.lat) as latitude,
  COALESCE(c.longitude, child_avg.lng) as longitude
FROM cities c
LEFT JOIN (
  SELECT
    parent_name,
    AVG(latitude) as lat,
    AVG(longitude) as lng
  FROM cities
  WHERE name LIKE 'Paris %'
  GROUP BY substring(name, 1, position(' ' in name)-1)
) child_avg ON child_avg.parent_name = c.name
```

**Pros**:
- Minimal code changes
- Database-level solution
- Scalable and performant

**Cons**:
- Requires SQL view management
- More complex schema
- Need to identify parent-child patterns

---

## Recommendations

### Immediate Fix (Today)

**Option 1A**: Manually set Paris coordinates to city center:
```elixir
mix run -e "alias EventasaurusDiscovery.Locations.City; alias EventasaurusApp.Repo; import Ecto.Query; Repo.update_all(from(c in City, where: c.id == 371), set: [latitude: Decimal.new(\"48.8566\"), longitude: Decimal.new(\"2.3522\"), updated_at: NaiveDateTime.utc_now()])"
```

This unblocks `/c/paris` immediately while we design a proper solution.

### Short-term Fix (This Week)

**Option 3**: Add aggregate coordinate calculation for Paris in `CityCoordinateCalculationJob`.
- Detect parent cities by pattern matching
- Calculate coordinates from child cities
- Minimal risk, contained change

### Long-term Solution (Next Sprint)

**Option 2**: Implement city hierarchy with `parent_id`.
- Proper data model for cities with subdivisions
- Scales to other cities (London, NYC, Tokyo)
- Clean separation of concerns

---

## Testing Strategy

### Verification Steps

1. **Check Current State**:
```bash
# Verify Paris has no coordinates
mix run -e "EventasaurusDiscovery.Locations.get_city_by_slug!(\"paris\") |> IO.inspect()"

# Check arrondissement coordinates
mix run -e "EventasaurusApp.Repo.all(from c in EventasaurusDiscovery.Locations.City, where: like(c.slug, \"paris-%\")) |> Enum.map(&{&1.slug, &1.latitude, &1.longitude}) |> IO.inspect(limit: :infinity)"
```

2. **Test Coordinate Job**:
```bash
# Try to calculate Paris coordinates (will fail with :no_venues)
mix discovery.calculate_city_coordinates --city-id=371 --force

# Verify arrondissements can calculate
mix discovery.calculate_city_coordinates --city-id=372 --force  # Paris 5
```

3. **Test URL Access**:
```bash
# After fix, should work:
curl http://localhost:4000/c/paris
```

### Regression Testing

After implementing any solution:
1. Verify all Paris arrondissement URLs still work (`/c/paris-5`, `/c/paris-9`)
2. Check venue counts are correct
3. Verify coordinate calculation job still works for other cities
4. Test Sortiraparis scraper creates venues in correct cities

---

## Impact Analysis

### Current Impact

- **84 Sortiraparis events** are in the system
- **64 unique venues** across Paris arrondissements
- **Main Paris URL** is completely broken
- **Arrondissement URLs** work fine (e.g., `/c/paris-5`)

### User Impact

**Severity**: High
- Users cannot browse events via `/c/paris`
- Must use specific arrondissement URLs
- Poor UX - users don't know arrondissement slugs
- Dashboard shows "Paris" but URL doesn't work

### Similar Cities at Risk

Any city with administrative subdivisions faces the same issue:
- **London** (boroughs: Westminster, Camden, etc.)
- **New York** (boroughs: Manhattan, Brooklyn, etc.)
- **Tokyo** (wards: Shibuya, Shinjuku, etc.)
- **Berlin** (districts: Mitte, Kreuzberg, etc.)

---

## Related Issues

- City coordinate calculation depends on venues existing
- No city hierarchy or parent-child relationships
- URL routing assumes flat city structure
- Geocoding returns overly granular city names

---

## Next Steps

1. **Immediate**: Apply manual coordinate fix for Paris
2. **Review**: Discuss solution options with team
3. **Design**: Create detailed design for chosen approach
4. **Implement**: Build and test solution
5. **Migrate**: Update existing data if needed
6. **Document**: Update scraper documentation about city handling
