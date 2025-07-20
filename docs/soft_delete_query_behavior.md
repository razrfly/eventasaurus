# Soft Delete Query Behavior Documentation

## Overview

As of the implementation of soft delete functionality, all event-related queries in the `EventasaurusApp.Events` context now exclude soft-deleted events by default. This ensures that soft-deleted events are hidden from normal application operations while still being preserved in the database.

## Default Behavior

All query functions that return events or event-related data now automatically filter out soft-deleted records (where `deleted_at` is not null) unless explicitly told otherwise.

## Including Soft-Deleted Records

To include soft-deleted records in query results, pass the `include_deleted: true` option:

```elixir
# Exclude soft-deleted (default)
Events.list_events()

# Include soft-deleted
Events.list_events(include_deleted: true)
```

## Updated Functions

### Event Query Functions

The following functions now support soft delete filtering:

1. **`list_events(opts \\ [])`**
   - Returns all events, excluding soft-deleted by default
   - Options: `include_deleted: true` to include soft-deleted events

2. **`list_active_events(opts \\ [])`**
   - Returns active (non-canceled) events with future end dates
   - Excludes soft-deleted events by default

3. **`list_polling_events(opts \\ [])`**
   - Returns events in polling phase
   - Excludes soft-deleted events by default

4. **`list_ticketed_events(opts \\ [])`**
   - Returns confirmed events that can sell tickets
   - Excludes soft-deleted events by default

5. **`list_ended_events(opts \\ [])`**
   - Returns events that have ended
   - Excludes soft-deleted events by default

6. **`list_threshold_events(opts \\ [])`**
   - Returns events in threshold status
   - Excludes soft-deleted events by default

7. **`list_threshold_met_events(opts \\ [])`**
   - Returns threshold events that have met their requirements
   - Excludes soft-deleted events by default

8. **`list_threshold_pending_events(opts \\ [])`**
   - Returns threshold events that haven't met requirements
   - Excludes soft-deleted events by default

9. **`list_events_by_threshold_type(threshold_type, opts \\ [])`**
   - Returns events filtered by threshold type
   - Excludes soft-deleted events by default

10. **`list_events_by_min_revenue(min_revenue_cents, opts \\ [])`**
    - Returns events with minimum revenue threshold
    - Excludes soft-deleted events by default

11. **`list_events_by_min_attendee_count(min_attendee_count, opts \\ [])`**
    - Returns events with minimum attendee threshold
    - Excludes soft-deleted events by default

12. **`list_events_by_user(user, opts \\ [])`**
    - Returns events where user is an organizer
    - Excludes soft-deleted events by default

### Single Event Retrieval

1. **`get_event!(id)`**
   - Raises `Ecto.NoResultsError` if event is soft-deleted
   - No option to include soft-deleted (use `get_event/2` instead)

2. **`get_event(id, opts \\ [])`**
   - Returns `nil` for soft-deleted events by default
   - Options: `include_deleted: true` to retrieve soft-deleted events

3. **`get_event_by_slug!(slug)`**
   - Raises `Ecto.NoResultsError` if event is soft-deleted
   - No option to include soft-deleted

4. **`get_event_by_slug(slug, opts \\ [])`**
   - Returns `nil` for soft-deleted events by default
   - Options: `include_deleted: true` to retrieve soft-deleted events

5. **`get_event_by_title(title, opts \\ [])`**
   - Returns `nil` for soft-deleted events by default
   - Options: `include_deleted: true` to retrieve soft-deleted events

### Participant-Related Queries

1. **`list_events_with_participation(user, opts \\ [])`**
   - Returns events where user is a participant
   - Excludes events that have been soft-deleted

2. **`list_organizer_events_with_participants(user, opts \\ [])`**
   - Returns events organized by user that have participants
   - Excludes soft-deleted events from results

3. **`get_historical_participants(organizer, opts \\ [])`**
   - Returns participants from organizer's past events
   - Excludes participants from soft-deleted events

### Poll-Related Queries

1. **`get_event_poll(event, poll_type, opts \\ [])`**
   - Returns poll for an event
   - Returns `nil` if the event is soft-deleted (unless `include_deleted: true`)

### Internal Helper Functions

The following internal functions have been updated to respect soft delete filtering:

1. **`get_organizer_event_ids_basic/1`**
   - Excludes soft-deleted events when getting organizer's event IDs

2. **`get_participants_for_events/4`**
   - Excludes participants from soft-deleted events

## Implementation Details

### Filter Helper Function

A private helper function `apply_soft_delete_filter/2` has been added to consistently apply soft delete filtering:

```elixir
defp apply_soft_delete_filter(query, opts) do
  include_deleted = Keyword.get(opts, :include_deleted, false)
  
  if include_deleted do
    query
  else
    from e in query,
      where: is_nil(e.deleted_at)
  end
end
```

### Query Composition

Soft delete filtering is applied after building the base query but before execution:

```elixir
def list_events(opts \\ []) do
  query = from e in Event
  
  query = apply_soft_delete_filter(query, opts)
  Repo.all(query)
end
```

## Migration Guide

### For Existing Code

Most existing code will continue to work as expected, with soft-deleted events automatically excluded. However, if your application needs to:

1. **Display soft-deleted events** (e.g., in an admin interface):
   ```elixir
   # Add the include_deleted option
   Events.list_events(include_deleted: true)
   ```

2. **Check if an event exists regardless of deletion status**:
   ```elixir
   # Use get_event with include_deleted option
   case Events.get_event(event_id, include_deleted: true) do
     nil -> # Event doesn't exist at all
     %Event{deleted_at: nil} -> # Event exists and is active
     %Event{deleted_at: _} -> # Event exists but is soft-deleted
   end
   ```

### Testing Considerations

When writing tests that involve soft-deleted events:

1. Explicitly test both cases (with and without soft-deleted records)
2. Use the `include_deleted: true` option when verifying soft deletion
3. Remember that `get_event!/1` will raise for soft-deleted events

### Performance Considerations

1. The soft delete filter adds a simple `WHERE deleted_at IS NULL` clause
2. Ensure `deleted_at` column is indexed for optimal performance
3. Consider partial indexes for frequently queried combinations

## Related Modules

- `EventasaurusApp.Events.SoftDelete` - Handles soft deletion operations
- `EventasaurusApp.Events.HardDelete` - Handles hard deletion operations
- `EventasaurusApp.Events.Delete` - Unified deletion interface

## Future Considerations

1. **Cascade Filtering**: Currently, when an event is soft-deleted, its related records (polls, tickets, etc.) are also soft-deleted but queries on these related entities may need their own filtering.

2. **Archive System**: A scheduled job to permanently delete old soft-deleted records may be implemented in the future.

3. **Restoration**: The `restore_event/2` function in `SoftDelete` module can restore soft-deleted events and their related records.