defmodule EventasaurusWeb.Cache.CityEventsMv do
  @moduledoc """
  Shared operations for the `city_events_mv` materialized view.

  Centralizes the SQL and error handling for refresh and row count queries,
  used by both `CityEventsMvInitializer` (startup) and
  `RefreshCityEventsViewJob` (hourly cron).
  """

  alias EventasaurusApp.JobRepo

  @doc """
  Refresh the materialized view concurrently.

  Uses `REFRESH MATERIALIZED VIEW CONCURRENTLY` which does not block reads
  and requires the unique index on `event_id`.

  Returns `{:ok, row_count}` on success, `{:error, reason}` on failure.
  """
  @spec refresh() :: {:ok, non_neg_integer()} | {:error, term()}
  def refresh do
    case JobRepo.query(
           "REFRESH MATERIALIZED VIEW CONCURRENTLY city_events_mv",
           [],
           timeout: :timer.minutes(5)
         ) do
      {:ok, _} ->
        case row_count() do
          {:ok, count} -> {:ok, count}
          {:error, _} -> {:ok, 0}
        end

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        {:error, :view_not_found}

      {:error, reason} ->
        {:error, reason}
    end
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
