defmodule EventasaurusApp.Repo.Migrations.AddExternalIdsToMovies do
  use Ecto.Migration

  def change do
    alter table(:movies) do
      # IMDB ID (e.g., "tt0172495") - captured from OMDB/IMDB providers
      add :imdb_id, :string

      # Which provider successfully matched this movie: "tmdb", "omdb", "imdb", "now_playing"
      add :matched_by_provider, :string

      # When the movie was matched (for audit trail)
      add :matched_at, :utc_datetime
    end

    # Index on imdb_id for lookups (unique but nullable)
    create unique_index(:movies, [:imdb_id], where: "imdb_id IS NOT NULL")

    # Index on matched_by_provider for analytics queries
    create index(:movies, [:matched_by_provider])

    # Migrate existing matched_by_provider values from metadata to column
    execute(
      # Up migration
      """
      UPDATE movies
      SET matched_by_provider = metadata->>'matched_by_provider',
          matched_at = NOW()
      WHERE metadata->>'matched_by_provider' IS NOT NULL
        AND matched_by_provider IS NULL
      """,
      # Down migration (no-op, data stays in metadata)
      "SELECT 1"
    )
  end
end
