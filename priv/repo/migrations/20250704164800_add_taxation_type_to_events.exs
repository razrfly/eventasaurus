defmodule EventasaurusApp.Repo.Migrations.AddTaxationTypeToEvents do
  use Ecto.Migration

  def up do
    # Step 1: Add the taxation_type column as nullable first (zero-downtime)
    alter table(:events) do
      add :taxation_type, :string
    end

    # Step 2: Set default values for existing records
    execute """
    UPDATE events SET taxation_type = 'ticketed_event' WHERE taxation_type IS NULL;
    """

    # Step 3: Set default and make column not null
    alter table(:events) do
      modify :taxation_type, :string, default: "ticketed_event", null: false
    end

    # Step 4: Add check constraint for valid taxation types
    create constraint(:events, :valid_taxation_type,
      check: "taxation_type IN ('ticketed_event', 'contribution_collection')"
    )

    # Step 5: Add index for performance (taxation_type will be queried frequently)
    create index(:events, [:taxation_type])
  end

  def down do
    # Remove constraint and index
    drop constraint(:events, :valid_taxation_type)
    drop index(:events, [:taxation_type])

    # Remove column
    alter table(:events) do
      remove :taxation_type
    end
  end
end
