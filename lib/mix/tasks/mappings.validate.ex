defmodule Mix.Tasks.Mappings.Validate do
  @moduledoc """
  Validates that YAML and DB mapping backends produce identical results.

  This task runs the same category lookups through both backends and
  reports any mismatches. Use this to ensure 100% parity before enabling
  the DB backend in production.

  ## Usage

      mix mappings.validate
      mix mappings.validate --limit 1000
      mix mappings.validate --source bandsintown

  ## Options

      --limit N        Number of events to sample (default: 1000)
      --source NAME    Only test specific source
      --verbose        Show detailed mismatch output
      --sample FILE    Use sample file instead of database
  """

  use Mix.Task
  require Logger
  import Ecto.Query, warn: false

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.CategoryMapper
  alias EventasaurusDiscovery.Categories.CategoryMappings

  @shortdoc "Validate YAML and DB mapping parity"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [limit: :integer, source: :string, verbose: :boolean, sample: :string],
        aliases: [l: :limit, s: :source, v: :verbose]
      )

    limit = Keyword.get(opts, :limit, 1000)
    source_filter = Keyword.get(opts, :source)
    verbose? = Keyword.get(opts, :verbose, false)

    # Start application
    Mix.Task.run("app.start")

    IO.puts("\n#{IO.ANSI.cyan()}🔍 Category Mapping Parity Validation#{IO.ANSI.reset()}")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

    # Build category lookup (shared by both backends)
    category_lookup = build_category_lookup()
    IO.puts("  Categories loaded: #{map_size(category_lookup)}")

    # Ensure ETS cache is warmed for DB backend
    IO.puts("  Warming ETS cache...")
    CategoryMappings.refresh_cache()

    # Get test cases
    test_cases = get_test_cases(limit, source_filter)
    IO.puts("  Test cases: #{length(test_cases)}\n")

    if test_cases == [] do
      IO.puts("#{IO.ANSI.yellow()}⚠️  No test cases found. Run with real event data.#{IO.ANSI.reset()}\n")
      :ok
    else
      # Run validation
      results = validate_parity(test_cases, category_lookup, verbose?)

      # Print results
      print_results(results)

      # Exit with error code if mismatches
      if results.mismatches > 0 do
        IO.puts("#{IO.ANSI.red()}❌ PARITY CHECK FAILED#{IO.ANSI.reset()}\n")
        exit({:shutdown, 1})
      else
        IO.puts("#{IO.ANSI.green()}✅ PARITY CHECK PASSED#{IO.ANSI.reset()}\n")
        :ok
      end
    end
  end

  defp build_category_lookup do
    Repo.all(
      from(c in EventasaurusDiscovery.Categories.Category,
        select: {c.slug, {c.id, c.is_active}}
      )
    )
    |> Map.new()
  end

  defp get_test_cases(limit, source_filter) do
    # Get real event source categories from the database
    query =
      from(pe in "public_events",
        join: esc in "event_source_categories", on: esc.event_id == pe.id,
        select: %{
          source: esc.source,
          categories: esc.source_categories
        },
        where: not is_nil(esc.source_categories),
        where: fragment("array_length(?, 1) > 0", esc.source_categories),
        limit: ^limit
      )

    query =
      if source_filter do
        from([pe, esc] in query, where: esc.source == ^source_filter)
      else
        query
      end

    Repo.all(query)
  rescue
    e in [Ecto.QueryError, Postgrex.Error, DBConnection.ConnectionError] ->
      # Table might not exist or have different schema
      Logger.debug("Falling back to synthetic test cases: #{inspect(e.__struct__)}")
      get_synthetic_test_cases(limit, source_filter)
  end

  defp get_synthetic_test_cases(limit, source_filter) do
    # Generate synthetic test cases from known mappings
    test_terms = %{
      "bandsintown" => ["Rock", "Jazz", "Pop", "Electronic", "Hip-Hop", "R&B", "Country", "Folk", "Classical", "Metal"],
      "ticketmaster" => ["MUSIC", "SPORTS", "ARTS & THEATRE", "COMEDY", "FAMILY", "UNDEFINED"],
      "karnet" => ["koncerty", "wystawy", "teatr", "kino", "muzyka", "sport", "festiwale"],
      "cinema_city" => ["Action", "Comedy", "Drama", "Horror", "Thriller", "Animation", "Documentary"],
      "sortiraparis" => ["concerts-music-festival", "exhibit-museum", "theatre-show", "cinema"],
      "waw4free" => ["koncert", "wystawa", "teatr", "film", "festiwal"],
      "week_pl" => ["muzyka", "sztuka", "teatr", "sport", "rozrywka"],
      "_defaults" => ["concert", "theatre", "sports", "food", "festival", "comedy", "art", "film"]
    }

    sources =
      if source_filter do
        [source_filter]
      else
        Map.keys(test_terms)
      end

    cases =
      for source <- sources,
          terms = Map.get(test_terms, source, []),
          term <- terms do
        %{source: source, categories: [term]}
      end

    Enum.take(cases, limit)
  end

  defp validate_parity(test_cases, category_lookup, verbose?) do
    {matches, mismatches_list} =
      test_cases
      |> Enum.reduce({0, []}, fn %{source: source, categories: cats}, {match_count, mismatches} ->
        # Get YAML result
        yaml_result = run_with_backend(:yaml, source, cats, category_lookup)

        # Get DB result
        db_result = run_with_backend(:db, source, cats, category_lookup)

        # Compare (normalize order for comparison)
        yaml_ids = yaml_result |> Enum.map(&elem(&1, 0)) |> Enum.sort()
        db_ids = db_result |> Enum.map(&elem(&1, 0)) |> Enum.sort()

        if yaml_ids == db_ids do
          {match_count + 1, mismatches}
        else
          mismatch = %{
            source: source,
            categories: cats,
            yaml_result: yaml_ids,
            db_result: db_ids
          }

          if verbose? do
            IO.puts("#{IO.ANSI.yellow()}MISMATCH:#{IO.ANSI.reset()}")
            IO.puts("  Source: #{source}")
            IO.puts("  Input: #{inspect(cats)}")
            IO.puts("  YAML: #{inspect(yaml_ids)}")
            IO.puts("  DB:   #{inspect(db_ids)}")
          end

          {match_count, [mismatch | mismatches]}
        end
      end)

    %{
      total: length(test_cases),
      matches: matches,
      mismatches: length(mismatches_list),
      mismatches_list: Enum.reverse(mismatches_list),
      parity_percent: if(length(test_cases) > 0, do: matches / length(test_cases) * 100, else: 100.0)
    }
  end

  defp run_with_backend(backend, source, categories, category_lookup) do
    # Save current config
    original = Application.get_env(:eventasaurus, :discovery)[:use_db_mappings] || false
    current_config = Application.get_env(:eventasaurus, :discovery) || []

    # Set backend
    case backend do
      :yaml ->
        Application.put_env(:eventasaurus, :discovery, Keyword.put(current_config, :use_db_mappings, false))

      :db ->
        Application.put_env(:eventasaurus, :discovery, Keyword.put(current_config, :use_db_mappings, true))
    end

    # Run mapping
    result = CategoryMapper.map_categories(source, categories, category_lookup)

    # Restore config
    restored_config = Application.get_env(:eventasaurus, :discovery) || []
    Application.put_env(:eventasaurus, :discovery, Keyword.put(restored_config, :use_db_mappings, original))

    result
  end

  defp print_results(results) do
    IO.puts("#{IO.ANSI.bright()}📊 Validation Results#{IO.ANSI.reset()}")
    IO.puts("───────────────────────────────────────────────────────────")
    IO.puts("  Total test cases: #{results.total}")
    IO.puts("  Matches:          #{results.matches}")
    IO.puts("  Mismatches:       #{results.mismatches}")
    IO.puts("  Parity:           #{:erlang.float_to_binary(results.parity_percent, decimals: 2)}%")
    IO.puts("───────────────────────────────────────────────────────────\n")

    if results.mismatches > 0 && results.mismatches <= 10 do
      IO.puts("#{IO.ANSI.yellow()}Mismatched cases (first 10):#{IO.ANSI.reset()}")

      results.mismatches_list
      |> Enum.take(10)
      |> Enum.each(fn m ->
        IO.puts("  #{m.source}: #{inspect(m.categories)}")
        IO.puts("    YAML: #{inspect(m.yaml_result)}")
        IO.puts("    DB:   #{inspect(m.db_result)}")
      end)

      IO.puts("")
    end
  end
end
