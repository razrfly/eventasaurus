defmodule EventasaurusDiscovery.Monitoring.Health do
  @moduledoc """
  Programmatic API for scraper health monitoring and SLO tracking.

  Provides functions to check scraper health, monitor SLO compliance,
  and identify degrading performance before it becomes critical.

  ## Examples

      # Check health for a source
      {:ok, health} = Health.check("cinema_city", hours: 24)

      # Get overall health score
      score = Health.score(health)
      # => 95.2

      # Check if meeting SLOs
      meeting_slos? = Health.meeting_slos?(health)
      # => true

      # Get degraded workers
      degraded = Health.degraded_workers(health, threshold: 90.0)
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  import Ecto.Query

  # Legacy patterns kept for reference but no longer used - patterns are now generated dynamically
  # @source_patterns %{
  #   "cinema_city" => "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%",
  #   ...
  # }

  # SLO Targets (legacy - kept for backwards compatibility)
  @slo_success_rate 95.0
  @slo_p95_duration 3000.0

  # Z-score thresholds for relative performance assessment
  # Success rate: lower is worse (negative z-score = below average)
  @zscore_success_warning -1.0
  @zscore_success_critical -1.5
  # Duration: higher is worse (positive z-score = slower than average)
  @zscore_duration_warning 1.5
  @zscore_duration_critical 2.0

  @doc """
  Checks health for a given source over a time period.

  ## Options

    * `:hours` - Number of hours to look back (default: 24)
    * `:limit` - Maximum number of executions to analyze (default: 500)

  ## Examples

      {:ok, health} = Health.check("cinema_city", hours: 48)
      {:error, :unknown_source} = Health.check("invalid")
      {:error, :no_executions} = Health.check("cinema_city")  # when no data exists
  """
  def check(source, opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    limit = Keyword.get(opts, :limit, 500)

    case get_source_pattern(source) do
      {:ok, worker_pattern} ->
        from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)
        to_time = DateTime.utc_now()

        executions = fetch_executions(worker_pattern, from_time, to_time, limit)

        if Enum.empty?(executions) do
          {:error, :no_executions}
        else
          health_data = calculate_health(executions, source, hours)
          {:ok, health_data}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns the overall health score (0-100).

  The score is calculated based on:
    * Success rate (70% weight)
    * SLO compliance (30% weight)

  ## Examples

      {:ok, health} = Health.check("cinema_city")
      score = Health.score(health)
      # => 95.2
  """
  def score(health) do
    success_weight = 0.7
    slo_weight = 0.3

    success_score = health.success_rate
    slo_score = if health.meeting_slos, do: 100.0, else: health.success_rate * 0.8

    success_weight * success_score + slo_weight * slo_score
  end

  @doc """
  Returns whether the source is meeting its SLOs.

  SLOs:
    * Success rate >= 95%
    * P95 duration <= 3000ms

  ## Examples

      {:ok, health} = Health.check("cinema_city")
      Health.meeting_slos?(health)
      # => true
  """
  def meeting_slos?(health) do
    health.meeting_slos
  end

  # =============================================================================
  # Z-Score Based Relative Performance Assessment
  # =============================================================================

  @typedoc "Z-score classification status"
  @type zscore_status :: :normal | :warning | :critical

  @typedoc "Source z-score metrics"
  @type source_zscore :: %{
          source: String.t(),
          success_rate: float(),
          avg_duration: float(),
          success_zscore: float(),
          duration_zscore: float(),
          success_status: zscore_status(),
          duration_status: zscore_status(),
          overall_status: zscore_status()
        }

  @typedoc "Aggregate z-score stats across all sources"
  @type zscore_stats :: %{
          sources: [source_zscore()],
          success_mean: float(),
          success_stddev: float(),
          duration_mean: float(),
          duration_stddev: float(),
          normal_count: non_neg_integer(),
          warning_count: non_neg_integer(),
          critical_count: non_neg_integer()
        }

  @doc """
  Calculates z-score for a value given mean and standard deviation.

  Z-score = (value - mean) / stddev

  Returns 0.0 if stddev is 0 (all values are identical).

  ## Examples

      iex> Health.calculate_zscore(85.0, 75.0, 10.0)
      1.0

      iex> Health.calculate_zscore(65.0, 75.0, 10.0)
      -1.0
  """
  @spec calculate_zscore(number(), number(), number()) :: float()
  def calculate_zscore(_value, _mean, stddev) when stddev == 0, do: 0.0

  def calculate_zscore(value, mean, stddev) do
    Float.round((value - mean) / stddev, 2)
  end

  @doc """
  Classifies a z-score into :normal, :warning, or :critical status.

  For success rate (higher is better, so negative z-scores are bad):
    - z >= -1.0: normal
    - -1.5 <= z < -1.0: warning
    - z < -1.5: critical

  For duration (lower is better, so positive z-scores are bad):
    - z <= 1.5: normal
    - 1.5 < z <= 2.0: warning
    - z > 2.0: critical

  ## Examples

      iex> Health.classify_zscore(-0.5, :success)
      :normal

      iex> Health.classify_zscore(-1.2, :success)
      :warning

      iex> Health.classify_zscore(2.5, :duration)
      :critical
  """
  @spec classify_zscore(float(), :success | :duration) :: zscore_status()
  def classify_zscore(zscore, :success) do
    cond do
      zscore < @zscore_success_critical -> :critical
      zscore < @zscore_success_warning -> :warning
      true -> :normal
    end
  end

  def classify_zscore(zscore, :duration) do
    cond do
      zscore > @zscore_duration_critical -> :critical
      zscore > @zscore_duration_warning -> :warning
      true -> :normal
    end
  end

  @doc """
  Computes z-scores for all active sources based on their relative performance.

  Queries last 7 days of job execution data, calculates mean and standard deviation
  across all sources, then returns z-scores showing how each source compares to peers.

  ## Options

    * `:hours` - Number of hours to analyze (default: 168 = 7 days)

  ## Examples

      {:ok, stats} = Health.compute_source_zscores()
      # => %{
      #   sources: [
      #     %{source: "cinema_city", success_rate: 28.7, success_zscore: -1.71, ...},
      #     %{source: "karnet", success_rate: 98.3, success_zscore: 1.00, ...},
      #     ...
      #   ],
      #   success_mean: 72.6,
      #   success_stddev: 25.6,
      #   duration_mean: 16.9,
      #   duration_stddev: 29.9,
      #   normal_count: 5,
      #   warning_count: 1,
      #   critical_count: 1
      # }
  """
  @spec compute_source_zscores(keyword()) :: {:ok, zscore_stats()} | {:error, atom()}
  def compute_source_zscores(opts \\ []) do
    hours = Keyword.get(opts, :hours, 168)
    from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)

    # Query aggregated stats per source
    source_stats = fetch_source_aggregate_stats(from_time)

    if Enum.empty?(source_stats) do
      {:error, :no_data}
    else
      # Calculate mean and stddev for success rate
      success_rates = Enum.map(source_stats, & &1.success_rate)
      success_mean = mean(success_rates)
      success_stddev = stddev(success_rates, success_mean)

      # Calculate mean and stddev for duration
      durations = Enum.map(source_stats, & &1.avg_duration)
      duration_mean = mean(durations)
      duration_stddev = stddev(durations, duration_mean)

      # Calculate z-scores for each source
      sources_with_zscores =
        source_stats
        |> Enum.map(fn stat ->
          success_zscore = calculate_zscore(stat.success_rate, success_mean, success_stddev)
          duration_zscore = calculate_zscore(stat.avg_duration, duration_mean, duration_stddev)

          success_status = classify_zscore(success_zscore, :success)
          duration_status = classify_zscore(duration_zscore, :duration)

          # Overall status is the worse of the two
          overall_status = worse_status(success_status, duration_status)

          %{
            source: stat.source,
            success_rate: stat.success_rate,
            avg_duration: stat.avg_duration,
            total_jobs: stat.total_jobs,
            success_zscore: success_zscore,
            duration_zscore: duration_zscore,
            success_status: success_status,
            duration_status: duration_status,
            overall_status: overall_status
          }
        end)
        |> Enum.sort_by(& &1.success_zscore)

      # Count by status
      status_counts =
        sources_with_zscores
        |> Enum.group_by(& &1.overall_status)
        |> Map.new(fn {status, sources} -> {status, length(sources)} end)

      {:ok,
       %{
         sources: sources_with_zscores,
         success_mean: Float.round(success_mean, 1),
         success_stddev: Float.round(success_stddev, 1),
         duration_mean: Float.round(duration_mean, 1),
         duration_stddev: Float.round(duration_stddev, 1),
         normal_count: Map.get(status_counts, :normal, 0),
         warning_count: Map.get(status_counts, :warning, 0),
         critical_count: Map.get(status_counts, :critical, 0),
         hours: hours
       }}
    end
  end

  @doc """
  Returns a summary of source health using z-scores.

  Provides a quick overview suitable for dashboard display.

  ## Examples

      {:ok, summary} = Health.zscore_summary()
      # => %{
      #   total_sources: 7,
      #   normal_count: 5,
      #   warning_count: 1,
      #   critical_count: 1,
      #   outliers: ["cinema_city", "repertuary"],
      #   status: :warning  # :normal | :warning | :critical
      # }
  """
  @spec zscore_summary(keyword()) :: {:ok, map()} | {:error, atom()}
  def zscore_summary(opts \\ []) do
    case compute_source_zscores(opts) do
      {:ok, stats} ->
        outliers =
          stats.sources
          |> Enum.filter(&(&1.overall_status != :normal))
          |> Enum.map(& &1.source)

        overall_status =
          cond do
            stats.critical_count > 0 -> :critical
            stats.warning_count > 0 -> :warning
            true -> :normal
          end

        {:ok,
         %{
           total_sources: length(stats.sources),
           normal_count: stats.normal_count,
           warning_count: stats.warning_count,
           critical_count: stats.critical_count,
           outliers: outliers,
           status: overall_status,
           success_mean: stats.success_mean,
           duration_mean: stats.duration_mean
         }}

      {:error, _} = error ->
        error
    end
  end

  # Fetch aggregate stats for all sources from job_execution_summaries
  defp fetch_source_aggregate_stats(from_time) do
    query =
      from(j in JobExecutionSummary,
        where: j.attempted_at >= ^from_time,
        where: like(j.worker, "EventasaurusDiscovery.Sources.%"),
        group_by: fragment("substring(? from 'Sources\\.([^.]+)\\.Jobs')", j.worker),
        having: count(j.id) >= 10,
        select: %{
          source_match: fragment("substring(? from 'Sources\\.([^.]+)\\.Jobs')", j.worker),
          total_jobs: count(j.id),
          completed_jobs: count(fragment("CASE WHEN ? = 'completed' THEN 1 END", j.state)),
          avg_duration_ms:
            avg(fragment("CASE WHEN ? = 'completed' THEN ? END", j.state, j.duration_ms))
        }
      )

    Repo.replica().all(query)
    |> Enum.reject(fn row -> is_nil(row.source_match) end)
    |> Enum.map(fn row ->
      # Convert PascalCase to snake_case for source name
      source = Macro.underscore(row.source_match)

      success_rate =
        if row.total_jobs > 0 do
          Float.round(row.completed_jobs / row.total_jobs * 100, 1)
        else
          0.0
        end

      avg_duration =
        case row.avg_duration_ms do
          nil -> 0.0
          %Decimal{} = d -> Decimal.to_float(d) / 1000
          ms when is_number(ms) -> Float.round(ms / 1000, 1)
        end

      %{
        source: source,
        total_jobs: row.total_jobs,
        success_rate: success_rate,
        avg_duration: avg_duration
      }
    end)
  end

  # Calculate mean of a list of numbers
  defp mean([]), do: 0.0

  defp mean(values) do
    Enum.sum(values) / length(values)
  end

  # Calculate standard deviation
  defp stddev([], _mean), do: 0.0
  defp stddev([_], _mean), do: 0.0

  defp stddev(values, mean) do
    variance =
      values
      |> Enum.map(fn v -> :math.pow(v - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  # Return the worse of two statuses
  defp worse_status(:critical, _), do: :critical
  defp worse_status(_, :critical), do: :critical
  defp worse_status(:warning, _), do: :warning
  defp worse_status(_, :warning), do: :warning
  defp worse_status(_, _), do: :normal

  @doc """
  Returns workers that are performing below the threshold.

  ## Options

    * `:threshold` - Minimum acceptable success rate (default: 90.0)

  ## Examples

      {:ok, health} = Health.check("cinema_city")
      degraded = Health.degraded_workers(health, threshold: 90.0)
      # => [{"MovieDetailJob", 85.2}, {"ShowtimeProcessJob", 88.1}]
  """
  def degraded_workers(health, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 90.0)

    health.worker_health
    |> Enum.filter(fn {_name, metrics} -> metrics.success_rate < threshold end)
    |> Enum.map(fn {name, metrics} -> {name, metrics.success_rate} end)
    |> Enum.sort_by(fn {_name, rate} -> rate end)
  end

  @doc """
  Returns recent failures for investigation.

  ## Options

    * `:limit` - Maximum number of recent failures to return (default: 10)

  ## Examples

      {:ok, health} = Health.check("cinema_city")
      failures = Health.recent_failures(health, limit: 5)
  """
  def recent_failures(health, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    Enum.take(health.recent_failures, limit)
  end

  @typedoc "Trend data point with hourly aggregates"
  @type trend_data_point :: %{
          hour: DateTime.t(),
          success_rate: float(),
          total: non_neg_integer()
        }

  @typedoc "Trend direction indicator"
  @type trend_direction :: :improving | :stable | :degrading

  @typedoc "Trend data result"
  @type trend_data_result :: %{
          source: String.t(),
          hours: pos_integer(),
          data_points: [trend_data_point()],
          trend_direction: trend_direction()
        }

  @doc """
  Fetches 7-day hourly trend data for sparklines.

  Returns a list of hourly aggregates with success counts for visualization.
  Each data point represents one hour, with the most recent hour last.

  ## Options

    * `:hours` - Number of hours to look back (default: 168 = 7 days)

  ## Examples

      {:ok, trend} = Health.trend_data("cinema_city")
      # => %{
      #   source: "cinema_city",
      #   hours: 168,
      #   data_points: [%{hour: ~U[2024-01-01 00:00:00Z], success_rate: 95.5, total: 20}, ...]
      #   trend_direction: :improving  # :improving | :stable | :degrading
      # }
  """
  @spec trend_data(String.t(), keyword()) :: {:ok, trend_data_result()} | {:error, atom()}
  def trend_data(source, opts \\ []) do
    hours = Keyword.get(opts, :hours, 168)

    case get_source_pattern(source) do
      {:ok, worker_pattern} ->
        from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)
        to_time = DateTime.utc_now()

        data_points = fetch_hourly_aggregates(worker_pattern, from_time, to_time)
        trend_direction = calculate_trend_direction(data_points)

        {:ok,
         %{
           source: source,
           hours: hours,
           data_points: data_points,
           trend_direction: trend_direction
         }}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Fetches overall health history for chart visualization.

  Aggregates hourly health data across all sources into a single timeline
  suitable for Chart.js rendering.

  ## Options

    * `:hours` - Number of hours to look back (default: 168 = 7 days)
    * `:sources` - List of sources to include (default: all)

  ## Examples

      {:ok, history} = Health.health_history(hours: 168)
      # => %{
      #   labels: ["Dec 22 00:00", "Dec 22 01:00", ...],
      #   data_points: [95.2, 94.8, 96.1, ...],
      #   slo_target: 95.0
      # }
  """
  @spec health_history(keyword()) :: {:ok, map()}
  def health_history(opts \\ []) do
    hours = Keyword.get(opts, :hours, 168)
    from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)
    to_time = DateTime.utc_now()

    # Query to aggregate all job executions by hour across all sources
    query =
      from(j in JobExecutionSummary,
        where: j.attempted_at >= ^from_time and j.attempted_at <= ^to_time,
        group_by: fragment("date_trunc('hour', ?)", j.attempted_at),
        order_by: [asc: fragment("date_trunc('hour', ?)", j.attempted_at)],
        select: %{
          hour: fragment("date_trunc('hour', ?)", j.attempted_at),
          total: count(j.id),
          completed: count(fragment("CASE WHEN ? = 'completed' THEN 1 END", j.state))
        }
      )

    data_points =
      Repo.replica().all(query)
      |> Enum.map(fn row ->
        success_rate =
          if row.total > 0 do
            row.completed / row.total * 100
          else
            100.0
          end

        %{
          hour: row.hour,
          total: row.total,
          completed: row.completed,
          success_rate: Float.round(success_rate, 1)
        }
      end)

    # Format for Chart.js
    labels =
      data_points
      |> Enum.map(fn point ->
        Calendar.strftime(point.hour, "%b %d %H:%M")
      end)

    values = Enum.map(data_points, & &1.success_rate)

    {:ok,
     %{
       labels: labels,
       data_points: values,
       raw_data: data_points,
       slo_target: @slo_success_rate,
       hours: hours
     }}
  end

  @doc """
  Fetches trend data for multiple sources in parallel.

  Returns a map of source -> trend data for efficient batch loading.

  ## Examples

      {:ok, trends} = Health.trends_for_sources(["cinema_city", "kino_krakow"])
      # => %{"cinema_city" => %{...}, "kino_krakow" => %{...}}
  """
  @spec trends_for_sources([String.t()], keyword()) ::
          {:ok, %{String.t() => trend_data_result() | nil}}
  def trends_for_sources(sources, opts \\ []) when is_list(sources) do
    # Reduced concurrency to avoid exhausting database connection pool
    # The default pool size in production is only 5 for replica connections
    results =
      sources
      |> Task.async_stream(
        fn source ->
          case trend_data(source, opts) do
            {:ok, data} -> {source, data}
            {:error, _} -> {source, nil}
          end
        end,
        timeout: 15_000,
        max_concurrency: 2,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _} -> {nil, nil}
      end)
      |> Enum.reject(fn {source, _} -> is_nil(source) end)
      |> Map.new()

    {:ok, results}
  end

  @doc """
  Compares current performance against a baseline period (default: 7 days ago).

  For each source, calculates current vs baseline metrics and identifies
  any significant regressions.

  ## Options

    * `:hours` - Current period duration in hours (default: 24)
    * `:baseline_offset_days` - How many days ago to compare against (default: 7)
    * `:sources` - List of sources to compare (default: all known sources)

  ## Examples

      {:ok, comparisons} = Health.baseline_comparison(hours: 24)
      # => [
      #   %{
      #     source: "cinema_city",
      #     current: %{success_rate: 95.2, avg_duration: 1200.0, ...},
      #     baseline: %{success_rate: 94.0, avg_duration: 1350.0, ...},
      #     changes: %{success_rate: 1.2, avg_duration: -150.0, ...},
      #     status: :ok | :warning | :alert
      #   },
      #   ...
      # ]
  """
  @spec baseline_comparison(keyword()) :: {:ok, map()}
  def baseline_comparison(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    baseline_offset_days = Keyword.get(opts, :baseline_offset_days, 7)

    sources =
      Keyword.get(opts, :sources, [
        "cinema_city",
        "kino_krakow",
        "karnet",
        "week_pl",
        "bandsintown",
        "resident_advisor",
        "inquizition",
        "waw4free",
        "pubquiz",
        "repertuary"
      ])

    # Calculate time windows
    now = DateTime.utc_now()
    current_start = DateTime.add(now, -hours, :hour)
    current_end = now

    baseline_end = DateTime.add(now, -baseline_offset_days, :day)
    baseline_start = DateTime.add(baseline_end, -hours, :hour)

    # Fetch comparison data for all sources with reduced concurrency
    # to avoid exhausting database connection pool
    comparisons =
      sources
      |> Task.async_stream(
        fn source ->
          compare_source_periods(source, current_start, current_end, baseline_start, baseline_end)
        end,
        timeout: 15_000,
        max_concurrency: 2,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn comp -> comp.source end)

    {:ok,
     %{
       comparisons: comparisons,
       current_period: %{start: current_start, end: current_end},
       baseline_period: %{start: baseline_start, end: baseline_end},
       baseline_offset_days: baseline_offset_days
     }}
  end

  defp compare_source_periods(source, current_start, current_end, baseline_start, baseline_end) do
    case get_source_pattern(source) do
      {:ok, worker_pattern} ->
        # Fetch current period executions
        current_executions = fetch_executions(worker_pattern, current_start, current_end, 500)

        # Fetch baseline period executions
        baseline_executions = fetch_executions(worker_pattern, baseline_start, baseline_end, 500)

        # Calculate metrics for both periods
        current_metrics = calculate_period_metrics(current_executions)
        baseline_metrics = calculate_period_metrics(baseline_executions)

        # Calculate changes
        changes = calculate_changes(current_metrics, baseline_metrics)

        # Determine status based on regressions
        status = determine_comparison_status(changes, current_metrics, baseline_metrics)

        %{
          source: source,
          current: current_metrics,
          baseline: baseline_metrics,
          changes: changes,
          status: status,
          has_current_data: length(current_executions) > 0,
          has_baseline_data: length(baseline_executions) > 0
        }

      {:error, _} ->
        nil
    end
  end

  defp calculate_period_metrics([]),
    do: %{success_rate: nil, avg_duration: nil, p95_duration: nil, total: 0}

  defp calculate_period_metrics(executions) do
    total = length(executions)
    completed = Enum.count(executions, &(&1.state == "completed"))
    success_rate = completed / total * 100

    durations =
      executions
      |> Enum.map(& &1.duration_ms)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    avg_duration = if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0
    p95_duration = percentile(durations, 0.95)

    %{
      success_rate: Float.round(success_rate, 1),
      avg_duration: Float.round(avg_duration * 1.0, 1),
      p95_duration: Float.round(p95_duration * 1.0, 1),
      total: total,
      completed: completed
    }
  end

  defp calculate_changes(current, baseline) do
    cond do
      is_nil(current.success_rate) or is_nil(baseline.success_rate) ->
        %{success_rate: nil, avg_duration: nil, p95_duration: nil}

      true ->
        %{
          success_rate: Float.round(current.success_rate - baseline.success_rate, 1),
          avg_duration: Float.round(current.avg_duration - baseline.avg_duration, 1),
          p95_duration: Float.round(current.p95_duration - baseline.p95_duration, 1)
        }
    end
  end

  defp determine_comparison_status(changes, current, baseline) do
    cond do
      # No data for comparison
      is_nil(changes.success_rate) ->
        :no_data

      # No baseline data to compare against
      baseline.total == 0 ->
        :no_baseline

      # No current data
      current.total == 0 ->
        :no_current

      # Significant regression in success rate (> 5% drop)
      changes.success_rate < -5.0 ->
        :alert

      # Current success rate below SLO (95%)
      current.success_rate < @slo_success_rate ->
        :alert

      # Moderate regression (> 2% drop) or P95 significantly worse
      changes.success_rate < -2.0 or changes.p95_duration > 500 ->
        :warning

      # Performance improved or stable
      true ->
        :ok
    end
  end

  # Private helpers

  defp fetch_hourly_aggregates(worker_pattern, from_time, to_time) do
    # Query to aggregate executions by hour
    query =
      from(j in JobExecutionSummary,
        where: like(j.worker, ^worker_pattern),
        where: j.attempted_at >= ^from_time and j.attempted_at <= ^to_time,
        group_by: fragment("date_trunc('hour', ?)", j.attempted_at),
        order_by: [asc: fragment("date_trunc('hour', ?)", j.attempted_at)],
        select: %{
          hour: fragment("date_trunc('hour', ?)", j.attempted_at),
          total: count(j.id),
          completed: count(fragment("CASE WHEN ? = 'completed' THEN 1 END", j.state))
        }
      )

    Repo.replica().all(query)
    |> Enum.map(fn row ->
      success_rate =
        if row.total > 0 do
          row.completed / row.total * 100
        else
          100.0
        end

      %{
        hour: row.hour,
        total: row.total,
        completed: row.completed,
        success_rate: Float.round(success_rate, 1)
      }
    end)
  end

  defp calculate_trend_direction(data_points) when length(data_points) < 24 do
    :stable
  end

  defp calculate_trend_direction(data_points) do
    # Compare last 24 hours vs previous 24 hours
    recent_points = Enum.take(data_points, -24)
    older_points = data_points |> Enum.drop(-24) |> Enum.take(-24)

    if Enum.empty?(older_points) or Enum.empty?(recent_points) do
      :stable
    else
      recent_avg = average_success_rate(recent_points)
      older_avg = average_success_rate(older_points)

      cond do
        recent_avg - older_avg > 3.0 -> :improving
        older_avg - recent_avg > 3.0 -> :degrading
        true -> :stable
      end
    end
  end

  defp average_success_rate([]), do: 100.0

  defp average_success_rate(points) do
    total_weight = points |> Enum.map(& &1.total) |> Enum.sum()

    if total_weight > 0 do
      weighted_sum =
        points
        |> Enum.map(fn p -> p.success_rate * p.total end)
        |> Enum.sum()

      weighted_sum / total_weight
    else
      100.0
    end
  end

  # Dynamically generate worker pattern from source name
  # e.g., "cinema_city" -> "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%"
  #       "pubquiz" -> "EventasaurusDiscovery.Sources.Pubquiz.Jobs.%"
  defp get_source_pattern(source) when is_binary(source) do
    # Convert snake_case source name to PascalCase module name
    module_name =
      source
      |> String.split("_")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("")

    pattern = "EventasaurusDiscovery.Sources.#{module_name}.Jobs.%"
    {:ok, pattern}
  end

  defp get_source_pattern(_), do: {:error, :invalid_source}

  defp fetch_executions(worker_pattern, from_time, to_time, limit) do
    from(j in JobExecutionSummary,
      where: like(j.worker, ^worker_pattern),
      where: j.attempted_at >= ^from_time and j.attempted_at <= ^to_time,
      order_by: [desc: j.attempted_at],
      limit: ^limit
    )
    |> Repo.replica().all()
  end

  defp calculate_health(executions, source, hours) do
    total = length(executions)

    # Overall metrics
    completed = Enum.count(executions, &(&1.state == "completed"))
    failed = Enum.count(executions, &(&1.state in ["discarded", "cancelled"]))
    success_rate = completed / total * 100

    # Performance metrics
    durations =
      executions
      |> Enum.map(& &1.duration_ms)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    avg_duration = if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0
    p95_duration = percentile(durations, 0.95)

    # SLO compliance
    meeting_slos = success_rate >= @slo_success_rate and p95_duration <= @slo_p95_duration

    # Worker-level health
    worker_health =
      executions
      |> Enum.group_by(& &1.worker)
      |> Map.new(fn {worker, jobs} ->
        worker_name = worker |> String.split(".") |> List.last()
        worker_total = length(jobs)
        worker_completed = Enum.count(jobs, &(&1.state == "completed"))
        worker_success_rate = worker_completed / worker_total * 100

        worker_durations =
          jobs
          |> Enum.map(& &1.duration_ms)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        worker_avg_duration =
          if length(worker_durations) > 0,
            do: Enum.sum(worker_durations) / length(worker_durations),
            else: 0

        {worker_name,
         %{
           success_rate: worker_success_rate,
           total: worker_total,
           completed: worker_completed,
           failed: worker_total - worker_completed,
           avg_duration: worker_avg_duration
         }}
      end)

    # Recent failures
    recent_failures =
      executions
      |> Enum.filter(&(&1.state in ["discarded", "cancelled"]))
      |> Enum.take(10)
      |> Enum.map(fn job ->
        %{
          worker: job.worker |> String.split(".") |> List.last(),
          error_category: job.results["error_category"],
          error: job.error,
          attempted_at: job.attempted_at
        }
      end)

    %{
      source: source,
      hours: hours,
      total_executions: total,
      completed: completed,
      failed: failed,
      success_rate: success_rate,
      avg_duration: avg_duration,
      p95_duration: p95_duration,
      meeting_slos: meeting_slos,
      slo_targets: %{
        success_rate: @slo_success_rate,
        p95_duration: @slo_p95_duration
      },
      worker_health: worker_health,
      recent_failures: recent_failures
    }
  end

  defp percentile([], _p), do: 0.0

  defp percentile(sorted_list, p) do
    k = (length(sorted_list) - 1) * p
    f = floor(k)
    c = ceil(k)

    if f == c do
      Enum.at(sorted_list, round(k)) * 1.0
    else
      lower = Enum.at(sorted_list, f)
      upper = Enum.at(sorted_list, c)
      lower + (upper - lower) * (k - f)
    end
  end
end
