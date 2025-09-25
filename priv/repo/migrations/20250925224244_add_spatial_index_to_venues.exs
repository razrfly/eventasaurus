defmodule EventasaurusApp.Repo.Migrations.AddSpatialIndexToVenues do
  use Ecto.Migration

  def change do
    # Create a GIST index on the geography point for efficient spatial queries
    # This significantly improves performance for ST_DWithin and other spatial operations
    execute(
      "CREATE INDEX IF NOT EXISTS venues_location_gist ON venues USING GIST ((ST_MakePoint(longitude, latitude)::geography))",
      "DROP INDEX IF EXISTS venues_location_gist"
    )

    # Also add standard btree indexes on individual columns for non-spatial queries
    create_if_not_exists index(:venues, [:latitude])
    create_if_not_exists index(:venues, [:longitude])
  end
end
