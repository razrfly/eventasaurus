defmodule EventasaurusWeb.Cache.CityEventsMv do
  @moduledoc """
  Shared operations for the `city_events_mv` materialized view.

  Centralizes the SQL and error handling for refresh and row count queries,
  used by both `CityEventsMvInitializer` (startup) and
  `RefreshCityEventsViewJob` (hourly cron).
  """

  require Logger

  alias EventasaurusApp.JobRepo

  @doc """
  Refresh the materialized view concurrently.

  Uses `REFRESH MATERIALIZED VIEW CONCURRENTLY` which does not block reads
  and requires the unique index on `event_id`.

  Returns `{:ok, row_count}` on success, `{:error, reason}` on failure.
  """
  @spec refresh() :: {:ok, non_neg_integer() | :unknown} | {:error, term()}
  def refresh do
    start_time = System.monotonic_time(:millisecond)

    case JobRepo.query(
           "REFRESH MATERIALIZED VIEW CONCURRENTLY city_events_mv",
           [],
           timeout: :timer.minutes(5)
         ) do
      {:ok, _} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        case row_count() do
          {:ok, count} ->
            persist_last_refresh(count, duration_ms)
            {:ok, count}

          {:error, reason} ->
            Logger.warning("[CityEventsMv] row_count failed after refresh: #{inspect(reason)}")
            {:ok, :unknown}
        end

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        {:error, :view_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Store the result of the most recent MV refresh."
  @spec persist_last_refresh(non_neg_integer() | :unknown, non_neg_integer()) :: :ok
  def persist_last_refresh(row_count, duration_ms) do
    :persistent_term.put({__MODULE__, :last_refresh}, %{
      at: DateTime.utc_now(),
      row_count: row_count,
      duration_ms: duration_ms
    })
  end

  @doc "Get the stored result of the most recent MV refresh. Returns nil if no refresh has run."
  @spec last_refresh_info() :: map() | nil
  def last_refresh_info do
    :persistent_term.get({__MODULE__, :last_refresh}, nil)
  end

  @doc """
  Get the current row count of the materialized view.

  Returns `{:ok, count}` or `{:error, reason}`.
  """
  @spec row_count() :: {:ok, non_neg_integer()} | {:error, term()}
  def row_count do
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
end
