defmodule EventasaurusApp.Repo.Migrations.CreateGeocodingProviders do
  use Ecto.Migration

  def up do
    create table(:geocoding_providers) do
      add :name, :string, null: false
      add :priority, :integer, null: false
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:geocoding_providers, [:name])
    create index(:geocoding_providers, [:priority])
    create index(:geocoding_providers, [:is_active, :priority])

    # Seed all providers with equal priority (1) for testing
    # This allows random provider selection to test all providers equally
    execute """
    INSERT INTO geocoding_providers (name, priority, is_active, inserted_at, updated_at)
    VALUES
      ('mapbox', 1, true, NOW(), NOW()),
      ('here', 1, true, NOW(), NOW()),
      ('geoapify', 1, true, NOW(), NOW()),
      ('locationiq', 1, true, NOW(), NOW()),
      ('openstreetmap', 1, true, NOW(), NOW()),
      ('photon', 1, true, NOW(), NOW()),
      ('google_maps', 1, false, NOW(), NOW()),
      ('google_places', 1, false, NOW(), NOW())
    """
  end

  def down do
    drop table(:geocoding_providers)
  end
end
