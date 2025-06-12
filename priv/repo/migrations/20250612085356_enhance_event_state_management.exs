defmodule EventasaurusApp.Repo.Migrations.EnhanceEventStateManagement do
  use Ecto.Migration

  def up do
    # Add new state-related fields (only the necessary ones)
    alter table(:events) do
      add :polling_deadline, :utc_datetime
      add :threshold_count, :integer
      add :canceled_at, :utc_datetime
    end

    # Convert existing string state to enum values
    # First, rename the current state column
    rename table(:events), :state, to: :old_state

    # Add new status column with enum constraint
    alter table(:events) do
      add :status, :string, default: "confirmed", null: false
    end

    # Create constraint for valid enum values
    create constraint(:events, :valid_status,
      check: "status IN ('draft', 'polling', 'threshold', 'confirmed', 'canceled')"
    )

    # Migrate existing data
    execute """
    UPDATE events
    SET status = CASE
      WHEN old_state = 'confirmed' THEN 'confirmed'
      WHEN old_state = 'polling' THEN 'polling'
      WHEN old_state = 'draft' THEN 'draft'
      WHEN old_state = 'active' THEN 'confirmed'
      WHEN old_state = 'inactive' THEN 'canceled'
      WHEN old_state = 'cancelled' THEN 'canceled'
      ELSE 'confirmed'
    END
    """

    # Remove the old state column
    alter table(:events) do
      remove :old_state
    end

    # Add indexes for performance (only for columns that will be queried)
    create index(:events, [:status])
    create index(:events, [:polling_deadline])
    create index(:events, [:canceled_at])
  end

  def down do
    # Add back the old state column
    alter table(:events) do
      add :old_state, :string
    end

    # Migrate data back
    execute """
    UPDATE events SET old_state =
      CASE
        WHEN status = 'draft' THEN 'draft'
        WHEN status = 'polling' THEN 'polling'
        WHEN status = 'confirmed' THEN 'confirmed'
        WHEN status = 'canceled' THEN 'cancelled'
        ELSE 'confirmed'
      END
    """

    # Remove new columns and constraints
    drop constraint(:events, :valid_status)
    drop index(:events, [:status])
    drop index(:events, [:polling_deadline])
    drop index(:events, [:canceled_at])

    alter table(:events) do
      remove :status
      remove :polling_deadline
      remove :threshold_count
      remove :canceled_at
    end

    # Rename back to original
    rename table(:events), :old_state, to: :state
  end
end
