defmodule EventasaurusApp.Workers.TriviaExportRefreshWorker do
  @moduledoc """
  Daily worker to refresh the trivia_events_export materialized view.

  ## Why a Materialized View?

  The `trivia_events_export` view joins 7+ tables (public_events, venues, cities,
  countries, sources, public_event_sources, public_event_categories) and is
  queried ~4,500 times/day with PostGIS geospatial filters.

  As a regular VIEW, each query re-executed the full join, causing:
  - P99 latency: 1,015ms
  - 30 million rows read/day
  - 18% of total database runtime

  As a MATERIALIZED VIEW with proper indexes:
  - Pre-computed data stored physically
  - GiST spatial index enables fast st_dwithin queries
  - Expected P99: <50ms

  ## Refresh Strategy

  - Runs daily at 5 AM UTC (trivia events change infrequently)
  - Uses CONCURRENTLY for zero-downtime refresh
  - Takes ~10-30 seconds depending on data size

  ## Configuration

  Add to crontab in `config/runtime.exs`:

      {"0 5 * * *", EventasaurusApp.Workers.TriviaExportRefreshWorker}

  ## Manual Refresh

  Can also be triggered manually:

      EventasaurusApp.Workers.TriviaExportRefreshWorker.new(%{})
      |> Oban.insert()

  Or directly in IEx:

      EventasaurusApp.Repo.query!("REFRESH MATERIALIZED VIEW CONCURRENTLY trivia_events_export")
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    Logger.info("[TriviaExportRefreshWorker] Starting materialized view refresh [job #{job_id}]")

    start_time = System.monotonic_time(:millisecond)

    # Use CONCURRENTLY to avoid locking the view during refresh
    # This requires a UNIQUE index on the materialized view (we have trivia_events_export_id_idx)
    result =
      JobRepo.query(
        "REFRESH MATERIALIZED VIEW CONCURRENTLY trivia_events_export",
        [],
        timeout: :timer.minutes(5)
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _} ->
        # Get row count after refresh (defensive - don't fail job if count query fails)
        row_count =
          case JobRepo.query("SELECT COUNT(*) FROM trivia_events_export") do
            {:ok, %{rows: [[count]]}} -> count
            _ -> nil
          end

        Logger.info(
          "[TriviaExportRefreshWorker] Refresh completed in #{duration_ms}ms. Row count: #{row_count || "unknown"}"
        )

        {:ok, %{duration_ms: duration_ms, row_count: row_count}}

      {:error, reason} ->
        Logger.error(
          "[TriviaExportRefreshWorker] Refresh failed after #{duration_ms}ms: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
