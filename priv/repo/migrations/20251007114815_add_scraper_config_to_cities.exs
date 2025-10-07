defmodule EventasaurusApp.Repo.Migrations.AddDiscoveryConfigToCities do
  use Ecto.Migration

  def up do
    # Add fields for automated discovery orchestration
    alter table(:cities) do
      add :discovery_enabled, :boolean, default: false
      add :discovery_config, :map
    end

    # Add index for efficient queries on discovery-enabled cities
    create index(:cities, [:discovery_enabled])

    # Add GIN index for JSONB queries on discovery_config
    create index(:cities, [:discovery_config], using: :gin)
  end

  def down do
    drop index(:cities, [:discovery_config])
    drop index(:cities, [:discovery_enabled])

    alter table(:cities) do
      remove :discovery_config
      remove :discovery_enabled
    end
  end
end
