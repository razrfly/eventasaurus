defmodule EventasaurusApp.ReleaseTasks do
  @moduledoc """
  Tasks that can be run in production releases via `bin/eventasaurus eval`.

  Mix tasks are not available in releases, so we need standalone modules.

  ## Usage

      # Fix duplicate cinema_city_film_ids (dry run)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates()"

      # Fix duplicate cinema_city_film_ids (apply changes)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_cinema_city_duplicates(true)"

      # Fix orphaned events (dry run)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_orphan_events()"

      # Fix orphaned events (apply changes)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.fix_orphan_events(true)"
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

  @doc """
  Fix orphaned events - events in public_events with no public_event_sources record.

  These orphans are created when the Ecto.Multi transaction partially fails.
  See GitHub issue #2897 for root cause analysis.

  ## Usage

      # Dry run
      fix_orphan_events()

      # Apply changes
      fix_orphan_events(true)
  """
  def fix_orphan_events(apply_changes \\ false) do
    start_app()

    IO.puts("🔍 Scanning for orphaned events (events without source records)...")

    orphans = find_orphan_events()

    if Enum.empty?(orphans) do
      IO.puts("✅ No orphans found! Database is clean.")
    else
      IO.puts("Found #{length(orphans)} orphaned events")
      IO.puts("")

      # Group by likely source
      by_source = group_orphans_by_source(orphans)

      IO.puts("📊 Breakdown by likely source:")

      for {source, events} <- Enum.sort_by(by_source, fn {_, e} -> -length(e) end) do
        IO.puts("  #{source}: #{length(events)}")
      end

      IO.puts("")

      if apply_changes do
        IO.puts("🗑️  Deleting #{length(orphans)} orphan events...")

        {deleted, errors} = delete_orphan_events(orphans)

        IO.puts("")
        IO.puts("✅ Deleted: #{deleted}")

        if errors > 0 do
          IO.puts("❌ Errors: #{errors}")
        end
      else
        IO.puts("ℹ️  Dry run - no changes made")
        IO.puts("   Run with: fix_orphan_events(true) to apply")
      end
    end

    :ok
  end

  defp find_orphan_events do
    alias EventasaurusApp.Repo

    query = """
    SELECT
      pe.id,
      pe.title,
      pe.starts_at,
      pe.venue_id,
      v.name as venue_name
    FROM public_events pe
    LEFT JOIN public_event_sources pes ON pe.id = pes.event_id
    LEFT JOIN venues v ON pe.venue_id = v.id
    WHERE pes.id IS NULL
    ORDER BY pe.inserted_at DESC
    """

    case Repo.query(query) do
      {:ok, %{rows: rows, columns: columns}} ->
        columns = Enum.map(columns, &String.to_atom/1)
        Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)

      {:error, error} ->
        IO.puts("Failed to query orphans: #{inspect(error)}")
        []
    end
  end

  defp group_orphans_by_source(orphans) do
    Enum.group_by(orphans, fn orphan ->
      title = orphan.title || ""

      cond do
        String.contains?(title, "Cinema City") -> "Cinema City"
        String.contains?(title, "Ifn") or String.contains?(title, "IFN") -> "IFN/Repertuary"
        String.contains?(title, "Kijow") -> "Kino Krakow"
        String.contains?(String.downcase(title), "quiz") -> "PubQuiz/Inquizition"
        true -> "Other"
      end
    end)
  end

  defp delete_orphan_events(orphans) do
    import Ecto.Query

    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.PublicEvents.PublicEvent

    orphan_ids = Enum.map(orphans, & &1.id)

    # Delete in batches of 100
    orphan_ids
    |> Enum.chunk_every(100)
    |> Enum.reduce({0, 0}, fn batch, {deleted, errors} ->
      query = from(pe in PublicEvent, where: pe.id in ^batch)

      case Repo.delete_all(query) do
        {count, _} ->
          IO.puts("  Deleted batch of #{count} events")
          {deleted + count, errors}

        {:error, reason} ->
          IO.puts("  Failed to delete batch: #{inspect(reason)}")
          {deleted, errors + length(batch)}
      end
    end)
  end
end
