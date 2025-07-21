
alias EventasaurusApp.Events.{Event, Ticket, Order, Poll, PollOption, PollVote}
alias EventasaurusApp.Events.{EventParticipant, EventUser}

# Test all schemas have the soft delete and deletion metadata fields
schemas = [
  {Event, "Event"},
  {Ticket, "Ticket"},
  {Order, "Order"},
  {Poll, "Poll"},
  {PollOption, "PollOption"},
  {PollVote, "PollVote"},
  {EventParticipant, "EventParticipant"},
  {EventUser, "EventUser"}
]

Enum.each(schemas, fn {schema, name} ->
  fields = schema.__schema__(:fields)
  has_deleted_at = :deleted_at in fields
  has_deletion_reason = :deletion_reason in fields
  has_deleted_by = :deleted_by_user_id in fields
  
  IO.puts "#{name} schema:"
  IO.puts "  - deleted_at: #{has_deleted_at}"
  IO.puts "  - deletion_reason: #{has_deletion_reason}"
  IO.puts "  - deleted_by_user_id: #{has_deleted_by}"
  IO.puts ""
end)

System.halt(0)

