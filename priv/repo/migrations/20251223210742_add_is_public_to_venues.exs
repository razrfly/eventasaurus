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

    # Backfill: Set is_public=true for all scraper-created venues
    execute(
      "UPDATE venues SET is_public = true WHERE source = 'scraper'",
      "UPDATE venues SET is_public = false WHERE source = 'scraper'"
    )
  end
end
