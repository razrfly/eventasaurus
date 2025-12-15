defmodule Mix.Tasks.FixCinemaCityDuplicates do
  @moduledoc """
  Fixes duplicate cinema_city_film_id entries in movies table.

  Due to a bug in MovieDetailJob.store_cinema_city_film_id, some movies ended up
  with incorrect cinema_city_film_id values that belong to different films.

  This task identifies movies with duplicate film_ids and removes the film_id
  from the NEWER entries (keeping the oldest/correct one).

  ## Usage

      # Dry run (show what would be fixed, no changes)
      mix fix_cinema_city_duplicates

      # Actually fix the data
      mix fix_cinema_city_duplicates --apply

  ## What it does

  1. Finds all cinema_city_film_ids that appear on multiple movies
  2. For each duplicate group, keeps the OLDEST movie's film_id (first created)
  3. Removes cinema_city_film_id from the NEWER movies

  The affected movies will get correctly re-matched on the next scraper run.
  """

  use Mix.Task
  require Logger

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie

  @shortdoc "Fix duplicate cinema_city_film_id entries in movies"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    apply_changes = "--apply" in args

    Logger.info("🔍 Scanning for duplicate cinema_city_film_id entries...")

    # Find all duplicate film_ids
    duplicates = find_duplicate_film_ids()

    if Enum.empty?(duplicates) do
      Logger.info("✅ No duplicates found! Database is clean.")
    else
      Logger.info("Found #{length(duplicates)} duplicate cinema_city_film_id values")

      # Get movies to fix (the newer ones in each duplicate group)
      movies_to_fix = find_movies_to_fix(duplicates)

      Logger.info("📋 Movies that need cinema_city_film_id removed:")
      Logger.info("")

      for movie <- movies_to_fix do
        Logger.info(
          "  ID: #{movie.id} | #{movie.title} | TMDB: #{movie.tmdb_id} | film_id: #{movie.cc_film_id}"
        )
      end

      Logger.info("")
      Logger.info("Total: #{length(movies_to_fix)} movies to fix")

      if apply_changes do
        Logger.info("")
        Logger.info("🔧 Applying fixes...")

        results =
          Enum.map(movies_to_fix, fn movie_info ->
            fix_movie(movie_info.id)
          end)

        success_count = Enum.count(results, &(&1 == :ok))
        error_count = Enum.count(results, &(&1 == :error))

        Logger.info("")
        Logger.info("✅ Fixed: #{success_count}")

        if error_count > 0 do
          Logger.error("❌ Errors: #{error_count}")
        end
      else
        Logger.info("")
        Logger.info("ℹ️  Dry run - no changes made")
        Logger.info("   Run with --apply to fix these entries")
      end
    end
  end

  defp find_duplicate_film_ids do
    # Raw SQL to find film_ids with multiple movies
    query = """
    SELECT metadata->>'cinema_city_film_id' as film_id, COUNT(*) as cnt
    FROM movies
    WHERE metadata->>'cinema_city_film_id' IS NOT NULL
    GROUP BY metadata->>'cinema_city_film_id'
    HAVING COUNT(*) > 1
    """

    case Repo.query(query) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [film_id, _count] -> film_id end)

      {:error, error} ->
        Logger.error("Failed to query duplicates: #{inspect(error)}")
        []
    end
  end

  defp find_movies_to_fix(duplicate_film_ids) do
    # For each duplicate film_id, find movies and return all except the oldest
    Enum.flat_map(duplicate_film_ids, fn film_id ->
      query =
        from(m in Movie,
          where: fragment("?->>'cinema_city_film_id' = ?", m.metadata, ^film_id),
          order_by: [asc: m.inserted_at],
          select: %{
            id: m.id,
            title: m.title,
            tmdb_id: m.tmdb_id,
            inserted_at: m.inserted_at,
            cc_film_id: fragment("?->>'cinema_city_film_id'", m.metadata)
          }
        )

      movies = Repo.all(query)

      # Skip the first one (oldest = correct), return the rest
      case movies do
        [_oldest | rest] -> rest
        _ -> []
      end
    end)
  end

  defp fix_movie(movie_id) do
    movie = Repo.get!(Movie, movie_id)
    current_metadata = movie.metadata || %{}

    # Remove cinema_city_film_id and cinema_city_source_id
    updated_metadata =
      current_metadata
      |> Map.delete("cinema_city_film_id")
      |> Map.delete("cinema_city_source_id")

    changeset = Movie.changeset(movie, %{metadata: updated_metadata})

    case Repo.update(changeset) do
      {:ok, _updated} ->
        Logger.info("  ✅ Fixed movie #{movie_id}: #{movie.title}")
        :ok

      {:error, changeset} ->
        Logger.error("  ❌ Failed to fix movie #{movie_id}: #{inspect(changeset.errors)}")
        :error
    end
  end
end
