# Container Date Range Display Issue

## Problem

Container detail pages show incorrect date ranges that don't reflect the actual span of events within the container.

**Example**: Unsound Kraków 2025 displays "Oct 06, 2025 - Oct 06, 2025" when the actual events run from October 7-12, 2025.

**Location**: `http://localhost:4000/c/krakow/festivals/unsound-krakow-2025-281`

**File**: `lib/eventasaurus_web/live/city_live/container_detail_live.ex:57`

## Root Cause Analysis

### Current Behavior

1. Containers are created during Resident Advisor sync when umbrella events (venue ID `267425`) are detected
2. At detection time, individual sub-events haven't been fetched yet, so `sub_events` list is empty
3. Date calculation logic falls back to umbrella event's single date field:
   ```elixir
   # container_grouper.ex:169
   defp calculate_end_date([], festival), do: festival.start_date  # ❌ Same as start!
   ```
4. Both `start_date` and `end_date` are set to the same value
5. Dates are never updated after individual events are associated with the container

### Database State

```sql
-- Current container data
SELECT id, title, start_date, end_date
FROM public_event_containers
WHERE id = 2;

id | title               | start_date          | end_date
2  | Unsound Kraków 2025 | 2025-10-06 00:00:00 | 2025-10-06 23:59:59

-- Actual event date range
SELECT MIN(starts_at), MAX(starts_at)
FROM public_events e
INNER JOIN public_event_container_memberships m ON m.event_id = e.id
WHERE m.container_id = 2;

min                 | max
2025-10-07 17:00:00 | 2025-10-12 17:00:00
```

## Solution Approaches

### Hierarchical Data Sourcing Strategy

The solution should prioritize authoritative data from Resident Advisor, with fallback to calculated values.

**Data Source Priority**:
1. **Primary**: Use umbrella event's `endTime` from RA GraphQL (if available and valid)
2. **Validation**: Ensure umbrella `endTime` isn't before the latest actual event
3. **Fallback**: Calculate from actual member events (MIN/MAX dates)

### Option 1: Extract Umbrella Event endTime (Recommended)

Modify ContainerGrouper to extract and use umbrella event's `endTime` field from RA GraphQL.

**Why This Approach**:
- Uses authoritative data from source system
- Respects festival organizer's intended date range
- Falls back gracefully when data missing or invalid

**Implementation**:

```elixir
# In container_grouper.ex:78-88
defp extract_festival_metadata(umbrella_event) do
  event = umbrella_event["event"]

  %{
    promoter_id: get_in(event, ["promoters", Access.at(0), "id"]),
    promoter_name: get_in(event, ["promoters", Access.at(0), "name"]),
    title_prefix: extract_title_prefix(event["title"]),
    start_date: parse_date(event["startTime"] || event["date"]),
    end_date: parse_date(event["endTime"]),  # ✅ NEW: Extract endTime
    umbrella_event_id: event["id"]
  }
end
```

```elixir
# In container_grouper.ex:169-179
# Update date calculation to use umbrella endTime first, then calculate
defp calculate_end_date([], festival) do
  # Use umbrella's endTime if available, otherwise use start_date
  festival.end_date || festival.start_date
end

defp calculate_end_date(sub_events, festival) do
  calculated_end = sub_events
    |> Enum.map(fn raw_event -> parse_date(raw_event["event"]["date"]) end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> festival.start_date
      dates -> Enum.max(dates, Date)
    end

  # Validation: Ensure umbrella endTime isn't before calculated end
  # If umbrella endTime is valid and >= calculated end, use it
  # Otherwise use calculated end (more accurate)
  case {festival.end_date, calculated_end} do
    {nil, calculated} -> calculated
    {umbrella_end, calculated} when umbrella_end >= calculated -> umbrella_end
    {_umbrella_end, calculated} -> calculated  # Umbrella data conflicts, use calculated
  end
end
```

**Validation Logic**:
- If umbrella `endTime` exists and is >= latest event date → use umbrella `endTime`
- If umbrella `endTime` conflicts (before latest event) → use calculated date
- If umbrella `endTime` is nil → use calculated date

### Option 2: Backend Data Refresh (Maintenance)

Add function to recalculate dates for existing containers with bad data.

**Implementation**:

```elixir
# Add to public_event_containers.ex
@doc """
Refresh container dates from associated events.
Uses hierarchical data sourcing: umbrella event dates first, then calculated.
"""
def refresh_container_dates(%PublicEventContainer{} = container) do
  query =
    from e in PublicEvent,
      join: m in PublicEventContainerMembership,
      on: m.event_id == e.id,
      where: m.container_id == ^container.id,
      select: %{
        min_date: min(e.starts_at),
        max_date: max(e.starts_at)
      }

  case Repo.one(query) do
    %{min_date: nil, max_date: nil} ->
      # No events, keep existing dates (from umbrella event)
      {:ok, container}

    %{min_date: min_date, max_date: max_date} ->
      # If container has umbrella end_date that's valid, keep it
      # Otherwise use calculated max_date
      end_date =
        if container.end_date && DateTime.compare(container.end_date, max_date) >= :eq do
          container.end_date
        else
          max_date
        end

      update_container(container, %{
        start_date: min_date,
        end_date: end_date
      })
  end
end
```

**One-time migration**:
```elixir
# Run in IEx to fix existing containers
alias Eventasaurus.Discovery.PublicEventContainers
PublicEventContainers.list_containers()
|> Enum.each(&PublicEventContainers.refresh_container_dates/1)
```

### Option 3: Frontend Fallback (Resilience)

Add smart fallback in UI to handle edge cases.

**Implementation**:
```elixir
# In container_detail_live.ex
defp get_display_date_range(container, events) do
  # Check if dates look invalid (same start and end)
  dates_look_invalid? =
    container.start_date && container.end_date &&
    DateTime.diff(container.end_date, container.start_date, :day) == 0

  if dates_look_invalid? && length(events) > 0 do
    # Calculate from events as fallback
    dates = Enum.map(events, & &1.starts_at)
    {Enum.min(dates, DateTime), Enum.max(dates, DateTime)}
  else
    # Use database dates (from RA or calculated)
    {container.start_date, container.end_date}
  end
end
```

## Recommendations

1. **Primary**: Implement Option 1 to extract umbrella event `endTime` from RA GraphQL
2. **Maintenance**: Implement Option 2 to refresh existing containers
3. **Resilience**: Add Option 3's frontend fallback for edge cases

## Additional Considerations

### Edge Cases to Handle

1. **Empty containers**: No events yet associated
   - Keep umbrella event date or set to nil

2. **Single-day events**: All events on same day
   - Valid to have same start_date and end_date

3. **Timezone handling**: Events have DateTime with timezone
   - Need to preserve timezone information

4. **Date updates**: Events added/removed over time
   - Should trigger date recalculation

### Future Enhancements

1. **Automatic refresh**: Trigger date recalculation when:
   - New event associated with container
   - Event removed from container
   - Event date changes

2. **Validation**: Add database constraint or validation:
   ```elixir
   validate_change(:end_date, fn :end_date, end_date ->
     if container.start_date && DateTime.compare(end_date, container.start_date) == :lt do
       [{:end_date, "must be after start date"}]
     else
       []
     end
   end)
   ```

3. **Monitoring**: Track containers with suspicious date ranges
   ```sql
   -- Find containers that might need date refresh
   SELECT id, title, start_date, end_date
   FROM public_event_containers
   WHERE start_date = DATE_TRUNC('day', end_date);
   ```

## Files Involved

- `lib/eventasaurus_discovery/sources/resident_advisor/container_grouper.ex` - Initial date calculation
- `lib/eventasaurus_discovery/public_events/public_event_containers.ex` - Container CRUD operations
- `lib/eventasaurus_web/live/city_live/container_detail_live.ex` - Date display
- `lib/eventasaurus_discovery/public_events/public_event_containers.ex:428` - Date range matching

## Testing

### Manual Testing Steps

1. Navigate to container detail page
2. Verify date range shows full span of events
3. Check that events are grouped correctly by date
4. Verify date range updates when events added/removed

### Automated Tests

```elixir
describe "refresh_container_dates/1" do
  test "updates dates from associated events" do
    container = container_fixture(%{
      start_date: ~U[2025-10-06 00:00:00Z],
      end_date: ~U[2025-10-06 23:59:59Z]
    })

    event1 = event_fixture(%{starts_at: ~U[2025-10-07 17:00:00Z]})
    event2 = event_fixture(%{starts_at: ~U[2025-10-12 17:00:00Z]})

    associate_event_to_container(event1, container)
    associate_event_to_container(event2, container)

    {:ok, updated} = PublicEventContainers.refresh_container_dates(container)

    assert DateTime.to_date(updated.start_date) == ~D[2025-10-07]
    assert DateTime.to_date(updated.end_date) == ~D[2025-10-12]
  end
end
```

## Related Issues

- #TBD - Container creation from umbrella events
- #TBD - Event association timing and order
- #TBD - Umbrella event storage vs. metadata-only approach
