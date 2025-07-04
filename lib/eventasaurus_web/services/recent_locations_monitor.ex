defmodule EventasaurusWeb.Services.RecentLocationsMonitor do
  @moduledoc """
  Monitoring service for Recent Locations cache performance.

  This service tracks cache hit/miss ratios, query performance,
  and provides insights for ongoing optimization.
  """

  use GenServer
  require Logger

  @monitor_name __MODULE__

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @monitor_name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Record a cache hit event.
  """
  def record_cache_hit(user_id, response_time_ms \\ 0) do
    GenServer.cast(@monitor_name, {:cache_hit, user_id, response_time_ms})
  end

  @doc """
  Record a cache miss event.
  """
  def record_cache_miss(user_id, response_time_ms \\ 0) do
    GenServer.cast(@monitor_name, {:cache_miss, user_id, response_time_ms})
  end

  @doc """
  Record a database query event.
  """
  def record_db_query(user_id, response_time_ms, result_count \\ 0) do
    GenServer.cast(@monitor_name, {:db_query, user_id, response_time_ms, result_count})
  end

  @doc """
  Get performance metrics.
  """
  def get_metrics do
    GenServer.call(@monitor_name, :get_metrics)
  end

  @doc """
  Get detailed performance report.
  """
  def get_performance_report do
    GenServer.call(@monitor_name, :get_performance_report)
  end

  @doc """
  Reset all metrics.
  """
  def reset_metrics do
    GenServer.cast(@monitor_name, :reset_metrics)
  end

  # Server implementation

  @impl true
  def init(_) do
    Logger.info("Starting Recent Locations Monitor")

    # Schedule periodic reporting
    :timer.send_interval(60_000, :periodic_report)  # Every minute

    {:ok, %{
      cache_hits: 0,
      cache_misses: 0,
      db_queries: 0,
      total_cache_response_time: 0,
      total_db_response_time: 0,
      max_cache_response_time: 0,
      max_db_response_time: 0,
      min_cache_response_time: :infinity,
      min_db_response_time: :infinity,
      total_results_returned: 0,
      started_at: DateTime.utc_now()
    }}
  end

  @impl true
  def handle_cast({:cache_hit, user_id, response_time_ms}, state) do
    Logger.debug("Cache hit for user #{user_id} in #{response_time_ms}ms")

    new_state = %{
      state |
      cache_hits: state.cache_hits + 1,
      total_cache_response_time: state.total_cache_response_time + response_time_ms,
      max_cache_response_time: max(state.max_cache_response_time, response_time_ms),
      min_cache_response_time: min(state.min_cache_response_time, response_time_ms)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:cache_miss, user_id, response_time_ms}, state) do
    Logger.debug("Cache miss for user #{user_id} in #{response_time_ms}ms")

    new_state = %{
      state |
      cache_misses: state.cache_misses + 1,
      total_cache_response_time: state.total_cache_response_time + response_time_ms,
      max_cache_response_time: max(state.max_cache_response_time, response_time_ms),
      min_cache_response_time: min(state.min_cache_response_time, response_time_ms)
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:db_query, user_id, response_time_ms, result_count}, state) do
    Logger.debug("DB query for user #{user_id} in #{response_time_ms}ms, returned #{result_count} results")

    new_state = %{
      state |
      db_queries: state.db_queries + 1,
      total_db_response_time: state.total_db_response_time + response_time_ms,
      max_db_response_time: max(state.max_db_response_time, response_time_ms),
      min_db_response_time: min(state.min_db_response_time, response_time_ms),
      total_results_returned: state.total_results_returned + result_count
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reset_metrics, _state) do
    Logger.info("Resetting Recent Locations Monitor metrics")

    {:noreply, %{
      cache_hits: 0,
      cache_misses: 0,
      db_queries: 0,
      total_cache_response_time: 0,
      total_db_response_time: 0,
      max_cache_response_time: 0,
      max_db_response_time: 0,
      min_cache_response_time: :infinity,
      min_db_response_time: :infinity,
      total_results_returned: 0,
      started_at: DateTime.utc_now()
    }}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    total_requests = state.cache_hits + state.cache_misses

    metrics = %{
      cache_hit_ratio: (if total_requests > 0, do: state.cache_hits / total_requests * 100, else: 0),
      total_requests: total_requests,
      cache_hits: state.cache_hits,
      cache_misses: state.cache_misses,
      db_queries: state.db_queries,
      avg_cache_response_time: (if total_requests > 0, do: state.total_cache_response_time / total_requests, else: 0),
      avg_db_response_time: (if state.db_queries > 0, do: state.total_db_response_time / state.db_queries, else: 0),
      max_cache_response_time: state.max_cache_response_time,
      max_db_response_time: state.max_db_response_time,
      min_cache_response_time: (if state.min_cache_response_time == :infinity, do: 0, else: state.min_cache_response_time),
      min_db_response_time: (if state.min_db_response_time == :infinity, do: 0, else: state.min_db_response_time),
      avg_results_per_query: (if state.db_queries > 0, do: state.total_results_returned / state.db_queries, else: 0),
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at)
    }

    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:get_performance_report, _from, state) do
    metrics = handle_call(:get_metrics, nil, state) |> elem(1)

    report = """
    Recent Locations Cache Performance Report
    ========================================

    Uptime: #{metrics.uptime_seconds} seconds

    Cache Performance:
    - Hit Ratio: #{Float.round(metrics.cache_hit_ratio, 2)}%
    - Total Requests: #{metrics.total_requests}
    - Cache Hits: #{metrics.cache_hits}
    - Cache Misses: #{metrics.cache_misses}

    Response Times:
    - Average Cache Response: #{Float.round(metrics.avg_cache_response_time, 2)}ms
    - Average DB Response: #{Float.round(metrics.avg_db_response_time, 2)}ms
    - Max Cache Response: #{metrics.max_cache_response_time}ms
    - Max DB Response: #{metrics.max_db_response_time}ms

    Database Performance:
    - Total DB Queries: #{metrics.db_queries}
    - Average Results per Query: #{Float.round(metrics.avg_results_per_query, 2)}

    Performance Improvement:
    - Cache Speedup: #{if metrics.avg_db_response_time > 0, do: Float.round(metrics.avg_db_response_time / metrics.avg_cache_response_time, 2), else: "N/A"}x faster
    """

    {:reply, report, state}
  end

  @impl true
  def handle_info(:periodic_report, state) do
    # Only log if we have activity
    if state.cache_hits + state.cache_misses > 0 do
      metrics = handle_call(:get_metrics, nil, state) |> elem(1)

      Logger.info("Recent Locations Cache Performance - Hit Rate: #{Float.round(metrics.cache_hit_ratio, 1)}%, " <>
                  "Total Requests: #{metrics.total_requests}, " <>
                  "Avg Cache Time: #{Float.round(metrics.avg_cache_response_time, 1)}ms, " <>
                  "Avg DB Time: #{Float.round(metrics.avg_db_response_time, 1)}ms")
    end

    {:noreply, state}
  end
end
