defmodule EventasaurusApp.Repo.Migrations.MigrateKinoKrakowSlugToRepertuarySlug do
  use Ecto.Migration

  @moduledoc """
  Migrates movie metadata key from kino_krakow_slug to repertuary_slug.

  This completes the Repertuary rename by updating the 70 movies in production
  that still have the old key name. After this migration, all movies will use
  the repertuary_slug key consistently.

  Related: GitHub Issue #2649
  """

  def up do
    # Rename metadata key from kino_krakow_slug to repertuary_slug
    # Uses jsonb_set to add new key, then removes old key
    execute("""
    UPDATE movies
    SET metadata = jsonb_set(
      metadata - 'kino_krakow_slug',
      '{repertuary_slug}',
      metadata->'kino_krakow_slug'
    )
    WHERE metadata ? 'kino_krakow_slug'
    """)
  end

  def down do
    # Reverse: rename back from repertuary_slug to kino_krakow_slug
    execute("""
    UPDATE movies
    SET metadata = jsonb_set(
      metadata - 'repertuary_slug',
      '{kino_krakow_slug}',
      metadata->'repertuary_slug'
    )
    WHERE metadata ? 'repertuary_slug'
    """)
  end
end
