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
  alias EventasaurusDiscovery.Sources.SourceRegistry
  require Logger

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
    # Get worker name from SourceRegistry
    case SourceRegistry.get_worker_name(source_name) do
      {:error, :not_found} ->
        Logger.debug("Unknown source: #{source_name}")
        default_stats()

      {:ok, worker} ->
        # Check if source requires city using SourceRegistry
        requires_city = SourceRegistry.requires_city_id?(source_name)

        if requires_city do
          get_city_stats(worker, city_id)
        else
          get_country_wide_stats(worker)
        end
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
    # Separate sources by scope using SourceRegistry
    {non_city_sources, city_sources} =
      Enum.split_with(source_names, fn source_name ->
        not SourceRegistry.requires_city_id?(source_name)
      end)

    # Get stats for city-specific sources
    city_stats = get_city_sources_batch(city_id, city_sources)

    # Get stats for non-city sources (country-wide/regional)
    non_city_stats = get_country_wide_sources_batch(non_city_sources)

    # Merge the results
    Map.merge(city_stats, non_city_stats)
  end

  def get_all_source_stats(_city_id, _source_names) do
    Logger.warning("Invalid input to get_all_source_stats")
    %{}
  end

  # Private functions

  defp get_city_stats(worker, city_id) do
    # Query for aggregate stats with city filter
    stats_query =
      from(j in "oban_jobs",
        where: j.worker == ^worker,
        where: fragment("? ->> 'city_id' = ?", j.args, ^to_string(city_id)),
        where: j.state in ["completed", "discarded"],
        select: %{
          run_count: count(j.id),
          success_count: fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.state),
          error_count: fragment("COUNT(CASE WHEN ? = 'discarded' THEN 1 END)", j.state),
          last_run_at:
            fragment(
              "MAX(COALESCE(?, ?, ?))",
              j.completed_at,
              j.discarded_at,
              j.attempted_at
            )
        }
      )

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
      from(j in "oban_jobs",
        where: j.worker == ^worker,
        where: j.state in ["completed", "discarded"],
        select: %{
          run_count: count(j.id),
          success_count: fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.state),
          error_count: fragment("COUNT(CASE WHEN ? = 'discarded' THEN 1 END)", j.state),
          last_run_at:
            fragment(
              "MAX(COALESCE(?, ?, ?))",
              j.completed_at,
              j.discarded_at,
              j.attempted_at
            )
        }
      )

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
    # Build worker name mapping using SourceRegistry
    worker_to_source =
      source_names
      |> Enum.map(fn source_name ->
        case SourceRegistry.get_worker_name(source_name) do
          {:ok, worker} -> {worker, source_name}
          {:error, _} -> {nil, source_name}
        end
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
        from(j in "oban_jobs",
          where: j.worker in ^workers,
          where: fragment("? ->> 'city_id' = ?", j.args, ^to_string(city_id)),
          where: j.state in ["completed", "discarded"],
          group_by: j.worker,
          select: %{
            worker: j.worker,
            run_count: count(j.id),
            success_count: fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.state),
            error_count: fragment("COUNT(CASE WHEN ? = 'discarded' THEN 1 END)", j.state),
            last_run_at:
              fragment(
                "MAX(COALESCE(?, ?, ?))",
                j.completed_at,
                j.discarded_at,
                j.attempted_at
              )
          }
        )

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
    # Build worker name mapping using SourceRegistry
    worker_to_source =
      source_names
      |> Enum.map(fn source_name ->
        case SourceRegistry.get_worker_name(source_name) do
          {:ok, worker} -> {worker, source_name}
          {:error, _} -> {nil, source_name}
        end
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
        from(j in "oban_jobs",
          where: j.worker in ^workers,
          where: j.state in ["completed", "discarded"],
          group_by: j.worker,
          select: %{
            worker: j.worker,
            run_count: count(j.id),
            success_count: fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.state),
            error_count: fragment("COUNT(CASE WHEN ? = 'discarded' THEN 1 END)", j.state),
            last_run_at:
              fragment(
                "MAX(COALESCE(?, ?, ?))",
                j.completed_at,
                j.discarded_at,
                j.attempted_at
              )
          }
        )

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
      from(j in "oban_jobs",
        where: j.worker == ^worker,
        where: fragment("? ->> 'city_id' = ?", j.args, ^to_string(city_id)),
        where: j.state == "discarded",
        order_by: [
          desc:
            fragment(
              "COALESCE(?, ?, ?)",
              j.discarded_at,
              j.completed_at,
              j.attempted_at
            )
        ],
        limit: 1,
        select: j.errors
      )

    case Repo.one(error_query) do
      nil -> nil
      [] -> nil
      errors when is_list(errors) -> format_error(List.first(errors))
      _ -> nil
    end
  end

  defp get_last_error_country_wide(worker) do
    error_query =
      from(j in "oban_jobs",
        where: j.worker == ^worker,
        where: j.state == "discarded",
        order_by: [
          desc:
            fragment(
              "COALESCE(?, ?, ?)",
              j.discarded_at,
              j.completed_at,
              j.attempted_at
            )
        ],
        limit: 1,
        select: j.errors
      )

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
      from(j in "oban_jobs",
        where: j.worker in ^workers,
        where: fragment("? ->> 'city_id' = ?", j.args, ^to_string(city_id)),
        where: j.state == "discarded",
        distinct: [j.worker],
        order_by: [
          asc: j.worker,
          desc:
            fragment(
              "COALESCE(?, ?, ?)",
              j.discarded_at,
              j.completed_at,
              j.attempted_at
            )
        ],
        select: {j.worker, j.errors}
      )

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
      from(j in "oban_jobs",
        where: j.worker in ^workers,
        where: j.state == "discarded",
        distinct: [j.worker],
        order_by: [
          asc: j.worker,
          desc:
            fragment(
              "COALESCE(?, ?, ?)",
              j.discarded_at,
              j.completed_at,
              j.attempted_at
            )
        ],
        select: {j.worker, j.errors}
      )

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

  # Helper to convert NaiveDateTime to DateTime (assumes UTC)
  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp to_datetime(nil), do: nil

  @doc """
  Get the run history for a specific source.

  Returns a list of recent job executions with their status and metadata.

  ## Parameters

    * `source_slug` - The source name (string)
    * `limit` - Maximum number of runs to return (default: 10)

  ## Returns

  A list of maps with job execution details.

  ## Examples

      iex> get_run_history("bandsintown", 5)
      [
        %{
          completed_at: ~U[2025-01-07 12:00:00Z],
          state: "completed",
          duration_seconds: 125,
          errors: nil,
          city_id: 1
        },
        ...
      ]
  """
  def get_run_history(source_slug, limit \\ 10)
      when is_binary(source_slug) and is_integer(limit) do
    case SourceRegistry.get_worker_name(source_slug) do
      {:error, :not_found} ->
        []

      {:ok, worker_name} ->
        query =
          from(j in "oban_jobs",
            where: j.worker == ^worker_name,
            where: j.state in ["completed", "discarded"],
            order_by: [
              desc:
                fragment(
                  "COALESCE(?, ?)",
                  j.completed_at,
                  j.discarded_at
                )
            ],
            limit: ^limit,
            select: %{
              completed_at:
                fragment(
                  "COALESCE(?, ?)",
                  j.completed_at,
                  j.discarded_at
                ),
              attempted_at: j.attempted_at,
              state: j.state,
              errors: j.errors,
              args: j.args
            }
          )

        query
        |> Repo.all()
        |> Enum.map(&enrich_job_history/1)
    end
  end

  defp enrich_job_history(job) do
    # Calculate duration in seconds
    duration_seconds =
      if job.completed_at && job.attempted_at do
        # Convert NaiveDateTime to DateTime for diff calculation
        completed = to_datetime(job.completed_at)
        attempted = to_datetime(job.attempted_at)
        DateTime.diff(completed, attempted)
      else
        nil
      end

    # Extract city_id from args if present
    city_id =
      case job.args do
        %{"city_id" => city_id} when is_integer(city_id) ->
          city_id
        %{"city_id" => city_id} when is_binary(city_id) ->
          case Integer.parse(city_id) do
            {id, ""} -> id
            _ -> nil
          end
        _ ->
          nil
      end

    # Format errors
    formatted_error =
      case job.errors do
        nil -> nil
        [] -> nil
        errors when is_list(errors) -> format_error(List.first(errors))
        _ -> nil
      end

    %{
      completed_at: job.completed_at,
      attempted_at: job.attempted_at,
      state: job.state,
      duration_seconds: duration_seconds,
      errors: formatted_error,
      city_id: city_id
    }
  end

  @doc """
  Get the average runtime for a source over the last N days.

  ## Parameters

    * `source_slug` - The source name (string)
    * `days` - Number of days to look back (default: 30)

  ## Returns

  Average runtime in seconds, or nil if no data available.

  ## Examples

      iex> get_average_runtime("bandsintown", 7)
      142.5
  """
  def get_average_runtime(source_slug, days \\ 30)
      when is_binary(source_slug) and is_integer(days) do
    case SourceRegistry.get_worker_name(source_slug) do
      {:error, :not_found} ->
        nil

      {:ok, worker_name} ->
        cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)

        query =
          from(j in "oban_jobs",
            where: j.worker == ^worker_name,
            where: j.state == "completed",
            where: j.completed_at >= ^cutoff,
            select:
              avg(
                fragment(
                  "EXTRACT(EPOCH FROM (? - ?))",
                  j.completed_at,
                  j.attempted_at
                )
              )
          )

        case Repo.one(query) do
          nil -> nil
          avg when is_float(avg) or is_integer(avg) -> avg
          %Decimal{} = decimal -> Decimal.to_float(decimal)
          _ -> nil
        end
    end
  end

  @doc """
  Get events by city for a specific source.

  Returns a list of cities with event counts for city-scoped sources.

  ## Parameters

    * `source_slug` - The source name (string)
    * `limit` - Maximum number of cities to return (default: 20)

  ## Returns

  A list of maps with city and event count data.

  ## Examples

      iex> get_events_by_city_for_source("bandsintown", 10)
      [
        %{city_id: 1, city_name: "Krakow", event_count: 234, new_this_week: 12},
        ...
      ]
  """
  def get_events_by_city_for_source(source_slug, limit \\ 20)
      when is_binary(source_slug) and is_integer(limit) do
    # Get the source ID from the database
    source_query =
      from(s in EventasaurusDiscovery.Sources.Source,
        where: s.slug == ^source_slug,
        select: s.id
      )

    case Repo.one(source_query) do
      nil ->
        []

      source_id ->
        week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

        # Query for city-level event counts
        query =
          from(pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
            join: e in EventasaurusDiscovery.PublicEvents.PublicEvent,
            on: e.id == pes.event_id,
            join: v in EventasaurusApp.Venues.Venue,
            on: v.id == e.venue_id,
            join: c in EventasaurusDiscovery.Locations.City,
            on: c.id == v.city_id,
            where: pes.source_id == ^source_id,
            group_by: [c.id, c.name],
            order_by: [desc: count(e.id)],
            limit: ^limit,
            select: %{
              city_id: c.id,
              city_name: c.name,
              event_count: count(e.id),
              new_this_week:
                fragment(
                  "COUNT(CASE WHEN ? >= ? THEN 1 END)",
                  e.inserted_at,
                  ^week_ago
                )
            }
          )

        Repo.all(query)
    end
  end
end
