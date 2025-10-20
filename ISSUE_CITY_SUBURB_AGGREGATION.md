# City/Suburb Aggregation Problem

## Problem Statement

The application treats city suburbs (e.g., "Paris 1", "Paris 8", "Paris 16") as completely separate cities, which creates fragmentation issues across multiple areas:

### Current Issues

1. **Statistics Page Fragmentation** (`discovery_dashboard_live.html.heex:777-828`)
   - Shows "Paris 1", "Paris 8", "Paris 16", etc. as separate entries with individual event counts
   - Difficult to see total Paris events at a glance
   - No way to understand that these are related to "Paris"

2. **Activities/Events Page Navigation**
   - Events in "Paris 9" don't show their relationship to parent city "Paris"
   - Missing breadcrumb navigation: Home > Paris > Paris 9 > Event
   - Users can't easily navigate back to the parent city

3. **Discovery Stats Inconsistency**
   - City detail views treat suburbs independently
   - No aggregation of statistics for metropolitan areas
   - Misleading metrics when comparing "cities"

### Real Data Examples

From the statistics page:
```
City          Event Count
Kraków        336
Paris         302
London        83
Paris 8       21
Paris 16      21
Paris 1       16
Paris 12      14
Paris 19      14
```

This pattern affects:
- Paris districts (Paris 1-20)
- London boroughs (potentially)
- New York boroughs (when added)
- Any other cities with administrative subdivisions

## Root Cause

Cities are created explicitly with coordinates, but there's no concept of city hierarchy or parent-child relationships. The geocoding process (via CityResolver) returns the most specific location name, which for Paris includes the arrondissement number.

## Current Architecture

### City Schema (`locations/city.ex`)
```elixir
schema "cities" do
  field(:name, :string)
  field(:slug, Slug.Type)
  field(:latitude, :decimal)
  field(:longitude, :decimal)
  field(:discovery_enabled, :boolean, default: false)
  field(:discovery_config, :map)

  belongs_to(:country, EventasaurusDiscovery.Locations.Country)
  has_many(:venues, EventasaurusApp.Venues.Venue)
end
```

### Key Observations
- Cities have coordinates (lat/long)
- No parent_city_id or hierarchy fields
- Each city is independent in the database
- Venues belong to specific cities (including suburbs)

## Solution Approach: Pure Geographic Clustering

**Goal**: Solve this problem WITHOUT database migrations using pure geographic proximity detection. No regex patterns needed.

### Why Pure Geographic?

✅ **100% objective** - no ambiguous name pattern matching
✅ **Works globally** - any naming convention (Paris 9, Brooklyn, Kraków-Nowa Huta, etc.)
✅ **Self-correcting** - adapts automatically as data grows
✅ **Simpler code** - no regex patterns to maintain
✅ **Data-driven** - cities with more events naturally become primaries

### Proposed Module: `CityHierarchy`

Location: `lib/eventasaurus_discovery/locations/city_hierarchy.ex`

#### Core Functions

```elixir
defmodule EventasaurusDiscovery.Locations.CityHierarchy do
  @moduledoc """
  Runtime detection of metropolitan areas using pure geographic clustering.
  No database changes or regex patterns required.
  """

  # Clustering
  def cluster_nearby_cities(cities, distance_km \\ 20.0)
  def get_primary_city(cluster)

  # Statistics
  def aggregate_stats_by_cluster(city_stats)

  # Navigation
  def build_breadcrumbs(city, all_cities)
  def get_metro_area_cities(city_id)
end
```

#### Clustering Algorithm

**Step 1: Calculate Distance Matrix**
- For each pair of cities, calculate Haversine distance
- Only consider cities in the same country
- Build adjacency list where distance < threshold (20-30km)

**Step 2: Form Clusters**
- Use connected components algorithm to group nearby cities
- All cities within threshold distance are in same cluster
- Each cluster represents a metropolitan area

**Step 3: Select Primary City**
- Within each cluster, the city with MOST EVENTS becomes primary
- This naturally makes "Paris" (302 events) primary over "Paris 8" (21 events)
- Self-correcting as data grows

**Step 4: Display-Time Aggregation**
- Compute clusters on-demand when loading statistics
- No caching needed initially (optimization can come later if needed)
- Simple, stateless transformation

#### Distance Calculation (Haversine)

```elixir
defp haversine_distance(lat1, lon1, lat2, lon2) do
  # Earth radius in kilometers
  r = 6371.0

  # Convert to radians
  lat1_rad = degrees_to_radians(Decimal.to_float(lat1))
  lat2_rad = degrees_to_radians(Decimal.to_float(lat2))
  delta_lat = degrees_to_radians(Decimal.to_float(lat2) - Decimal.to_float(lat1))
  delta_lon = degrees_to_radians(Decimal.to_float(lon2) - Decimal.to_float(lon1))

  # Haversine formula
  a = :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
      :math.cos(lat1_rad) * :math.cos(lat2_rad) *
      :math.sin(delta_lon / 2) * :math.sin(delta_lon / 2)

  c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

  r * c
end

defp degrees_to_radians(degrees), do: degrees * :math.pi() / 180.0
```

#### Complete Algorithm Example

```elixir
def aggregate_stats_by_cluster(city_stats, distance_threshold \\ 20.0) do
  # Load all cities with their coordinates
  cities = load_cities_with_coords(city_stats)

  # Build clusters based on geographic proximity
  clusters = cluster_nearby_cities(cities, distance_threshold)

  # For each cluster, aggregate stats
  Enum.map(clusters, fn cluster ->
    # Find primary city (most events)
    city_stats_in_cluster = Enum.filter(city_stats, fn stat ->
      Enum.any?(cluster, & &1.id == stat.city_id)
    end)

    primary_stat = Enum.max_by(city_stats_in_cluster, & &1.count)
    primary_city = Enum.find(cluster, & &1.id == primary_stat.city_id)

    # Build aggregated result
    %{
      city_id: primary_city.id,
      city_name: primary_city.name,
      city_slug: primary_city.slug,
      count: Enum.sum(Enum.map(city_stats_in_cluster, & &1.count)),
      subcities: Enum.reject(city_stats_in_cluster, & &1.city_id == primary_city.id)
    }
  end)
  |> Enum.sort_by(& &1.count, :desc)
end

defp cluster_nearby_cities(cities, distance_threshold) do
  # Build adjacency map: city_id -> [nearby_city_ids]
  adjacency = build_adjacency_map(cities, distance_threshold)

  # Find connected components (clusters)
  find_connected_components(adjacency)
end

defp build_adjacency_map(cities, threshold) do
  cities
  |> Enum.reduce(%{}, fn city, acc ->
    nearby = Enum.filter(cities, fn other ->
      city.id != other.id and
      city.country_id == other.country_id and
      haversine_distance(city.latitude, city.longitude, other.latitude, other.longitude) < threshold
    end)

    Map.put(acc, city.id, Enum.map(nearby, & &1.id))
  end)
end

defp find_connected_components(adjacency) do
  # Standard graph traversal to find all connected components
  # Each component becomes a metropolitan area cluster
  # Implementation: BFS or DFS from each unvisited node
end
```

### Application Points

#### 1. Statistics Page Aggregation

**File**: `lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex`

```elixir
# In mount or handle_params
defp load_city_stats do
  city_stats = query_city_event_counts() # Existing query

  # Apply clustering aggregation
  CityHierarchy.aggregate_stats_by_cluster(city_stats, 20.0)
end
```

**UI Change**: Expandable rows showing metro area breakdown

```heex
<%= for stat <- @city_stats do %>
  <tr>
    <td>
      <%= if length(stat.subcities) > 0 do %>
        <button phx-click="toggle_metro_details" phx-value-city-id={stat.city_id}
                class="flex items-center gap-2">
          <span>{stat.city_name}</span>
          <span class="text-xs text-gray-500">
            ({length(stat.subcities) + 1} areas)
          </span>
          <%= if @expanded_metro_id == stat.city_id do %>
            ▼
          <% else %>
            ▶
          <% end %>
        </button>
      <% else %>
        {stat.city_name}
      <% end %>
    </td>
    <td>{format_number(stat.count)}</td>
    <td><!-- actions --></td>
  </tr>

  <%= if @expanded_metro_id == stat.city_id do %>
    <%= for subcity <- stat.subcities do %>
      <tr class="bg-gray-50">
        <td class="pl-12 text-sm">{subcity.city_name}</td>
        <td class="text-sm">{format_number(subcity.count)}</td>
        <td class="text-sm"><!-- actions --></td>
      </tr>
    <% end %>
  <% end %>
<% end %>
```

**Before**:
```
Paris    302
Paris 8   21
Paris 16  21
Paris 1   16
```

**After**:
```
▶ Paris    360  (4 areas)
  [Click to expand and see: Paris 302, Paris 8 21, Paris 16 21, Paris 1 16]
```

#### 2. Breadcrumb Navigation

**File**: `lib/eventasaurus_web/helpers/breadcrumb_helper.ex` (new)

```elixir
defmodule EventasaurusWeb.Helpers.BreadcrumbHelper do
  alias EventasaurusDiscovery.Locations.CityHierarchy

  @doc """
  Builds breadcrumb trail for a city, including metro area primary if applicable.
  """
  def city_breadcrumbs(city, all_nearby_cities) do
    # Find if this city is part of a metro cluster
    cluster = CityHierarchy.find_cluster_for_city(city, all_nearby_cities)
    primary = CityHierarchy.get_primary_city(cluster)

    if primary && primary.id != city.id do
      # City is in a metro area with different primary
      [
        %{label: "Home", path: "/"},
        %{label: primary.name, path: "/city/#{primary.slug}"},
        %{label: city.name, path: "/city/#{city.slug}"}
      ]
    else
      # City is standalone or is the primary
      [
        %{label: "Home", path: "/"},
        %{label: city.name, path: "/city/#{city.slug}"}
      ]
    end
  end
end
```

**Apply to**: All city live views (events, venues, container_detail)

#### 3. SEO Improvements (Optional)

For non-primary cities in a metro area, optionally add:

```heex
<%= if primary_city = get_metro_primary(@city) do %>
  <link rel="canonical" href={url(~p"/city/#{primary_city.slug}")} />
  <meta name="description" content={"Events in #{@city.name}, #{primary_city.name} area"} />
<% end %>
```

## Implementation Phases

### Phase 0: Core Module (No UI Changes)
**Goal**: Build and test the clustering logic

- [ ] Create `CityHierarchy` module with clustering functions
- [ ] Implement Haversine distance calculation
- [ ] Implement connected components algorithm for clustering
- [ ] Write comprehensive tests covering:
  - Distance calculation accuracy
  - Clustering with various thresholds (10km, 20km, 30km)
  - Primary city selection (most events wins)
  - Same-country validation
  - Edge cases (isolated cities, equal event counts)
- [ ] Performance testing with real Paris data

**Deliverable**: Fully tested module, no UI changes

### Phase 1: Statistics Page
**Goal**: Fix the fragmented city statistics display

- [ ] Integrate `aggregate_stats_by_cluster/1` in dashboard live
- [ ] Add expandable metro area rows in UI
- [ ] Add toggle state management
- [ ] Test with real Paris data

**Validation**: Paris shows as single entry (360 events, 4 areas)

### Phase 2: Breadcrumb Navigation
**Goal**: Show metro area hierarchy in navigation

- [ ] Create `BreadcrumbHelper` module
- [ ] Update all city LiveViews to use breadcrumbs
- [ ] Style breadcrumbs component
- [ ] Test navigation flow

**Result**: Events in Paris 9 show: Home > Paris > Paris 9 > Event Name

### Phase 3: Discovery Stats Page
**Goal**: Consistent aggregation across all stats views

- [ ] Update city detail page to show metro area context
- [ ] Add "View all [Primary City] areas" link
- [ ] Update trend charts for metro aggregation

### Phase 4: SEO & Optimization (Optional)
**Goal**: Performance and search engine optimization

- [ ] Add canonical URLs for non-primary cities
- [ ] Add caching if performance becomes an issue
- [ ] Update sitemap generation

## Distance Threshold Selection

**Recommended**: 20-25km for most metropolitan areas

**Analysis by City Type**:
- **Compact Cities** (Paris, Barcelona): 10-15km captures all districts
- **Medium Cities** (London, Berlin): 20-25km for boroughs
- **Large Cities** (NYC, Tokyo): 30-40km for outer boroughs

**Configurable Options**:
1. Start with 20km default
2. Add per-country override if needed
3. Make it a config value for easy tuning

## Alternative Approaches Considered

### ❌ Approach 1: Add parent_city_id to Database
**Pros**:
- Explicit relationships
- Fast queries

**Cons**:
- Requires migration
- Manual maintenance
- Doesn't leverage coordinate data

**Verdict**: Rejected - requires migration

### ❌ Approach 2: Regex Pattern Matching + Geographic
**Pros**:
- Can detect specific naming patterns

**Cons**:
- Complex to maintain across languages/cultures
- Regex can create false positives/negatives
- Adds unnecessary complexity
- Geographic proximity alone is sufficient

**Verdict**: Rejected - unnecessary complexity

### ✅ Approach 3: Pure Geographic Clustering (Proposed)
**Pros**:
- No migrations required ✅
- No regex patterns to maintain ✅
- 100% objective, data-driven ✅
- Works globally for any naming convention ✅
- Self-correcting as data grows ✅

**Cons**:
- Requires computation (negligible for <100 cities)
- May need threshold tuning

**Verdict**: Best fit - simple, robust, maintainable

## Edge Cases Handled

1. **Cities with same name in different countries**
   - ✅ Solution: Always check country_id matches in clustering

2. **Isolated cities**
   - ✅ Solution: Form single-city clusters (no subcities)

3. **Equal event counts**
   - ✅ Solution: Tie-breaker using city_id or name length

4. **Three cities in a line**
   - ✅ Solution: All join same cluster if within threshold

5. **Performance with many cities**
   - ✅ Solution: O(n²) distance matrix, acceptable for <500 cities
   - Can optimize with spatial indexing if needed later

## Testing Strategy

### Unit Tests
- Distance calculation accuracy (known lat/lon pairs)
- Clustering algorithm correctness
- Primary city selection logic
- Edge case handling

### Integration Tests
- Real Paris data aggregation
- Statistics page rendering
- Breadcrumb generation

### Manual Testing
- Verify Paris districts cluster correctly
- Check isolated cities (Kraków) remain standalone
- Test with London boroughs (when added)

## Performance Analysis

**Computational Complexity**:
- Distance matrix: O(n²) where n = number of cities
- Connected components: O(n + e) where e = edges
- For 100 cities: ~10,000 distance calculations
- Each Haversine: ~1μs
- **Total: ~10ms** for full clustering (acceptable)

**Optimization Options** (if needed later):
- Cache clustering results (refresh hourly)
- Use spatial indexing (PostGIS) for faster neighbor queries
- Precompute clusters on city updates

**Memory Usage**:
- Distance matrix: 100 cities × 100 cities × 8 bytes = ~80KB
- Negligible impact

## Success Metrics

- ✅ Statistics page shows <50 city entries (currently ~100+)
- ✅ All Paris areas aggregate under "Paris" (currently split across 10+ entries)
- ✅ Breadcrumbs show metro area on non-primary city pages
- ✅ Clustering computation: <20ms for 100 cities
- ✅ Zero database migrations required

## Related Files

### To Modify
- `lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex` - Statistics aggregation
- `lib/eventasaurus_web/live/city_live/*.ex` - Breadcrumb integration

### To Create
- `lib/eventasaurus_discovery/locations/city_hierarchy.ex` - Core module
- `lib/eventasaurus_web/helpers/breadcrumb_helper.ex` - Breadcrumb builder
- `test/eventasaurus_discovery/locations/city_hierarchy_test.exs` - Tests

### Reference
- `lib/eventasaurus_discovery/locations/city.ex` - City schema
- `lib/eventasaurus_discovery/helpers/city_resolver.ex` - Geocoding patterns

## Questions for Discussion

1. **Distance threshold**: Start with 20km? Make configurable per-country?
2. **UI display**: Aggregated by default with expand, or list all with grouping header?
3. **Breadcrumbs**: Always show primary city, or only when viewing non-primary?
4. **Caching**: Implement immediately or wait for performance needs?
5. **Admin override**: Need manual cluster override interface?

## Conclusion

This simplified approach uses **pure geographic clustering** to solve city/suburb aggregation without database migrations or complex regex patterns. It's:

- **Simple**: Just distance calculations and clustering
- **Objective**: Based on coordinates and event counts
- **Global**: Works for any city naming convention worldwide
- **Maintainable**: No patterns to update for new cities
- **Performant**: <20ms for typical city counts
- **Self-correcting**: Automatically adapts as data grows

The phased implementation validates core logic before UI changes, minimizing risk.
