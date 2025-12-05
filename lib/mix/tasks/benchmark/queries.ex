defmodule Mix.Tasks.Benchmark.Queries do
  @moduledoc """
  Run query performance benchmarks to track PlanetScale optimizations.

  ## Usage

      # Capture a new baseline (do this BEFORE deploying changes)
      mix benchmark.queries baseline

      # Run benchmark and compare to stored baseline (do this AFTER deploying)
      mix benchmark.queries report

      # Show PlanetScale baseline values (the original problem metrics)
      mix benchmark.queries planetscale

      # Quick status check
      mix benchmark.queries status

  ## Background

  This tracks the queries identified in PlanetScale insights (GitHub Issue #2537):

  1. public_events + sources JOIN with occurrences (33% runtime)
  2. cities unsplash_gallery (14.4% runtime)
  3. oban_jobs aggregation (7.48% runtime) - Fixed with replica routing
  4. venues metadata JOIN (5.58% runtime) - Fixed with partial index
  5. description translations (4.44% runtime)

  Run `mix benchmark.queries baseline` before changes, then
  `mix benchmark.queries report` after 1 hour to measure impact.
  """

  use Mix.Task

  @shortdoc "Run query performance benchmarks"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["baseline"] -> capture_baseline()
      ["report"] -> run_report()
      ["planetscale"] -> show_planetscale_baseline()
      ["status"] -> show_status()
      _ -> show_help()
    end
  end

  defp capture_baseline do
    IO.puts("\n📊 Capturing query performance baseline...\n")

    {:ok, baseline} = EventasaurusApp.Monitoring.QueryBenchmark.capture_baseline()

    IO.puts("✅ Baseline captured at #{baseline.captured_at}")
    IO.puts("\nEnvironment:")
    IO.puts("  Replica Routing: #{if baseline.environment.replica_enabled, do: "✅ Enabled", else: "❌ Disabled"}")

    baseline.environment.indexes_applied
    |> Enum.each(fn {index, applied} ->
      status = if applied, do: "✅", else: "❌"
      IO.puts("  #{index}: #{status}")
    end)

    IO.puts("\nMetrics captured for #{map_size(baseline.metrics)} queries.")
    IO.puts("\n💡 Run `mix benchmark.queries report` after 1 hour to compare results.")
  end

  defp run_report do
    IO.puts("\n📊 Running query performance benchmark report...\n")

    case EventasaurusApp.Monitoring.QueryBenchmark.run_benchmark_report() do
      {:ok, %{current: current, comparison: comparison}} ->
        IO.puts("\n═══════════════════════════════════════════════════════════════════")
        IO.puts("QUERY PERFORMANCE BENCHMARK REPORT")
        IO.puts("Captured: #{current.captured_at}")
        IO.puts("═══════════════════════════════════════════════════════════════════\n")

        IO.puts("Environment:")
        IO.puts("  Replica Routing: #{if current.environment.replica_enabled, do: "✅ Enabled", else: "❌ Disabled"}")

        current.environment.indexes_applied
        |> Enum.each(fn {index, applied} ->
          status = if applied, do: "✅", else: "❌"
          IO.puts("  #{index}: #{status}")
        end)

        IO.puts("\nQuery Metrics:")

        current.metrics
        |> Enum.each(fn {query_id, metric} ->
          IO.puts("\n  #{query_id}:")
          IO.puts("    Duration: #{Map.get(metric, :measured_duration_ms, "N/A")}ms")
          IO.puts("    Row Count: #{Map.get(metric, :row_count, "N/A")}")

          if Map.get(metric, :uses_replica) do
            IO.puts("    Uses Replica: ✅")
          end

          if note = Map.get(metric, :note) do
            IO.puts("    Note: #{note}")
          end
        end)

        if comparison do
          IO.puts("\n───────────────────────────────────────────────────────────────────")
          IO.puts("COMPARISON WITH BASELINE (#{comparison.baseline_captured_at})")
          IO.puts("───────────────────────────────────────────────────────────────────\n")

          comparison.comparisons
          |> Enum.each(fn {query_id, comp} ->
            status_icon =
              case comp.status do
                :improved -> "✅"
                :regressed -> "⚠️"
                :stable -> "➡️"
              end

            change =
              if comp.change_pct >= 0,
                do: "+#{comp.change_pct}%",
                else: "#{comp.change_pct}%"

            IO.puts("  #{query_id}: #{status_icon} #{change}")
            IO.puts("    Before: #{comp.baseline_duration_ms}ms → After: #{comp.current_duration_ms}ms")
          end)

          IO.puts("\nSummary:")
          IO.puts("  #{comparison.summary.improved_count}/#{comparison.summary.total} queries improved")
          IO.puts("  #{comparison.summary.regressed_count}/#{comparison.summary.total} queries regressed")
          IO.puts("  Overall: #{comparison.summary.overall_assessment}")
        else
          IO.puts("\n💡 No previous baseline found for comparison.")
          IO.puts("   Run `mix benchmark.queries baseline` first, wait 1 hour, then run report again.")
        end

    end
  end

  defp show_planetscale_baseline do
    IO.puts("\n📊 PlanetScale Baseline Values (Original Problem Metrics)")
    IO.puts("═══════════════════════════════════════════════════════════════════\n")

    IO.puts("These are the values from the original PlanetScale insights that we")
    IO.puts("are working to improve (GitHub Issue #2537):\n")

    EventasaurusApp.Monitoring.QueryBenchmark.planetscale_baseline()
    |> Enum.each(fn {query_id, metrics} ->
      IO.puts("#{query_id}:")
      IO.puts("  Runtime: #{metrics.runtime_pct}% of total")
      IO.puts("  P99 Latency: #{metrics.p99_ms}ms")
      IO.puts("  Rows Read: #{format_number(metrics.rows_read)}")
      IO.puts("  Rows Returned: #{format_number(metrics.rows_returned)}")
      IO.puts("  Notes: #{metrics.notes}")
      IO.puts("")
    end)

    IO.puts("───────────────────────────────────────────────────────────────────")
    IO.puts("Total runtime of tracked queries: ~65% of database load")
    IO.puts("───────────────────────────────────────────────────────────────────")
  end

  defp show_status do
    IO.puts("\n📊 Quick Status Check\n")

    case EventasaurusApp.Monitoring.QueryBenchmark.get_stored_baseline() do
      {:ok, baseline} ->
        IO.puts("✅ Baseline exists from: #{baseline.captured_at}")
        IO.puts("   Replica enabled: #{baseline.environment.replica_enabled}")

      {:error, :no_baseline} ->
        IO.puts("⚠️  No baseline captured yet")
        IO.puts("   Run `mix benchmark.queries baseline` to capture one")
    end

    # Quick check of current index status
    IO.puts("\nIndex Status:")

    check_index("idx_venues_with_metadata", "Venues metadata partial index")
    check_index("oban_jobs_state_queue_idx", "Oban state/queue index (should be REMOVED)")
  end

  defp check_index(index_name, description) do
    query = """
    SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = $1)
    """

    case EventasaurusApp.Repo.query(query, [index_name]) do
      {:ok, %{rows: [[true]]}} ->
        if String.contains?(description, "REMOVED") do
          IO.puts("  ⚠️  #{description}: EXISTS (migration not yet run)")
        else
          IO.puts("  ✅ #{description}: EXISTS")
        end

      {:ok, %{rows: [[false]]}} ->
        if String.contains?(description, "REMOVED") do
          IO.puts("  ✅ #{description}: REMOVED")
        else
          IO.puts("  ❌ #{description}: MISSING (migration not yet run)")
        end

      _ ->
        IO.puts("  ❓ #{description}: Unable to check")
    end
  end

  defp show_help do
    IO.puts(@moduledoc)
  end

  defp format_number(num) when is_number(num) do
    num
    |> round()
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end
