defmodule EventasaurusApp.ReleaseTasks do
  @moduledoc """
  Tasks that can be run in production releases via `bin/eventasaurus eval`.

  Mix tasks are not available in releases, so we need standalone modules.

  ## Usage

      # Enqueue timezone jobs for cities missing timezone
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.enqueue_timezone_jobs()"

      # Force enqueue for ALL cities (even those with timezone set)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.enqueue_timezone_jobs(true)"

      # Fix duplicate cinema_city_film_ids (dry run)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates()"

      # Fix duplicate cinema_city_film_ids (apply changes)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates(true)"
  """

  require Logger
  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City

  @doc """
  Enqueue Oban jobs to populate timezone for cities.

  Jobs run in the background and use TzWorld to determine timezone from coordinates,
  with country-level fallback for cities without coordinates.

  See Issue #3334 for full analysis.

  ## Arguments

    - `force` - When true, enqueues jobs for ALL cities (even those with timezone set)

  ## Examples

      # Enqueue for cities missing timezone
      EventasaurusApp.ReleaseTasks.enqueue_timezone_jobs()

      # Force enqueue for ALL cities
      EventasaurusApp.ReleaseTasks.enqueue_timezone_jobs(true)
  """
  def enqueue_timezone_jobs(force \\ false) do
    start_app()

    alias EventasaurusApp.Workers.PopulateCityTimezoneJob

    # Get city IDs
    id_query =
      if force do
        from(c in City, select: c.id, order_by: [asc: c.id])
      else
        from(c in City, where: is_nil(c.timezone), select: c.id, order_by: [asc: c.id])
      end

    city_ids = Repo.all(id_query, timeout: 60_000)

    if Enum.empty?(city_ids) do
      IO.puts("✅ All cities already have timezones populated!")
    else
      IO.puts("🌍 Enqueuing timezone jobs for #{length(city_ids)} cities...")

      # Enqueue jobs in batches
      city_ids
      |> Enum.chunk_every(100)
      |> Enum.with_index(1)
      |> Enum.each(fn {batch_ids, _batch_num} ->
        jobs =
          Enum.map(batch_ids, fn city_id ->
            PopulateCityTimezoneJob.new(%{city_id: city_id})
          end)

        Oban.insert_all(jobs)
        IO.write(".")
      end)

      IO.puts("")
      IO.puts("✅ Enqueued #{length(city_ids)} jobs. They will process in the background.")
      IO.puts("   Monitor progress in the Oban dashboard or logs.")
    end

    :ok
  end

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
