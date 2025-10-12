defmodule EventasaurusApp.Repo.Migrations.CreateGeocodingProviders do
  use Ecto.Migration

  def up do
    create table(:geocoding_providers) do
      add :name, :string, null: false
      add :priority, :integer, null: false
      add :is_active, :boolean, default: true, null: false
      add :metadata, :jsonb, default: fragment("'{}'::jsonb")

      timestamps()
    end

    create unique_index(:geocoding_providers, [:name])
    create index(:geocoding_providers, [:priority])
    create index(:geocoding_providers, [:is_active, :priority])

    # Seed all providers with rate limits in metadata
    # Priority set to 1 for randomized testing
    execute """
    INSERT INTO geocoding_providers (name, priority, is_active, metadata, inserted_at, updated_at)
    VALUES
      -- Mapbox: 10 req/sec free tier
      ('mapbox', 1, true, '{"rate_limits": {"per_second": 10, "per_minute": 600, "per_hour": 36000}, "timeout_ms": 5000}'::jsonb, NOW(), NOW()),
      -- HERE: 10 req/sec free tier
      ('here', 1, true, '{"rate_limits": {"per_second": 10, "per_minute": 600, "per_hour": 36000}, "timeout_ms": 5000}'::jsonb, NOW(), NOW()),
      -- Geoapify: 5 req/sec free tier
      ('geoapify', 1, true, '{"rate_limits": {"per_second": 5, "per_minute": 300, "per_hour": 18000}, "timeout_ms": 5000}'::jsonb, NOW(), NOW()),
      -- LocationIQ: 5 req/sec free tier
      ('locationiq', 1, true, '{"rate_limits": {"per_second": 5, "per_minute": 300, "per_hour": 18000}, "timeout_ms": 5000}'::jsonb, NOW(), NOW()),
      -- OpenStreetMap: 1 req/sec (strictly enforced)
      ('openstreetmap', 1, true, '{"rate_limits": {"per_second": 1, "per_minute": 60, "per_hour": 3600}, "timeout_ms": 5000}'::jsonb, NOW(), NOW()),
      -- Photon: 10 req/sec (no official limit, conservative)
      ('photon', 1, true, '{"rate_limits": {"per_second": 10, "per_minute": 600, "per_hour": 36000}, "timeout_ms": 5000}'::jsonb, NOW(), NOW()),
      -- Google Maps: Disabled (requires API key)
      ('google_maps', 99, false, '{"rate_limits": {"per_second": 50, "per_minute": 3000}, "timeout_ms": 5000}'::jsonb, NOW(), NOW()),
      -- Google Places: Disabled (requires API key)
      ('google_places', 99, false, '{"rate_limits": {"per_second": 50, "per_minute": 3000}, "timeout_ms": 5000}'::jsonb, NOW(), NOW())
    """
  end

  def down do
    drop table(:geocoding_providers)
  end
end
