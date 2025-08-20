defmodule EventasaurusApp.Repo.Migrations.AddSettingsToPolls do
  use Ecto.Migration

  def up do
    # Add settings JSONB field for flexible configuration
    alter table(:polls) do
      add :settings, :map, default: %{}, null: false
    end

    # Set default location scope for existing places polls
    execute """
    UPDATE polls 
    SET settings = '{"location_scope": "place"}'::jsonb 
    WHERE poll_type = 'places' AND deleted_at IS NULL
    """

    # Add index for settings queries
    create index(:polls, [:settings], using: :gin)
  end

  def down do
    drop index(:polls, [:settings])
    
    alter table(:polls) do
      remove :settings
    end
  end
end