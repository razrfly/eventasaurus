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