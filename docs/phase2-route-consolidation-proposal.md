# Phase 2: Route Consolidation Proposal

## Problem Statement

We currently have TWO overlapping systems for displaying aggregated event content:

### System 1: ContainerDetailLive (Older)
- **Routes**: `/c/:city_slug/festivals/:container_slug`, `/c/:city_slug/conferences/:container_slug`, etc.
- **Purpose**: Displays events within a "container" (festival, conference, tour, series, exhibition, tournament)
- **Data Model**: Uses `PublicEventContainer` schema - events are explicitly grouped into containers
- **Features**: Date grouping, grid/list view toggle, language switcher, breadcrumbs
- **~500 lines** of code

### System 2: AggregatedContentLive (Newer)
- **Routes**:
  - City-scoped: `/c/:city_slug/:content_type/:identifier`
  - Multi-city: `/social/:identifier`, `/food/:identifier`, `/movies/:identifier`, etc.
- **Purpose**: Aggregates events by source (e.g., all PubQuiz.pl events, all Week.pl events)
- **Data Model**: Queries by `source_slug` - events are grouped dynamically by their source
- **Features**: City/multi-city scope toggle, themed hero cards, venue grouping, optimized queries (Phase 1)
- **~740 lines** of code

## Key Differences

| Aspect | ContainerDetailLive | AggregatedContentLive |
|--------|--------------------|-----------------------|
| Grouping | Explicit containers (festivals, tours) | Dynamic by source slug |
| Scope | City-only | City + Multi-city toggle |
| Performance | Fetches all events, groups in Elixir | Database-level aggregation (Phase 1) |
| Hero | Basic white header | Themed hero cards with content-type styling |
| View modes | Grid/List toggle | Grid only (by city groups) |
| Routes | Type-specific (`/festivals/`, `/conferences/`) | Generic (`/:content_type/:identifier`) |

## Recommendation: Keep Both (They Serve Different Purposes)

After analysis, these systems are NOT duplicates - they serve fundamentally different use cases:

### ContainerDetailLive is for:
- **Named event series**: "Unsound Festival 2025", "Restaurant Week Krakow Fall 2024"
- **Time-bounded collections**: Events with explicit start/end dates
- **Curated groupings**: Hand-picked events belonging to a specific festival/conference
- **Example**: `/c/krakow/festivals/unsound-festival-2025-abc123`

### AggregatedContentLive is for:
- **Source aggregation**: All events from a particular scraper source
- **Brand pages**: "All PubQuiz.pl quizzes", "All Week.pl listings"
- **Multi-city browsing**: View events across cities from the same source
- **Example**: `/social/pubquiz-pl` or `/c/krakow/social/pubquiz-pl`

## The Route Collision Issue

The REAL problem is that both systems define overlapping routes:

```elixir
# ContainerDetailLive routes (explicit type paths)
live "/:city_slug/festivals/:container_slug", CityLive.ContainerDetailLive, :show
live "/:city_slug/conferences/:container_slug", CityLive.ContainerDetailLive, :show
# ... more types

# AggregatedContentLive route (generic catch-all)
live "/:city_slug/:content_type/:identifier", AggregatedContentLive, :show
```

When you visit `/c/krakow/festivals/week_pl`:
- Router tries `ContainerDetailLive` first (matches `/festivals/`)
- ContainerDetailLive looks for a container with slug `week_pl`
- If not found, shows error - doesn't fall through to AggregatedContentLive

## Proposed Solution: Unified Routing with Smart Dispatch

### Option A: Merge into AggregatedContentLive with Container Support

Add container detection to AggregatedContentLive:

1. When mounting, check if `identifier` matches a container slug
2. If yes → load container data, render container-style layout
3. If no → continue with source aggregation logic

**Pros**: Single LiveView, unified behavior
**Cons**: Makes AggregatedContentLive more complex (~1000+ lines)

### Option B: Keep Separate but Fix Route Priority (RECOMMENDED)

1. **Remove overlapping ContainerDetailLive routes** from router
2. **Use AggregatedContentLive's generic route** as the entry point
3. **Add redirect/dispatch logic** that detects containers and redirects to ContainerDetailLive

```elixir
# In router.ex - REMOVE these:
# live "/:city_slug/festivals/:container_slug", CityLive.ContainerDetailLive, :show
# live "/:city_slug/conferences/:container_slug", CityLive.ContainerDetailLive, :show
# etc.

# KEEP only AggregatedContentLive:
live "/:city_slug/:content_type/:identifier", AggregatedContentLive, :show

# In AggregatedContentLive mount - add container check:
# If identifier matches a container slug → redirect to container route
```

**Pros**:
- Clean separation of concerns
- Each LiveView stays focused
- No duplicate routes
- Easy to maintain

**Cons**:
- Requires dedicated container routes (e.g., `/c/:city_slug/container/:slug`)

### Option C: Remove ContainerDetailLive Entirely

Since AggregatedContentLive is newer and more feature-rich:
1. Move container rendering into AggregatedContentLive
2. Delete ContainerDetailLive
3. Update all container-related links

**Pros**: Single system
**Cons**: Loses some container-specific features (date grouping, view toggle)

## Implementation Plan (Option B - Recommended)

### Step 1: Add New Dedicated Container Route
```elixir
# New route just for containers
live "/c/:city_slug/container/:container_slug", CityLive.ContainerDetailLive, :show
```

### Step 2: Remove Overlapping Routes
Remove the type-specific container routes:
```elixir
# DELETE these lines from router.ex:
live "/:city_slug/festivals/:container_slug", ...
live "/:city_slug/conferences/:container_slug", ...
live "/:city_slug/tours/:container_slug", ...
live "/:city_slug/series/:container_slug", ...
live "/:city_slug/exhibitions/:container_slug", ...
live "/:city_slug/tournaments/:container_slug", ...
```

### Step 3: Add Container Detection to AggregatedContentLive
In `handle_params`, before loading events:
```elixir
# Check if identifier is actually a container
case PublicEventContainers.get_container_by_slug(identifier) do
  %PublicEventContainer{} = container ->
    # Redirect to dedicated container route
    {:noreply, push_navigate(socket, to: ~p"/c/#{city.slug}/container/#{container.slug}")}
  nil ->
    # Continue with source aggregation
    socket = load_events(socket, scope)
    {:noreply, socket}
end
```

### Step 4: Update Links Throughout Codebase
Update any hardcoded links to use the new container route format.

### Step 5: Apply Performance Optimizations to ContainerDetailLive
Port the Phase 1 database-level aggregation optimizations to ContainerDetailLive.

## Files to Modify

1. `lib/eventasaurus_web/router.ex` - Route changes
2. `lib/eventasaurus_web/live/aggregated_content_live.ex` - Container detection
3. `lib/eventasaurus_web/live/city_live/container_detail_live.ex` - Route update, performance
4. Various templates/components that link to containers

## Questions for Review

1. **Route format preference**: Should container routes be `/c/:city/container/:slug` or `/c/:city/event-series/:slug`?
2. **Redirect behavior**: Should we 301 redirect old container URLs or handle transparently?
3. **Container types in URL**: Keep type in URL (`/festivals/unsound`) or use generic (`/container/unsound`)?

## Estimated Effort

- Route consolidation: 1-2 hours
- Container detection logic: 1 hour
- Link updates: 1-2 hours
- Testing: 1-2 hours
- **Total: 4-7 hours**
