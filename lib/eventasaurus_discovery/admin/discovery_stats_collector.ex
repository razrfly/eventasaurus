defmodule EventasaurusDiscovery.Admin.DiscoveryStatsCollector do
  @moduledoc """
  Collects discovery statistics by querying the Oban jobs table directly.
  This provides real-time stats based on actual job completion rather than manual tracking.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo

  # Maps source names to their Oban worker module names.
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
    worker =
      case Map.get(@source_to_worker, source_name) do
        nil -> nil
        "Elixir." <> _ = w -> w
        w when is_binary(w) -> "Elixir." <> w
      end

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

      # Fetch error details only when there are discarded jobs
      last_error =
        case stats.error_count do
          0 -> nil
          _ -> get_last_error(worker, city_id)
        end

      Map.put(stats, :last_error, last_error)
    else
      default_stats()
    end
  end

  @doc """
  Get statistics for all sources for a given city.

  Returns a map of source_name => stats.

  Optimized to use a single batched query instead of N individual queries.

  ## Examples

      iex> get_all_source_stats(1, ["bandsintown", "ticketmaster"])
      %{
        "bandsintown" => %{run_count: 5, success_count: 4, ...},
        "ticketmaster" => %{run_count: 3, success_count: 3, ...}
      }
  """
  def get_all_source_stats(city_id, source_names) do
    # Build worker name mapping
    worker_to_source =
      source_names
      |> Enum.map(fn source_name ->
        worker =
          case Map.get(@source_to_worker, source_name) do
            nil -> nil
            "Elixir." <> _ = w -> w
            w when is_binary(w) -> "Elixir." <> w
          end

        {worker, source_name}
      end)
      |> Enum.reject(fn {worker, _} -> is_nil(worker) end)
      |> Map.new()

    workers = Map.keys(worker_to_source)

    if Enum.empty?(workers) do
      # No valid workers, return default stats for all sources
      source_names
      |> Enum.map(fn source -> {source, default_stats()} end)
      |> Map.new()
    else
      # Single batched query for all workers
      stats_query =
        from j in "oban_jobs",
          where: j.worker in ^workers,
          where: fragment("? ->> 'city_id' = ?", j.args, ^to_string(city_id)),
          where: j.state in ["completed", "discarded"],
          group_by: j.worker,
          select: %{
            worker: j.worker,
            run_count: count(j.id),
            success_count:
              fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.state),
            error_count:
              fragment("COUNT(CASE WHEN ? = 'discarded' THEN 1 END)", j.state),
            last_run_at: max(j.completed_at)
          }

      stats_by_worker =
        stats_query
        |> Repo.all()
        |> Enum.map(fn stats ->
          {stats.worker, Map.delete(stats, :worker)}
        end)
        |> Map.new()

      # Batch fetch errors for workers that have failures
      workers_with_errors =
        stats_by_worker
        |> Enum.filter(fn {_worker, stats} -> stats.error_count > 0 end)
        |> Enum.map(fn {worker, _stats} -> worker end)

      errors_by_worker =
        if Enum.empty?(workers_with_errors) do
          %{}
        else
          get_last_errors_batch(workers_with_errors, city_id)
        end

      # Map back to source names with error details
      source_to_worker_inverted =
        worker_to_source
        |> Enum.map(fn {k, v} -> {v, k} end)
        |> Map.new()

      source_names
      |> Enum.map(fn source_name ->
        worker = Map.get(source_to_worker_inverted, source_name)

        stats =
          case Map.get(stats_by_worker, worker) do
            nil -> default_stats()
            stats -> Map.put(stats, :last_error, Map.get(errors_by_worker, worker))
          end

        {source_name, stats}
      end)
      |> Map.new()
    end
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

  defp get_last_errors_batch(workers, city_id) do
    # Fetch latest error for each worker in a single query
    error_query =
      from j in "oban_jobs",
        where: j.worker in ^workers,
        where: fragment("? ->> 'city_id' = ?", j.args, ^to_string(city_id)),
        where: j.state == "discarded",
        distinct: [j.worker],
        order_by: [asc: j.worker, desc: j.completed_at],
        select: {j.worker, j.errors}

    error_query
    |> Repo.all()
    |> Enum.map(fn {worker, errors} ->
      formatted_error =
        case errors do
          nil -> nil
          [] -> nil
          errors when is_list(errors) -> format_error(List.first(errors))
          _ -> nil
        end

      {worker, formatted_error}
    end)
    |> Map.new()
  end

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
