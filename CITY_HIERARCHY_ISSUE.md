# City Clustering Bug: Random Suburbs Displayed Instead of Major Cities

## Problem Statement

The city clustering system is displaying random suburbs and villages as primary cities instead of major metropolitan areas. Examples:

- **Pantin** (small Paris suburb) shows as primary with 25 areas, including Paris 8, Paris 1, etc. as subcities
- **Grange** (unknown location) shows as primary with 18 areas, including Brisbane (major Australian city) as a subcity
- **Meaux** (rural village 46km from Paris) was showing as primary until diameter validation fix

This makes the "Top 10 Cities" list completely nonsensical, showing villages that "barely exist" instead of major metropolitan areas like Paris and Brisbane.

## Root Cause Analysis

### The Fundamental Data Flow Problem

```
1. Database Query (discovery_stats_cache.ex:337-355)
   ↓
   SELECT cities WHERE event_count >= 1
   ↓
   Result: Only cities with events (excludes base cities with 0 events)

2. Clustering (city_hierarchy.ex:56-70)
   ↓
   Groups nearby cities geographically
   ↓
   Result: Clusters contain subcities but missing base cities

3. Primary City Selection (city_hierarchy.ex:267-301)
   ↓
   Selects "best" city from cluster using scoring system
   ↓
   Result: WRONG - base city not in candidate list!
```

### Why Base Cities Have 0 Events

Base cities like "Paris" and "Brisbane" are **administrative concepts** - they don't have venues or events directly associated with them. Instead:

- Events are stored at **venues**
- Venues are in specific **districts/suburbs** (Paris 8, Paris 1, West End, Fortitude Valley)
- The base city "Paris" itself has no venues, therefore **0 events**
- But "Paris" is clearly the most important city in the region

This creates a paradox:
- **Event count** measures district-level activity
- **Metropolitan importance** should aggregate activity across all districts
- We're using event count to rank cities, but it fails for parent cities

### The Missing Data Problem

The `aggregate_stats_by_cluster/2` function receives:

```elixir
city_stats = [
  %{city_id: pantin_id, count: 7},      # Pantin has events
  %{city_id: paris_8_id, count: 8},     # Paris 8 has events
  %{city_id: paris_1_id, count: 5},     # Paris 1 has events
  # ... but NO entry for Paris base city (0 events, filtered by query)
]
```

The parent detection logic `is_parent_city_of_cluster?/2` is **correct** but applied to an **incomplete dataset**. It can only detect parents among cities that have events, so it can never select Paris if Paris has 0 events.

### Why This Wasn't Caught

1. **Assumption Failure**: Assumed `city_stats` would contain all cities in a cluster
2. **Testing Gap**: Only tested that Meaux was separated from Paris, didn't verify Paris became primary
3. **Narrow Focus**: Focused on fixing transitive clustering (Meaux 46km away) without considering missing base city problem
4. **No End-to-End Verification**: Didn't trace data flow from database query to UI display

## The Chicken-and-Egg Problem

- To know which cities to include in the query, we need to know the hierarchy
- To know the hierarchy, we need to have all cities in the clustering algorithm
- But we can't cluster cities we haven't queried
- So we query based on events, which excludes the cities we need to establish hierarchy

## Examples of the Bug

### Example 1: Pantin over Paris
```
Current (WRONG):
Pantin (25 areas) - 59 events
├─ Paris 8 - 8 events
├─ Paris 1 - 5 events
├─ Paris 19 - 4 events
└─ ... (Paris districts as subcities)

Expected (CORRECT):
Paris (25 areas) - 59 events
├─ Paris 8 - 8 events
├─ Paris 1 - 5 events
├─ Paris 19 - 4 events
├─ Pantin - 7 events
└─ ... (districts as subcities)
```

### Example 2: Grange over Brisbane
```
Current (WRONG):
Grange (18 areas) - 21 events
├─ West End - 2 events
├─ Brisbane - 2 events
└─ ... (Brisbane suburbs as subcities)

Expected (CORRECT):
Brisbane (18 areas) - 21 events
├─ West End - 2 events
├─ Grange - ? events
├─ Fortitude Valley - 1 event
└─ ... (suburbs as subcities)
```

## Proposed Solutions

### Solution 1: Two-Phase Clustering (RECOMMENDED for immediate fix)

**Phase 1: Cluster by Geography** (as currently implemented)
- Group nearby cities within distance threshold
- Validate cluster diameter to prevent distant outliers

**Phase 2: Inject Base Cities**
- For each cluster, detect potential base cities by pattern matching:
  - City slug has no numeric suffix (not `paris-8`, just `paris`)
  - City name is substring/prefix of other cities in cluster
  - City name is shorter than other cities
- If detected pattern matches, load base city from database
- Inject into candidate list with `count: 0`
- Let existing scoring system handle selection

**Implementation**:
```elixir
defp aggregate_cluster_stats(city_ids_in_cluster, city_stats, cities) do
  # Current logic to get city_stats_in_cluster
  city_stats_in_cluster = Enum.filter(city_stats, fn stat ->
    stat.city_id in city_ids_in_cluster
  end)

  # NEW: Detect and inject base cities
  all_cities_in_cluster = Enum.map(city_ids_in_cluster, fn id ->
    Enum.find(cities, &(&1.id == id))
  end)

  potential_base_city = detect_base_city(all_cities_in_cluster)

  city_stats_in_cluster_with_base =
    if potential_base_city && !Enum.any?(city_stats_in_cluster, &(&1.city_id == potential_base_city.id)) do
      # Base city not in stats, inject it
      [%{city_id: potential_base_city.id, count: 0} | city_stats_in_cluster]
    else
      city_stats_in_cluster
    end

  # Continue with existing primary selection logic...
end

defp detect_base_city(cities) do
  # Find city with shortest name, no suffix, matches other names
  # ...
end
```

**Pros**:
- Minimal changes to existing code
- Works with current query structure
- Handles missing base cities elegantly
- Can be implemented quickly

**Cons**:
- Additional DB lookups per cluster (but minimal, only 10 clusters typically)
- Heuristic-based detection (relies on naming patterns)

### Solution 2: Pre-compute City Hierarchy (RECOMMENDED for long-term)

**Database Schema Changes**:
```sql
ALTER TABLE cities ADD COLUMN parent_city_id INTEGER REFERENCES cities(id);

-- Examples:
-- Paris 8 → parent_city_id = Paris.id
-- Paris 1 → parent_city_id = Paris.id
-- Pantin → parent_city_id = Paris.id
-- Paris → parent_city_id = NULL
```

**Query Changes**:
```elixir
query =
  from(e in PublicEvent,
    join: v in Venue, on: v.id == e.venue_id,
    join: c in City, on: c.id == v.city_id,
    left_join: p in City, on: p.id == c.parent_city_id,
    group_by: [coalesce(p.id, c.id), coalesce(p.name, c.name)],
    select: %{
      city_id: coalesce(p.id, c.id),
      city_name: coalesce(p.name, c.name),
      count: count(e.id)
    }
  )
```

**Pros**:
- Cleanest solution
- Fastest queries
- Explicit data model
- No inference needed
- Scales to complex hierarchies

**Cons**:
- Requires schema migration
- Requires data population (which cities are parents?)
- Ongoing maintenance as cities are added
- Takes time to implement

### Solution 3: Expand Query to Include Base Cities

Modify query to include cities with 0 events if they match base city patterns:

```elixir
# This is complex and not recommended
query =
  from(e in PublicEvent,
    # ... existing joins ...
    union: ^base_cities_subquery,  # Cities matching base patterns
    group_by: [...],
    having: count(e.id) >= 1 OR is_base_city(c.slug)
  )
```

**Pros**:
- Solves at query layer
- No post-processing needed

**Cons**:
- Very complex SQL
- Hard to maintain
- Doesn't scale to all hierarchy patterns
- Performance concerns

## Recommended Approach

1. **Immediate (This Sprint)**: Implement Solution 1 (Two-Phase Clustering)
   - Quick to implement
   - Solves immediate problem
   - Minimal risk

2. **Long-term (Next Quarter)**: Implement Solution 2 (City Hierarchy Schema)
   - Proper data modeling
   - Enables future features (browsing by region, filtering by metro area)
   - Foundation for multi-level hierarchies

## Testing Strategy

### Unit Tests
- Test parent detection with various naming patterns
- Test that base city with 0 events beats suburb with events
- Test edge cases: cities with same prefix, very long names, etc.

### Integration Tests
- Query real database for Paris region
- Verify "Paris" appears as primary (not Pantin, not Paris 8)
- Verify total event count is sum of all subcities

### Regression Tests
- Verify London still works correctly
- Verify cities without hierarchy (Kraków, Warszawa) still work
- Verify cluster diameter validation still prevents Meaux from clustering

## Success Criteria

- [ ] Paris appears as primary city (not Pantin, not Paris 8)
- [ ] Brisbane appears as primary city (not Grange, not West End)
- [ ] London continues to work correctly
- [ ] Event counts are summed correctly across all subcities
- [ ] No performance degradation on admin stats page
- [ ] All existing tests pass

## Related Code

- `lib/eventasaurus_discovery/locations/city_hierarchy.ex:260-341` - Primary city selection
- `lib/eventasaurus_discovery/admin/discovery_stats_cache.ex:337-376` - City performance query
- `lib/eventasaurus_web/live/admin/discovery_stats_live.ex` - UI display

## Priority: CRITICAL

This bug makes the entire city statistics feature unusable and displays nonsensical information to users.
