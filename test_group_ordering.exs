# Test script to verify group event ordering

# Assuming we're in a mix context
alias EventasaurusApp.{Repo, Events, Groups, Accounts}
alias EventasaurusApp.Accounts.User
import Ecto.Query

# Get or create a test user
user = case Repo.one(from u in User, limit: 1) do
  nil -> 
    # Insert a basic user for testing
    %User{}
    |> User.changeset(%{
      name: "Test User",
      email: "test@example.com",
      supabase_id: "test_#{System.unique_integer()}"
    })
    |> Repo.insert!()
  existing_user ->
    existing_user
end

# Create a test group
{:ok, group} = Groups.create_group(%{
  name: "Test Group #{System.unique_integer()}",
  slug: "test-group-#{System.unique_integer()}",
  description: "Test group for ordering verification"
})

# Create events with different dates
now = DateTime.utc_now()

events_data = [
  %{
    title: "Past Event 3 days ago",
    start_at: DateTime.add(now, -3, :day),
    group_id: group.id
  },
  %{
    title: "Past Event 1 day ago",
    start_at: DateTime.add(now, -1, :day),
    group_id: group.id
  },
  %{
    title: "Past Event 5 days ago",
    start_at: DateTime.add(now, -5, :day),
    group_id: group.id
  },
  %{
    title: "Upcoming Event in 2 days",
    start_at: DateTime.add(now, 2, :day),
    group_id: group.id
  },
  %{
    title: "Upcoming Event in 5 days",
    start_at: DateTime.add(now, 5, :day),
    group_id: group.id
  },
  %{
    title: "Event without date",
    start_at: nil,
    group_id: group.id
  }
]

# Create events
created_events = Enum.map(events_data, fn event_data ->
  {:ok, event} = Events.create_event(Map.merge(event_data, %{
    description: "Test event",
    slug: "test-event-#{System.unique_integer()}",
    status: "published",
    taxation_type: "simple"
  }), user)
  event
end)

IO.puts("\n=== Testing Group Event Ordering ===\n")

# Test 1: Get all events
IO.puts("Test 1: All events for group")
all_events = Events.list_events_for_group(group, user, [time_filter: :all])
IO.puts("Found #{length(all_events)} events")
Enum.each(all_events, fn event ->
  date_str = if event.start_at, do: Calendar.strftime(event.start_at, "%Y-%m-%d"), else: "No date"
  IO.puts("  - #{event.title} (#{date_str})")
end)

# Test 2: Get upcoming events
IO.puts("\nTest 2: Upcoming events (should be in ascending order)")
upcoming_events = Events.list_events_for_group(group, user, [time_filter: :upcoming])
IO.puts("Found #{length(upcoming_events)} upcoming events")
Enum.each(upcoming_events, fn event ->
  date_str = if event.start_at, do: Calendar.strftime(event.start_at, "%Y-%m-%d"), else: "No date"
  IO.puts("  - #{event.title} (#{date_str})")
end)

# Test 3: Get past events
IO.puts("\nTest 3: Past events (should be in descending order - most recent first)")
past_events = Events.list_events_for_group(group, user, [time_filter: :past])
IO.puts("Found #{length(past_events)} past events")
Enum.each(past_events, fn event ->
  date_str = if event.start_at, do: Calendar.strftime(event.start_at, "%Y-%m-%d"), else: "No date"
  IO.puts("  - #{event.title} (#{date_str})")
end)

# Verify ordering
IO.puts("\n=== Verification ===")

# Check past events are in descending order
past_dates = past_events |> Enum.map(& &1.start_at) |> Enum.reject(&is_nil/1)
is_desc_ordered = past_dates == Enum.sort(past_dates, {:desc, DateTime})
IO.puts("Past events in descending order (most recent first): #{is_desc_ordered}")

# Check upcoming events are in ascending order
upcoming_dates = upcoming_events |> Enum.map(& &1.start_at) |> Enum.reject(&is_nil/1)
is_asc_ordered = upcoming_dates == Enum.sort(upcoming_dates, {:asc, DateTime})
IO.puts("Upcoming events in ascending order (soonest first): #{is_asc_ordered}")

# Clean up
Enum.each(created_events, fn event ->
  Events.delete_event(event)
end)
Groups.delete_group(group)
# Don't delete the user if it was pre-existing

IO.puts("\n✅ Test completed!")