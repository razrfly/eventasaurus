defmodule EventasaurusDiscovery.JobExecutionSummaries do
  @moduledoc """
  Context module for managing job execution summaries.

  Provides query functions for the admin dashboard and analytics.

  All read operations use `Repo.replica()` to route queries to the
  read-optimized connection pool, reducing load on the primary pool. This is safe because:
  - All queries are read-only analytics/monitoring data
  - Slight replication lag (typically milliseconds) is acceptable
  - Data is historical and not time-critical
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  @doc """
  Lists all job execution summaries with optional filters.

  ## Options

  - `:worker` - Filter by worker module name
  - `:state` - Filter by job state
  - `:error_category` - Filter by error category
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
        worker: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob"
      )

      # Get jobs with validation errors
      JobExecutionSummaries.list_summaries(error_category: "validation_error")
  """
  def list_summaries(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    order_by = Keyword.get(opts, :order_by, desc: :attempted_at)

    query =
      from(s in JobExecutionSummary,
        order_by: ^order_by,
        limit: ^limit,
        offset: ^offset
      )

    query
    |> filter_by_worker(opts[:worker])
    |> filter_by_state(opts[:state])
    |> filter_by_error_category(opts[:error_category])
    |> Repo.replica().all()
  end

  @doc """
  Gets a single job execution summary by ID.
  """
  def get_summary!(id), do: Repo.replica().get!(JobExecutionSummary, id)

  @doc """
  Gets aggregated metrics for a specific worker.

  Returns a map with:
  - total_jobs: Total number of executions
  - completed: Number of completed jobs
  - cancelled: Number of cancelled jobs (intentional skips)
  - failed: Number of failed/discarded jobs (real errors)
  - pipeline_health: Percentage of jobs that ran successfully (completed + cancelled)
  - match_rate: Percentage of completed jobs out of completed + cancelled
  - avg_duration_ms: Average execution time
  """
  def get_worker_metrics(worker_name) do
    query =
      from(s in JobExecutionSummary,
        where: s.worker == ^worker_name,
        select: %{
          total_jobs: count(s.id),
          completed: count(s.id) |> filter(s.state == "completed"),
          cancelled: count(s.id) |> filter(s.state == "cancelled"),
          failed: count(s.id) |> filter(s.state == "discarded"),
          avg_duration_ms: avg(s.duration_ms)
        }
      )

    result = Repo.replica().one(query)

    if result.total_jobs > 0 do
      # Pipeline Health: (completed + cancelled) / total
      # This shows how many jobs ran without real errors
      pipeline_health =
        Float.round((result.completed + result.cancelled) / result.total_jobs * 100, 2)

      # Match Rate: completed / (completed + cancelled)
      # For jobs that process data, this shows successful processing rate
      match_rate =
        if result.completed + result.cancelled > 0 do
          Float.round(result.completed / (result.completed + result.cancelled) * 100, 2)
        else
          0.0
        end

      # Convert Decimal to float for avg_duration_ms
      avg_duration =
        if result.avg_duration_ms do
          result.avg_duration_ms |> Decimal.to_float() |> Float.round(2)
        else
          nil
        end

      result
      |> Map.put(:pipeline_health, pipeline_health)
      |> Map.put(:match_rate, match_rate)
      |> Map.put(:avg_duration_ms, avg_duration)
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
      from(s in JobExecutionSummary,
        group_by: s.worker,
        select: %{
          worker: s.worker,
          total_executions: count(s.id),
          last_execution: max(s.attempted_at)
        },
        order_by: [desc: max(s.attempted_at)]
      )

    Repo.replica().all(query)
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
      from(s in JobExecutionSummary,
        where: s.attempted_at >= ^from and s.attempted_at <= ^to,
        order_by: [desc: :attempted_at]
      )

    Repo.replica().all(query)
  end

  @doc """
  Gets overall system metrics for dashboard summary cards.

  Returns aggregated metrics across all workers within a time range.
  Now includes:
  - pipeline_health: (completed + cancelled) / total - shows jobs without real errors
  - match_rate: completed / (completed + cancelled) - shows data processing success rate
  - error_rate: (retryable + failed) / total - shows actual error rate
  """
  def get_system_metrics(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    query =
      from(s in JobExecutionSummary,
        where: s.attempted_at >= ^cutoff,
        select: %{
          total_jobs: count(s.id),
          completed: count(s.id) |> filter(s.state == "completed"),
          cancelled: count(s.id) |> filter(s.state == "cancelled"),
          failed: count(s.id) |> filter(s.state == "discarded"),
          retryable: count(s.id) |> filter(s.state == "retryable"),
          avg_duration_ms: avg(s.duration_ms),
          unique_workers: fragment("COUNT(DISTINCT ?)", s.worker)
        }
      )

    result = Repo.replica().one(query)

    if result.total_jobs > 0 do
      # Pipeline Health: (completed + cancelled) / total
      pipeline_health =
        Float.round((result.completed + result.cancelled) / result.total_jobs * 100, 2)

      # Match Rate: completed / (completed + cancelled)
      match_rate =
        if result.completed + result.cancelled > 0 do
          Float.round(result.completed / (result.completed + result.cancelled) * 100, 2)
        else
          0.0
        end

      # Error Rate: (retryable + failed) / total
      error_rate = Float.round((result.retryable + result.failed) / result.total_jobs * 100, 2)

      result
      |> Map.put(:pipeline_health, pipeline_health)
      |> Map.put(:match_rate, match_rate)
      |> Map.put(:error_rate, error_rate)
    else
      result
      |> Map.put(:pipeline_health, 0.0)
      |> Map.put(:match_rate, 0.0)
      |> Map.put(:error_rate, 0.0)
    end
  end

  @doc """
  Gets execution timeline data for charting.

  Groups executions by hour or day depending on time range.
  Now separates cancelled (intentional skips) from failed (real errors).
  """
  def get_execution_timeline(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    # Group by hour if < 48 hours, by day otherwise
    if hours_back <= 48 do
      # Hourly granularity
      query =
        from(s in JobExecutionSummary,
          where: s.attempted_at >= ^cutoff,
          group_by: fragment("date_trunc('hour', ?)", s.attempted_at),
          select: %{
            time_bucket: fragment("date_trunc('hour', ?)", s.attempted_at),
            total: count(s.id),
            completed: count(s.id) |> filter(s.state == "completed"),
            cancelled: count(s.id) |> filter(s.state == "cancelled"),
            failed: count(s.id) |> filter(s.state == "discarded")
          },
          order_by: fragment("date_trunc('hour', ?)", s.attempted_at)
        )

      Repo.replica().all(query)
    else
      # Daily granularity
      query =
        from(s in JobExecutionSummary,
          where: s.attempted_at >= ^cutoff,
          group_by: fragment("date_trunc('day', ?)", s.attempted_at),
          select: %{
            time_bucket: fragment("date_trunc('day', ?)", s.attempted_at),
            total: count(s.id),
            completed: count(s.id) |> filter(s.state == "completed"),
            cancelled: count(s.id) |> filter(s.state == "cancelled"),
            failed: count(s.id) |> filter(s.state == "discarded")
          },
          order_by: fragment("date_trunc('day', ?)", s.attempted_at)
        )

      Repo.replica().all(query)
    end
  end

  @doc """
  Gets top workers by execution count within a time range.
  """
  def get_top_workers(hours_back \\ 24, limit \\ 10) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    query =
      from(s in JobExecutionSummary,
        where: s.attempted_at >= ^cutoff,
        group_by: s.worker,
        select: %{
          worker: s.worker,
          total_executions: count(s.id),
          completed: count(s.id) |> filter(s.state == "completed"),
          cancelled: count(s.id) |> filter(s.state == "cancelled"),
          failed: count(s.id) |> filter(s.state == "discarded"),
          avg_duration_ms: avg(s.duration_ms)
        },
        order_by: [desc: count(s.id)],
        limit: ^limit
      )

    Repo.replica().all(query)
    |> Enum.map(fn worker ->
      # Pipeline Health: (completed + cancelled) / total
      pipeline_health =
        if worker.total_executions > 0 do
          Float.round((worker.completed + worker.cancelled) / worker.total_executions * 100, 2)
        else
          0.0
        end

      # Match Rate: completed / (completed + cancelled)
      match_rate =
        if worker.completed + worker.cancelled > 0 do
          Float.round(worker.completed / (worker.completed + worker.cancelled) * 100, 2)
        else
          0.0
        end

      worker
      |> Map.put(:pipeline_health, pipeline_health)
      |> Map.put(:match_rate, match_rate)
    end)
  end

  @doc """
  Gets executions for a specific worker within a time range.
  """
  def get_worker_executions(worker, hours_back \\ 24, limit \\ 100) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    query =
      from(s in JobExecutionSummary,
        where: s.worker == ^worker and s.attempted_at >= ^cutoff,
        order_by: [desc: :attempted_at],
        limit: ^limit
      )

    Repo.replica().all(query)
  end

  @doc """
  Gets aggregated metrics for a specific worker within a time range.

  Returns a map with:
  - total: Total number of executions
  - completed: Number of completed jobs
  - failed: Number of failed/discarded jobs
  - success_rate: Percentage of successful jobs
  - avg_duration_ms: Average execution time

  ## Examples

      # Get metrics for last 7 days
      get_worker_metrics_for_period("MyWorker", 168)
  """
  def get_worker_metrics_for_period(worker, hours_back) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    query =
      from(s in JobExecutionSummary,
        where: s.worker == ^worker and s.attempted_at >= ^cutoff,
        select: %{
          total: count(s.id),
          completed: count(s.id) |> filter(s.state == "completed"),
          cancelled: count(s.id) |> filter(s.state == "cancelled"),
          failed: count(s.id) |> filter(s.state == "discarded"),
          avg_duration_ms: avg(s.duration_ms)
        }
      )

    result = Repo.replica().one(query)

    # Calculate metrics and format duration
    if result.total > 0 do
      # Pipeline Health: (completed + cancelled) / total
      pipeline_health = Float.round((result.completed + result.cancelled) / result.total * 100, 2)

      # Match Rate: completed / (completed + cancelled)
      match_rate =
        if result.completed + result.cancelled > 0 do
          Float.round(result.completed / (result.completed + result.cancelled) * 100, 2)
        else
          0.0
        end

      # Convert Decimal to float for avg_duration_ms
      avg_duration =
        if result.avg_duration_ms do
          result.avg_duration_ms |> Decimal.to_float() |> Float.round(2)
        else
          0.0
        end

      result
      |> Map.put(:pipeline_health, pipeline_health)
      |> Map.put(:match_rate, match_rate)
      |> Map.put(:avg_duration_ms, avg_duration)
    else
      %{
        total: 0,
        completed: 0,
        cancelled: 0,
        failed: 0,
        pipeline_health: 0.0,
        match_rate: 0.0,
        avg_duration_ms: 0.0
      }
    end
  end

  @doc """
  Gets timeline data for a specific worker, grouped by day.

  Returns a list of maps, each containing:
  - date: ISO8601 date string
  - total: Total executions for that day
  - completed: Completed executions
  - failed: Failed/discarded executions

  ## Examples

      # Get daily timeline for last 7 days
      get_worker_timeline_data("MyWorker", 168)
  """
  def get_worker_timeline_data(worker, hours_back) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    query =
      from(s in JobExecutionSummary,
        where: s.worker == ^worker and s.attempted_at >= ^cutoff,
        group_by: fragment("date_trunc('day', ?)", s.attempted_at),
        select: %{
          date_bucket: fragment("date_trunc('day', ?)", s.attempted_at),
          total: count(s.id),
          completed: count(s.id) |> filter(s.state == "completed"),
          cancelled: count(s.id) |> filter(s.state == "cancelled"),
          failed: count(s.id) |> filter(s.state == "discarded")
        },
        order_by: fragment("date_trunc('day', ?)", s.attempted_at)
      )

    Repo.replica().all(query)
    |> Enum.map(fn bucket ->
      %{
        date: Date.to_iso8601(NaiveDateTime.to_date(bucket.date_bucket)),
        total: bucket.total,
        completed: bucket.completed,
        cancelled: bucket.cancelled,
        failed: bucket.failed
      }
    end)
  end

  @doc """
  Extracts scraper name from worker module path.

  ## Examples

      iex> extract_scraper_name("EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob")
      "repertuary"

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

  Now includes job_type_count to show how many distinct job types each scraper has.
  Separates cancelled (intentional skips) from failed (real errors).
  """
  def get_scraper_metrics(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    summaries =
      from(s in JobExecutionSummary,
        where: s.attempted_at >= ^cutoff,
        select: s
      )
      |> Repo.replica().all()

    # Group by scraper name (extracted from worker)
    summaries
    |> Enum.group_by(&extract_scraper_name(&1.worker))
    |> Enum.map(fn {scraper_name, executions} ->
      total = length(executions)
      completed = Enum.count(executions, &(&1.state == "completed"))
      cancelled = Enum.count(executions, &(&1.state == "cancelled"))
      failed = Enum.count(executions, &(&1.state == "discarded"))

      durations = Enum.map(executions, & &1.duration_ms) |> Enum.reject(&is_nil/1)

      avg_duration =
        if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0

      # Pipeline Health: (completed + cancelled) / total
      pipeline_health =
        if total > 0, do: Float.round((completed + cancelled) / total * 100, 2), else: 0.0

      # Match Rate: completed / (completed + cancelled)
      match_rate =
        if completed + cancelled > 0 do
          Float.round(completed / (completed + cancelled) * 100, 2)
        else
          0.0
        end

      # Calculate distinct job types for this scraper
      job_type_count =
        executions
        |> Enum.map(& &1.worker)
        |> Enum.uniq()
        |> length()

      # Get the most recent execution timestamp
      last_run =
        executions
        |> Enum.map(& &1.attempted_at)
        |> Enum.max(DateTime, fn -> nil end)

      %{
        scraper_name: scraper_name,
        total_executions: total,
        completed: completed,
        cancelled: cancelled,
        failed: failed,
        pipeline_health: pipeline_health,
        match_rate: match_rate,
        avg_duration_ms: Float.round(avg_duration, 2),
        job_type_count: job_type_count,
        last_run: last_run
      }
    end)
    |> Enum.sort_by(& &1.total_executions, :desc)
  end

  @doc """
  Gets pipeline metrics for a specific source, grouped by job type.

  Returns a list of maps, each containing metrics for one stage in the pipeline.

  ## Examples

      # Get Cinema City pipeline metrics for last 24 hours
      JobExecutionSummaries.get_source_pipeline_metrics("cinema_city", 24)

  Returns:
      [
        %{
          worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
          job_type: "SyncJob",
          total_runs: 48,
          completed: 48,
          failed: 0,
          success_rate: 100.0,
          avg_duration_ms: 2100.5,
          last_run: ~U[2025-01-23 10:45:00Z]
        },
        %{
          worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
          job_type: "CinemaDateJob",
          total_runs: 48,
          completed: 36,
          failed: 12,
          success_rate: 75.0,
          avg_duration_ms: 8500.2,
          last_run: ~U[2025-01-23 10:45:00Z]
        },
        ...
      ]
  """
  def get_source_pipeline_metrics(source_slug, hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    # Get all workers for this source
    from(s in JobExecutionSummary,
      where: s.attempted_at >= ^cutoff,
      group_by: s.worker,
      select: %{
        worker: s.worker,
        total_runs: count(s.id),
        completed: count(s.id) |> filter(s.state == "completed"),
        # Split cancelled into two categories:
        # - cancelled_failed: movie_not_matched (processing failures)
        # - cancelled_expected: other reasons or null (intentional skips)
        cancelled_failed:
          count(s.id)
          |> filter(
            s.state == "cancelled" and
              fragment("?->>'cancel_reason' = ?", s.results, "movie not matched")
          ),
        cancelled_expected:
          count(s.id)
          |> filter(
            s.state == "cancelled" and
              fragment(
                "(?->>'cancel_reason' IS NULL OR ?->>'cancel_reason' != ?)",
                s.results,
                s.results,
                "movie not matched"
              )
          ),
        failed: count(s.id) |> filter(s.state == "discarded"),
        # Retryable: jobs that failed but haven't exhausted retries yet
        retryable: count(s.id) |> filter(s.state == "retryable"),
        avg_duration_ms: avg(s.duration_ms),
        last_run: max(s.attempted_at)
      }
    )
    |> Repo.replica().all()
    |> Enum.filter(fn worker_stats ->
      # Only include workers matching the source_slug
      extract_scraper_name(worker_stats.worker) == source_slug
    end)
    |> Enum.map(fn worker_stats ->
      # Total cancelled for backward compatibility
      total_cancelled = worker_stats.cancelled_failed + worker_stats.cancelled_expected

      # Pipeline Health: (completed + cancelled_expected) / total
      # Only count intentional cancellations as healthy, not processing failures
      pipeline_health =
        if worker_stats.total_runs > 0 do
          Float.round(
            (worker_stats.completed + worker_stats.cancelled_expected) / worker_stats.total_runs *
              100,
            2
          )
        else
          0.0
        end

      # Processing Failure Rate: (cancelled_failed + discarded + retryable) / total
      # Tracks actual failures excluding intentional skips
      # Includes retryable jobs since they've failed at least once
      processing_failure_rate =
        if worker_stats.total_runs > 0 do
          Float.round(
            (worker_stats.cancelled_failed + worker_stats.failed + worker_stats.retryable) /
              worker_stats.total_runs * 100,
            2
          )
        else
          0.0
        end

      # Match Rate: completed / (completed + cancelled_expected)
      # For jobs where cancellation is intentional, shows data processing success
      match_rate =
        if worker_stats.completed + worker_stats.cancelled_expected > 0 do
          Float.round(
            worker_stats.completed / (worker_stats.completed + worker_stats.cancelled_expected) *
              100,
            2
          )
        else
          0.0
        end

      # Convert avg_duration_ms from Decimal to float
      avg_duration =
        if worker_stats.avg_duration_ms do
          worker_stats.avg_duration_ms |> Decimal.to_float() |> Float.round(2)
        else
          0.0
        end

      # Extract job type from worker name (last part after .Jobs.)
      job_type =
        worker_stats.worker
        |> String.split(".Jobs.")
        |> List.last()

      worker_stats
      |> Map.put(:cancelled, total_cancelled)
      |> Map.put(:pipeline_health, pipeline_health)
      |> Map.put(:processing_failure_rate, processing_failure_rate)
      |> Map.put(:match_rate, match_rate)
      |> Map.put(:avg_duration_ms, avg_duration)
      |> Map.put(:job_type, job_type)
    end)
    # Sort by typical pipeline order (SyncJob first, then others alphabetically)
    |> Enum.sort_by(fn stats ->
      case stats.job_type do
        "SyncJob" -> "0_SyncJob"
        other -> "1_#{other}"
      end
    end)
  end

  @doc """
  Gets error breakdown by job type for a specific source.

  Returns error categories attributed to specific pipeline stages.

  ## Examples

      # Get Cinema City error breakdown for last 24 hours
      JobExecutionSummaries.get_source_error_breakdown("cinema_city", 24)

  Returns:
      [
        %{
          worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
          job_type: "CinemaDateJob",
          error_category: "network_error",
          count: 8,
          example_error: "Request timeout after 30000ms",
          first_seen: ~U[2025-01-23 08:00:00Z],
          last_seen: ~U[2025-01-23 10:30:00Z]
        },
        %{
          worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
          job_type: "CinemaDateJob",
          error_category: "validation_error",
          count: 3,
          example_error: "Missing required field: title",
          first_seen: ~U[2025-01-23 09:15:00Z],
          last_seen: ~U[2025-01-23 10:15:00Z]
        },
        ...
      ]
  """
  def get_source_error_breakdown(source_slug, hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    # Get all failed jobs grouped by worker and error_category
    from(s in JobExecutionSummary,
      where: s.attempted_at >= ^cutoff,
      where: s.state in ["discarded", "cancelled"],
      where: fragment("? ->> ? IS NOT NULL", s.results, "error_category"),
      group_by: [s.worker, fragment("? ->> ?", s.results, "error_category")],
      select: %{
        worker: s.worker,
        error_category: fragment("? ->> ?", s.results, "error_category"),
        count: count(s.id),
        example_error: fragment("(array_agg(? ->> ?))[1]", s.results, "error_message"),
        first_seen: min(s.attempted_at),
        last_seen: max(s.attempted_at)
      },
      order_by: [desc: count(s.id)]
    )
    |> Repo.replica().all()
    |> Enum.filter(fn error_stats ->
      # Only include workers matching the source_slug
      extract_scraper_name(error_stats.worker) == source_slug
    end)
    |> Enum.map(fn error_stats ->
      # Extract job type from worker name
      job_type =
        error_stats.worker
        |> String.split(".Jobs.")
        |> List.last()

      Map.put(error_stats, :job_type, job_type)
    end)
  end

  @doc """
  Gets recent pipeline executions for a source.

  Returns complete pipeline runs showing all stages grouped by execution time.

  ## Examples

      # Get last 20 pipeline runs for Cinema City
      JobExecutionSummaries.get_source_recent_pipeline_runs("cinema_city", 20)

  Returns:
      [
        %{
          started_at: ~U[2025-01-23 10:45:00Z],
          total_duration_ms: 18200,
          total_jobs: 4,
          completed_jobs: 4,
          failed_jobs: 0,
          status: :success,
          failed_stage: nil,
          stages: [
            %{job_type: "SyncJob", state: "completed", duration_ms: 2100, ...},
            %{job_type: "CinemaDateJob", state: "completed", duration_ms: 8500, ...},
            %{job_type: "MovieDetailJob", state: "completed", duration_ms: 5800, ...},
            %{job_type: "ShowtimeProcessJob", state: "completed", duration_ms: 1800, ...}
          ]
        },
        ...
      ]
  """
  def get_source_recent_pipeline_runs(source_slug, limit \\ 20) do
    # Get recent SyncJob executions as pipeline identifiers
    # Each SyncJob run represents one complete pipeline execution
    sync_job_pattern = "%.Sources." <> Macro.camelize(source_slug) <> ".Jobs.SyncJob"

    sync_jobs =
      from(s in JobExecutionSummary,
        where: like(s.worker, ^sync_job_pattern),
        order_by: [desc: s.attempted_at],
        limit: ^limit,
        select: %{
          id: s.id,
          job_id: s.job_id,
          attempted_at: s.attempted_at,
          state: s.state,
          duration_ms: s.duration_ms
        }
      )
      |> Repo.replica().all()

    # For each SyncJob, find all related jobs in the pipeline
    # We'll look for jobs that started around the same time (within 5 minutes)
    Enum.map(sync_jobs, fn sync_job ->
      time_window_start = DateTime.add(sync_job.attempted_at, -60, :second)
      time_window_end = DateTime.add(sync_job.attempted_at, 300, :second)

      # Get all jobs for this source within the time window
      pipeline_jobs =
        from(s in JobExecutionSummary,
          where: s.attempted_at >= ^time_window_start,
          where: s.attempted_at <= ^time_window_end,
          order_by: [asc: s.attempted_at],
          select: s
        )
        |> Repo.replica().all()
        |> Enum.filter(fn job ->
          extract_scraper_name(job.worker) == source_slug
        end)

      # Calculate pipeline statistics
      total_jobs = length(pipeline_jobs)
      completed_jobs = Enum.count(pipeline_jobs, &(&1.state == "completed"))
      failed_jobs = Enum.count(pipeline_jobs, &(&1.state in ["discarded", "cancelled"]))

      total_duration =
        pipeline_jobs
        |> Enum.map(& &1.duration_ms)
        |> Enum.reject(&is_nil/1)
        |> Enum.sum()

      # Determine overall status
      status =
        cond do
          failed_jobs > 0 -> :failed
          completed_jobs == total_jobs -> :success
          true -> :partial
        end

      # Find first failed stage
      failed_stage =
        pipeline_jobs
        |> Enum.find(&(&1.state in ["discarded", "cancelled"]))
        |> case do
          nil -> nil
          job -> job.worker |> String.split(".Jobs.") |> List.last()
        end

      # Transform jobs into stages
      stages =
        Enum.map(pipeline_jobs, fn job ->
          %{
            job_type: job.worker |> String.split(".Jobs.") |> List.last(),
            state: job.state,
            duration_ms: job.duration_ms,
            attempted_at: job.attempted_at,
            error_category: get_in(job.results, ["error_category"]),
            error_message: get_in(job.results, ["error_message"])
          }
        end)

      %{
        started_at: sync_job.attempted_at,
        total_duration_ms: total_duration,
        total_jobs: total_jobs,
        completed_jobs: completed_jobs,
        failed_jobs: failed_jobs,
        status: status,
        failed_stage: failed_stage,
        stages: stages
      }
    end)
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
      from(s in JobExecutionSummary,
        where: s.attempted_at < ^cutoff_date
      )

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
    |> Repo.replica().all()
    |> Enum.filter(&is_silent_failure?/1)
  end

  @doc """
  Gets count of silent failures by scraper.

  Returns a list of maps, each containing scraper name, failure count, and example job ID.
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

  @doc """
  Gets error category breakdown for failed jobs within a time range.

  Returns a list of maps with error_category and count.

  ## Examples

      # Get error breakdown for last 24 hours
      JobExecutionSummaries.get_error_category_breakdown(24)
  """
  def get_error_category_breakdown(hours_back \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    from(s in JobExecutionSummary,
      where: s.attempted_at >= ^cutoff,
      where: s.state in ["discarded", "cancelled"],
      where: fragment("? ->> ? IS NOT NULL", s.results, "error_category"),
      group_by: fragment("? ->> ?", s.results, "error_category"),
      select: %{
        error_category: fragment("? ->> ?", s.results, "error_category"),
        count: count(s.id)
      },
      order_by: [desc: count(s.id)]
    )
    |> Repo.replica().all()
  end

  @doc """
  Gets error rate trends over time with configurable granularity.

  Returns a list of time buckets with error counts and rates.

  ## Options

  - `:granularity` - Time bucket size (`:hour` or `:day`, default: `:hour`)

  ## Examples

      # Get hourly error trends for last 7 days
      JobExecutionSummaries.get_error_trends(168, granularity: :hour)

      # Get daily error trends for last 30 days
      JobExecutionSummaries.get_error_trends(720, granularity: :day)
  """
  def get_error_trends(hours_back \\ 168, opts \\ []) do
    granularity = Keyword.get(opts, :granularity, :hour)
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    # Determine time bucket truncation based on granularity
    time_trunc = if granularity == :day, do: "day", else: "hour"

    from(s in JobExecutionSummary,
      where: s.attempted_at >= ^cutoff,
      select: %{
        time_bucket:
          selected_as(fragment("date_trunc(?, ?)", ^time_trunc, s.attempted_at), :time_bucket),
        total: count(s.id),
        completed: count(s.id) |> filter(s.state == "completed"),
        cancelled: count(s.id) |> filter(s.state == "cancelled"),
        failed: count(s.id) |> filter(s.state == "discarded")
      },
      group_by: selected_as(:time_bucket),
      order_by: selected_as(:time_bucket)
    )
    |> Repo.replica().all()
    |> Enum.map(fn bucket ->
      # Error Rate: only count real errors (discarded), not cancelled
      error_rate =
        if bucket.total > 0 do
          Float.round(bucket.failed / bucket.total * 100, 2)
        else
          0.0
        end

      Map.put(bucket, :error_rate, error_rate)
    end)
  end

  @doc """
  Gets the top N most common error messages within a time range.

  Returns a list of maps with error message and occurrence count.

  ## Options

  - `:limit` - Maximum number of error messages to return (default: 20)

  ## Examples

      # Get top 10 error messages from last 7 days
      JobExecutionSummaries.get_top_error_messages(168, limit: 10)
  """
  def get_top_error_messages(hours_back \\ 168, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    from(s in JobExecutionSummary,
      where: s.attempted_at >= ^cutoff,
      where: s.state in ["discarded", "cancelled"],
      where: fragment("? ->> ? IS NOT NULL", s.results, "error_message"),
      group_by: [
        fragment("? ->> ?", s.results, "error_message"),
        fragment("? ->> ?", s.results, "error_category")
      ],
      select: %{
        error_message: fragment("? ->> ?", s.results, "error_message"),
        error_category: fragment("? ->> ?", s.results, "error_category"),
        count: count(s.id),
        first_seen: min(s.attempted_at),
        last_seen: max(s.attempted_at)
      },
      order_by: [desc: count(s.id)],
      limit: ^limit
    )
    |> Repo.replica().all()
  end

  @doc """
  Compares success rates and performance metrics across all scrapers.

  Returns a list of scraper statistics for side-by-side comparison.

  ## Examples

      # Compare scrapers over last 7 days
      JobExecutionSummaries.compare_scrapers(168)
  """
  def compare_scrapers(hours_back \\ 168) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_back, :hour)

    from(s in JobExecutionSummary,
      where: s.attempted_at >= ^cutoff,
      group_by: s.worker,
      select: %{
        worker: s.worker,
        total_jobs: count(s.id),
        completed: count(s.id) |> filter(s.state == "completed"),
        cancelled: count(s.id) |> filter(s.state == "cancelled"),
        failed: count(s.id) |> filter(s.state == "discarded"),
        avg_duration_ms: avg(s.duration_ms)
      },
      order_by: [desc: count(s.id)]
    )
    |> Repo.replica().all()
    |> Enum.map(fn scraper ->
      # Pipeline Health: (completed + cancelled) / total
      pipeline_health =
        if scraper.total_jobs > 0 do
          Float.round((scraper.completed + scraper.cancelled) / scraper.total_jobs * 100, 2)
        else
          0.0
        end

      # Match Rate: completed / (completed + cancelled)
      match_rate =
        if scraper.completed + scraper.cancelled > 0 do
          Float.round(scraper.completed / (scraper.completed + scraper.cancelled) * 100, 2)
        else
          0.0
        end

      avg_duration =
        if scraper.avg_duration_ms do
          scraper.avg_duration_ms |> Decimal.to_float() |> Float.round(2)
        else
          nil
        end

      scraper
      |> Map.put(:pipeline_health, pipeline_health)
      |> Map.put(:match_rate, match_rate)
      |> Map.put(:avg_duration_ms, avg_duration)
    end)
  end

  # Private query filters

  defp filter_by_worker(query, nil), do: query

  defp filter_by_worker(query, worker) do
    from(s in query, where: s.worker == ^worker)
  end

  defp filter_by_state(query, nil), do: query

  defp filter_by_state(query, state) do
    from(s in query, where: s.state == ^state)
  end

  defp filter_by_error_category(query, nil), do: query

  defp filter_by_error_category(query, error_category) do
    from(s in query,
      where: fragment("? ->> ? = ?", s.results, "error_category", ^error_category)
    )
  end
end
