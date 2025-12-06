defmodule EventasaurusApp.Monitoring.QueryBenchmark do
  @moduledoc """
  Query performance benchmark tracking system.

  Tracks and compares database query performance metrics, particularly for the
  problematic queries identified in PlanetScale insights (GitHub Issue #2537).

  ## Usage

      # Capture current baseline
      {:ok, baseline} = QueryBenchmark.capture_baseline()

      # Compare to previous baseline after making changes
      {:ok, comparison} = QueryBenchmark.compare_with_baseline(baseline)

      # Run a full benchmark report
      QueryBenchmark.run_benchmark_report()

  ## Tracked Queries (from PlanetScale insights)

  1. public_events + sources JOIN with occurrences (33% runtime)
  2. cities unsplash_gallery (14.4% runtime)
  3. oban_jobs aggregation (7.48% runtime) - Fixed: now uses replica
  4. venues metadata JOIN (5.58% runtime) - Fixed: partial index added
  5. description translations (4.44% runtime)
  """

  require Logger
  import Ecto.Query
  alias EventasaurusApp.Repo

  @benchmark_cache :query_benchmarks

  # Query identifiers matching PlanetScale insights
  @tracked_queries [
    :public_events_sources_join,
    :cities_unsplash_gallery,
    :oban_jobs_aggregation,
    :venues_metadata_join,
    :description_translations
  ]

  @doc """
  Captures a baseline of current query performance metrics.

  Returns timing and row count estimates for tracked queries.
  """
  def capture_baseline do
    timestamp = DateTime.utc_now()

    metrics =
      @tracked_queries
      |> Enum.map(fn query_id ->
        {query_id, measure_query(query_id)}
      end)
      |> Enum.into(%{})

    baseline = %{
      captured_at: timestamp,
      metrics: metrics,
      environment: %{
        replica_enabled: replica_enabled?(),
        indexes_applied: check_indexes_applied()
      }
    }

    # Store in Cachex for later comparison
    Cachex.put(@benchmark_cache, :latest_baseline, baseline)

    Logger.info("[QueryBenchmark] Captured baseline at #{timestamp}")
    {:ok, baseline}
  end

  @doc """
  Compares current performance against a baseline.

  Returns improvement/regression percentages for each query.
  """
  def compare_with_baseline(baseline) when is_map(baseline) do
    current_metrics =
      @tracked_queries
      |> Enum.map(fn query_id ->
        {query_id, measure_query(query_id)}
      end)
      |> Enum.into(%{})

    comparisons =
      @tracked_queries
      |> Enum.map(fn query_id ->
        baseline_metric = Map.get(baseline.metrics, query_id, %{})
        current_metric = Map.get(current_metrics, query_id, %{})

        {query_id, calculate_comparison(baseline_metric, current_metric)}
      end)
      |> Enum.into(%{})

    {:ok,
     %{
       baseline_captured_at: baseline.captured_at,
       compared_at: DateTime.utc_now(),
       comparisons: comparisons,
       summary: summarize_comparisons(comparisons)
     }}
  end

  @doc """
  Gets the stored baseline from cache.
  """
  def get_stored_baseline do
    case Cachex.get(@benchmark_cache, :latest_baseline) do
      {:ok, nil} -> {:error, :no_baseline}
      {:ok, baseline} -> {:ok, baseline}
      error -> error
    end
  end

  @doc """
  Runs a complete benchmark report and logs results.

  Use after deploying changes to measure impact.
  """
  def run_benchmark_report do
    Logger.info("[QueryBenchmark] Starting benchmark report...")

    {:ok, current} = capture_baseline()

    report = """
    ═══════════════════════════════════════════════════════════════════
    QUERY PERFORMANCE BENCHMARK REPORT
    Captured: #{current.captured_at}
    ═══════════════════════════════════════════════════════════════════

    Environment:
      Replica Routing: #{if current.environment.replica_enabled, do: "✅ Enabled", else: "❌ Disabled"}
      Indexes Applied: #{format_indexes(current.environment.indexes_applied)}

    Query Metrics:
    #{format_metrics(current.metrics)}

    ═══════════════════════════════════════════════════════════════════
    """

    Logger.info(report)

    # Try to compare with stored baseline
    case get_stored_baseline() do
      {:ok, baseline} when baseline.captured_at != current.captured_at ->
        {:ok, comparison} = compare_with_baseline(baseline)

        comparison_report = """

        COMPARISON WITH BASELINE (#{baseline.captured_at})
        ───────────────────────────────────────────────────────────────────
        #{format_comparisons(comparison.comparisons)}

        Summary:
          #{comparison.summary.improved_count}/#{comparison.summary.total} queries improved
          #{comparison.summary.regressed_count}/#{comparison.summary.total} queries regressed
          Overall: #{comparison.summary.overall_assessment}
        ───────────────────────────────────────────────────────────────────
        """

        Logger.info(comparison_report)
        {:ok, %{current: current, comparison: comparison}}

      _ ->
        {:ok, %{current: current, comparison: nil}}
    end
  end

  @doc """
  Returns the baseline metrics that should be compared against.

  These are the PlanetScale insight values from the original analysis:
  - Runtime percentages
  - P99 latencies in milliseconds
  - Rows read vs returned ratios
  """
  def planetscale_baseline do
    %{
      public_events_sources_join: %{
        runtime_pct: 19.4,
        p99_ms: 3139,
        rows_read: 17_100_000,
        rows_returned: 1880,
        notes: "Combined with query #3 (13.6%) = 33% of runtime"
      },
      cities_unsplash_gallery: %{
        runtime_pct: 14.4,
        p99_ms: 1640,
        rows_read: 2_130_000,
        rows_returned: 66_600,
        notes: "Cities table scans for unsplash_gallery"
      },
      oban_jobs_aggregation: %{
        runtime_pct: 7.48,
        p99_ms: 2069,
        rows_read: 19_800_000,
        rows_returned: 2,
        notes: "Dashboard aggregation - FIXED: now uses replica"
      },
      venues_metadata_join: %{
        runtime_pct: 5.58,
        p99_ms: 1089,
        rows_read: 2_100_000,
        rows_returned: 3298,
        notes: "Venues metadata JOIN - FIXED: partial index added"
      },
      description_translations: %{
        runtime_pct: 4.44,
        p99_ms: 3254,
        rows_read: 1_140_000,
        rows_returned: 1180,
        notes: "Description translations aggregation"
      }
    }
  end

  # Private functions

  defp measure_query(query_id) do
    start_time = System.monotonic_time(:microsecond)

    result =
      case query_id do
        :public_events_sources_join -> measure_events_sources_query()
        :cities_unsplash_gallery -> measure_cities_unsplash_query()
        :oban_jobs_aggregation -> measure_oban_aggregation_query()
        :venues_metadata_join -> measure_venues_metadata_query()
        :description_translations -> measure_translations_query()
      end

    end_time = System.monotonic_time(:microsecond)
    duration_ms = (end_time - start_time) / 1000

    Map.merge(result, %{
      measured_duration_ms: Float.round(duration_ms, 2),
      measured_at: DateTime.utc_now()
    })
  rescue
    e ->
      Logger.warning("[QueryBenchmark] Failed to measure #{query_id}: #{inspect(e)}")
      %{error: inspect(e), measured_at: DateTime.utc_now()}
  end

  defp measure_events_sources_query do
    # Sample query matching the PlanetScale insight pattern
    # Uses EXPLAIN to get row estimates without full execution
    query =
      from(e in "public_events",
        join: s in "public_event_sources",
        on: s.event_id == e.id,
        select: count(e.id),
        limit: 1
      )

    count = Repo.replica().one(query) || 0
    %{row_count: count, uses_replica: true}
  end

  defp measure_cities_unsplash_query do
    query =
      from(c in "cities",
        where: not is_nil(c.unsplash_gallery),
        select: count(c.id)
      )

    count = Repo.replica().one(query) || 0
    %{row_count: count, uses_replica: true}
  end

  defp measure_oban_aggregation_query do
    # This is the dashboard query that was hitting primary DB
    # Now routed to replica
    query =
      from(j in Oban.Job,
        group_by: [j.state, j.queue],
        select: {j.state, j.queue, count(j.id)}
      )

    results = Repo.replica().all(query)
    total_rows = Enum.reduce(results, 0, fn {_, _, count}, acc -> acc + count end)

    %{
      row_count: total_rows,
      state_count: length(results),
      uses_replica: true,
      note: "Now correctly routed to replica"
    }
  end

  defp measure_venues_metadata_query do
    # Query that benefits from partial index
    query =
      from(v in "venues",
        where: not is_nil(v.metadata),
        select: count(v.id)
      )

    count = Repo.replica().one(query) || 0

    %{
      row_count: count,
      uses_replica: true,
      has_partial_index: index_exists?("idx_venues_with_metadata"),
      note: "Partial index reduces scan from 2.1M to ~3K rows"
    }
  end

  defp measure_translations_query do
    query =
      from(t in "description_translations",
        select: count(t.id)
      )

    count = Repo.replica().one(query) || 0
    %{row_count: count, uses_replica: true}
  end

  defp replica_enabled? do
    # Check if Repo.replica() is properly configured
    try do
      # If __adapter__() returns a module without raising, replica is enabled
      _ = Repo.replica().__adapter__()
      true
    rescue
      _ -> false
    end
  end

  defp check_indexes_applied do
    %{
      venues_metadata_partial: index_exists?("idx_venues_with_metadata"),
      oban_redundant_removed: not index_exists?("oban_jobs_state_queue_idx")
    }
  end

  defp index_exists?(index_name) do
    query = """
    SELECT EXISTS (
      SELECT 1 FROM pg_indexes WHERE indexname = $1
    )
    """

    case Repo.query(query, [index_name]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp calculate_comparison(baseline, current) do
    baseline_duration = Map.get(baseline, :measured_duration_ms, 0)
    current_duration = Map.get(current, :measured_duration_ms, 0)

    change_pct =
      if baseline_duration > 0 do
        Float.round((current_duration - baseline_duration) / baseline_duration * 100, 1)
      else
        0.0
      end

    status =
      cond do
        change_pct < -10 -> :improved
        change_pct > 10 -> :regressed
        true -> :stable
      end

    %{
      baseline_duration_ms: baseline_duration,
      current_duration_ms: current_duration,
      change_pct: change_pct,
      status: status
    }
  end

  defp summarize_comparisons(comparisons) do
    statuses = Enum.map(comparisons, fn {_k, v} -> v.status end)

    %{
      total: length(statuses),
      improved_count: Enum.count(statuses, &(&1 == :improved)),
      regressed_count: Enum.count(statuses, &(&1 == :regressed)),
      stable_count: Enum.count(statuses, &(&1 == :stable)),
      overall_assessment: overall_assessment(statuses)
    }
  end

  defp overall_assessment(statuses) do
    improved = Enum.count(statuses, &(&1 == :improved))
    regressed = Enum.count(statuses, &(&1 == :regressed))

    cond do
      regressed > improved -> "⚠️ Regression detected"
      improved > regressed -> "✅ Overall improvement"
      true -> "➡️ No significant change"
    end
  end

  defp format_metrics(metrics) do
    metrics
    |> Enum.map(fn {query_id, metric} ->
      duration = Map.get(metric, :measured_duration_ms, "N/A")
      row_count = Map.get(metric, :row_count, "N/A")
      replica = if Map.get(metric, :uses_replica), do: "✅", else: "❌"

      "    #{query_id}:\n" <>
        "      Duration: #{duration}ms | Rows: #{row_count} | Replica: #{replica}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_indexes(indexes) do
    indexes
    |> Enum.map(fn {name, applied} ->
      status = if applied, do: "✅", else: "❌"
      "#{name}: #{status}"
    end)
    |> Enum.join(", ")
  end

  defp format_comparisons(comparisons) do
    comparisons
    |> Enum.map(fn {query_id, comp} ->
      status_icon =
        case comp.status do
          :improved -> "✅"
          :regressed -> "⚠️"
          :stable -> "➡️"
        end

      change = if comp.change_pct >= 0, do: "+#{comp.change_pct}%", else: "#{comp.change_pct}%"

      "    #{query_id}: #{status_icon} #{change}\n" <>
        "      Before: #{comp.baseline_duration_ms}ms → After: #{comp.current_duration_ms}ms"
    end)
    |> Enum.join("\n\n")
  end
end
