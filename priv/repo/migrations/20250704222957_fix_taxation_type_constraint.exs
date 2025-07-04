defmodule EventasaurusApp.Repo.Migrations.FixTaxationTypeConstraint do
  use Ecto.Migration

  def up do
    # Drop the existing constraint
    execute("ALTER TABLE events DROP CONSTRAINT IF EXISTS valid_taxation_type")

    # Add the corrected constraint that includes 'ticketless'
    execute("ALTER TABLE events ADD CONSTRAINT valid_taxation_type CHECK (taxation_type IN ('ticketed_event', 'contribution_collection', 'ticketless'))")
  end

  def down do
    # Drop the extended constraint
    execute("ALTER TABLE events DROP CONSTRAINT IF EXISTS valid_taxation_type")

    # Re-create the original constraint (without 'ticketless')
    execute("ALTER TABLE events ADD CONSTRAINT valid_taxation_type CHECK (taxation_type IN ('ticketed_event', 'contribution_collection'))")
  end
end
