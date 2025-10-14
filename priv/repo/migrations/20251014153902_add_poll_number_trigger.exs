defmodule EventasaurusApp.Repo.Migrations.AddPollNumberTrigger do
  use Ecto.Migration

  def up do
    # Create function to automatically assign sequential poll numbers
    execute """
    CREATE OR REPLACE FUNCTION assign_poll_number()
    RETURNS TRIGGER AS $$
    DECLARE
      next_num integer;
    BEGIN
      -- Only assign if number not explicitly provided
      IF NEW.number IS NOT NULL THEN
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

    # Create trigger to call function before insert
    execute """
    CREATE TRIGGER set_poll_number
    BEFORE INSERT ON polls
    FOR EACH ROW
    WHEN (NEW.number IS NULL)
    EXECUTE FUNCTION assign_poll_number();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS set_poll_number ON polls;"
    execute "DROP FUNCTION IF EXISTS assign_poll_number();"
  end
end
