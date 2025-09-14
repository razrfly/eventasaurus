defmodule EventasaurusApp.Repo.Migrations.UpdateVenues do
  use Ecto.Migration

  def up do
    # Enable PostGIS and unaccent extensions
    execute "CREATE EXTENSION IF NOT EXISTS postgis"
    execute "CREATE EXTENSION IF NOT EXISTS unaccent"

    alter table(:venues) do
      add :normalized_name, :string
      add :slug, :string
      add :place_id, :string
      add :external_id, :string
      add :source, :string, default: "user"
      add :city_id, references(:cities, on_delete: :nilify_all)
      add :metadata, :map, default: %{}
    end

    # Create normalization function for venues
    execute """
    CREATE OR REPLACE FUNCTION normalize_venue_name(text) RETURNS text AS $$
    BEGIN
      RETURN LOWER(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            UNACCENT($1),
            '[^a-z0-9\\s]', '', 'gi'
          ),
          '\\s+', ' ', 'g'
        )
      );
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """

    # Create trigger to auto-normalize venue names
    execute """
    CREATE OR REPLACE FUNCTION venues_normalize_trigger() RETURNS trigger AS $$
    BEGIN
      NEW.normalized_name = normalize_venue_name(NEW.name);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER venues_normalize_name
    BEFORE INSERT OR UPDATE ON venues
    FOR EACH ROW
    EXECUTE FUNCTION venues_normalize_trigger();
    """


    # Create indexes
    create index(:venues, [:place_id])
    create index(:venues, [:city_id])
    create index(:venues, [:source])
    create index(:venues, [:normalized_name, :city_id])
    create unique_index(:venues, [:slug])
    create unique_index(:venues, [:external_id, :source])
  end

  def down do
    drop index(:venues, [:slug])
    drop index(:venues, [:external_id, :source])
    drop index(:venues, [:normalized_name, :city_id])
    drop index(:venues, [:source])
    drop index(:venues, [:city_id])
    drop index(:venues, [:place_id])

    execute "DROP TRIGGER IF EXISTS venues_normalize_name ON venues;"
    execute "DROP FUNCTION IF EXISTS venues_normalize_trigger();"
    execute "DROP FUNCTION IF EXISTS normalize_venue_name(text);"

    alter table(:venues) do
      remove :normalized_name
      remove :slug
      remove :place_id
      remove :external_id
      remove :source
      remove :city_id
      remove :metadata
    end
  end
end