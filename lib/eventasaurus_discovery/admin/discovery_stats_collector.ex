defmodule EventasaurusDiscovery.Admin.DiscoveryStatsCollector do
  @moduledoc """
  Collects discovery statistics by querying the Oban jobs table directly.
  This provides real-time stats based on actual job completion rather than manual tracking.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo

  @doc """
  Maps source names to their Oban worker module names.
  """
  @source_to_worker %{
    "bandsintown" => "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
    "ticketmaster" => "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob",
    "resident-advisor" => "EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.SyncJob",
    "karnet" => "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
    "kino-krakow" => "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob",
    "cinema-city" => "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
    "pubquiz-pl" => "EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob"
  }

  @doc """
  Get statistics for a specific source and city by querying Oban jobs.

  Returns a map with:
  - run_count: Total number of jobs (completed + discarded)
  - success_count: Number of completed jobs
  - error_count: Number of discarded jobs
  - last_run_at: Timestamp of most recent completion
  - last_error: Most recent error message (if any)

  ## Examples

      iex> get_source_stats(1, "bandsintown")
      %{
        run_count: 5,
        success_count: 4,
        error_count: 1,
        last_run_at: ~U[2025-01-07 12:00:00Z],
        last_error: "API rate limit exceeded"
      }
  """
  def get_source_stats(city_id, source_name) do
    worker = Map.get(@source_to_worker, source_name)

    if worker do
      # Query for aggregate stats
      stats_query =
        from j in "oban_jobs",
          where: j.worker == ^worker,
          where: fragment("? ->> 'city_id' = ?", j.args, ^to_string(city_id)),
          where: j.state in ["completed", "discarded"],
          select: %{
            run_count: count(j.id),
            success_count:
              fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.state),
            error_count:
              fragment("COUNT(CASE WHEN ? = 'discarded' THEN 1 END)", j.state),
            last_run_at: max(j.completed_at)
          }

      stats = Repo.one(stats_query) || default_stats()

      # Get the most recent error if there is one
      last_error = get_last_error(worker, city_id)

      Map.put(stats, :last_error, last_error)
    else
      default_stats()
    end
  end

  @doc """
  Get statistics for all sources for a given city.

  Returns a map of source_name => stats.

  ## Examples

      iex> get_all_source_stats(1, ["bandsintown", "ticketmaster"])
      %{
        "bandsintown" => %{run_count: 5, success_count: 4, ...},
        "ticketmaster" => %{run_count: 3, success_count: 3, ...}
      }
  """
  def get_all_source_stats(city_id, source_names) do
    Enum.map(source_names, fn source_name ->
      {source_name, get_source_stats(city_id, source_name)}
    end)
    |> Map.new()
  end

  # Private functions

  defp get_last_error(worker, city_id) do
    error_query =
      from j in "oban_jobs",
        where: j.worker == ^worker,
        where: fragment("? ->> 'city_id' = ?", j.args, ^to_string(city_id)),
        where: j.state == "discarded",
        order_by: [desc: j.completed_at],
        limit: 1,
        select: j.errors

    case Repo.one(error_query) do
      nil -> nil
      [] -> nil
      errors when is_list(errors) -> format_error(List.first(errors))
      _ -> nil
    end
  end

  defp format_error(nil), do: nil

  defp format_error(error) when is_map(error) do
    error["error"] || error["message"] || inspect(error)
  end

  defp format_error(error), do: inspect(error)

  defp default_stats do
    %{
      run_count: 0,
      success_count: 0,
      error_count: 0,
      last_run_at: nil,
      last_error: nil
    }
  end
end
