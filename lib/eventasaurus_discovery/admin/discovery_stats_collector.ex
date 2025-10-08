defmodule EventasaurusDiscovery.Admin.DiscoveryStatsCollector do
  @moduledoc """
  Collects discovery statistics by querying the Oban jobs table directly.
  This provides real-time stats based on actual job completion rather than manual tracking.

  ## Architecture

  Worker names in the Oban database do NOT include the 'Elixir.' prefix.
  The `@source_to_worker` map contains module names exactly as they appear in the database.

  ## Country-Wide Sources

  Some sources (e.g., pubquiz-pl) are country-wide and don't have a city_id.
  These are handled separately by checking the `@country_wide_sources` list.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  require Logger

  # Maps source names to their Oban worker module names.
  # These names must match exactly what's stored in the oban_jobs.worker column.
  @source_to_worker %{
    "bandsintown" => "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
    "ticketmaster" => "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob",
    "resident-advisor" => "EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.SyncJob",
    "karnet" => "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
    "kino-krakow" => "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob",
    "cinema-city" => "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
    "pubquiz-pl" => "EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob"
  }

  # Sources that operate country-wide and don't have city_id in their job args
  @country_wide_sources ["pubquiz-pl"]

  @doc """
  Get statistics for a specific source and city by querying Oban jobs.

  For city-specific sources, filters by city_id.
  For country-wide sources, returns stats without city filtering.

  ## Parameters

    * `city_id` - The city ID to filter by (integer or nil for country-wide)
    * `source_name` - The source name (string, must exist in @source_to_worker)

  ## Returns

  A map with:
    * `:run_count` - Total number of jobs (completed + discarded)
    * `:success_count` - Number of completed jobs
    * `:error_count` - Number of discarded jobs
    * `:last_run_at` - Timestamp of most recent completion (NaiveDateTime or nil)
    * `:last_error` - Most recent error message (string or nil)

  ## Examples

      iex> get_source_stats(1, "bandsintown")
      %{
        run_count: 5,
        success_count: 4,
        error_count: 1,
        last_run_at: ~N[2025-01-07 12:00:00],
        last_error: "API rate limit exceeded"
      }

      iex> get_source_stats(nil, "pubquiz-pl")
      %{
        run_count: 10,
        success_count: 10,
        error_count: 0,
        last_run_at: ~N[2025-01-07 12:00:00],
        last_error: nil
      }

      iex> get_source_stats(1, "unknown-source")
      %{run_count: 0, success_count: 0, error_count: 0, last_run_at: nil, last_error: nil}
  """
  def get_source_stats(city_id, source_name)
      when (is_integer(city_id) or is_nil(city_id)) and is_binary(source_name) do
    worker = Map.get(@source_to_worker, source_name)
    is_country_wide = source_name in @country_wide_sources

    cond do
      is_nil(worker) ->
        Logger.debug("Unknown source: #{source_name}")
        default_stats()

      is_country_wide ->
        get_country_wide_stats(worker)

      true ->
        get_city_stats(worker, city_id)
    end
  end

  def get_source_stats(_city_id, _source_name) do
    Logger.warning("Invalid input to get_source_stats")
    default_stats()
  end

  @doc """
  Get statistics for all sources for a given city.

  Automatically handles both city-specific and country-wide sources.
  Returns a map of source_name => stats.

  Optimized to use batched queries instead of N individual queries.

  ## Parameters

    * `city_id` - The city ID to filter by (integer)
    * `source_names` - List of source names to query (list of strings)

  ## Returns

  A map where keys are source names and values are stats maps.

  ## Examples

      iex> get_all_source_stats(1, ["bandsintown", "ticketmaster", "pubquiz-pl"])
      %{
        "bandsintown" => %{run_count: 5, success_count: 4, ...},
        "ticketmaster" => %{run_count: 3, success_count: 3, ...},
        "pubquiz-pl" => %{run_count: 10, success_count: 10, ...}
      }
  """
  def get_all_source_stats(city_id, source_names)
      when is_integer(city_id) and is_list(source_names) do
    # Separate country-wide from city-specific sources
    {country_wide_sources, city_sources} =
      Enum.split_with(source_names, &(&1 in @country_wide_sources))

    # Get stats for city-specific sources
    city_stats = get_city_sources_batch(city_id, city_sources)

    # Get stats for country-wide sources
    country_wide_stats = get_country_wide_sources_batch(country_wide_sources)

    # Merge the results
    Map.merge(city_stats, country_wide_stats)
  end

  def get_all_source_stats(_city_id, _source_names) do
    Logger.warning("Invalid input to get_all_source_stats")
    %{}
  end

  # Private functions

  defp get_city_stats(worker, city_id) do
    # Query for aggregate stats with city filter
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
  end

  defp get_country_wide_stats(worker) do
    # Query for aggregate stats WITHOUT city filter
    stats_query =
      from j in "oban_jobs",
        where: j.worker == ^worker,
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
        _ -> get_last_error_country_wide(worker)
      end

    Map.put(stats, :last_error, last_error)
  end

  defp get_city_sources_batch(city_id, source_names) do
    # Build worker name mapping
    worker_to_source =
      source_names
      |> Enum.map(fn source_name ->
        worker = Map.get(@source_to_worker, source_name)
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

  defp get_country_wide_sources_batch(source_names) do
    # Build worker name mapping
    worker_to_source =
      source_names
      |> Enum.map(fn source_name ->
        worker = Map.get(@source_to_worker, source_name)
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
      # Single batched query for all workers WITHOUT city filter
      stats_query =
        from j in "oban_jobs",
          where: j.worker in ^workers,
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
          get_last_errors_batch_country_wide(workers_with_errors)
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

  defp get_last_error_country_wide(worker) do
    error_query =
      from j in "oban_jobs",
        where: j.worker == ^worker,
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

  defp get_last_errors_batch_country_wide(workers) do
    # Fetch latest error for each worker in a single query (no city filter)
    error_query =
      from j in "oban_jobs",
        where: j.worker in ^workers,
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
