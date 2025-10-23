defmodule EventasaurusApp.Repo.Migrations.AddVenueImageQualityIndices do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Index for fast filtering of venues without images
    # Supports queries: WHERE city_id = X AND jsonb_array_length(venue_images) = 0
    # Uses partial index to only index venues without images (saves space)
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS venues_without_images_idx ON venues (city_id)
      WHERE COALESCE(jsonb_array_length(venue_images), 0) = 0
      """,
      "DROP INDEX IF EXISTS venues_without_images_idx"
    )

    # Index for city-based queries with image count
    # Supports general queries filtering by city
    create_if_not_exists index(:venues, [:city_id, :id],
             name: :venues_city_image_queries_idx,
             concurrently: true
           )
  end
end
