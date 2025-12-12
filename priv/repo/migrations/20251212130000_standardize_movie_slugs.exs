defmodule EventasaurusApp.Repo.Migrations.StandardizeMovieSlugs do
  use Ecto.Migration

  @moduledoc """
  Standardizes movie slugs to use title-tmdb_id format.

  Before: home-alone-499 (random suffix)
  After:  home-alone-771 (TMDB ID suffix)

  The TMDB ID ensures uniqueness even when titles are the same
  (e.g., two movies named "Brother" become "brother-51976" and "brother-1416589").

  Adds legacy_slug column to preserve old slugs for backwards compatibility
  with existing links. This column can be removed after ~6 months.
  """

  def up do
    # Step 1: Add legacy_slug column
    alter table(:movies) do
      add :legacy_slug, :string
    end

    # Step 2: Copy current slugs to legacy_slug
    execute "UPDATE movies SET legacy_slug = slug"

    # Step 3: Drop the unique constraint on slug temporarily for regeneration
    drop_if_exists index(:movies, [:slug], name: :movies_slug_index)
    drop_if_exists unique_index(:movies, [:slug])

    # Step 4: Regenerate all slugs as title-tmdb_id format
    # This creates slugs like "home-alone-771" instead of "home-alone-499"
    execute """
    UPDATE movies
    SET slug = CONCAT(
      LOWER(
        TRIM(BOTH '-' FROM
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(title, '[^a-zA-Z0-9\\s-]', '', 'g'),
              '\\s+', '-', 'g'
            ),
            '-+', '-', 'g'
          )
        )
      ),
      '-',
      tmdb_id
    )
    """

    # Step 5: Handle any movies with empty titles
    execute """
    UPDATE movies
    SET slug = CONCAT('movie-', tmdb_id)
    WHERE slug = CONCAT('-', tmdb_id) OR slug IS NULL
    """

    # Step 6: Add index on legacy_slug for backwards compatibility lookups
    create index(:movies, [:legacy_slug])

    # Step 7: Re-add unique index on slug (now guaranteed unique via TMDB ID)
    create unique_index(:movies, [:slug])
  end

  def down do
    # Restore slugs from legacy_slug
    execute "UPDATE movies SET slug = legacy_slug WHERE legacy_slug IS NOT NULL"

    # Drop indexes
    drop_if_exists index(:movies, [:legacy_slug])
    drop_if_exists unique_index(:movies, [:slug])

    # Remove legacy_slug column
    alter table(:movies) do
      remove :legacy_slug
    end

    # Restore unique constraint on slug
    create unique_index(:movies, [:slug])
  end
end
