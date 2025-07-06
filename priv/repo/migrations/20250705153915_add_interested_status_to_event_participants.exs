defmodule EventasaurusApp.Repo.Migrations.AddInterestedStatusToEventParticipants do
  use Ecto.Migration

  def up do
    # Add CHECK constraint to validate status values including new 'interested' status
    create constraint(:event_participants, :valid_status,
      check: "status IN ('pending', 'accepted', 'declined', 'cancelled', 'confirmed_with_order', 'interested')")
  end

  def down do
    # Remove the constraint to allow rollback
    drop constraint(:event_participants, :valid_status)
  end
end
