defmodule EventasaurusWeb.Cache.CityEventsMvInitializer do
  @moduledoc """
  Startup Initialization: Always refreshes the materialized view on boot.

  Ensures the `city_events_mv` materialized view has fresh data on application startup,
  before the application accepts traffic. This prevents the "no events found" bug
  that can occur when deploying to fresh infrastructure or after database sync.

  ## Problem Addressed (Issue #3501)

  The previous approach (Issue #3493) only checked if the MV had ANY rows:
  - If `COUNT(*) > 0`, it skipped refresh
  - But the MV could have data for Warsaw while Kraków had zero rows
  - Result: Kraków users see "No events found" despite events existing

  ## Solution

  Always refresh the MV on startup, regardless of current row count. This guarantees
  fresh data for ALL cities, not just "some data exists somewhere".

  ## Performance

  - Startup time: ~2-5 seconds for MV refresh
  - Trade-off: Slightly slower deploys vs guaranteed fresh data for all cities
  - Acceptable because deploys are infrequent and the alternative is user-facing bugs

  ## Usage

  Called from `Eventasaurus.Application.start/2`:

      case Supervisor.start_link(children, opts) do
        {:ok, pid} ->
          ensure_materialized_view_populated()
          {:ok, pid}
        error -> error
      end

  See: https://github.com/razrfly/eventasaurus/issues/3501
  See: https://github.com/razrfly/eventasaurus/issues/3490 (Original bug report)
  """

  require Logger

  alias EventasaurusApp.JobRepo

  @doc """
  Refreshes the materialized view on startup.

  Always performs a synchronous refresh before returning. This blocks the
  application startup until the MV has fresh data for ALL cities.

  ## Why Always Refresh?

  The previous approach checked `COUNT(*) > 0` and skipped refresh if any rows existed.
  This was flawed because the MV could have data for some cities but not others.
  Always refreshing guarantees fresh data for every city.

  ## Returns

    * `:ok` - MV refreshed successfully
    * `{:error, reason}` - Failed to refresh MV

  Errors are logged but not propagated to avoid preventing app startup
  when database issues occur. The hourly cron job will retry the refresh.
  """
  @spec ensure_populated() :: :ok | {:error, term()}
  def ensure_populated do
    Logger.info("[CityEventsMvInitializer] Refreshing materialized view on startup...")
    start_time = System.monotonic_time(:millisecond)

    case refresh_view() do
      {:ok, row_count} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        Logger.info(
          "[CityEventsMvInitializer] MV refreshed in #{duration_ms}ms - #{row_count} rows"
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
          "[CityEventsMvInitializer] MV refresh FAILED after #{duration_ms}ms: #{inspect(reason)}"
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
  - Takes ~2-5 seconds for typical data volumes
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

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        {:error, :view_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
