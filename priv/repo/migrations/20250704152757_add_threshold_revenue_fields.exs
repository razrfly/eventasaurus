defmodule EventasaurusApp.Repo.Migrations.AddThresholdRevenueFields do
  use Ecto.Migration

  def up do
    # Add new threshold fields to events table
    alter table(:events) do
      add :threshold_type, :string, default: "attendee_count", null: false
      add :threshold_revenue_cents, :integer
    end

    # Create constraint for valid threshold types
    create constraint(:events, :valid_threshold_type,
      check: "threshold_type IN ('attendee_count', 'revenue', 'both')"
    )

    # Add index for performance on threshold_type
    create index(:events, [:threshold_type])
  end

  def down do
    # Remove constraint and index
    drop constraint(:events, :valid_threshold_type)
    drop index(:events, [:threshold_type])

    # Remove columns
    alter table(:events) do
      remove :threshold_type
      remove :threshold_revenue_cents
    end
  end
end
