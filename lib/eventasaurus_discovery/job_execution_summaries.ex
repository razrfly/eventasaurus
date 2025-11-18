defmodule EventasaurusDiscovery.JobExecutionSummaries do
  @moduledoc """
  Context module for managing job execution summaries.

  Provides query functions for the admin dashboard and analytics.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  @doc """
  Lists all job execution summaries with optional filters.

  ## Options

  - `:worker` - Filter by worker module name
  - `:state` - Filter by job state
  - `:limit` - Limit number of results (default: 50)
  - `:offset` - Offset for pagination (default: 0)
  - `:order_by` - Order results (default: [desc: :attempted_at])

  ## Examples

      # Get recent executions
      JobExecutionSummaries.list_summaries()

      # Get failed jobs
      JobExecutionSummaries.list_summaries(state: "discarded")

      # Get jobs for specific worker
      JobExecutionSummaries.list_summaries(
        worker: "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.DayPageJob"
      )
  """
  def list_summaries(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    order_by = Keyword.get(opts, :order_by, [desc: :attempted_at])

    query =
      from s in JobExecutionSummary,
        order_by: ^order_by,
        limit: ^limit,
        offset: ^offset

    query
    |> filter_by_worker(opts[:worker])
    |> filter_by_state(opts[:state])
    |> Repo.all()
  end

  @doc """
  Gets a single job execution summary by ID.
  """
  def get_summary!(id), do: Repo.get!(JobExecutionSummary, id)

  @doc """
  Gets aggregated metrics for a specific worker.

  Returns a map with:
  - total_jobs: Total number of executions
  - completed: Number of completed jobs
  - failed: Number of failed/discarded jobs
  - success_rate: Percentage of successful jobs
  - avg_duration_ms: Average execution time
  """
  def get_worker_metrics(worker_name) do
    query =
      from s in JobExecutionSummary,
        where: s.worker == ^worker_name,
        select: %{
          total_jobs: count(s.id),
          completed: count(s.id) |> filter(s.state == "completed"),
          failed: count(s.id) |> filter(s.state in ["discarded", "cancelled"]),
          avg_duration_ms: avg(s.duration_ms)
        }

    result = Repo.one(query)

    if result.total_jobs > 0 do
      success_rate = Float.round(result.completed / result.total_jobs * 100, 2)
      Map.put(result, :success_rate, success_rate)
    else
      result
    end
  end

  @doc """
  Gets a list of unique workers with their execution counts.

  Returns a list of maps with:
  - worker: Worker module name
  - total_executions: Total number of executions
  - last_execution: Most recent execution timestamp
  """
  def list_workers do
    query =
      from s in JobExecutionSummary,
        group_by: s.worker,
        select: %{
          worker: s.worker,
          total_executions: count(s.id),
          last_execution: max(s.attempted_at)
        },
        order_by: [desc: max(s.attempted_at)]

    Repo.all(query)
  end

  @doc """
  Gets recent executions for dashboard display.

  Returns the last 100 job executions with key information.
  """
  def get_recent_executions(limit \\ 100) do
    list_summaries(limit: limit, order_by: [desc: :attempted_at])
  end

  @doc """
  Gets executions within a time range.

  ## Examples

      # Last 24 hours
      from = DateTime.add(DateTime.utc_now(), -24, :hour)
      JobExecutionSummaries.get_executions_in_range(from, DateTime.utc_now())
  """
  def get_executions_in_range(from, to) do
    query =
      from s in JobExecutionSummary,
        where: s.attempted_at >= ^from and s.attempted_at <= ^to,
        order_by: [desc: :attempted_at]

    Repo.all(query)
  end

  @doc """
  Gets overall system metrics for dashboard summary cards.

  Returns aggregated metrics across all workers within a time range.
  """
  def get_system_metrics(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    query =
      from s in JobExecutionSummary,
        where: s.attempted_at >= ^cutoff,
        select: %{
          total_jobs: count(s.id),
          completed: count(s.id) |> filter(s.state == "completed"),
          failed: count(s.id) |> filter(s.state in ["discarded", "cancelled"]),
          retryable: count(s.id) |> filter(s.state == "retryable"),
          avg_duration_ms: avg(s.duration_ms),
          unique_workers: fragment("COUNT(DISTINCT ?)", s.worker)
        }

    result = Repo.one(query)

    if result.total_jobs > 0 do
      success_rate = Float.round(result.completed / result.total_jobs * 100, 2)
      Map.put(result, :success_rate, success_rate)
    else
      Map.put(result, :success_rate, 0.0)
    end
  end

  @doc """
  Gets execution timeline data for charting.

  Groups executions by hour or day depending on time range.
  """
  def get_execution_timeline(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    # Group by hour if < 48 hours, by day otherwise
    if hours_back <= 48 do
      # Hourly granularity
      query =
        from s in JobExecutionSummary,
          where: s.attempted_at >= ^cutoff,
          group_by: fragment("date_trunc('hour', ?)", s.attempted_at),
          select: %{
            time_bucket: fragment("date_trunc('hour', ?)", s.attempted_at),
            total: count(s.id),
            completed: count(s.id) |> filter(s.state == "completed"),
            failed: count(s.id) |> filter(s.state in ["discarded", "cancelled"])
          },
          order_by: fragment("date_trunc('hour', ?)", s.attempted_at)

      Repo.all(query)
    else
      # Daily granularity
      query =
        from s in JobExecutionSummary,
          where: s.attempted_at >= ^cutoff,
          group_by: fragment("date_trunc('day', ?)", s.attempted_at),
          select: %{
            time_bucket: fragment("date_trunc('day', ?)", s.attempted_at),
            total: count(s.id),
            completed: count(s.id) |> filter(s.state == "completed"),
            failed: count(s.id) |> filter(s.state in ["discarded", "cancelled"])
          },
          order_by: fragment("date_trunc('day', ?)", s.attempted_at)

      Repo.all(query)
    end
  end

  @doc """
  Gets top workers by execution count within a time range.
  """
  def get_top_workers(hours_back \\ 24, limit \\ 10) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    query =
      from s in JobExecutionSummary,
        where: s.attempted_at >= ^cutoff,
        group_by: s.worker,
        select: %{
          worker: s.worker,
          total_executions: count(s.id),
          completed: count(s.id) |> filter(s.state == "completed"),
          failed: count(s.id) |> filter(s.state in ["discarded", "cancelled"]),
          avg_duration_ms: avg(s.duration_ms)
        },
        order_by: [desc: count(s.id)],
        limit: ^limit

    Repo.all(query)
    |> Enum.map(fn worker ->
      success_rate =
        if worker.total_executions > 0 do
          Float.round(worker.completed / worker.total_executions * 100, 2)
        else
          0.0
        end

      Map.put(worker, :success_rate, success_rate)
    end)
  end

  @doc """
  Gets executions for a specific worker within a time range.
  """
  def get_worker_executions(worker, hours_back \\ 24, limit \\ 100) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    query =
      from s in JobExecutionSummary,
        where: s.worker == ^worker and s.attempted_at >= ^cutoff,
        order_by: [desc: :attempted_at],
        limit: ^limit

    Repo.all(query)
  end

  @doc """
  Extracts scraper name from worker module path.

  ## Examples

      iex> extract_scraper_name("EventasaurusDiscovery.Sources.KinoKrakow.Jobs.DayPageJob")
      "kino_krakow"

      iex> extract_scraper_name("EventasaurusApp.Workers.UnsplashRefreshWorker")
      "unsplash"
  """
  def extract_scraper_name(worker) when is_binary(worker) do
    cond do
      # Pattern: EventasaurusDiscovery.Sources.ScraperName.Jobs.JobName
      String.contains?(worker, ".Sources.") ->
        worker
        |> String.split(".Sources.")
        |> List.last()
        |> String.split(".Jobs.")
        |> List.first()
        |> Macro.underscore()

      # Pattern: EventasaurusApp.Workers.ScraperNameWorker
      String.contains?(worker, ".Workers.") ->
        worker
        |> String.split(".")
        |> List.last()
        |> String.replace("Worker", "")
        |> Macro.underscore()

      # Fallback: use last part of module name
      true ->
        worker
        |> String.split(".")
        |> List.last()
        |> Macro.underscore()
    end
  end

  @doc """
  Gets metrics grouped by scraper name.
  """
  def get_scraper_metrics(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    summaries =
      from(s in JobExecutionSummary,
        where: s.attempted_at >= ^cutoff,
        select: s
      )
      |> Repo.all()

    # Group by scraper name (extracted from worker)
    summaries
    |> Enum.group_by(&extract_scraper_name(&1.worker))
    |> Enum.map(fn {scraper_name, executions} ->
      total = length(executions)
      completed = Enum.count(executions, &(&1.state == "completed"))
      failed = Enum.count(executions, &(&1.state in ["discarded", "cancelled"]))

      durations = Enum.map(executions, & &1.duration_ms) |> Enum.reject(&is_nil/1)
      avg_duration = if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0

      success_rate = if total > 0, do: Float.round(completed / total * 100, 2), else: 0.0

      %{
        scraper_name: scraper_name,
        total_executions: total,
        completed: completed,
        failed: failed,
        success_rate: success_rate,
        avg_duration_ms: Float.round(avg_duration, 2)
      }
    end)
    |> Enum.sort_by(& &1.total_executions, :desc)
  end

  @doc """
  Deletes old job execution summaries.

  Useful for cleanup jobs to maintain a manageable database size.

  ## Examples

      # Delete summaries older than 90 days
      days_to_keep = 90
      JobExecutionSummaries.delete_old_summaries(days_to_keep)
  """
  def delete_old_summaries(days_to_keep) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_to_keep, :day)

    query =
      from s in JobExecutionSummary,
        where: s.attempted_at < ^cutoff_date

    Repo.delete_all(query)
  end

  @doc """
  Detects silent failures - jobs that completed successfully but produced no useful output.

  A silent failure is defined as a completed job where:
  - State is "completed"
  - Job role is "worker" or "coordinator"
  - Key output metrics are zero (no entities created, no jobs queued, etc.)
  - Job was NOT explicitly skipped (skipped != true)

  ## Examples

      # Find silent failures in last 24 hours
      JobExecutionSummaries.detect_silent_failures(24)

      # Find silent failures in last week
      JobExecutionSummaries.detect_silent_failures(168)

  Returns a list of suspicious jobs with their metadata.
  """
  def detect_silent_failures(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    # Get all completed jobs in time range
    from(s in JobExecutionSummary,
      where: s.state == "completed",
      where: s.attempted_at >= ^cutoff,
      order_by: [desc: s.attempted_at]
    )
    |> Repo.all()
    |> Enum.filter(&is_silent_failure?/1)
  end

  @doc """
  Gets count of silent failures by scraper.

  Returns a map of scraper names to silent failure counts.
  """
  def get_silent_failure_counts(hours_back \\ 24) do
    silent_failures = detect_silent_failures(hours_back)

    silent_failures
    |> Enum.group_by(&extract_scraper_name(&1.worker))
    |> Enum.map(fn {scraper, failures} ->
      %{
        scraper_name: scraper,
        silent_failure_count: length(failures),
        example_job_id: List.first(failures).job_id
      }
    end)
    |> Enum.sort_by(& &1.silent_failure_count, :desc)
  end

  # Private helper functions

  # Determines if a job is a silent failure based on its results metadata
  defp is_silent_failure?(%JobExecutionSummary{results: nil}), do: false
  defp is_silent_failure?(%JobExecutionSummary{results: results}) when is_map(results) do
    # Skip if explicitly marked as skipped
    skipped = get_in(results, ["skipped"]) == true

    # Skip if job had no role (unknown job type)
    role = get_in(results, ["job_role"])

    if skipped or is_nil(role) do
      false
    else
      # Check for zero output indicators based on common result keys
      zero_output_indicators = [
        # Coordinator metrics
        {get_in(results, ["total_queued"]), 0},
        {get_in(results, ["cities_queued"]), 0},
        {get_in(results, ["countries_queued"]), 0},

        # Worker metrics
        {get_in(results, ["images_fetched"]), 0},
        {get_in(results, ["categories_refreshed"]), 0},
        {get_in(results, ["movies_scheduled"]), 0},
        {get_in(results, ["showtimes_count"]), 0},
        {get_in(results, ["events_created"]), 0},
        {get_in(results, ["venues_created"]), 0}
      ]

      # A job is a silent failure if ANY key output metric is explicitly zero
      # (we check for exact match to avoid false positives from missing keys)
      Enum.any?(zero_output_indicators, fn {value, zero} ->
        value == zero and not is_nil(value)
      end)
    end
  end

  # Private query filters

  defp filter_by_worker(query, nil), do: query

  defp filter_by_worker(query, worker) do
    from s in query, where: s.worker == ^worker
  end

  defp filter_by_state(query, nil), do: query

  defp filter_by_state(query, state) do
    from s in query, where: s.state == ^state
  end
end
