defmodule Mix.Tasks.Mappings.Validate do
  @moduledoc """
  Validates that database category mappings are working correctly.

  This task tests the category mapper with sample event data to ensure
  mappings are producing expected results from the database.

  ## Usage

      mix mappings.validate
      mix mappings.validate --limit 1000
      mix mappings.validate --source bandsintown

  ## Options

      --limit N        Number of events to sample (default: 1000)
      --source NAME    Only test specific source
      --verbose        Show detailed output
  """

  use Mix.Task
  require Logger
  import Ecto.Query, warn: false

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.CategoryMapper
  alias EventasaurusDiscovery.Categories.CategoryMappings

  @shortdoc "Validate category mappings are working"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [limit: :integer, source: :string, verbose: :boolean],
        aliases: [l: :limit, s: :source, v: :verbose]
      )

    limit = Keyword.get(opts, :limit, 1000)
    source_filter = Keyword.get(opts, :source)
    verbose? = Keyword.get(opts, :verbose, false)

    # Start application
    Mix.Task.run("app.start")

    IO.puts("\n#{IO.ANSI.cyan()}🔍 Category Mapping Validation#{IO.ANSI.reset()}")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

    # Build category lookup (shared by both backends)
    category_lookup = build_category_lookup()
    IO.puts("  Categories loaded: #{map_size(category_lookup)}")

    # Check ETS cache status
    IO.puts("  Checking ETS cache...")
    stats = CategoryMappings.get_stats()
    total_mappings = stats.total_direct + stats.total_patterns

    IO.puts(
      "  ETS cache: #{total_mappings} mappings (#{stats.total_direct} direct, #{stats.total_patterns} patterns)"
    )

    if total_mappings == 0 do
      IO.puts("\n#{IO.ANSI.red()}❌ ERROR: ETS cache is empty!#{IO.ANSI.reset()}")
      IO.puts("Run: EventasaurusDiscovery.Categories.CategoryMappings.refresh_cache()")
      exit({:shutdown, 1})
    end

    # Get test cases
    test_cases = get_test_cases(limit, source_filter)
    IO.puts("  Test cases: #{length(test_cases)}\n")

    test_cases =
      if test_cases == [] do
        IO.puts(
          "#{IO.ANSI.yellow()}⚠️  No test cases found. Using synthetic test data.#{IO.ANSI.reset()}\n"
        )

        get_synthetic_test_cases(limit, source_filter)
      else
        test_cases
      end

    # Run validation
    results = validate_mappings(test_cases, category_lookup, verbose?)

    # Print results
    print_results(results)

    # Exit with error code if too many failures
    if results.failure_rate > 50.0 do
      IO.puts("#{IO.ANSI.red()}❌ VALIDATION FAILED: High failure rate#{IO.ANSI.reset()}\n")
      exit({:shutdown, 1})
    else
      IO.puts("#{IO.ANSI.green()}✅ VALIDATION PASSED#{IO.ANSI.reset()}\n")
      :ok
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
        join: esc in "event_source_categories",
        on: esc.event_id == pe.id,
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
      "bandsintown" => [
        "Rock",
        "Jazz",
        "Pop",
        "Electronic",
        "Hip-Hop",
        "R&B",
        "Country",
        "Folk",
        "Classical",
        "Metal"
      ],
      "ticketmaster" => ["MUSIC", "SPORTS", "ARTS & THEATRE", "COMEDY", "FAMILY", "UNDEFINED"],
      "karnet" => ["koncerty", "wystawy", "teatr", "kino", "muzyka", "sport", "festiwale"],
      "cinema_city" => [
        "Action",
        "Comedy",
        "Drama",
        "Horror",
        "Thriller",
        "Animation",
        "Documentary"
      ],
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

  defp validate_mappings(test_cases, category_lookup, verbose?) do
    {successes, failures_list} =
      test_cases
      |> Enum.reduce({0, []}, fn %{source: source, categories: cats}, {success_count, failures} ->
        result = CategoryMapper.map_categories(source, cats, category_lookup)

        if result != [] do
          if verbose? do
            category_ids = Enum.map(result, &elem(&1, 0))

            IO.puts(
              "#{IO.ANSI.green()}✓#{IO.ANSI.reset()} #{source}: #{inspect(cats)} → #{inspect(category_ids)}"
            )
          end

          {success_count + 1, failures}
        else
          failure = %{source: source, categories: cats}

          if verbose? do
            IO.puts(
              "#{IO.ANSI.yellow()}○#{IO.ANSI.reset()} #{source}: #{inspect(cats)} → (no mapping)"
            )
          end

          {success_count, [failure | failures]}
        end
      end)

    total = length(test_cases)

    %{
      total: total,
      successes: successes,
      failures: length(failures_list),
      failures_list: Enum.reverse(failures_list),
      success_rate: if(total > 0, do: successes / total * 100, else: 100.0),
      failure_rate: if(total > 0, do: length(failures_list) / total * 100, else: 0.0)
    }
  end

  defp print_results(results) do
    IO.puts("\n#{IO.ANSI.bright()}📊 Validation Results#{IO.ANSI.reset()}")
    IO.puts("───────────────────────────────────────────────────────────")
    IO.puts("  Total test cases: #{results.total}")
    IO.puts("  Mapped:           #{results.successes}")
    IO.puts("  Unmapped:         #{results.failures}")
    IO.puts("  Success rate:     #{:erlang.float_to_binary(results.success_rate, decimals: 2)}%")
    IO.puts("───────────────────────────────────────────────────────────\n")

    if results.failures > 0 && results.failures <= 20 do
      IO.puts("#{IO.ANSI.yellow()}Unmapped categories (first 20):#{IO.ANSI.reset()}")

      results.failures_list
      |> Enum.take(20)
      |> Enum.each(fn f ->
        IO.puts("  #{f.source}: #{inspect(f.categories)}")
      end)

      IO.puts("\nNote: Some unmapped categories are expected (source-specific terms)")
      IO.puts("      Add mappings via /admin/category-mappings if needed\n")
    end
  end
end
