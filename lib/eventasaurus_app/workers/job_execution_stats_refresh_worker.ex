defmodule EventasaurusApp.Workers.JobExecutionStatsRefreshWorker do
  @moduledoc """
  Worker to refresh the job_execution_stats materialized view hourly.

  ## Why a Materialized View?

  The `job_execution_summaries` table has 400K+ rows and is queried 6x per dashboard
  load with expensive aggregations:
  - COUNT(*) for total processed
  - COUNT(*) WHERE collision_data IS NOT NULL
  - AVG(collision_data->>'confidence')
  - COUNT(DISTINCT source) with string parsing
  - GROUP BY worker, collision_type

  These queries have P99 latencies of 1-6 seconds, consuming 28% of total database runtime.

  ## Solution

  Pre-aggregate statistics into hourly buckets per source. The materialized view
  contains ~24 rows per source per day instead of querying 400K+ raw rows.

  Dashboard queries become simple sums over the materialized view:
  - SUM(total_processed) WHERE hour_bucket >= now() - interval '24 hours'

  ## Expected Impact

  - P99 latency: 1-6 seconds → <50ms
  - Rows read: 400K+ → <500 rows
  - Database runtime reduction: ~20 minutes/day

  ## Refresh Strategy

  - Runs hourly at minute 30 (offset from other hourly jobs)
  - Uses CONCURRENTLY for zero-downtime refresh
  - Takes ~10-30 seconds depending on data size
  - Hourly is sufficient since dashboard uses Cachex caching and data isn't time-sensitive

  ## Configuration

  Add to crontab in `config/runtime.exs`:

      {"30 * * * *", EventasaurusApp.Workers.JobExecutionStatsRefreshWorker}

  ## Manual Refresh

  Can also be triggered manually:

      EventasaurusApp.Workers.JobExecutionStatsRefreshWorker.new(%{})
      |> Oban.insert()

  Or directly in IEx:

      EventasaurusApp.Repo.query!("REFRESH MATERIALIZED VIEW CONCURRENTLY job_execution_stats")
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias EventasaurusApp.Repo
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    Logger.info(
      "[JobExecutionStatsRefreshWorker] Starting materialized view refresh [job #{job_id}]"
    )

    start_time = System.monotonic_time(:millisecond)

    # Use CONCURRENTLY to avoid locking the view during refresh
    # This requires a UNIQUE index on the materialized view (we have job_execution_stats_pk_idx)
    result =
      Repo.query(
        "REFRESH MATERIALIZED VIEW CONCURRENTLY job_execution_stats",
        [],
        timeout: :timer.minutes(5)
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _} ->
        # Get row count after refresh (defensive - don't fail job if count query fails)
        row_count =
          case Repo.query("SELECT COUNT(*) FROM job_execution_stats") do
            {:ok, %{rows: [[count]]}} -> count
            _ -> nil
          end

        Logger.info(
          "[JobExecutionStatsRefreshWorker] Refresh completed in #{duration_ms}ms. Row count: #{row_count || "unknown"}"
        )

        {:ok, %{duration_ms: duration_ms, row_count: row_count}}

      {:error, reason} ->
        Logger.error(
          "[JobExecutionStatsRefreshWorker] Refresh failed after #{duration_ms}ms: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
