defmodule EventasaurusApp.Repo.Migrations.AddEventSourceConstraintTriggers do
  use Ecto.Migration

  @moduledoc """
  Adds database-level triggers to prevent orphaned events.

  Two triggers are created:
  1. ensure_event_has_source - Prevents creating events without sources
     (deferred to COMMIT time to allow event+source creation in same transaction)
  2. prevent_orphaning_on_delete - Prevents deleting the last source from an event

  See GitHub issue #2904 for full context.
  """

  def up do
    # Trigger 1: Prevent creating events without sources
    # Uses DEFERRABLE INITIALLY DEFERRED so check runs at COMMIT time,
    # allowing the existing pattern: INSERT event, INSERT source, COMMIT
    execute """
    CREATE OR REPLACE FUNCTION check_event_has_source()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM public_event_sources WHERE event_id = NEW.id
      ) THEN
        RAISE EXCEPTION 'Event % must have at least one source record', NEW.id
          USING HINT = 'Ensure source is created within the same transaction';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE CONSTRAINT TRIGGER ensure_event_has_source
    AFTER INSERT ON public_events
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION check_event_has_source();
    """

    # Trigger 2: Prevent deleting the last source from an event
    # Runs BEFORE DELETE to block the operation if it would orphan the event
    execute """
    CREATE OR REPLACE FUNCTION prevent_last_source_deletion()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM public_event_sources
        WHERE event_id = OLD.event_id AND id != OLD.id
      ) THEN
        RAISE EXCEPTION 'Cannot delete the last source for event %', OLD.event_id
          USING HINT = 'Delete the event itself, or add another source first';
      END IF;
      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER prevent_orphaning_on_delete
    BEFORE DELETE ON public_event_sources
    FOR EACH ROW
    EXECUTE FUNCTION prevent_last_source_deletion();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS ensure_event_has_source ON public_events;"
    execute "DROP FUNCTION IF EXISTS check_event_has_source();"
    execute "DROP TRIGGER IF EXISTS prevent_orphaning_on_delete ON public_event_sources;"
    execute "DROP FUNCTION IF EXISTS prevent_last_source_deletion();"
  end
end
