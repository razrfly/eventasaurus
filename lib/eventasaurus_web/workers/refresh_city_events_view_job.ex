defmodule EventasaurusWeb.Workers.RefreshCityEventsViewJob do
  @moduledoc """
  Oban worker that refreshes the city_events_mv materialized view hourly.

  This materialized view provides a guaranteed data source for city pages when
  the Cachex cache misses. The view is used by `CityEventsFallback` to ensure
  event counts and event lists always come from the same data source.

  ## Schedule

  Runs hourly at minute 0 (configured in config/runtime.exs).

  ## Performance

  Uses REFRESH MATERIALIZED VIEW CONCURRENTLY which:
  - Requires the unique index on event_id (created in migration)
  - Does not lock reads during refresh
  - Takes ~1-5 seconds for typical data volumes

  See: https://github.com/anthropics/eventasaurus/issues/3373
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  alias EventasaurusApp.JobRepo

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("[RefreshCityEventsViewJob] Starting refresh (job_id: #{job_id})")

    result =
      JobRepo.query(
        "REFRESH MATERIALIZED VIEW CONCURRENTLY city_events_mv",
        [],
        timeout: :timer.minutes(5)
      )

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _} ->
        # Get row count for logging
        row_count = get_row_count()

        Logger.info(
          "[RefreshCityEventsViewJob] Completed in #{duration_ms}ms, #{row_count} rows (job_id: #{job_id})"
        )

        {:ok, %{duration_ms: duration_ms, row_count: row_count}}

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        Logger.error(
          "[RefreshCityEventsViewJob] Materialized view does not exist (job_id: #{job_id})"
        )

        {:error, :view_not_found}

      {:error, reason} ->
        Logger.error(
          "[RefreshCityEventsViewJob] Failed after #{duration_ms}ms: #{inspect(reason)} (job_id: #{job_id})"
        )

        {:error, reason}
    end
  end

  defp get_row_count do
    case JobRepo.query("SELECT COUNT(*) FROM city_events_mv", [], timeout: :timer.seconds(30)) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end
end
