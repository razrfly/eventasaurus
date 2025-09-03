# Quick test for poll seeding with movie data
alias EventasaurusApp.{Repo, Events, Accounts}
alias EventasaurusApp.Events.Event
import Ecto.Query
require Logger

# Get the holden user as organizer
organizer = case Repo.get_by(Accounts.User, email: "holden@gmail.com") do
  nil ->
    Logger.error("Organizer user (holden@gmail.com) not found! Please run user seeding first.")
    exit(:no_organizer)
  user -> user
end

# Create a few test events
events = for i <- 1..3 do
  title = case i do
    1 -> "Marvel Movie Marathon Night"
    2 -> "Game Night at the Arcade"
    3 -> "Restaurant Week Dinner"
  end
  
  case Events.create_event(%{
    title: title,
    description: "Test event for poll seeding #{i}",
    # Remove manual slug generation - let the system handle it automatically
    start_at: Timex.shift(DateTime.utc_now(), days: 7 + i),
    timezone: "America/Los_Angeles",
    visibility: "public",
    status: "confirmed"
  }) do
    {:ok, event} ->
      # Add the organizer
      case Events.add_user_to_event(event, organizer, "organizer") do
        {:ok, _event_user} -> :ok
        {:error, reason} ->
          Logger.error("Failed to add organizer to event: #{inspect(reason)}")
      end
      
      # Reload with users association
      Repo.get!(Event, event.id) |> Repo.preload(:users)
    {:error, reason} ->
      Logger.error("Failed to create event #{title}: #{inspect(reason)}")
      nil
  end
end |> Enum.reject(&is_nil/1)

Logger.info("Created #{length(events)} test events")

# Get some additional users for voting
users = Repo.all(from u in Accounts.User, limit: 10)

# Add users as participants to events
Enum.each(events, fn event ->
  Enum.take_random(users, 5)
  |> Enum.each(fn user ->
    case Events.create_event_participant(%{
      event_id: event.id,
      user_id: user.id,
      status: "accepted"
    }) do
      {:ok, _participant} -> :ok
      {:error, reason} ->
        Logger.warning("Failed to add participant #{user.id} to event #{event.id}: #{inspect(reason)}")
    end
  end)
end)

Logger.info("Added participants to events")

# Now run the poll seeding
Code.require_file("poll_seed.exs", __DIR__)
PollSeed.run()