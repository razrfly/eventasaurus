defmodule EventasaurusApp.Repo.Migrations.RemoveUpdatedAtFromPublicEventCategories do
  use Ecto.Migration

  def up do
    # Only remove the column if it exists
    execute """
    ALTER TABLE public_event_categories
    DROP COLUMN IF EXISTS updated_at
    """
  end

  def down do
    # Add it back if rolling back
    alter table(:public_event_categories) do
      add :updated_at, :utc_datetime, null: false
    end
  end
end