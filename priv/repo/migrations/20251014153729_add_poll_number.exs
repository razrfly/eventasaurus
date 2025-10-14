defmodule EventasaurusApp.Repo.Migrations.AddPollNumber do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Add number column with NOT NULL and default (idempotent)
    # Using DO block with conditional check for idempotency
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'polls' AND column_name = 'number'
      ) THEN
        ALTER TABLE polls ADD COLUMN number INTEGER NOT NULL DEFAULT 0;
      END IF;
    END $$;
    """

    # Backfill existing polls using ROW_NUMBER() window function
    # Only processes rows with number = 0 or NULL (idempotent)
    execute """
    WITH numbered_polls AS (
      SELECT
        id,
        ROW_NUMBER() OVER (
          PARTITION BY event_id
          ORDER BY inserted_at, id
        ) as seq
      FROM polls
      WHERE number = 0 OR number IS NULL
    )
    UPDATE polls
    SET number = numbered_polls.seq
    FROM numbered_polls
    WHERE polls.id = numbered_polls.id
    """

    # Create unique constraint to prevent duplicate numbers per event
    # IF NOT EXISTS makes this idempotent
    execute """
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS polls_event_id_number_index
    ON polls(event_id, number)
    """

    # Create trigger function to auto-assign poll numbers
    # CREATE OR REPLACE makes this idempotent
    execute """
    CREATE OR REPLACE FUNCTION assign_poll_number()
    RETURNS TRIGGER AS $$
    DECLARE
      next_num integer;
    BEGIN
      -- Only assign if number not explicitly provided or is default 0
      IF NEW.number IS NOT NULL AND NEW.number != 0 THEN
        RETURN NEW;
      END IF;

      -- Lock event row to prevent concurrent numbering conflicts
      -- This ensures only one transaction can assign numbers per event at a time
      PERFORM 1 FROM events WHERE id = NEW.event_id FOR UPDATE;

      -- Get next sequential number for this event
      SELECT COALESCE(MAX(number), 0) + 1 INTO next_num
      FROM polls
      WHERE event_id = NEW.event_id;

      NEW.number := next_num;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create trigger (idempotent with conditional check)
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.triggers
        WHERE trigger_name = 'set_poll_number'
        AND event_object_table = 'polls'
      ) THEN
        CREATE TRIGGER set_poll_number
        BEFORE INSERT ON polls
        FOR EACH ROW
        EXECUTE FUNCTION assign_poll_number();
      END IF;
    END $$;
    """

    # Remove the default now that trigger is active (idempotent)
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'polls'
        AND column_name = 'number'
        AND column_default IS NOT NULL
      ) THEN
        ALTER TABLE polls ALTER COLUMN number DROP DEFAULT;
      END IF;
    END $$;
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS set_poll_number ON polls;"
    execute "DROP FUNCTION IF EXISTS assign_poll_number();"

    alter table(:polls) do
      remove :number
    end
  end
end
