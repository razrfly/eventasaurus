defmodule EventasaurusDiscovery.Monitoring.Compare do
  @moduledoc """
  Programmatic API for comparing scraper performance baselines.

  Compares two baseline snapshots to measure improvements or regressions
  in scraper performance over time.

  ## Examples

      # Compare two baselines by file path
      {:ok, comparison} = Compare.from_files(before_path, after_path)

      # Compare two baseline maps
      comparison = Compare.baselines(before_baseline, after_baseline)

      # Get improvement summary
      summary = Compare.summary(comparison)

      # Check if performance improved
      improved? = Compare.improved?(comparison)
  """

  @doc """
  Compares two baseline files.

  ## Examples

      {:ok, comparison} = Compare.from_files(
        ".taskmaster/baselines/cinema_city_20241122.json",
        ".taskmaster/baselines/cinema_city_20241123.json"
      )
  """
  def from_files(before_path, after_path) do
    with {:ok, before} <- EventasaurusDiscovery.Monitoring.Baseline.load(before_path),
         {:ok, after_baseline} <- EventasaurusDiscovery.Monitoring.Baseline.load(after_path) do
      comparison = baselines(before, after_baseline)
      {:ok, comparison}
    end
  end

  @doc """
  Compares two baseline maps.

  Returns a comparison map with:
    * `:source` - Source identifier
    * `:before` - Before baseline summary
    * `:after` - After baseline summary
    * `:changes` - Map of metric changes
    * `:improved` - Boolean indicating overall improvement
    * `:regressions` - List of regressed metrics

  ## Examples

      {:ok, before} = Baseline.create("cinema_city")
      # ... wait some time ...
      {:ok, after_baseline} = Baseline.create("cinema_city")
      comparison = Compare.baselines(before, after_baseline)
  """
  def baselines(before, after_baseline) do
    # Overall metrics comparison
    success_rate_change = after_baseline["success_rate"] - before["success_rate"]
    duration_change = after_baseline["avg_duration"] - before["avg_duration"]
    p95_change = after_baseline["p95"] - before["p95"]
    error_rate_before = (before["failed"] + before["cancelled"]) / before["sample_size"] * 100

    error_rate_after =
      (after_baseline["failed"] + after_baseline["cancelled"]) / after_baseline["sample_size"] *
        100

    error_rate_change = error_rate_after - error_rate_before

    # Determine improvement
    improved =
      success_rate_change > 0 or duration_change < 0 or p95_change < 0 or error_rate_change < 0

    # Identify regressions
    regressions =
      []
      |> maybe_add_regression(:success_rate, success_rate_change, fn change -> change < -1.0 end)
      |> maybe_add_regression(:avg_duration, duration_change, fn change -> change > 100 end)
      |> maybe_add_regression(:p95_duration, p95_change, fn change -> change > 200 end)
      |> maybe_add_regression(:error_rate, error_rate_change, fn change -> change > 1.0 end)

    # Job chain comparison
    before_chain = chain_map(before["chain_health"] || [])
    after_chain = chain_map(after_baseline["chain_health"] || [])

    all_jobs =
      (Map.keys(before_chain) ++ Map.keys(after_chain))
      |> Enum.uniq()
      |> Enum.sort()

    chain_changes =
      Map.new(all_jobs, fn job ->
        before_rate = Map.get(before_chain, job, 0)
        after_rate = Map.get(after_chain, job, 0)
        change = after_rate - before_rate
        {job, %{before: before_rate, after: after_rate, change: change}}
      end)

    # Error category comparison
    before_errors = error_map(before["error_categories"] || [])
    after_errors = error_map(after_baseline["error_categories"] || [])

    all_categories =
      (Map.keys(before_errors) ++ Map.keys(after_errors))
      |> Enum.uniq()
      |> Enum.sort()

    error_changes =
      Map.new(all_categories, fn category ->
        before_count = Map.get(before_errors, category, 0)
        after_count = Map.get(after_errors, category, 0)
        change = after_count - before_count
        {category, %{before: before_count, after: after_count, change: change}}
      end)

    %{
      source: before["source"],
      before: %{
        period_start: before["period_start"],
        period_end: before["period_end"],
        sample_size: before["sample_size"]
      },
      after: %{
        period_start: after_baseline["period_start"],
        period_end: after_baseline["period_end"],
        sample_size: after_baseline["sample_size"]
      },
      changes: %{
        success_rate: %{
          before: before["success_rate"],
          after: after_baseline["success_rate"],
          change: success_rate_change
        },
        avg_duration: %{
          before: before["avg_duration"],
          after: after_baseline["avg_duration"],
          change: duration_change
        },
        p95_duration: %{
          before: before["p95"],
          after: after_baseline["p95"],
          change: p95_change
        },
        error_rate: %{
          before: error_rate_before,
          after: error_rate_after,
          change: error_rate_change
        },
        chain: chain_changes,
        errors: error_changes
      },
      improved: improved,
      regressions: regressions
    }
  end

  @doc """
  Returns a summary of the comparison.

  ## Examples

      {:ok, comparison} = Compare.from_files(before_path, after_path)
      summary = Compare.summary(comparison)
      # => %{
      #   success_rate_change: 2.3,
      #   duration_improvement: -150.0,
      #   improved: true,
      #   regression_count: 0
      # }
  """
  def summary(comparison) do
    %{
      success_rate_change: comparison.changes.success_rate.change,
      avg_duration_change: comparison.changes.avg_duration.change,
      p95_duration_change: comparison.changes.p95_duration.change,
      error_rate_change: comparison.changes.error_rate.change,
      improved: comparison.improved,
      regression_count: length(comparison.regressions)
    }
  end

  @doc """
  Returns whether performance improved overall.

  ## Examples

      {:ok, comparison} = Compare.from_files(before_path, after_path)
      Compare.improved?(comparison)
      # => true
  """
  def improved?(comparison) do
    comparison.improved
  end

  @doc """
  Returns whether there are any regressions.

  ## Examples

      {:ok, comparison} = Compare.from_files(before_path, after_path)
      Compare.has_regressions?(comparison)
      # => false
  """
  def has_regressions?(comparison) do
    length(comparison.regressions) > 0
  end

  @doc """
  Returns jobs that improved in the comparison.

  ## Examples

      {:ok, comparison} = Compare.from_files(before_path, after_path)
      improved = Compare.improved_jobs(comparison)
      # => [{"MovieDetailJob", 5.2}, {"ShowtimeProcessJob", 3.1}]
  """
  def improved_jobs(comparison) do
    comparison.changes.chain
    |> Enum.filter(fn {_job, metrics} -> metrics.change > 0 end)
    |> Enum.map(fn {job, metrics} -> {job, metrics.change} end)
    |> Enum.sort_by(fn {_job, change} -> -change end)
  end

  @doc """
  Returns jobs that regressed in the comparison.

  ## Examples

      {:ok, comparison} = Compare.from_files(before_path, after_path)
      regressed = Compare.regressed_jobs(comparison)
      # => [{"CinemaDateJob", -2.5}]
  """
  def regressed_jobs(comparison) do
    comparison.changes.chain
    |> Enum.filter(fn {_job, metrics} -> metrics.change < 0 end)
    |> Enum.map(fn {job, metrics} -> {job, metrics.change} end)
    |> Enum.sort_by(fn {_job, change} -> change end)
  end

  # Private helpers

  defp chain_map(chain_health) do
    Map.new(chain_health, fn job ->
      {job["name"], job["success_rate"]}
    end)
  end

  defp error_map(error_categories) do
    Map.new(error_categories, fn {category, count} -> {category, count} end)
  end

  defp maybe_add_regression(list, metric, change, threshold_fn) do
    if threshold_fn.(change) do
      list ++ [metric]
    else
      list
    end
  end
end
