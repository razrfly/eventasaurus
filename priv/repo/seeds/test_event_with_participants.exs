# Test event with participants for relationship permission testing
# Run with: mix run priv/repo/seeds/test_event_with_participants.exs
#
# Prerequisites: Run test_users_with_preferences.exs first
#
# Creates a test event and adds all test users as participants
# so we can test the RelationshipButtonComponent in the attendees modal

import Ecto.Query, warn: false

alias EventasaurusApp.Repo
alias EventasaurusApp.Accounts.User
alias EventasaurusApp.Events
alias EventasaurusApp.Events.{Event, EventUser}
alias EventasaurusApp.Venues.Venue
alias EventasaurusDiscovery.Locations.City

IO.puts("🌱 Creating test event for relationship permission testing...")

# Find users
demo = Repo.get_by(User, email: "demo@example.com")
holden = Repo.get_by(User, email: "holden.thomas@gmail.com")
alice = Repo.get_by(User, email: "alice@example.com")
bob = Repo.get_by(User, email: "bob@example.com")
carol = Repo.get_by(User, email: "carol@example.com")
dave = Repo.get_by(User, email: "dave@example.com")
eve = Repo.get_by(User, email: "eve@example.com")

# Use demo or holden as the organizer
organizer = demo || holden

if is_nil(organizer) do
  IO.puts("❌ No organizer found. Log in first to create a user.")
else
  IO.puts("  Found organizer: #{organizer.email}")

  # Find or create a test venue
  # Get a real city for the venue
  test_city = Repo.one(from c in City, limit: 1)

  venue =
    case Repo.get_by(Venue, name: "Test Privacy Venue") do
      nil ->
        {:ok, v} =
          %Venue{}
          |> Venue.changeset(%{
            name: "Test Privacy Venue",
            slug: "test-privacy-venue",
            address: "123 Test Street",
            latitude: 52.2297,
            longitude: 21.0122,
            city_id: test_city && test_city.id
          })
          |> Repo.insert()

        v

      v ->
        v
    end

  IO.puts("  Using venue: #{venue.name}")

  # Find or create the test event
  event =
    case Repo.get_by(Event, slug: "privacy-permissions-test-event") do
      nil ->
        # Create the event
        start_at = DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60, :second)
        ends_at = DateTime.add(start_at, 3 * 60 * 60, :second)

        {:ok, e} =
          %Event{}
          |> Event.changeset(%{
            title: "Privacy Permissions Test Event",
            slug: "privacy-permissions-test-event",
            description: "A test event for verifying relationship permission settings in the attendees modal.",
            start_at: start_at,
            ends_at: ends_at,
            timezone: "America/New_York",
            visibility: :public,
            status: :confirmed,
            venue_id: venue.id
          })
          |> Repo.insert()

        # Add organizer as EventUser
        %EventUser{}
        |> EventUser.changeset(%{
          event_id: e.id,
          user_id: organizer.id,
          role: :organizer
        })
        |> Repo.insert()

        e

      e ->
        e
    end

  IO.puts("  Using event: #{event.title} (#{event.slug})")

  # Add organizer as participant (so they can see the connect buttons)
  case Events.get_event_participant_by_event_and_user(event, organizer) do
    nil ->
      case Events.create_event_participant(%{
             event_id: event.id,
             user_id: organizer.id,
             status: :accepted,
             role: :invitee
           }) do
        {:ok, _} ->
          IO.puts("  ✅ Added #{organizer.name || organizer.email} as participant (organizer)")

        {:error, reason} ->
          IO.puts("  ❌ Failed to add organizer as participant: #{inspect(reason)}")
      end

    _existing ->
      IO.puts("  ⏭️  #{organizer.name || organizer.email} already a participant")
  end

  # Add all test users as participants
  test_users = [alice, bob, carol, dave, eve] |> Enum.reject(&is_nil/1)

  for user <- test_users do
    case Events.get_event_participant_by_event_and_user(event, user) do
      nil ->
        case Events.create_event_participant(%{
               event_id: event.id,
               user_id: user.id,
               status: :accepted,
               role: :invitee
             }) do
          {:ok, _} ->
            IO.puts("  ✅ Added #{user.name} as participant")

          {:error, reason} ->
            IO.puts("  ❌ Failed to add #{user.name}: #{inspect(reason)}")
        end

      _existing ->
        IO.puts("  ⏭️  #{user.name} already a participant")
    end
  end

  IO.puts("")
  IO.puts("📊 Test event created:")
  IO.puts("  URL: /events/#{event.slug}")
  IO.puts("  Organizer: #{organizer.email}")
  IO.puts("")
  IO.puts("🧪 Testing scenarios:")
  IO.puts("  When logged in as organizer (#{organizer.email}):")
  IO.puts("    - Alice (open): Button should be ENABLED")
  IO.puts("    - Bob (event_attendees): Button should be ENABLED (shared event)")
  IO.puts("    - Carol (extended_network): Button should be DISABLED (not in network)")
  IO.puts("    - Dave (closed): Button should be DISABLED")
  IO.puts("    - Eve (event_attendees): Button should be ENABLED (shared event)")
  IO.puts("")
  IO.puts("🌱 Test event seeded!")
end
