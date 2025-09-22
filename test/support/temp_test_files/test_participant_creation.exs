import Ecto.Query

alias EventasaurusApp.Events
alias EventasaurusApp.Accounts

# Get an event and user to test participant creation
event = Events.list_events() |> List.first()
user = Accounts.list_users() |> List.first()

if event && user do
  IO.puts("Testing participant creation...")
  IO.puts("Event: #{event.title} (ID: #{event.id})")
  IO.puts("User: #{user.name} (ID: #{user.id})")
  
  result = Events.create_event_participant(%{
    event_id: event.id,
    user_id: user.id,
    status: :accepted,
    role: :ticket_holder
  })
  
  case result do
    {:ok, participant} ->
      IO.puts("✅ Participant created successfully!")
      IO.puts("Participant ID: #{participant.id}")
    {:error, changeset} ->
      IO.puts("❌ Failed to create participant:")
      IO.inspect(changeset.errors)
  end
else
  IO.puts("❌ Missing event or user for test")
end
