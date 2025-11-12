alias EventasaurusApp.Repo
alias EventasaurusApp.Events.Event
alias EventasaurusApp.Events.EventUser
alias EventasaurusApp.Accounts
import Ecto.Query

IO.puts("\n🎬 Creating poll suggestions test data...")

# Find Holden's user account
holden = Repo.one(from u in Accounts.User, where: u.email == "holden@gmail.com")

unless holden do
  IO.puts("❌ Holden user not found! Run main seeds first: mix run priv/repo/seeds.exs")
  exit(:shutdown)
end

IO.puts("✅ Found Holden (#{holden.email})")

# Find group 6 (The Dinner Club)
group_6 = Repo.get(EventasaurusApp.Groups.Group, 6)

unless group_6 do
  IO.puts("❌ Group 6 (The Dinner Club) not found!")
  exit(:shutdown)
end

IO.puts("✅ Found group: #{group_6.name}")

# Create a new event in group 6 with NO polls
# This will allow Holden to see poll suggestions based on his existing poll history
event_attrs = %{
  title: "Summer BBQ & Games Night",
  description: "Join us for a casual summer evening with BBQ, drinks, and board games. This is a test event for poll suggestions!",
  start_at: DateTime.add(DateTime.utc_now(), 14, :day),
  ends_at: DateTime.add(DateTime.utc_now(), 14, :day) |> DateTime.add(4 * 3600, :second),
  status: :draft,
  visibility: :public,
  group_id: group_6.id,
  slug: "summer-bbq-test-#{:rand.uniform(999999)}",
  timezone: "America/Los_Angeles"
}

# Check if we already have a similar test event
existing_event = Repo.one(
  from e in Event,
  where: e.title == ^event_attrs.title and e.group_id == ^group_6.id and is_nil(e.deleted_at),
  limit: 1
)

event = if existing_event do
  IO.puts("ℹ️  Test event already exists: #{existing_event.slug}")
  existing_event
else
  changeset = Event.changeset(%Event{}, event_attrs)
  case Repo.insert(changeset) do
    {:ok, created_event} ->
      IO.puts("✅ Created new test event: #{created_event.slug}")
      created_event
    {:error, changeset} ->
      IO.puts("❌ Failed to create event:")
      IO.inspect(changeset.errors)
      exit(:shutdown)
  end
end

# Make Holden an organizer of this event
existing_organizer = Repo.one(
  from eu in EventUser,
  where: eu.event_id == ^event.id and eu.user_id == ^holden.id
)

if existing_organizer do
  IO.puts("ℹ️  Holden is already an organizer of this event")
else
  event_user_attrs = %{
    event_id: event.id,
    user_id: holden.id,
    role: "organizer",
    status: "confirmed"
  }

  changeset = EventUser.changeset(%EventUser{}, event_user_attrs)
  case Repo.insert(changeset) do
    {:ok, _event_user} ->
      IO.puts("✅ Added Holden as organizer")
    {:error, changeset} ->
      IO.puts("❌ Failed to add Holden as organizer:")
      IO.inspect(changeset.errors)
  end
end

# Display test instructions
IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("🎉 Poll Suggestions Test Data Ready!")
IO.puts(String.duplicate("=", 70))
IO.puts("\n📋 Test Instructions:")
IO.puts("1. Login as: holden@gmail.com / sawyer1234")
IO.puts("2. Visit: http://localhost:4000/events/#{event.slug}/polls")
IO.puts("3. You should see poll suggestions based on Holden's previous polls:")
IO.puts("   • Date selection polls (binary voting)")
IO.puts("   • Movie polls (star rating)")
IO.puts("\n✨ Expected Behavior:")
IO.puts("• Suggestion banner will appear (gradient purple/indigo)")
IO.puts("• Shows 1-2 suggestion cards with poll types and common options")
IO.puts("• Click 'Use Template' to pre-fill poll creation form")
IO.puts("• Click 'Dismiss' to see normal empty state")
IO.puts("\n" <> String.duplicate("=", 70))
