defmodule EventasaurusApp.Repo.Migrations.AddInterestedStatusToEventParticipants do
  use Ecto.Migration

  def up do
    # First check if any existing data would violate the new constraint
    execute """
    UPDATE event_participants
    SET status = 'pending'
    WHERE status NOT IN ('pending', 'accepted', 'declined', 'cancelled', 'confirmed_with_order', 'interested')
    """

    # Only create the constraint if it doesn't already exist
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage
        WHERE constraint_name = 'valid_status'
        AND table_name = 'event_participants'
      ) THEN
        ALTER TABLE event_participants
        ADD CONSTRAINT valid_status
        CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled', 'confirmed_with_order', 'interested'));
      END IF;
    END $$;
    """
  end

  def down do
    # Only drop the constraint if it exists
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage
        WHERE constraint_name = 'valid_status'
        AND table_name = 'event_participants'
      ) THEN
        ALTER TABLE event_participants DROP CONSTRAINT valid_status;
      END IF;
    END $$;
    """
  end
end
