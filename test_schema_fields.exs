
alias EventasaurusApp.Events.Event

# Test that Event schema has the soft delete fields
event_fields = Event.__schema__(:fields)
IO.puts "Event schema fields: #{inspect(event_fields)}"

# Check if deleted_at field is present
has_deleted_at = :deleted_at in event_fields
IO.puts "Event has deleted_at field: #{has_deleted_at}"

# Check if deletion metadata fields are present
has_deletion_reason = :deletion_reason in event_fields
has_deleted_by = :deleted_by_user_id in event_fields
IO.puts "Event has deletion_reason field: #{has_deletion_reason}"
IO.puts "Event has deleted_by_user_id field: #{has_deleted_by}"

System.halt(0)

