defmodule EventasaurusApp.Repo.Migrations.FixIsPublicBackfillForAllSources do
  use Ecto.Migration

  @doc """
  Fixes the is_public backfill to include ALL non-user venues.

  The original migration only set is_public=true for source='scraper',
  but venues created by scrapers have source set to their geocoding provider:
  - provided, mapbox, geoapify, photon, locationiq, here, openstreetmap, scraper

  Only user-created venues (source='user') should be private.
  """
  def up do
    execute("UPDATE venues SET is_public = true WHERE source != 'user'")
  end

  def down do
    # Revert to only scraper sources being public (original incorrect state)
    execute("UPDATE venues SET is_public = false WHERE source != 'user' AND source != 'scraper'")
  end
end
