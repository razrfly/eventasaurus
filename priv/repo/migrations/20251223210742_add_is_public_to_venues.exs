defmodule EventasaurusApp.Repo.Migrations.AddIsPublicToVenues do
  use Ecto.Migration

  @doc """
  Adds is_public boolean field to venues table.

  This field provides an explicit public/private distinction:
  - true: Public venues (theaters, bars, concert halls) - created by scrapers
  - false: Private venues (user homes, private addresses) - created by users

  This eliminates the need for cross-app joins to determine venue "publicness"
  and enables faster queries via the indexed boolean field.
  """
  def change do
    alter table(:venues) do
      add :is_public, :boolean, default: false, null: false
    end

    # Index for fast filtering on public venues (sitemap, search, listings)
    create index(:venues, [:is_public])

    # Composite index for common query pattern: public venues in a city
    create index(:venues, [:city_id, :is_public])

    # Backfill: Set is_public=true for all non-user venues
    # Venues created by scrapers have source set to geocoding provider names
    # (mapbox, google, geoapify, here, locationiq, openstreetmap, photon, provided, scraper)
    # Only user-created venues should remain private (is_public=false)
    execute(
      "UPDATE venues SET is_public = true WHERE source != 'user' OR source IS NULL",
      "UPDATE venues SET is_public = false WHERE source != 'user' OR source IS NULL"
    )
  end
end
