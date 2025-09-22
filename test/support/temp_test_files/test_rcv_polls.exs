# Simple RCV Poll Creation Test
# Tests that RCV polls can be created successfully

import Ecto.Query
alias EventasaurusApp.{Repo, Events, Accounts}

# Get available users and create a simple event
users = Repo.all(from(u in Accounts.User, limit: 10))
if users == [] do
  IO.puts("❌ No users found. Seed users before running this script.")
  System.halt(1)
end
organizer = Enum.random(users)

IO.puts("=== Testing RCV Poll Creation ===")

# Create a simple test event
event_params = %{
  title: "RCV Test Event",
  description: "Testing RCV poll functionality",
  start_at: DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60, :second),
  ends_at: DateTime.add(DateTime.utc_now(), 8 * 24 * 60 * 60, :second),
  timezone: "America/Los_Angeles",
  visibility: "public",
  status: :confirmed,
  is_virtual: true,
  virtual_venue_url: "https://zoom.us/test",
  polling_deadline: DateTime.add(DateTime.utc_now(), 6 * 24 * 60 * 60, :second)
}

case Events.create_event(event_params) do
  {:ok, event} ->
    IO.puts("✓ Test event created: #{event.title}")
    
    # Add organizer to event
    Events.add_user_to_event(event, organizer, "organizer")
    
    # Add some participants
    participants = users |> Enum.reject(&(&1.id == organizer.id)) |> Enum.take(5)
    Enum.each(participants, fn participant ->
      Events.create_event_participant(%{
        event_id: event.id,
        user_id: participant.id,
        status: "confirmed"
      })
    end)
    
    IO.puts("✓ Added #{length(participants)} participants to event")
    
    # Create RCV poll
    poll_params = %{
      event_id: event.id,
      title: "Choose Your Favorite Movies (RCV Test)",
      description: "Rank these movies in order of preference using Ranked Choice Voting",
      poll_type: "movie",
      voting_system: "ranked", 
      created_by_id: organizer.id,
      voting_deadline: event.polling_deadline
    }
    
    case Events.create_poll(poll_params) do
      {:ok, poll} ->
        IO.puts("✓ RCV poll created successfully: #{poll.title}")
        
        # Transition to voting phase
        {:ok, poll} = Events.transition_poll_phase(poll, "voting_only")
        IO.puts("✓ Poll transitioned to voting phase")
        
        # Create movie options
        movies = [
          "The Shawshank Redemption",
          "The Godfather", 
          "The Dark Knight",
          "Pulp Fiction",
          "Forrest Gump"
        ]
        
        Enum.each(movies, fn movie ->
          {:ok, _option} = Events.create_poll_option(%{
            poll_id: poll.id,
            title: movie,
            description: "Classic movie option",
            suggested_by_id: organizer.id
          })
        end)
        
        IO.puts("✓ Created #{length(movies)} movie options")
        
        # Test that the poll was created with correct voting system
        rcv_poll = Repo.get(Events.Poll, poll.id)
        if rcv_poll.voting_system == "ranked" do
          IO.puts("✅ SUCCESS: RCV poll created with voting_system: 'ranked'")
        else
          IO.puts("❌ ERROR: Poll voting system is '#{rcv_poll.voting_system}', expected 'ranked'")
        end
        
      {:error, changeset} ->
        IO.puts("❌ Failed to create RCV poll: #{inspect(changeset.errors)}")
    end
    
  {:error, changeset} ->
    IO.puts("❌ Failed to create test event: #{inspect(changeset.errors)}")
end

# Check final poll counts
polls = from(p in Events.Poll, where: is_nil(p.deleted_at), group_by: p.voting_system, select: {p.voting_system, count(p.id)}) |> Repo.all()

IO.puts("\n=== FINAL POLL COUNTS BY VOTING SYSTEM ===")
Enum.each(polls, fn {system, count} ->
  IO.puts("#{system}: #{count}")
end)

# Check for RCV specifically
rcv_polls = from(p in Events.Poll, where: is_nil(p.deleted_at) and p.voting_system == "ranked") |> Repo.aggregate(:count)
IO.puts("\n*** RCV/Ranked Polls: #{rcv_polls} ***")