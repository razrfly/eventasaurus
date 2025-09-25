defmodule EventasaurusApp.Repo.Migrations.FixEventPlansUniqueConstraint do
  use Ecto.Migration

  def up do
    # First, remove duplicate event_plans, keeping only the most recent one per user+public_event
    execute """
    DELETE FROM event_plans
    WHERE id NOT IN (
      SELECT DISTINCT ON (public_event_id, created_by) id
      FROM event_plans
      ORDER BY public_event_id, created_by, inserted_at DESC
    )
    """

    # Drop the old incorrect unique constraint
    drop_if_exists unique_index(:event_plans, [:public_event_id, :private_event_id, :created_by])

    # Add the correct unique constraint
    create unique_index(:event_plans, [:public_event_id, :created_by],
      name: :unique_user_plan_per_public_event)
  end

  def down do
    # Remove the new constraint
    drop_if_exists unique_index(:event_plans, [:public_event_id, :created_by],
      name: :unique_user_plan_per_public_event)

    # Restore the old constraint (though it was problematic)
    create unique_index(:event_plans, [:public_event_id, :private_event_id, :created_by])
  end
end
