defmodule EventasaurusApp.Repo.Migrations.AddCityDuplicateDetectionFunction do
  use Ecto.Migration

  def up do
    # Create a function to normalize city names for comparison
    # This handles common diacritics/accent variations
    execute """
    CREATE OR REPLACE FUNCTION normalize_city_name(name text) RETURNS text AS $$
    BEGIN
      RETURN lower(
        translate(
          name,
          'àáâãäåèéêëìíîïòóôõöùúûüýÿñçłßÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÝŸÑÇŁ',
          'aaaaaaeeeeiiiiooooouuuuyynclsAAAAAAAAEEEEIIIIOOOOOUUUUYYNCL'
        )
      );
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """

    # Create an index on normalized names for faster comparisons
    execute """
    CREATE INDEX IF NOT EXISTS cities_normalized_name_idx
    ON cities (normalize_city_name(name));
    """

    # Create a trigram index for fuzzy name matching
    execute """
    CREATE INDEX IF NOT EXISTS cities_name_trgm_idx
    ON cities USING gin (name gin_trgm_ops);
    """

    # Create spatial index if not exists (for PostGIS distance queries)
    # Note: We use a simpler approach without casting the geometry to geography
    # The query itself will handle the geography conversion
    execute """
    CREATE INDEX IF NOT EXISTS cities_location_idx
    ON cities USING gist (
      ST_SetSRID(ST_MakePoint(longitude::float8, latitude::float8), 4326)
    )
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS cities_location_idx;"
    execute "DROP INDEX IF EXISTS cities_name_trgm_idx;"
    execute "DROP INDEX IF EXISTS cities_normalized_name_idx;"
    execute "DROP FUNCTION IF EXISTS normalize_city_name(text);"
  end
end
