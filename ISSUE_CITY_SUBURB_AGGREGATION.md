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

## Solution Approach: Runtime City Hierarchy Detection

**Goal**: Solve this problem WITHOUT database migrations by using runtime computation based on existing geo-coordinates and name patterns.

### Proposed Module: `CityHierarchy`

Location: `lib/eventasaurus_discovery/locations/city_hierarchy.ex`

#### Core Functions

```elixir
defmodule EventasaurusDiscovery.Locations.CityHierarchy do
  @moduledoc """
  Runtime detection of city-suburb relationships using geographic
  coordinates and naming patterns. No database changes required.
  """

  # Detection
  def get_parent_city(city)
  def get_suburb_cities(parent_city)
  def is_suburb?(city)

  # Statistics
  def aggregate_stats_by_parent(city_stats)
  def get_city_with_suburbs(city_id)

  # Navigation
  def build_breadcrumbs(city)
  def get_canonical_city(city)
end
```

#### Detection Algorithm

**Step 1: Pattern Matching**
- Regex: `~r/^(.+?)\s+\d+$/` (e.g., "Paris 9" → "Paris")
- Regex: `~r/^(.+?)\s+\d{1,2}(st|nd|rd|th)?$/` (e.g., "Paris 8th" → "Paris")
- Additional patterns for other naming conventions

**Step 2: Geographic Validation**
- Calculate distance between potential suburb and parent using Haversine formula
- Threshold: Suburbs must be within 50km of parent city center
- Prevents false matches (e.g., "Springfield 1" in different states)

**Step 3: Database Lookup**
- Check if parent city exists in database by name and country
- Match must be in same country
- Return parent city if found and distance check passes

**Step 4: Caching**
- Cache results in ETS table keyed by city_id
- TTL: 1 hour (suburbs don't change frequently)
- Invalidate on city updates

#### Distance Calculation (Haversine)

```elixir
defp haversine_distance(lat1, lon1, lat2, lon2) do
  # Earth radius in kilometers
  r = 6371.0

  # Convert to radians
  lat1_rad = degrees_to_radians(lat1)
  lat2_rad = degrees_to_radians(lat2)
  delta_lat = degrees_to_radians(lat2 - lat1)
  delta_lon = degrees_to_radians(lon2 - lon1)

  # Haversine formula
  a = :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
      :math.cos(lat1_rad) * :math.cos(lat2_rad) *
      :math.sin(delta_lon / 2) * :math.sin(delta_lon / 2)

  c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

  r * c
end
```

### Application Points

#### 1. Statistics Page Aggregation

**File**: `lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex`

```elixir
# Before rendering city_stats
defp aggregate_city_stats(city_stats) do
  city_stats
  |> Enum.group_by(fn stat ->
    city = Repo.get(City, stat.city_id)
    parent = CityHierarchy.get_parent_city(city)
    if parent, do: parent.id, else: stat.city_id
  end)
  |> Enum.map(fn {parent_id, stats} ->
    parent_city = Repo.get(City, parent_id)
    suburbs = Enum.map(stats, fn s ->
      city = Repo.get(City, s.city_id)
      %{id: city.id, name: city.name, count: s.count}
    end)

    %{
      city_id: parent_id,
      city_name: parent_city.name,
      count: Enum.sum(Enum.map(stats, & &1.count)),
      suburbs: suburbs
    }
  end)
  |> Enum.sort_by(& &1.count, :desc)
end
```

**UI Change**: Expandable rows showing suburb breakdown
```heex
<tr>
  <td>
    <button phx-click="toggle_suburb_details" phx-value-city-id={stat.city_id}>
      {stat.city_name}
      <%= if length(stat.suburbs) > 0 do %>
        <span class="text-xs text-gray-500">({length(stat.suburbs)} areas)</span>
      <% end %>
    </button>
  </td>
  <td>{format_number(stat.count)}</td>
</tr>
<%= if @expanded_city_id == stat.city_id do %>
  <%= for suburb <- stat.suburbs do %>
    <tr class="bg-gray-50">
      <td class="pl-12">{suburb.name}</td>
      <td>{format_number(suburb.count)}</td>
    </tr>
  <% end %>
<% end %>
```

#### 2. Breadcrumb Navigation

**File**: `lib/eventasaurus_web/helpers/breadcrumb_helper.ex` (new)

```elixir
defmodule EventasaurusWeb.Helpers.BreadcrumbHelper do
  alias EventasaurusDiscovery.Locations.CityHierarchy

  def city_breadcrumbs(city) do
    case CityHierarchy.get_parent_city(city) do
      nil ->
        [
          %{label: "Home", path: "/"},
          %{label: city.name, path: "/city/#{city.slug}"}
        ]
      parent ->
        [
          %{label: "Home", path: "/"},
          %{label: parent.name, path: "/city/#{parent.slug}"},
          %{label: city.name, path: "/city/#{city.slug}"}
        ]
    end
  end
end
```

**Apply to**: All city live views (events, venues, container_detail)

#### 3. SEO Improvements

**Canonical URLs**: Point suburb pages to parent city
```heex
<%= if parent = CityHierarchy.get_parent_city(@city) do %>
  <link rel="canonical" href={url(~p"/city/#{parent.slug}")} />
<% end %>
```

**Meta Descriptions**: Include parent city context
```heex
<meta name="description" content={"Events in #{@city.name}, #{parent.name}"} />
```

## Implementation Phases

### Phase 0: Core Module (No UI Changes)
**Goal**: Build and test the hierarchy detection logic

- [ ] Create `CityHierarchy` module with detection functions
- [ ] Implement Haversine distance calculation
- [ ] Add ETS caching for performance
- [ ] Write comprehensive tests covering:
  - Pattern matching (Paris 9, New York 1, etc.)
  - Distance validation (prevent false matches)
  - Same-country validation
  - Edge cases (single-word cities, similar names)
- [ ] Performance testing (should be <5ms per lookup with cache)

**Deliverable**: Fully tested module, no UI changes

### Phase 1: Statistics Page
**Goal**: Fix the fragmented city statistics display

- [ ] Implement `aggregate_city_stats/1` in dashboard live
- [ ] Add expandable suburb rows in UI
- [ ] Add toggle state management
- [ ] Test with real Paris data

**Before**:
```
Paris    302
Paris 8   21
Paris 16  21
```

**After**:
```
Paris    344  (3 areas) [expandable]
  ├─ Paris      302
  ├─ Paris 8     21
  └─ Paris 16    21
```

### Phase 2: Breadcrumb Navigation
**Goal**: Show city hierarchy in navigation

- [ ] Create `BreadcrumbHelper` module
- [ ] Update all city LiveViews to use breadcrumbs
- [ ] Style breadcrumbs component
- [ ] Test navigation flow

**Result**: Events in Paris 9 show: Home > Paris > Paris 9 > Event Name

### Phase 3: SEO & Metadata
**Goal**: Improve search engine understanding

- [ ] Add canonical URL links for suburbs
- [ ] Update meta descriptions to include parent city
- [ ] Generate schema.org structured data with city hierarchy
- [ ] Update sitemap generation to understand relationships

### Phase 4: Discovery Stats Page
**Goal**: Consistent aggregation across all stats views

- [ ] Update city detail page to show parent city context
- [ ] Add "View all [Parent City] areas" link
- [ ] Aggregate source statistics by parent city
- [ ] Update trend charts to show parent city trends

## Alternative Approaches Considered

### ❌ Approach 1: Add parent_city_id to Database
**Pros**:
- Explicit relationships
- Easy queries
- No runtime computation

**Cons**:
- Requires migration
- Need to populate existing data
- Manual maintenance when cities added
- What about cities that change (historical data)?
- Doesn't leverage existing coordinate data

**Verdict**: Rejected due to migration requirement and maintenance burden

### ❌ Approach 2: Pre-compute and Store in discovery_config
**Pros**:
- No query-time computation
- Explicit storage

**Cons**:
- Still requires updates to all existing cities
- Redundant with coordinate data
- Discovery_config is for different purpose
- Harder to maintain

**Verdict**: Rejected - overloads config field

### ✅ Approach 3: Runtime Detection (Proposed)
**Pros**:
- No migrations required ✅
- Uses existing coordinate data
- Automatically works for new cities
- Can be improved over time without data changes
- Performance acceptable with caching (<5ms)

**Cons**:
- Requires computation (mitigated by ETS cache)
- Slightly more complex logic
- Pattern matching might need tuning for different cities

**Verdict**: Best fit for requirements

## Edge Cases to Handle

1. **Cities with same name in different countries**
   - Solution: Always check country_id matches
   - Example: Springfield, USA vs Springfield, UK

2. **Cities that legitimately have numbers**
   - Solution: Distance check will fail if not related
   - Example: "City 1" that's 1000km from "City"

3. **False positives**
   - Solution: Require both pattern match AND distance check
   - Can add manual override list if needed

4. **Multiple parent candidates**
   - Solution: Choose closest parent by distance
   - Example: If "Paris 9" and another "Paris" both exist, use closer one

5. **Circular references**
   - Solution: Pattern only matches parent if parent has NO number suffix
   - "Paris 9" → "Paris" ✅
   - "Paris" → nothing ✅

6. **Performance with many cities**
   - Solution: ETS cache with 1-hour TTL
   - Lazy loading (only compute when needed)
   - Consider preloading on app startup for active cities

## Testing Strategy

### Unit Tests
- Pattern matching logic
- Distance calculation accuracy
- Cache hit/miss behavior
- Edge case handling

### Integration Tests
- Statistics aggregation with real data
- Breadcrumb generation for various city types
- Performance benchmarks (should be <5ms cached)

### Manual Testing
- Verify Paris districts aggregate correctly
- Check London boroughs (when added)
- Ensure Kraków shows correctly (no suburbs)

## Performance Considerations

**Cache Strategy**:
- ETS table: `:city_hierarchy_cache`
- Key: `{:parent, city_id}` and `{:suburbs, city_id}`
- TTL: 1 hour (configurable)
- Invalidation: On city updates (via Ecto callbacks)

**Expected Performance**:
- Uncached lookup: ~10-20ms (DB + computation)
- Cached lookup: <1ms (ETS)
- Cache hit rate: >95% for active cities

**Memory Usage**:
- ~100 bytes per cached relationship
- 1000 cities = ~100KB in cache
- Negligible impact

## Future Enhancements

1. **Admin UI for Manual Overrides**
   - Allow admins to explicitly set parent-child relationships
   - Override automatic detection for edge cases

2. **Multi-level Hierarchy**
   - Support: Country > Region > City > Suburb
   - Example: France > Île-de-France > Paris > Paris 9

3. **City Merging Tool**
   - Admin interface to merge duplicate cities
   - Migrate events from suburb to parent

4. **Analytics**
   - Track which cities are most fragmented
   - Identify detection failures
   - Optimize patterns based on real data

## Success Metrics

- ✅ Statistics page shows <50 city entries (currently ~100+)
- ✅ All Paris events aggregate under "Paris" (currently split across 10+ entries)
- ✅ Breadcrumbs show parent city on all suburb event pages
- ✅ Performance: <5ms per city hierarchy lookup (cached)
- ✅ Zero database migrations required

## Related Files

### To Modify
- `lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex` - Statistics aggregation
- `lib/eventasaurus_web/live/city_live/*.ex` - Breadcrumb integration
- `lib/eventasaurus_web/helpers/public_event_display_helpers.ex` - Display helpers

### To Create
- `lib/eventasaurus_discovery/locations/city_hierarchy.ex` - Core module
- `lib/eventasaurus_web/helpers/breadcrumb_helper.ex` - Breadcrumb builder
- `test/eventasaurus_discovery/locations/city_hierarchy_test.exs` - Tests

### Reference
- `lib/eventasaurus_discovery/locations/city.ex` - City schema
- `lib/eventasaurus_discovery/helpers/city_resolver.ex` - Geocoding patterns

## Questions for Discussion

1. Should we show aggregated stats by default with expand option, or show suburbs with aggregate option?
2. Distance threshold: 50km reasonable? Should vary by country/region?
3. Should suburban event pages redirect to parent city, or show with breadcrumbs?
4. Do we need a way for admins to manually override hierarchy detection?
5. Should we preload hierarchy for all cities on app start, or lazy load?

## Conclusion

This approach solves the city/suburb aggregation problem without database migrations by using runtime detection based on existing geographic coordinates and naming patterns. It's performant (with ETS caching), maintainable (pure functions), and extensible (can add patterns over time).

The phased implementation approach allows us to validate the core logic before rolling out UI changes, minimizing risk.
