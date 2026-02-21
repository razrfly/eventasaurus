defmodule EventasaurusApp.ReleaseTasks do
  @moduledoc """
  Tasks that can be run in production releases via `bin/eventasaurus eval`.

  Mix tasks are not available in releases, so we need standalone modules.

  ## Usage

      # Migrate YAML category mappings to database
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.migrate_yaml_mappings()"

      # Dry run - show what would be migrated
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.migrate_yaml_mappings(true)"

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
  Re-import category mappings from archived YAML files to the database.

  NOTE: As of Phase 2.3 (Issue #3469), YAML files have been archived to
  `priv/category_mappings_archived/`. The database is now the authoritative
  source for category mappings. This task is for emergency recovery only.

  For normal operations, use the admin UI at `/admin/category-mappings`.

  ## Usage

      # Clear and re-import all archived YAML mappings (EMERGENCY RECOVERY)
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.migrate_yaml_mappings()"

      # Dry run - show what would be imported
      bin/eventasaurus eval "EventasaurusApp.ReleaseTasks.migrate_yaml_mappings(true)"
  """
  @spec migrate_yaml_mappings(boolean()) :: :ok | {:error, :no_yaml_files}
  def migrate_yaml_mappings(dry_run \\ false) do
    start_app()

    alias EventasaurusDiscovery.Categories.CategoryMappings
    alias EventasaurusDiscovery.Categories.CategoryMapping

    IO.puts("\n📦 YAML to Database Migration (from archived files)")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

    IO.puts("⚠️  Note: YAML files are archived. Database is the authoritative source.")
    IO.puts("   Use /admin/category-mappings for normal operations.\n")

    if dry_run do
      IO.puts("🔍 DRY RUN MODE - No changes will be made\n")
    end

    # Load YAML files
    yaml_files = load_yaml_files()

    if Enum.empty?(yaml_files) do
      IO.puts("⚠️  No YAML files found")
      {:error, :no_yaml_files}
    else
      IO.puts("Found #{length(yaml_files)} YAML files to process\n")

      unless dry_run do
        # Clear all existing mappings
        IO.puts("🗑️  Clearing ALL existing mappings...")
        {count, _} = Repo.delete_all(CategoryMapping)
        IO.puts("   Cleared #{count} total mappings\n")
      end

      # Process each file
      results =
        Enum.map(yaml_files, fn {source, file_path} ->
          process_yaml_file(source, file_path, dry_run)
        end)

      # Print summary
      print_migration_summary(results, dry_run)

      # Refresh ETS cache after migration
      unless dry_run do
        IO.puts("🔄 Refreshing ETS cache...")
        CategoryMappings.refresh_cache()
        IO.puts("✅ ETS cache refreshed\n")
      end

      :ok
    end
  end

  defp load_yaml_files do
    priv_dir = :code.priv_dir(:eventasaurus)
    # Read from archived YAML files (archived in Phase 2.3, Issue #3469)
    config_path = Path.join(priv_dir, "category_mappings_archived")

    if File.dir?(config_path) do
      config_path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".yml"))
      |> Enum.map(fn file ->
        source_key =
          case file do
            "_defaults.yml" -> "_defaults"
            other -> Path.basename(other, ".yml")
          end

        {source_key, Path.join(config_path, file)}
      end)
      |> Enum.sort_by(fn {source, _} ->
        # Process _defaults first
        if source == "_defaults", do: "", else: source
      end)
    else
      []
    end
  end

  defp process_yaml_file(source, file_path, dry_run) do
    alias EventasaurusDiscovery.Categories.CategoryMappings

    IO.puts("📁 Processing: #{source}")
    IO.puts("   File: #{file_path}")

    case YamlElixir.read_from_file(file_path) do
      {:ok, %{"mappings" => mappings} = data} ->
        patterns = data["patterns"] || []

        # Build mapping attributes
        direct_attrs = build_yaml_direct_attrs(source, mappings)
        pattern_attrs = build_yaml_pattern_attrs(source, patterns)
        all_attrs = direct_attrs ++ pattern_attrs

        result =
          if dry_run do
            %{
              source: source,
              direct: length(direct_attrs),
              patterns: length(pattern_attrs),
              status: :dry_run
            }
          else
            # import_mappings/1 always returns {:ok, results} - errors are collected in the errors list
            {:ok, import_result} = CategoryMappings.import_mappings(all_attrs)

            %{
              source: source,
              direct: length(direct_attrs),
              patterns: length(pattern_attrs),
              imported: import_result.inserted,
              errors: import_result.errors,
              status: if(Enum.empty?(import_result.errors), do: :success, else: :partial)
            }
          end

        status_icon =
          case result.status do
            :dry_run -> "📋"
            :success -> "✅"
            :partial -> "⚠️"
          end

        imported_msg = if result[:imported], do: ", Imported: #{result.imported}", else: ""

        IO.puts(
          "   #{status_icon} Direct: #{result.direct}, Patterns: #{result.patterns}#{imported_msg}\n"
        )

        result

      {:ok, _} ->
        IO.puts("   ❌ Invalid YAML structure (missing 'mappings' key)\n")
        %{source: source, status: :error, error: "Invalid YAML structure"}

      {:error, reason} ->
        IO.puts("   ❌ Failed to read: #{inspect(reason)}\n")
        %{source: source, status: :error, error: reason}
    end
  end

  defp build_yaml_direct_attrs(source, mappings) when is_map(mappings) do
    Enum.map(mappings, fn {term, category_slug} ->
      %{
        source: source,
        external_term: String.downcase(to_string(term)),
        mapping_type: "direct",
        category_slug: to_string(category_slug),
        priority: 0,
        is_active: true,
        metadata: %{
          imported_from: "yaml",
          imported_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }
    end)
  end

  defp build_yaml_direct_attrs(_source, _), do: []

  defp build_yaml_pattern_attrs(source, patterns) when is_list(patterns) do
    patterns
    |> Enum.with_index()
    |> Enum.flat_map(fn {pattern, index} ->
      match_pattern = pattern["match"]
      categories = pattern["categories"] || []

      # Higher index = lower priority (first patterns in file are higher priority)
      priority = 100 - index

      Enum.map(categories, fn category_slug ->
        %{
          source: source,
          external_term: match_pattern,
          mapping_type: "pattern",
          category_slug: to_string(category_slug),
          priority: priority,
          is_active: true,
          metadata: %{
            imported_from: "yaml",
            imported_at: DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }
      end)
    end)
  end

  defp build_yaml_pattern_attrs(_source, _), do: []

  defp print_migration_summary(results, dry_run) do
    IO.puts("📊 Summary")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    successful = Enum.filter(results, &(&1.status in [:success, :dry_run]))
    partial = Enum.filter(results, &(&1.status == :partial))
    errors = Enum.filter(results, &(&1.status == :error))

    total_direct = Enum.map(successful ++ partial, & &1.direct) |> Enum.sum()
    total_patterns = Enum.map(successful ++ partial, & &1.patterns) |> Enum.sum()

    IO.puts("  Sources processed: #{length(results)}")
    IO.puts("  Successful: #{length(successful)}")

    if not Enum.empty?(partial) do
      IO.puts("  Partial (with errors): #{length(partial)}")
    end

    if not Enum.empty?(errors) do
      IO.puts("  Failed: #{length(errors)}")
    end

    IO.puts("")
    IO.puts("  Total mappings: #{total_direct + total_patterns}")
    IO.puts("    Direct: #{total_direct}")
    IO.puts("    Patterns: #{total_patterns}")

    if dry_run do
      IO.puts("\nRun without dry_run to import these mappings")
    else
      IO.puts("\n✅ Migration complete!")
    end

    IO.puts("")
  end

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
