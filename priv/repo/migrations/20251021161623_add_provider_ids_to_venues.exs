defmodule EventasaurusApp.Repo.Migrations.AddProviderIdsToVenues do
  use Ecto.Migration

  def up do
    # Add provider_ids JSONB field to store multiple provider-specific IDs
    alter table(:venues) do
      add :provider_ids, :jsonb, default: fragment("'{}'::jsonb")
    end

    # Add GIN index for fast provider ID lookups
    create index(:venues, [:provider_ids], using: :gin)

    # Migrate existing place_id to provider_ids.google_places
    # Only migrate if place_id is not null
    execute """
    UPDATE venues
    SET provider_ids = jsonb_build_object('google_places', place_id)
    WHERE place_id IS NOT NULL;
    """
  end

  def down do
    drop index(:venues, [:provider_ids])

    alter table(:venues) do
      remove :provider_ids
    end
  end
end
