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

  # SLO Targets
  @slo_success_rate 95.0
  @slo_p95_duration 3000.0

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

  # Private helpers

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
