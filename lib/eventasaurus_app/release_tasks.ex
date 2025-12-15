defmodule EventasaurusApp.ReleaseTasks do
  @moduledoc """
  Tasks that can be run in production releases via `bin/eventasaurus eval`.

  Mix tasks are not available in releases, so we need standalone modules.

  ## Usage

      # Fix duplicate cinema_city_film_ids (dry run)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates()"

      # Fix duplicate cinema_city_film_ids (apply changes)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates(true)"
  """

  require Logger

  def fix_cinema_city_duplicates(apply_changes \\ false) do
    # Start the repo
    start_app()

    IO.puts("🔍 Scanning for duplicate cinema_city_film_id entries...")

    # Find all duplicate film_ids
    duplicates = find_duplicate_film_ids()

    if Enum.empty?(duplicates) do
      IO.puts("✅ No duplicates found! Database is clean.")
    else
      IO.puts("Found #{length(duplicates)} duplicate cinema_city_film_id values")

      # Get movies to fix (the newer ones in each duplicate group)
      movies_to_fix = find_movies_to_fix(duplicates)

      IO.puts("")
      IO.puts("📋 Movies that need cinema_city_film_id removed:")
      IO.puts("")

      for movie <- movies_to_fix do
        IO.puts(
          "  ID: #{movie.id} | #{movie.title} | TMDB: #{movie.tmdb_id} | film_id: #{movie.cc_film_id}"
        )
      end

      IO.puts("")
      IO.puts("Total: #{length(movies_to_fix)} movies to fix")

      if apply_changes do
        IO.puts("")
        IO.puts("🔧 Applying fixes...")

        results =
          Enum.map(movies_to_fix, fn movie_info ->
            fix_movie(movie_info.id)
          end)

        success_count = Enum.count(results, &(&1 == :ok))
        error_count = Enum.count(results, &(&1 == :error))

        IO.puts("")
        IO.puts("✅ Fixed: #{success_count}")

        if error_count > 0 do
          IO.puts("❌ Errors: #{error_count}")
        end
      else
        IO.puts("")
        IO.puts("ℹ️  Dry run - no changes made")
        IO.puts("   Run with: fix_cinema_city_duplicates(true) to apply")
      end
    end

    :ok
  end

  defp start_app do
    Application.ensure_all_started(:eventasaurus)
  end

  defp find_duplicate_film_ids do
    import Ecto.Query

    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Movies.Movie

    # Find film_ids that appear on multiple movies
    query =
      from(m in Movie,
        where: not is_nil(fragment("?->>'cinema_city_film_id'", m.metadata)),
        group_by: fragment("?->>'cinema_city_film_id'", m.metadata),
        having: count(m.id) > 1,
        select: fragment("?->>'cinema_city_film_id'", m.metadata)
      )

    Repo.all(query)
  end

  defp find_movies_to_fix(duplicate_film_ids) do
    import Ecto.Query

    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Movies.Movie

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
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Movies.Movie

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
        IO.puts("  ✅ Fixed movie #{movie_id}: #{movie.title}")
        :ok

      {:error, changeset} ->
        IO.puts("  ❌ Failed to fix movie #{movie_id}: #{inspect(changeset.errors)}")
        :error
    end
  end
end
