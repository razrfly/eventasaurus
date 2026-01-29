defmodule Mix.Tasks.Benchmark.CategoryMapper do
  @moduledoc """
  Benchmark the category mapper to capture baseline metrics.

  This task measures:
  - Total mapping count (direct + patterns)
  - Lookup time for single and batch operations
  - "Other" category fallback rate

  ## Usage

      mix benchmark.category_mapper
      mix benchmark.category_mapper --iterations 100
      mix benchmark.category_mapper --save

  ## Options

      --iterations N   Number of iterations for timing (default: 50)
      --save           Save results to .taskmaster/baselines/ for comparison
      --verbose        Show detailed output
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Categories.CategoryMapper
  alias EventasaurusDiscovery.Categories.CategoryMappings

  @shortdoc "Benchmark category mapper performance"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [iterations: :integer, save: :boolean, verbose: :boolean],
        aliases: [i: :iterations, s: :save, v: :verbose]
      )

    iterations = Keyword.get(opts, :iterations, 50)
    save? = Keyword.get(opts, :save, false)
    verbose? = Keyword.get(opts, :verbose, false)

    # Start application for DB access
    Mix.Task.run("app.start")

    IO.puts("\n#{IO.ANSI.cyan()}📊 Category Mapper Benchmark#{IO.ANSI.reset()}")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("  Backend: #{IO.ANSI.bright()}DB+ETS#{IO.ANSI.reset()}")
    IO.puts("")

    # 1. Count mappings from database
    mapping_stats = count_db_mappings()
    print_mapping_stats(mapping_stats)

    # 2. Build category lookup
    category_lookup = build_category_lookup()

    if verbose? do
      IO.puts("\n#{IO.ANSI.yellow()}Categories loaded: #{map_size(category_lookup)}#{IO.ANSI.reset()}")
    end

    # 3. Benchmark lookup times
    timing_results = benchmark_lookups(category_lookup, iterations, verbose?)
    print_timing_results(timing_results)

    # 4. Calculate "Other" fallback rate
    other_rate = calculate_other_rate(category_lookup)
    print_other_rate(other_rate)

    # 5. Summary
    summary = build_summary(mapping_stats, timing_results, other_rate)
    print_summary(summary)

    # 6. Optionally save results
    if save? do
      save_baseline(summary)
    end

    :ok
  end

  # ============================================================================
  # Database Mapping Stats
  # ============================================================================

  defp count_db_mappings do
    stats = CategoryMappings.get_stats()

    %{
      total_direct: stats.total_direct,
      total_patterns: stats.total_patterns,
      by_source: stats.by_source
    }
  end

  defp print_mapping_stats(stats) do
    IO.puts("#{IO.ANSI.bright()}📁 DB+ETS Mapping Counts#{IO.ANSI.reset()}")
    IO.puts("───────────────────────────────────────────────────────────")

    stats.by_source
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.each(fn {source, %{direct: d, patterns: p}} ->
      IO.puts("  #{String.pad_trailing(source, 20)} Direct: #{String.pad_leading(to_string(d), 3)}  Patterns: #{String.pad_leading(to_string(p), 2)}")
    end)

    IO.puts("───────────────────────────────────────────────────────────")
    IO.puts(
      "  #{IO.ANSI.bright()}TOTAL#{IO.ANSI.reset()}                    Direct: #{String.pad_leading(to_string(stats.total_direct), 3)}  Patterns: #{String.pad_leading(to_string(stats.total_patterns), 2)}"
    )

    IO.puts("")
  end

  defp build_category_lookup do
    import Ecto.Query

    EventasaurusApp.Repo.all(
      from(c in EventasaurusDiscovery.Categories.Category,
        select: {c.slug, {c.id, c.is_active}}
      )
    )
    |> Map.new()
  end

  defp benchmark_lookups(category_lookup, iterations, verbose?) do
    # Test data - representative samples from different sources
    test_cases = [
      {"bandsintown", ["Rock", "Jazz", "Electronic"]},
      {"ticketmaster", ["MUSIC", "SPORTS", "ARTS & THEATRE"]},
      {"karnet", ["koncerty", "wystawy", "teatr"]},
      {"cinema_city", ["Action", "Comedy", "Drama"]},
      {"sortiraparis", ["concerts-music-festival", "exhibit-museum"]},
      {"_defaults", ["concert", "theatre", "sports", "food"]}
    ]

    if verbose? do
      IO.puts("\n#{IO.ANSI.yellow()}Running #{iterations} iterations per test case...#{IO.ANSI.reset()}")
    end

    # Warm up
    Enum.each(test_cases, fn {source, cats} ->
      CategoryMapper.map_categories(source, cats, category_lookup)
    end)

    # Single lookup benchmark
    single_times =
      Enum.flat_map(1..iterations, fn _ ->
        Enum.map(test_cases, fn {source, cats} ->
          {time, _result} =
            :timer.tc(fn ->
              CategoryMapper.map_categories(source, cats, category_lookup)
            end)

          time
        end)
      end)

    # Batch lookup benchmark (10 categories at once)
    batch_categories = Enum.flat_map(test_cases, fn {_, cats} -> cats end)

    batch_times =
      Enum.map(1..iterations, fn _ ->
        {time, _result} =
          :timer.tc(fn ->
            CategoryMapper.map_categories("_defaults", batch_categories, category_lookup)
          end)

        time
      end)

    %{
      single: calculate_stats(single_times),
      batch: calculate_stats(batch_times)
    }
  end

  defp calculate_stats(times) do
    sorted = Enum.sort(times)
    count = length(sorted)

    %{
      min: Enum.min(times),
      max: Enum.max(times),
      avg: Enum.sum(times) / count,
      p50: Enum.at(sorted, div(count, 2)),
      p95: Enum.at(sorted, round(count * 0.95) - 1),
      p99: Enum.at(sorted, round(count * 0.99) - 1)
    }
  end

  defp print_timing_results(results) do
    IO.puts("#{IO.ANSI.bright()}⏱️  Lookup Performance (microseconds)#{IO.ANSI.reset()}")
    IO.puts("───────────────────────────────────────────────────────────")

    IO.puts("  Single Lookup (3 categories):")
    print_stats(results.single)

    IO.puts("\n  Batch Lookup (18 categories):")
    print_stats(results.batch)

    IO.puts("")
  end

  defp print_stats(stats) do
    IO.puts("    Min: #{format_time(stats.min)}  Max: #{format_time(stats.max)}  Avg: #{format_time(stats.avg)}")
    IO.puts("    P50: #{format_time(stats.p50)}  P95: #{format_time(stats.p95)}  P99: #{format_time(stats.p99)}")
  end

  defp format_time(microseconds) do
    cond do
      microseconds < 1000 ->
        "#{String.pad_leading(to_string(round(microseconds)), 6)}µs"

      microseconds < 1_000_000 ->
        "#{String.pad_leading(:erlang.float_to_binary(microseconds / 1000, decimals: 1), 6)}ms"

      true ->
        "#{String.pad_leading(:erlang.float_to_binary(microseconds / 1_000_000, decimals: 2), 6)}s"
    end
  end

  defp calculate_other_rate(category_lookup) do
    # Get the "Other" category ID
    other_id =
      case Map.get(category_lookup, "other") do
        {id, true} -> id
        _ -> nil
      end

    if is_nil(other_id) do
      %{rate: 0.0, sample_size: 0, other_count: 0}
    else
      # Sample mappings from various sources with unmappable terms
      test_terms = [
        # Known mappable terms
        {"bandsintown", ["Rock", "Jazz", "Pop"]},
        {"karnet", ["koncerty", "teatr"]},
        {"ticketmaster", ["MUSIC", "SPORTS"]},
        # Unknown/unmappable terms
        {"bandsintown", ["xyzabc123", "totally_made_up"]},
        {"karnet", ["nieznana_kategoria", "cos_innego"]},
        {"unknown_source", ["random", "stuff", "here"]}
      ]

      results =
        Enum.flat_map(test_terms, fn {source, terms} ->
          Enum.map(terms, fn term ->
            result = CategoryMapper.map_categories(source, [term], category_lookup)

            case result do
              [] -> :unmapped
              [{^other_id, _}] -> :other
              _ -> :mapped
            end
          end)
        end)

      total = length(results)
      other_count = Enum.count(results, &(&1 == :other))
      unmapped_count = Enum.count(results, &(&1 == :unmapped))

      %{
        rate: if(total > 0, do: (other_count + unmapped_count) / total * 100, else: 0.0),
        sample_size: total,
        other_count: other_count,
        unmapped_count: unmapped_count
      }
    end
  end

  defp print_other_rate(stats) do
    IO.puts("#{IO.ANSI.bright()}🎯 Fallback Rate#{IO.ANSI.reset()}")
    IO.puts("───────────────────────────────────────────────────────────")
    IO.puts("  Sample size: #{stats.sample_size} terms")
    IO.puts("  \"Other\" fallbacks: #{stats.other_count}")
    IO.puts("  Unmapped (no match): #{stats[:unmapped_count] || 0}")
    IO.puts("  Fallback rate: #{:erlang.float_to_binary(stats.rate, decimals: 1)}%")
    IO.puts("")
  end

  defp build_summary(mapping_stats, timing_results, other_rate) do
    %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: "db",
      mappings: %{
        total_direct: mapping_stats.total_direct,
        total_patterns: mapping_stats.total_patterns,
        total: mapping_stats.total_direct + mapping_stats.total_patterns,
        by_source: mapping_stats.by_source
      },
      performance: %{
        single_lookup_avg_us: timing_results.single.avg,
        single_lookup_p95_us: timing_results.single.p95,
        batch_lookup_avg_us: timing_results.batch.avg,
        batch_lookup_p95_us: timing_results.batch.p95
      },
      quality: %{
        fallback_rate_percent: other_rate.rate,
        sample_size: other_rate.sample_size
      }
    }
  end

  defp print_summary(summary) do
    IO.puts("#{IO.ANSI.bright()}📋 Summary#{IO.ANSI.reset()}")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("  Total mappings: #{summary.mappings.total} (#{summary.mappings.total_direct} direct + #{summary.mappings.total_patterns} patterns)")
    IO.puts("  Avg single lookup: #{format_time(summary.performance.single_lookup_avg_us)}")
    IO.puts("  Fallback rate: #{:erlang.float_to_binary(summary.quality.fallback_rate_percent, decimals: 1)}%")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  end

  defp save_baseline(summary) do
    baselines_dir = Path.join([File.cwd!(), ".taskmaster", "baselines"])
    File.mkdir_p!(baselines_dir)

    date_str = Date.utc_today() |> Date.to_iso8601(:basic)
    filename = "category_mapper_db_#{date_str}.json"
    filepath = Path.join(baselines_dir, filename)

    json = Jason.encode!(summary, pretty: true)
    File.write!(filepath, json)

    IO.puts("#{IO.ANSI.green()}✅ Baseline saved to: #{filepath}#{IO.ANSI.reset()}\n")
  end
end
