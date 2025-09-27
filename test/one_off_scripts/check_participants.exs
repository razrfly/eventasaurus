import Ecto.Query
alias EventasaurusApp.Events
alias EventasaurusApp.Repo

# Check event participants
events_with_participants = from(e in Events.Event, 
  left_join: p in Events.EventParticipant, on: p.event_id == e.id and is_nil(p.deleted_at),
  where: is_nil(e.deleted_at),
  group_by: e.id,
  select: {e.id, e.title, count(p.id)}
) |> Repo.all()

IO.puts("Events and their participant counts:")
Enum.each(events_with_participants, fn {id, title, count} ->
  IO.puts("#{id}: #{title} - #{count} participants")
end)
