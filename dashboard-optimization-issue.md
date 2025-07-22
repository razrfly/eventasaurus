# Dashboard Tab Performance Optimization

## Problem Description

The dashboard experiences significant delays when switching between "Upcoming", "Past", and "Archived" tabs. Each tab change triggers a new database query and page reload, resulting in poor user experience with noticeable loading times in production.

## Current Implementation Analysis

### 1. **Tab Switching Flow**
- Each tab click triggers `handle_event("filter_time", ...)` in `dashboard_live.ex`
- This calls `load_unified_events/1` which executes a fresh database query
- The page is patched with new URL parameters via `push_patch`
- No caching or preloading of tab data exists

### 2. **Query Structure**
The `list_unified_events_for_user/2` function uses a UNION query combining:
- **Organizer events**: Events where user is an organizer (via EventUser join)
- **Participant events**: Events where user is a participant (via EventParticipant join)

Each query includes:
- Multiple JOINs (EventUser/EventParticipant)
- Soft delete filtering
- Time-based filtering (upcoming/past)
- Ordering and limiting
- No database indexes optimization visible

### 3. **Performance Bottlenecks**
1. **Repeated Queries**: Each tab switch executes the full UNION query again
2. **Count Calculations**: Filter counts are recalculated on every load via `count_events_by_filter/3`
3. **No Caching**: Results are not cached between tab switches
4. **Synchronous Loading**: All operations are blocking, no async data fetching
5. **Archived Events**: Uses a completely different query path (`list_deleted_events_by_user/1`)

## Proposed Solutions

### Solution 1: Preload All Tab Data (Recommended)
**Pros**: Best UX, instant tab switching
**Cons**: Higher initial load time, more memory usage

```elixir
def mount(_params, _session, socket) do
  # ... existing code ...
  
  if user do
    # Start async tasks to load all tabs
    upcoming_task = Task.async(fn -> 
      Events.list_unified_events_for_user(user, time_filter: :upcoming, limit: 50)
    end)
    
    past_task = Task.async(fn -> 
      Events.list_unified_events_for_user(user, time_filter: :past, limit: 50)
    end)
    
    archived_task = Task.async(fn -> 
      Events.list_deleted_events_by_user(user)
    end)
    
    {:ok,
     socket
     |> assign(:loading_tasks, %{
       upcoming: upcoming_task,
       past: past_task,
       archived: archived_task
     })
     |> assign(:events_cache, %{})
     |> assign(:time_filter, :upcoming)
     # ... rest of assigns
    }
  end
end

def handle_info({ref, result}, socket) when is_reference(ref) do
  # Handle async task completion
  # Update events_cache with results
end

def handle_event("filter_time", %{"filter" => filter}, socket) do
  # Use cached data instead of reloading
  cached_events = socket.assigns.events_cache[String.to_atom(filter)]
  
  {:noreply,
   socket
   |> assign(:time_filter, String.to_atom(filter))
   |> assign(:events, cached_events || [])
   |> push_patch(to: build_dashboard_path(...))}
end
```

### Solution 2: Optimize Database Queries
**Pros**: Better performance without architectural changes
**Cons**: Still has some delay on tab switches

1. **Add Database Indexes**:
```sql
-- Composite indexes for the UNION query
CREATE INDEX idx_event_users_user_event ON event_users(user_id, event_id);
CREATE INDEX idx_event_participants_user_event_status ON event_participants(user_id, event_id, status);
CREATE INDEX idx_events_start_at_deleted ON events(start_at, deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX idx_events_deleted_at ON events(deleted_at) WHERE deleted_at IS NOT NULL;
```

2. **Optimize the UNION Query**:
- Use a single CTE to fetch all data once
- Apply filters in memory for tab switching

### Solution 3: Client-Side Filtering (Alternative)
**Pros**: Zero latency tab switching
**Cons**: Requires loading all data upfront, may not scale well

Load all events once and filter on the client using Alpine.js or hooks:
```heex
<div x-data="{ activeTab: 'upcoming', events: <%= Jason.encode!(@all_events) %> }">
  <!-- Tab buttons update x-data activeTab -->
  <!-- Events are filtered based on activeTab value -->
</div>
```

### Solution 4: Incremental Improvements
1. **Add Loading States**: Show skeleton screens while loading
2. **Implement Query Result Caching**: Cache results for 5-10 minutes
3. **Use LiveView Streams**: For more efficient DOM updates
4. **Paginate Results**: Load fewer events initially, lazy load more

## Implementation Recommendations

1. **Start with Solution 1 (Preloading)** as it provides the best user experience
2. **Add database indexes** regardless of chosen solution
3. **Monitor performance** with telemetry to measure improvements
4. **Consider pagination** if users have hundreds of events

## Metrics to Track
- Initial page load time
- Tab switch latency
- Database query execution time
- Memory usage per session
- User engagement with different tabs

## Additional Considerations
- The count badges could be loaded asynchronously after initial render
- Consider implementing a "stale-while-revalidate" pattern
- Add proper error handling for failed async loads
- Implement connection-aware loading (don't preload on slow connections)

---

## UPDATE: Further Performance Analysis

After implementing the initial optimization (async preloading), the performance improvement was minimal. A deeper analysis reveals several fundamental issues:

### Root Cause Analysis

1. **UNION Query Overhead**
   - The `list_unified_events_for_user/2` uses a UNION ALL to combine organizer and participant events
   - This creates a complex execution plan that's inherently slow
   - Each subquery must be executed separately before the UNION
   - The database can't optimize across the UNION boundary effectively

2. **Multiple Database Round Trips**
   - Main query fetches events (with UNION)
   - `get_venues_for_events/1` runs a separate query for venues
   - `get_participants_for_events/1` runs another query for participants
   - This results in 3+ database round trips per tab load

3. **N+1 Query Pattern**
   - Although batch loading is attempted, the venue and participant queries still run separately
   - Each event's computed fields require additional processing

4. **Inefficient Filtering**
   - Time filtering happens AFTER the UNION in a subquery
   - This means both queries run fully before filtering
   - Database can't use indexes effectively on the UNION result

5. **Separate Count Queries**
   - Filter counts run the same expensive queries again
   - No reuse of already fetched data

### Recommended Optimizations

#### 1. **Single Query Approach (High Priority)**
Replace the UNION with a single query using conditional logic:

```elixir
def list_all_user_events(%User{} = user) do
  from e in Event,
    left_join: eu in EventUser, on: e.id == eu.event_id and eu.user_id == ^user.id,
    left_join: ep in EventParticipant, on: e.id == ep.event_id and ep.user_id == ^user.id,
    left_join: v in assoc(e, :venue),
    left_join: all_participants in assoc(e, :participants),
    where: not is_nil(eu.id) or not is_nil(ep.id),
    where: is_nil(e.deleted_at),
    select: %{
      event: e,
      venue: v,
      is_organizer: not is_nil(eu.id),
      participant_status: ep.status,
      # Include aggregated participant data
    },
    preload: [participants: all_participants]
end
```

Benefits:
- Single query instead of UNION + 2 additional queries
- All data loaded in one round trip
- Better index utilization
- Easier to filter and paginate

#### 2. **Materialized View for Dashboard**
Create a materialized view that pre-computes user event relationships:

```sql
CREATE MATERIALIZED VIEW user_event_dashboard AS
SELECT 
  e.*,
  v.name as venue_name,
  v.address as venue_address,
  CASE WHEN eu.user_id IS NOT NULL THEN 'organizer' ELSE 'participant' END as user_role,
  COALESCE(ep.status, 'confirmed') as user_status,
  COUNT(DISTINCT ep2.user_id) as participant_count
FROM events e
LEFT JOIN event_users eu ON e.id = eu.event_id
LEFT JOIN event_participants ep ON e.id = ep.event_id
LEFT JOIN venues v ON e.venue_id = v.id
LEFT JOIN event_participants ep2 ON e.id = ep2.event_id
WHERE e.deleted_at IS NULL
GROUP BY e.id, eu.user_id, ep.user_id, ep.status, v.id;

CREATE INDEX idx_user_event_dashboard_user_start ON user_event_dashboard(user_id, start_at);
```

Refresh strategy:
- Refresh on event changes via triggers
- Or refresh periodically (every few minutes)

#### 3. **Denormalization Strategy**
Add computed fields directly to the events table:

```elixir
alter table(:events) do
  add :participant_count, :integer, default: 0
  add :organizer_count, :integer, default: 0
end
```

Update counts via database triggers or application logic when participants change.

#### 4. **Smart Caching with ETS**
Implement an ETS-based cache at the context level:

```elixir
defmodule EventasaurusApp.Events.DashboardCache do
  use GenServer
  
  def get_user_events(user_id) do
    case :ets.lookup(:dashboard_cache, user_id) do
      [{^user_id, events, inserted_at}] ->
        if DateTime.diff(DateTime.utc_now(), inserted_at, :second) < 300 do
          {:ok, events}
        else
          {:miss, :stale}
        end
      [] ->
        {:miss, :not_found}
    end
  end
  
  def put_user_events(user_id, events) do
    :ets.insert(:dashboard_cache, {user_id, events, DateTime.utc_now()})
  end
end
```

#### 5. **Optimized Count Strategy**
Calculate counts from the already-loaded events instead of separate queries:

```elixir
defp calculate_counts_from_events(events) do
  Enum.reduce(events, %{upcoming: 0, past: 0, created: 0, participating: 0}, fn event, acc ->
    acc
    |> update_time_counts(event)
    |> update_role_counts(event)
  end)
end
```

#### 6. **PostgreSQL-Specific Optimizations**

```sql
-- Partial indexes for common queries
CREATE INDEX idx_events_upcoming ON events(start_at) 
WHERE deleted_at IS NULL AND (start_at IS NULL OR start_at > NOW());

CREATE INDEX idx_events_past ON events(start_at DESC) 
WHERE deleted_at IS NULL AND start_at <= NOW();

-- Composite indexes for the joins
CREATE INDEX idx_event_users_composite ON event_users(user_id, event_id) INCLUDE (role);
CREATE INDEX idx_event_participants_composite ON event_participants(user_id, event_id) INCLUDE (status);

-- Enable parallel queries
SET max_parallel_workers_per_gather = 4;
```

### Implementation Priority

1. **Immediate**: Replace UNION with single query approach
2. **Short-term**: Implement ETS caching
3. **Medium-term**: Add materialized view for complex dashboards
4. **Long-term**: Consider GraphQL with DataLoader for optimal query batching

### Expected Performance Gains

- **Single Query**: 60-70% reduction in query time
- **ETS Caching**: Near-instant tab switches for cached data
- **Materialized View**: 80-90% faster initial loads
- **Combined**: Sub-100ms dashboard loads

### Database Query Analysis Tools

To measure improvements:
```elixir
# Add to config/dev.exs
config :eventasaurus, EventasaurusApp.Repo,
  log: :debug,
  show_sensitive_data_on_connection_error: true

# Use EXPLAIN ANALYZE
Repo.explain(:all, query, analyze: true, verbose: true)
```