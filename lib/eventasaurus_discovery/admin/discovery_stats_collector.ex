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

  **DEPRECATED**: Use `get_metadata_based_source_stats/2` instead for accurate event-level tracking.

  This function queries job.state (completed/discarded) which only reflects job execution outcomes,
  not actual event processing success/failure. After MetricsTracker was implemented, the correct
  approach is to query meta->>'status' (success/failed) for event-level accuracy.

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

  @doc """
  Get metadata-based source statistics for all sources.

  RECOMMENDED: Use this instead of get_all_source_stats for accurate success/failure tracking.

  Queries meta->>'status' (success/failed) from job metadata instead of job.state (completed/discarded).
  This provides accurate event-level processing outcomes rather than just job execution outcomes.

  ## Parameters

    * `city_id` - The city ID to filter by (integer or nil for all cities aggregated)
    * `source_names` - List of source names to query (list of strings)

  ## Returns

  A map where keys are source names and values are enhanced stats maps including:
    * `:events_processed` - Total events processed (from metadata)
    * `:events_succeeded` - Events that succeeded (from metadata)
    * `:events_failed` - Events that failed (from metadata)
    * `:success_rate` - Success rate percentage
    * `:last_run_at` - Most recent job completion timestamp

  ## Examples

      iex> get_metadata_based_source_stats(1, ["bandsintown", "karnet"])
      %{
        "bandsintown" => %{
          events_processed: 1250,
          events_succeeded: 1180,
          events_failed: 70,
          success_rate: 94.4,
          last_run_at: ~U[2025-01-07 12:00:00Z]
        },
        "karnet" => %{...}
      }

      iex> get_metadata_based_source_stats(nil, ["bandsintown"])
      %{
        "bandsintown" => %{
          events_processed: 2500,  # Aggregated across all cities
          events_succeeded: 2300,
          ...
        }
      }
  """
  def get_metadata_based_source_stats(city_id, source_names)
      when (is_integer(city_id) or is_nil(city_id)) and is_list(source_names) do
    source_names
    |> Enum.map(fn source_name ->
      stats = get_detailed_source_stats(city_id, source_name)
      {source_name, stats}
    end)
    |> Enum.into(%{})
  end

  def get_metadata_based_source_stats(_city_id, _source_names) do
    Logger.warning("Invalid input to get_metadata_based_source_stats")
    %{}
  end

  # Private functions

  defp get_city_stats(worker, city_id) do
    # Query for aggregate stats with city filter
    # Note: args->>'city_id' returns TEXT, so we cast to integer for comparison
    # Guard: only cast if value is numeric to prevent query crashes
    stats_query =
      from(j in "oban_jobs",
        where: j.worker == ^worker,
        where: fragment("?->>'city_id' ~ '^[0-9]+$'", j.args),
        where: fragment("(? ->> 'city_id')::integer = ?", j.args, ^city_id),
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

    stats = Repo.replica().one(stats_query) || default_stats()

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

    stats = Repo.replica().one(stats_query) || default_stats()

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
      # Note: args->>'city_id' returns TEXT, so we cast to integer for comparison
      # Guard: only cast if value is numeric to prevent query crashes
      stats_query =
        from(j in "oban_jobs",
          where: j.worker in ^workers,
          where: fragment("?->>'city_id' ~ '^[0-9]+$'", j.args),
          where: fragment("(? ->> 'city_id')::integer = ?", j.args, ^city_id),
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
        |> Repo.replica().all()
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
        |> Repo.replica().all()
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
    # Note: args->>'city_id' returns TEXT, so we cast to integer for comparison
    # Guard: only cast if value is numeric to prevent query crashes
    error_query =
      from(j in "oban_jobs",
        where: j.worker == ^worker,
        where: fragment("?->>'city_id' ~ '^[0-9]+$'", j.args),
        where: fragment("(? ->> 'city_id')::integer = ?", j.args, ^city_id),
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

    case Repo.replica().one(error_query) do
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

    case Repo.replica().one(error_query) do
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
    # Note: args->>'city_id' returns TEXT, so we cast to integer for comparison
    # Guard: only cast if value is numeric to prevent query crashes
    error_query =
      from(j in "oban_jobs",
        where: j.worker in ^workers,
        where: fragment("?->>'city_id' ~ '^[0-9]+$'", j.args),
        where: fragment("(? ->> 'city_id')::integer = ?", j.args, ^city_id),
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
    |> Repo.replica().all()
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
    |> Repo.replica().all()
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
  Get the run history for a specific source (DEPRECATED - shows failures only).

  **DEPRECATED**: Use `get_complete_run_history/2` for accurate success + failure history.

  Returns a list of recent job executions with their status and metadata.

  Queries DETAIL workers (e.g., EventDetailJob, VenueDetailJob) instead of sync workers,
  and uses metadata status (meta->>'status') instead of job state for accurate event-level tracking.

  ## Parameters

    * `source_slug` - The source name (string)
    * `limit` - Maximum number of runs to return (default: 10)

  ## Returns

  A list of maps with job execution details from metadata.

  ## Examples

      iex> get_run_history("bandsintown", 5)
      [
        %{
          completed_at: ~U[2025-01-07 12:00:00Z],
          state: "success",
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

      {:ok, sync_worker} ->
        # Get the detail worker instead of sync worker
        detail_worker = determine_detail_worker(sync_worker)

        query =
          from(j in "oban_jobs",
            where: j.worker == ^detail_worker,
            where: j.state in ["completed", "discarded"],
            where: fragment("meta->>'status' IS NOT NULL"),
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
              state: fragment("meta->>'status'"),
              errors: fragment("meta->>'error_message'"),
              args: j.args,
              meta: j.meta
            }
          )

        query
        |> Repo.replica().all()
        |> Enum.map(&enrich_job_history/1)
    end
  end

  @doc """
  Get complete run history for a specific source (successes AND failures).

  Returns a list of recent job executions including BOTH successful and failed runs.
  This provides accurate context by showing the complete pattern of job execution,
  not just failures.

  Queries DETAIL workers (e.g., EventDetailJob, VenueDetailJob) instead of sync workers,
  and uses metadata status (meta->>'status') for accurate event-level tracking.

  ## Parameters

    * `source_slug` - The source name (string)
    * `limit` - Maximum number of runs to return (default: 20)

  ## Returns

  A list of maps with complete job execution details (successes + failures).

  ## Examples

      iex> get_complete_run_history("bandsintown", 20)
      [
        %{
          completed_at: ~U[2025-01-07 12:00:00Z],
          state: "completed",
          duration_seconds: 125,
          errors: nil,
          city_id: 1
        },
        %{
          completed_at: ~U[2025-01-07 11:55:00Z],
          state: "failed",
          duration_seconds: 5,
          errors: "Network timeout",
          city_id: 1
        },
        ...
      ]
  """
  def get_complete_run_history(source_slug, limit \\ 20)
      when is_binary(source_slug) and is_integer(limit) do
    case SourceRegistry.get_worker_name(source_slug) do
      {:error, :not_found} ->
        []

      {:ok, sync_worker} ->
        # Get the detail worker instead of sync worker
        detail_worker = determine_detail_worker(sync_worker)

        # Query ALL jobs (with or without metadata status) to show complete history
        query =
          from(j in "oban_jobs",
            where: j.worker == ^detail_worker,
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
              id: j.id,
              completed_at:
                fragment(
                  "COALESCE(?, ?)",
                  j.completed_at,
                  j.discarded_at
                ),
              attempted_at: j.attempted_at,
              # Use metadata status if available, otherwise map job state
              state:
                fragment(
                  "COALESCE(meta->>'status', CASE WHEN ? = 'completed' THEN 'success' ELSE 'failed' END)",
                  j.state
                ),
              errors: fragment("meta->>'error_message'"),
              args: j.args,
              meta: j.meta
            }
          )

        query
        |> Repo.replica().all()
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

    # Errors come from metadata now (already extracted as string)
    # No need to format since it's already meta->>'error_message'
    formatted_error = job.errors

    %{
      id: job.id,
      completed_at: job.completed_at,
      attempted_at: job.attempted_at,
      state: job.state,
      duration_seconds: duration_seconds,
      errors: formatted_error,
      city_id: city_id,
      meta: job.meta,
      args: job.args
    }
  end

  @doc """
  Get the average runtime for a source over the last N days.

  Queries DETAIL workers (e.g., EventDetailJob, VenueDetailJob) instead of sync workers,
  and uses metadata status (meta->>'status' = 'success') to ensure only successful
  event-level processing runs are included in the average.

  ## Parameters

    * `source_slug` - The source name (string)
    * `days` - Number of days to look back (default: 30)

  ## Returns

  Average runtime in seconds, or nil if no successful runs available.

  ## Examples

      iex> get_average_runtime("bandsintown", 7)
      142.5

      iex> get_average_runtime("sortiraparis", 30)
      nil  # Returns nil when no successful detail worker runs exist
  """
  def get_average_runtime(source_slug, days \\ 30)
      when is_binary(source_slug) and is_integer(days) do
    case SourceRegistry.get_worker_name(source_slug) do
      {:error, :not_found} ->
        nil

      {:ok, sync_worker} ->
        # Get the detail worker instead of sync worker
        detail_worker = determine_detail_worker(sync_worker)
        cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)

        # Query detail workers with successful metadata status
        query =
          from(j in "oban_jobs",
            where: j.worker == ^detail_worker,
            where: j.state == "completed",
            where: fragment("meta->>'status' = 'success'"),
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

        case Repo.replica().one(query) do
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

    case Repo.replica().one(source_query) do
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

        Repo.replica().all(query)
    end
  end

  @doc """
  Get detailed metrics for a source including success/failure breakdown from job metadata.

  Returns both job-level stats and event-level stats from metadata.

  ## Parameters

    * `city_id` - The city ID to filter by (integer or nil for country-wide)
    * `source_name` - The source name (string)

  ## Returns

  Enhanced stats map with:
    * `:events_processed` - Total events processed (from metadata)
    * `:events_succeeded` - Events that succeeded (from metadata)
    * `:events_failed` - Events that failed (from metadata)
    * `:success_rate` - Success rate percentage

  ## Examples

      iex> get_detailed_source_stats(1, "bandsintown")
      %{
        run_count: 5,
        success_count: 4,
        error_count: 1,
        events_processed: 1250,
        events_succeeded: 1180,
        events_failed: 70,
        success_rate: 94.4
      }
  """
  def get_detailed_source_stats(city_id, source_name) do
    base_stats = get_source_stats(city_id, source_name)

    # Get event-level metrics from job metadata
    case SourceRegistry.get_worker_name(source_name) do
      {:ok, worker} ->
        detail_worker = determine_detail_worker(worker)
        event_stats = get_event_level_stats(detail_worker, city_id, source_name)

        # Compute last_run_at from detail worker instead of sync worker
        # This is especially important when city_id is nil (aggregating across all cities)
        last_run_at = get_last_run_at(detail_worker, city_id, source_name)

        Map.merge(base_stats, %{
          # New metadata-based fields
          events_processed: event_stats.processed,
          events_succeeded: event_stats.succeeded,
          events_failed: event_stats.failed,
          success_rate: calculate_success_rate(event_stats.succeeded, event_stats.processed),
          last_run_at: last_run_at || base_stats.last_run_at,
          # Legacy fields for backward compatibility with Stats page template
          run_count: event_stats.processed,
          success_count: event_stats.succeeded,
          error_count: event_stats.failed
        })

      {:error, _} ->
        base_stats
    end
  end

  @doc """
  Get event-level statistics for all sources.

  Returns a list of detailed stats for each source, sorted by success rate.

  ## Parameters

    * `opts` - Options (keyword list)
      * `:city_id` - Filter by city (nil for aggregate)
      * `:min_events` - Minimum events to include (default: 0)

  ## Returns

  List of maps with detailed source stats.

  ## Examples

      iex> get_detailed_source_statistics(min_events: 10)
      [
        %{
          source: "bandsintown",
          events_processed: 1250,
          events_succeeded: 1180,
          events_failed: 70,
          success_rate: 94.4,
          last_run_at: ~U[2025-01-07 12:00:00Z]
        },
        ...
      ]
  """
  def get_detailed_source_statistics(opts \\ []) do
    city_id = Keyword.get(opts, :city_id)
    min_events = Keyword.get(opts, :min_events, 0)

    # Get all sources
    sources = SourceRegistry.all_sources()

    # For each source, get detailed stats
    sources
    |> Enum.map(fn source_name ->
      stats = get_detailed_source_stats(city_id, source_name)

      %{
        source: source_name,
        events_processed: stats[:events_processed] || 0,
        events_succeeded: stats[:events_succeeded] || 0,
        events_failed: stats[:events_failed] || 0,
        success_rate: stats[:success_rate] || 0.0,
        last_run_at: stats[:last_run_at]
      }
    end)
    |> Enum.filter(fn stats -> stats.events_processed >= min_events end)
    |> Enum.sort_by(& &1.success_rate, :desc)
  end

  # Private helper functions for event-level stats

  defp get_event_level_stats(detail_worker, city_id, source_name) do
    # Build the appropriate query based on whether source requires city_id
    stats_query =
      if SourceRegistry.requires_city_id?(source_name) && city_id do
        from(j in "oban_jobs",
          where: j.worker == ^detail_worker,
          where: fragment("?->>'city_id' ~ '^[0-9]+$'", j.args),
          where: fragment("(? ->> 'city_id')::integer = ?", j.args, ^city_id),
          where: j.state in ["completed", "discarded"],
          select: %{
            processed: fragment("COUNT(*) FILTER (WHERE meta->>'status' IS NOT NULL)"),
            succeeded: fragment("COUNT(*) FILTER (WHERE meta->>'status' = 'success')"),
            failed: fragment("COUNT(*) FILTER (WHERE meta->>'status' = 'failed')")
          }
        )
      else
        from(j in "oban_jobs",
          where: j.worker == ^detail_worker,
          where: j.state in ["completed", "discarded"],
          select: %{
            processed: fragment("COUNT(*) FILTER (WHERE meta->>'status' IS NOT NULL)"),
            succeeded: fragment("COUNT(*) FILTER (WHERE meta->>'status' = 'success')"),
            failed: fragment("COUNT(*) FILTER (WHERE meta->>'status' = 'failed')")
          }
        )
      end

    Repo.replica().one(stats_query) || %{processed: 0, succeeded: 0, failed: 0}
  end

  defp get_last_run_at(detail_worker, city_id, source_name) do
    # Query for most recent job completion timestamp from detail worker
    # This fixes the issue where city_id=nil aggregation would return nil last_run_at
    timestamp_query =
      if SourceRegistry.requires_city_id?(source_name) && city_id do
        from(j in "oban_jobs",
          where: j.worker == ^detail_worker,
          where: fragment("?->>'city_id' ~ '^[0-9]+$'", j.args),
          where: fragment("(? ->> 'city_id')::integer = ?", j.args, ^city_id),
          where: j.state in ["completed", "discarded"],
          select:
            fragment(
              "MAX(COALESCE(?, ?, ?))",
              j.completed_at,
              j.discarded_at,
              j.attempted_at
            )
        )
      else
        from(j in "oban_jobs",
          where: j.worker == ^detail_worker,
          where: j.state in ["completed", "discarded"],
          select:
            fragment(
              "MAX(COALESCE(?, ?, ?))",
              j.completed_at,
              j.discarded_at,
              j.attempted_at
            )
        )
      end

    Repo.replica().one(timestamp_query)
  end

  defp determine_detail_worker(sync_worker) do
    # Map SyncJob workers to their corresponding detail job workers
    cond do
      String.contains?(sync_worker, "Bandsintown.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob"

      String.contains?(sync_worker, "ResidentAdvisor.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.EventDetailJob"

      String.contains?(sync_worker, "Karnet.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.Karnet.Jobs.EventDetailJob"

      String.contains?(sync_worker, "Sortiraparis.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJob"

      String.contains?(sync_worker, "Ticketmaster.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob"

      String.contains?(sync_worker, "Repertuary.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.Repertuary.Jobs.ShowtimeProcessJob"

      String.contains?(sync_worker, "CinemaCity.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob"

      String.contains?(sync_worker, "PubquizPl.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.PubquizPl.Jobs.VenueDetailJob"

      String.contains?(sync_worker, "QuestionOne.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.QuestionOne.Jobs.VenueDetailJob"

      String.contains?(sync_worker, "GeeksWhoDrink.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.VenueDetailJob"

      String.contains?(sync_worker, "Quizmeisters.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.Quizmeisters.Jobs.VenueDetailJob"

      String.contains?(sync_worker, "Inquizition.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.Inquizition.Jobs.VenueDetailJob"

      String.contains?(sync_worker, "SpeedQuizzing.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.SpeedQuizzing.Jobs.EventDetailJob"

      String.contains?(sync_worker, "Waw4free.Jobs.SyncJob") ->
        "EventasaurusDiscovery.Sources.Waw4free.Jobs.EventDetailJob"

      true ->
        # Fallback to sync worker if no mapping found
        sync_worker
    end
  end

  defp calculate_success_rate(_succeeded, 0), do: 0.0

  defp calculate_success_rate(succeeded, processed) when processed > 0 do
    (succeeded / processed * 100) |> Float.round(1)
  end
end
