defmodule EventasaurusApp.Repo.Migrations.RenameGeocodingProvidersToVenueDataProviders do
  use Ecto.Migration

  def up do
    # Rename table (PostgreSQL automatically updates indices, constraints, and foreign keys)
    execute "ALTER TABLE geocoding_providers RENAME TO venue_data_providers;"

    # Remove deprecated priority field (now replaced by priorities JSONB map)
    alter table(:venue_data_providers) do
      remove :priority
    end
  end

  def down do
    # Re-add priority field for rollback
    alter table(:venue_data_providers) do
      add :priority, :integer, default: 99
    end

    # Restore priority from priorities.geocoding if available
    execute """
    UPDATE venue_data_providers
    SET priority = COALESCE((priorities->>'geocoding')::integer, 99);
    """

    # Rename table back
    execute "ALTER TABLE venue_data_providers RENAME TO geocoding_providers;"
  end
end
