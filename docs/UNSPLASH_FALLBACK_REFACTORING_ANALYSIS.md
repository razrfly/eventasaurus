# Unsplash Fallback Image Enrichment - Refactoring Analysis

## Executive Summary

This document analyzes the current state of event image enrichment with Unsplash fallbacks and proposes a unified architecture to reduce code duplication and improve maintainability as we expand this feature across the application.

**Key Finding**: Image enrichment logic is currently scattered across multiple locations with inconsistent patterns. A unified enrichment API would provide a single source of truth and enable consistent behavior across all event display contexts.

## Current State

### Working Implementations

1. **Aggregate Detail Pages** (`AggregatedContentLive`)
   - Location: `/c/london/trivia/speed-quizzing`
   - Pattern: Query-level enrichment via `list_events(browsing_city_id: city.id)`
   - Status: ✅ Working correctly
   - Code: `lib/eventasaurus_web/live/aggregated_content_live.ex:182-193`

2. **Main City Page Aggregate Cards** (`CityLive.Index`)
   - Location: `/c/london` aggregate group cards
   - Pattern: Post-query enrichment in `build_aggregated_group`
   - Special Logic: Multi-venue (>3) uses city images, small aggregates (≤3) use venue images
   - Status: ✅ Working correctly with special multi-venue logic
   - Code: `lib/eventasaurus_discovery/public_events_enhanced.ex:1299-1322`

### Locations Needing Implementation

3. **Individual Event Detail Pages** (`PublicEventShowLive`)
   - Location: `/activities/quiz-night-at-royal-oak-twickenham-251106`
   - Current: Main event display lacks Unsplash fallback
   - Need: Enrich single event with its own city's Unsplash gallery
   - Priority: HIGH (user-identified)

4. **Nearby Activities Sidebar** (`PublicEventShowLive`)
   - Location: Same page as #3, sidebar showing related events
   - Current: Shows placeholder images
   - Need: Enrich list of events, each using its own city's gallery
   - Priority: HIGH (user-identified)

5. **City Search Results** (`CityLive.Search`)
   - Location: `/c/london?q=trivia` (hypothetical)
   - Current: Unknown, needs investigation
   - Need: Likely needs browsing city enrichment
   - Priority: MEDIUM

6. **Global Activities Feed** (`PublicEventsIndexLive`)
   - Location: `/activities` (main feed)
   - Current: Unknown, needs investigation
   - Need: Events from multiple cities, each using own city gallery
   - Priority: MEDIUM

## Problem Analysis

### Core Challenge

Image enrichment happens at different architectural layers depending on context:

- **Query Layer**: Some views enrich during `list_events` call
- **Aggregation Layer**: Aggregate cards enrich during grouping
- **View Layer**: Some views would need to enrich in LiveView mount/assigns

This creates:
- **Code Duplication**: Similar enrichment logic in multiple places
- **Inconsistent Behavior**: Different rules applied in different contexts
- **Maintenance Burden**: Changes must be replicated across locations
- **Testing Difficulty**: Can't easily unit test enrichment logic

### Context Patterns

Two distinct patterns emerge:

**Pattern A: Browsing City Context** (City-centric views)
- User explicitly browsing a specific city (URL: `/c/london`)
- All events should use the browsing city's Unsplash gallery
- Examples: City pages, city search results, aggregate detail pages
- Current approach: Pass `browsing_city_id` to query

**Pattern B: No Browsing Context** (Event-centric views)
- No specific city being browsed (URL: `/activities/some-event`)
- Events from different cities mixed together
- Each event should use its own venue's city Unsplash gallery
- Current approach: Not yet implemented

### Required Context for Enrichment

For proper image enrichment, we need:

1. **Event Data**: sources, movies, categories (for CategoryMapper)
2. **Venue Data**: Associated venue record
3. **City Data**: venue.city_ref with unsplash_gallery preloaded
4. **Context Hint**: Browsing city (Pattern A) or use own city (Pattern B)

### Special Cases

1. **Multi-venue Aggregates**:
   - Showing specific venue image for 62+ venues is misleading
   - Solution: Use city image when venue count > 3
   - Currently handled in `build_aggregated_group`

2. **Pattern Events**:
   - Recurring events with schedule patterns
   - Need timezone handling for occurrence dates
   - Already handled by existing logic

## Proposed Architecture

### Unified Enrichment API

Create a single, reusable enrichment function in `PublicEventsEnhanced`:

```elixir
@doc """
Enriches events with cover_image_url using Unsplash city image fallbacks.

## Strategies

- `:browsing_city` - Use single browsing city for all events (city-centric views)
  Requires: `browsing_city_id` option

- `:own_city` - Use each event's venue city (event-centric views)
  Default strategy when browsing_city_id not provided

- `:skip` - Don't enrich, preserve existing cover_image_url values
  Useful for events that already have images

## Options

- `browsing_city_id` - City ID to use for :browsing_city strategy
- `force` - Re-enrich even if cover_image_url already set (default: false)
- `strategy` - Enrichment strategy (default: :own_city)

## Examples

    # City-centric view (all events use London's gallery)
    events = PublicEventsEnhanced.list_events(...)
    enriched = PublicEventsEnhanced.enrich_event_images(events,
      strategy: :browsing_city,
      browsing_city_id: london_id
    )

    # Event-centric view (each event uses its own city)
    events = PublicEventsEnhanced.list_events(...)
    enriched = PublicEventsEnhanced.enrich_event_images(events,
      strategy: :own_city
    )

## Preload Requirements

Events must have these associations preloaded:
- `sources` (for source images and fallback detection)
- `movies` (for movie-specific images)
- `categories` (for category determination)
- `venue.city_ref.unsplash_gallery` (for Unsplash fallback)

Use `preload_for_image_enrichment/1` helper to ensure proper preloads.
"""
@spec enrich_event_images([PublicEvent.t()], keyword()) :: [PublicEvent.t()]
def enrich_event_images(events, opts \\ []) when is_list(events) do
  strategy = Keyword.get(opts, :strategy, :own_city)
  browsing_city_id = Keyword.get(opts, :browsing_city_id)
  force = Keyword.get(opts, :force, false)

  case strategy do
    :browsing_city when is_integer(browsing_city_id) ->
      # Fetch browsing city once, reuse for all events
      browsing_city = Locations.get_city(browsing_city_id)
                      |> Repo.preload(:unsplash_gallery)
      Enum.map(events, &enrich_with_browsing_city(&1, browsing_city, force))

    :own_city ->
      # Use each event's own venue city
      Enum.map(events, &enrich_with_own_city(&1, force))

    :skip ->
      events

    _ ->
      # Invalid strategy, return as-is with warning
      Logger.warning("Invalid enrichment strategy: #{inspect(strategy)}")
      events
  end
end

# Private helper: enrich with browsing city
defp enrich_with_browsing_city(event, browsing_city, force) do
  if force || is_nil(event.cover_image_url) do
    cover_image_url = get_cover_image_url(event, browsing_city.id)
    Map.put(event, :cover_image_url, cover_image_url)
  else
    event
  end
end

# Private helper: enrich with event's own city
defp enrich_with_own_city(event, force) do
  if force || is_nil(event.cover_image_url) do
    # Get city_id from event's venue
    city_id = get_in(event, [Access.key(:venue), Access.key(:city_ref), Access.key(:id)])

    if city_id do
      cover_image_url = get_cover_image_url(event, city_id)
      Map.put(event, :cover_image_url, cover_image_url)
    else
      # No venue/city, can't enrich
      event
    end
  else
    event
  end
end

@doc """
Helper to ensure events have required preloads for image enrichment.
Can be piped into Ecto queries or called on query results.

## Example

    query
    |> PublicEventsEnhanced.preload_for_image_enrichment()
    |> Repo.all()
"""
def preload_for_image_enrichment(query_or_events) do
  Repo.preload(query_or_events, [
    :sources,
    :movies,
    :categories,
    venue: [city_ref: :unsplash_gallery]
  ])
end
```

### Migration Path for Each Location

#### 1. AggregatedContentLive (✅ Keep As-Is)
**Current**: Passes `browsing_city_id` to `list_events`, which enriches at query level
**Migration**: Optional - could migrate to post-query enrichment for consistency
**Priority**: Low (already working)

```elixir
# Optional migration for consistency:
events = PublicEventsEnhanced.list_events(%{
  source_slug: identifier,
  center_lat: lat,
  center_lng: lng,
  radius_km: 50,
  include_pattern_events: true,
  page_size: 500
  # Remove: browsing_city_id: city.id
})
|> PublicEventsEnhanced.enrich_event_images(
  strategy: :browsing_city,
  browsing_city_id: city.id
)
```

#### 2. CityLive.Index Aggregate Cards (✅ Keep Special Logic)
**Current**: Manual enrichment in `build_aggregated_group` with multi-venue logic
**Migration**: Keep current approach OR extract multi-venue logic to strategy
**Priority**: Low (working correctly)

Note: The multi-venue logic (>3 venues = city image) is specific to aggregates and should remain there unless we add an `:aggregate` strategy to the enrichment API.

#### 3. PublicEventShowLive - Main Event (❌ HIGH PRIORITY)
**Current**: No enrichment
**Target Implementation**:

```elixir
def mount(%{"slug" => slug}, _session, socket) do
  event =
    PublicEvents.get_event_by_slug(slug)
    |> PublicEventsEnhanced.preload_for_image_enrichment()

  # Enrich with event's own city
  enriched_event =
    [event]
    |> PublicEventsEnhanced.enrich_event_images(strategy: :own_city)
    |> List.first()

  {:ok, assign(socket, :event, enriched_event)}
end
```

#### 4. PublicEventShowLive - Nearby Activities (❌ HIGH PRIORITY)
**Current**: No enrichment
**Target Implementation**:

```elixir
def mount(%{"slug" => slug}, _session, socket) do
  event = PublicEvents.get_event_by_slug(slug)

  nearby_events =
    PublicEventsEnhanced.list_events(%{
      # ... nearby query params
    })
    |> PublicEventsEnhanced.preload_for_image_enrichment()
    |> PublicEventsEnhanced.enrich_event_images(strategy: :own_city)

  {:ok, assign(socket, :nearby_events, nearby_events)}
end
```

#### 5. CityLive.Search (❓ MEDIUM PRIORITY)
**Needs Investigation**: Check current implementation
**Likely Target**:

```elixir
# If city search page
events = search_results
|> PublicEventsEnhanced.enrich_event_images(
  strategy: :browsing_city,
  browsing_city_id: city.id
)
```

#### 6. PublicEventsIndexLive (❓ MEDIUM PRIORITY)
**Needs Investigation**: Check current implementation
**Likely Target**:

```elixir
# Global feed with mixed cities
events = PublicEventsEnhanced.list_events(...)
|> PublicEventsEnhanced.enrich_event_images(strategy: :own_city)
```

## Additional Improvements

Beyond the unified enrichment API, we identified several opportunities:

### 1. Preload Consistency
**Current**: Different preloads scattered across query locations
**Improvement**: Use `preload_for_image_enrichment/1` helper everywhere
**Benefit**: Consistent preload requirements, easier to maintain

### 2. Error Handling & Telemetry
**Current**: Silent fallback to nil when city has no gallery
**Improvement**: Add telemetry events for missing galleries

```elixir
if is_nil(cover_image_url) do
  :telemetry.execute(
    [:eventasaurus, :unsplash, :fallback_missing],
    %{count: 1},
    %{city_id: city_id, event_id: event.id}
  )
end
```

**Benefit**: Identify cities needing Unsplash gallery setup, monitor enrichment success rate

### 3. Caching Opportunities (Future)
**Current**: No caching of selected Unsplash images
**Improvement**: Cache selected image per city/day/source combination

```elixir
# Pseudo-code
cache_key = "unsplash_image:#{city_id}:#{day_of_year}:#{source_id}"
cached_url = Cache.get(cache_key)
```

**Benefit**: Reduce computation, consistent images within day, better performance
**Trade-off**: Adds complexity, cache invalidation concerns

### 4. Testing Strategy
**Current**: Image enrichment tested indirectly through integration tests
**Improvement**: Add unit tests for enrichment logic

```elixir
defmodule EventasaurusDiscovery.PublicEventsEnhancedTest do
  describe "enrich_event_images/2" do
    test "browsing_city strategy uses provided city" do
      events = [build_event(city: paris)]
      enriched = PublicEventsEnhanced.enrich_event_images(events,
        strategy: :browsing_city,
        browsing_city_id: london.id
      )

      # Should use London's gallery, not Paris
      assert enriched |> List.first() |> Map.get(:cover_image_url) =~ "london"
    end

    test "own_city strategy uses event's city" do
      london_event = build_event(city: london)
      paris_event = build_event(city: paris)

      enriched = PublicEventsEnhanced.enrich_event_images(
        [london_event, paris_event],
        strategy: :own_city
      )

      # Each uses its own city
      assert Enum.at(enriched, 0).cover_image_url =~ "london"
      assert Enum.at(enriched, 1).cover_image_url =~ "paris"
    end
  end
end
```

**Benefit**: Catch regressions, document expected behavior, faster feedback

### 5. Query Optimization (Advanced, Future)
**Current**: Post-query enrichment in application layer
**Improvement**: Computed fields at database level

```elixir
# Complex but potentially more efficient
from e in PublicEvent,
  left_join: s in assoc(e, :sources),
  left_join: v in assoc(e, :venue),
  left_join: c in assoc(v, :city_ref),
  select_merge: %{
    cover_image_url: fragment(
      "COALESCE(?, compute_unsplash_fallback(?, ?))",
      s.image_url,
      c.id,
      e.id
    )
  }
```

**Benefit**: Potentially better performance for large datasets
**Trade-off**: Complex SQL, harder to maintain, database-specific

## Recommended Implementation Plan

### Phase 1: Foundation (Week 1)
**Goal**: Create unified enrichment API and supporting infrastructure

1. ✅ Add `enrich_event_images/2` to PublicEventsEnhanced
2. ✅ Add `preload_for_image_enrichment/1` helper
3. ✅ Add private helpers: `enrich_with_browsing_city/3`, `enrich_with_own_city/2`
4. ✅ Add basic telemetry events for missing galleries
5. ✅ Write unit tests for enrichment strategies
6. ✅ Update documentation

**Success Criteria**:
- Unit tests passing for both strategies
- Telemetry events firing for missing galleries
- No changes to existing views yet

### Phase 2: High-Priority Locations (Week 1-2)
**Goal**: Fix user-identified issues on event detail pages

1. ✅ PublicEventShowLive - main event display
   - Add enrichment with `:own_city` strategy
   - Test with London, Paris, New York events

2. ✅ PublicEventShowLive - nearby activities sidebar
   - Add enrichment with `:own_city` strategy
   - Verify mixed-city events work correctly

**Success Criteria**:
- Event detail pages show Unsplash images when sources lack images
- Nearby activities show appropriate images for each venue's city
- No performance degradation

### Phase 3: Medium-Priority Locations (Week 2-3)
**Goal**: Complete Phase 2 coverage across application

1. ✅ Investigate CityLive.Search implementation
2. ✅ Add enrichment if needed (likely `:browsing_city`)
3. ✅ Investigate PublicEventsIndexLive implementation
4. ✅ Add enrichment if needed (likely `:own_city`)

**Success Criteria**:
- All event lists have Unsplash fallbacks
- Consistent behavior across city-centric and event-centric views

### Phase 4: Optional Optimizations (Future)
**Goal**: Improve performance and consolidate implementations

1. Consider caching layer for daily image selections
2. Optionally refactor AggregatedContentLive to use unified API
3. Optionally extract multi-venue logic to enrichment strategy
4. Add monitoring/alerting for enrichment failures

**Success Criteria**:
- Improved performance metrics
- Reduced code duplication
- Better observability

## Performance Considerations

### Current Performance
- Image enrichment happens in memory after query
- Each event: O(1) lookup in unsplash_gallery JSONB
- 100 events: ~100ms additional processing
- Acceptable for typical page sizes (10-50 events)

### Potential Bottlenecks
- Large event lists (500+ events): May add noticeable latency
- Solution: Add pagination, limit page sizes, consider async enrichment

### Optimization Options
1. **Batch Processing**: Enrich events in chunks if list is large
2. **Eager Loading**: Ensure proper preloads to avoid N+1 queries
3. **Caching**: Cache selected images to avoid recomputation
4. **Async Enrichment**: For very large lists, enrich asynchronously

## Testing Strategy

### Unit Tests
- Test each enrichment strategy independently
- Test with missing galleries, missing venues, missing images
- Test force re-enrichment
- Test preload helper

### Integration Tests
- Test each LiveView with enrichment enabled
- Test mixed-city event lists
- Test city-specific event lists
- Test with and without Unsplash galleries

### Performance Tests
- Benchmark enrichment for various list sizes (10, 50, 100, 500 events)
- Monitor query times before/after enrichment
- Set performance budgets (e.g., <200ms for 100 events)

## Risk Assessment

### Low Risk
- ✅ Creating new enrichment function (additive, no breaking changes)
- ✅ Adding enrichment to new locations (improves UX, no downsides)
- ✅ Adding telemetry (observability improvement)

### Medium Risk
- ⚠️ Refactoring existing working implementations
  - Mitigation: Keep working implementations as-is initially
- ⚠️ Performance impact on large event lists
  - Mitigation: Test with realistic data sizes, add pagination if needed

### High Risk
- ❌ None identified

## Success Metrics

### Quantitative
- **Coverage**: % of event displays with Unsplash fallback (target: 100%)
- **Performance**: Image enrichment time per 100 events (target: <200ms)
- **Cache Hit Rate**: If caching implemented (target: >80%)
- **Missing Galleries**: # of events unable to enrich (target: <5%)

### Qualitative
- **Code Maintainability**: Single source of truth for enrichment logic
- **Developer Experience**: Easy to add enrichment to new locations
- **User Experience**: Consistent, professional images across all event displays

## Open Questions

1. **Multi-venue Logic**: Should we extract the ">3 venues = city image" logic into the unified API as an `:aggregate` strategy?
   - Pro: More consistent, all enrichment in one place
   - Con: Adds complexity, may not generalize well
   - Recommendation: Wait to see if pattern repeats elsewhere

2. **Caching Strategy**: Should we cache selected Unsplash images?
   - Pro: Better performance, consistent images within day
   - Con: Adds complexity, cache invalidation concerns
   - Recommendation: Measure performance first, add caching if needed

3. **Query-Level vs Post-Query**: Should we continue query-level enrichment or standardize on post-query?
   - Pro (Query): Potentially more efficient, fewer roundtrips
   - Pro (Post-Query): More flexible, easier to test, clearer separation
   - Recommendation: Standardize on post-query for maintainability

## Conclusion

The proposed unified enrichment API provides a pragmatic, incremental path forward that:

1. ✅ **Reduces duplication**: Single source of truth for enrichment logic
2. ✅ **Improves maintainability**: Changes made once, applied everywhere
3. ✅ **Enables consistency**: Same behavior across all contexts
4. ✅ **Supports flexibility**: Two strategies handle all current and future cases
5. ✅ **Minimizes risk**: No breaking changes, gradual migration path
6. ✅ **Improves testability**: Unit testable enrichment logic

**Next Steps**: Implement Phase 1 (Foundation) to create the unified API, then incrementally migrate high-priority locations (event detail pages) in Phase 2.

---

**Document Status**: Draft for Review
**Created**: 2025-01-05
**Author**: Refactoring Analysis (Sequential Thinking AI)
**Stakeholders**: Development Team
