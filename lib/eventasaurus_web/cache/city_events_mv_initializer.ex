defmodule EventasaurusWeb.Cache.CityEventsMvInitializer do
  @moduledoc """
  Layer 1 of the self-healing cache strategy: Startup Initialization.

  Ensures the `city_events_mv` materialized view is populated on application startup,
  before the application accepts traffic. This prevents the "no events found" bug
  that can occur when deploying to fresh infrastructure or after database migrations.

  ## Problem Addressed (Issue #3490)

  Without this initializer, a fresh deploy can result in:
  1. Materialized view empty (never refreshed)
  2. Cache empty (no data yet)
  3. User visits city page → sees "No events found"
  4. Async MV refresh job eventually runs (1+ minute delay)

  ## Solution

  On application startup (after Repo is available, before Endpoint accepts traffic):
  1. Check if `city_events_mv` has 0 rows
  2. If empty, refresh the view synchronously (blocking)
  3. Only then allow the application to proceed and accept traffic

  ## Performance

  - Normal startup (MV populated): ~10ms check
  - Cold-start (MV empty): ~1-5 seconds for refresh
  - Trade-off: Slightly slower deploys vs guaranteed data availability

  ## Usage

  Called from `Eventasaurus.Application.start/2`:

      case Supervisor.start_link(children, opts) do
        {:ok, pid} ->
          # Initialize MV before accepting traffic
          ensure_materialized_view_populated()
          {:ok, pid}
        error -> error
      end

  See: https://github.com/anthropics/eventasaurus/issues/3493 (RFC)
  See: https://github.com/anthropics/eventasaurus/issues/3490 (Bug report)
  """

  require Logger

  alias EventasaurusApp.JobRepo

  @doc """
  Ensures the materialized view is populated on startup.

  Checks if `city_events_mv` has 0 rows. If empty, performs a synchronous
  refresh before returning. This blocks the application startup until
  the MV is ready.

  ## Returns

    * `:ok` - MV is populated (either was already, or just refreshed)
    * `{:error, reason}` - Failed to check or refresh MV

  Errors are logged but not propagated to avoid preventing app startup
  when database issues occur. In that case, Layer 2 (cache-aware fallback)
  will handle requests gracefully.
  """
  @spec ensure_populated() :: :ok | {:error, term()}
  def ensure_populated do
    Logger.info("[CityEventsMvInitializer] Checking materialized view status...")
    start_time = System.monotonic_time(:millisecond)

    case get_row_count() do
      {:ok, 0} ->
        Logger.warning("[CityEventsMvInitializer] MV is EMPTY - refreshing synchronously...")
        refresh_result = refresh_view()
        duration_ms = System.monotonic_time(:millisecond) - start_time

        case refresh_result do
          {:ok, row_count} ->
            Logger.info(
              "[CityEventsMvInitializer] MV refreshed in #{duration_ms}ms - #{row_count} rows populated"
            )

            :ok

          {:error, reason} ->
            Logger.error(
              "[CityEventsMvInitializer] MV refresh FAILED after #{duration_ms}ms: #{inspect(reason)} - Layer 2 fallback will handle requests"
            )

            {:error, reason}
        end

      {:ok, row_count} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        Logger.info(
          "[CityEventsMvInitializer] MV already populated (#{row_count} rows) - checked in #{duration_ms}ms"
        )

        :ok

      {:error, :view_not_found} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        Logger.warning(
          "[CityEventsMvInitializer] MV does not exist (#{duration_ms}ms) - migrations may not have run"
        )

        {:error, :view_not_found}

      {:error, reason} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        Logger.error(
          "[CityEventsMvInitializer] Failed to check MV status (#{duration_ms}ms): #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Get the current row count of the materialized view.

  Used for health checks and debugging.
  """
  @spec get_row_count() :: {:ok, non_neg_integer()} | {:error, term()}
  def get_row_count do
    case JobRepo.query(
           "SELECT COUNT(*) FROM city_events_mv",
           [],
           timeout: :timer.seconds(30)
         ) do
      {:ok, %{rows: [[count]]}} ->
        {:ok, count}

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        {:error, :view_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Force refresh the materialized view.

  Uses REFRESH MATERIALIZED VIEW CONCURRENTLY which:
  - Does not block reads during refresh
  - Requires the unique index on event_id
  - Takes ~1-5 seconds for typical data volumes
  """
  @spec refresh_view() :: {:ok, non_neg_integer()} | {:error, term()}
  def refresh_view do
    case JobRepo.query(
           "REFRESH MATERIALIZED VIEW CONCURRENTLY city_events_mv",
           [],
           timeout: :timer.minutes(5)
         ) do
      {:ok, _} ->
        # Get updated row count
        case get_row_count() do
          {:ok, count} -> {:ok, count}
          {:error, _} -> {:ok, 0}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
