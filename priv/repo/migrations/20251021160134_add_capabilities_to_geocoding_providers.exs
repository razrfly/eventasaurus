defmodule EventasaurusApp.Repo.Migrations.AddCapabilitiesToGeocodingProviders do
  use Ecto.Migration

  def up do
    # Add new columns (non-breaking, additive only)
    alter table(:geocoding_providers) do
      add :capabilities, :jsonb, default: fragment("'{}'::jsonb")
      add :priorities, :jsonb, default: fragment("'{}'::jsonb")
    end

    # Migrate existing priority integer to priorities.geocoding
    execute """
    UPDATE geocoding_providers
    SET priorities = jsonb_build_object('geocoding', priority);
    """

    # Set capabilities based on known provider capabilities
    execute """
    UPDATE geocoding_providers
    SET capabilities = CASE name
      WHEN 'google_places' THEN '{"geocoding": true, "images": true, "reviews": true, "hours": true}'::jsonb
      WHEN 'here' THEN '{"geocoding": true, "images": true, "reviews": true, "hours": true}'::jsonb
      WHEN 'geoapify' THEN '{"geocoding": true, "images": true}'::jsonb
      ELSE '{"geocoding": true}'::jsonb
    END;
    """

    # Add GIN indices for JSONB query performance
    create index(:geocoding_providers, [:capabilities], using: :gin)
    create index(:geocoding_providers, [:priorities], using: :gin)
  end

  def down do
    drop index(:geocoding_providers, [:capabilities])
    drop index(:geocoding_providers, [:priorities])

    alter table(:geocoding_providers) do
      remove :capabilities
      remove :priorities
    end
  end
end
