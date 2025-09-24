defmodule Eventasaurus.Services.PosthogMonitor do
  @moduledoc """
  Monitors PostHog analytics health and tracks failures.

  Provides metrics on:
  - API request success/failure rates
  - Response times
  - Timeout frequency
  - Cache hit rates
  """

  use GenServer
  require Logger

  # Reset stats every hour
  @stats_reset_interval 60 * 60 * 1000
  # Log summary every 5 minutes
  @log_interval 5 * 60 * 1000

  # Client API

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Record a successful API request
  """
  def record_success(type, duration_ms) do
    GenServer.cast(__MODULE__, {:record_success, type, duration_ms})
  end

  @doc """
  Record a failed API request
  """
  def record_failure(type, reason) do
    GenServer.cast(__MODULE__, {:record_failure, type, reason})
  end

  @doc """
  Record a cache hit
  """
  def record_cache_hit(type) do
    GenServer.cast(__MODULE__, {:record_cache_hit, type})
  end

  @doc """
  Record a cache miss
  """
  def record_cache_miss(type) do
    GenServer.cast(__MODULE__, {:record_cache_miss, type})
  end

  @doc """
  Get current stats
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Get health status
  """
  def health_check do
    stats = get_stats()

    analytics_health = check_type_health(stats.analytics, "analytics")
    events_health = check_type_health(stats.events, "events")

    # Return the worst health status
    case {analytics_health, events_health} do
      {{:unhealthy, msg}, _} -> {:unhealthy, msg}
      {_, {:unhealthy, msg}} -> {:unhealthy, msg}
      {{:degraded, msg}, _} -> {:degraded, msg}
      {_, {:degraded, msg}} -> {:degraded, msg}
      _ -> {:healthy, "All systems operational"}
    end
  end

  # GenServer Callbacks

  @impl true
  def init(:ok) do
    # Schedule periodic tasks
    :timer.send_interval(@log_interval, :log_summary)
    :timer.send_interval(@stats_reset_interval, :reset_stats)

    {:ok, initial_state()}
  end

  @impl true
  def handle_cast({:record_success, type, duration_ms}, state) do
    new_state =
      state
      |> update_in([type, :success_count], &(&1 + 1))
      |> update_in([type, :total_duration], &(&1 + duration_ms))
      |> update_in([type, :max_duration], &max(&1, duration_ms))
      |> update_in([type, :min_duration], fn
        0 -> duration_ms
        current -> min(current, duration_ms)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_failure, type, reason}, state) do
    reason_key = categorize_failure(reason)

    new_state =
      state
      |> update_in([type, :failure_count], &(&1 + 1))
      |> update_in([type, :failures, reason_key], &((&1 || 0) + 1))

    # Log critical failures immediately
    if reason_key == :timeout and get_in(new_state, [type, :failures, :timeout]) >= 5 do
      Logger.error(
        "PostHog #{type} experiencing repeated timeouts (#{get_in(new_state, [type, :failures, :timeout])} in current period)"
      )
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_cache_hit, type}, state) do
    new_state = update_in(state, [type, :cache_hits], &(&1 + 1))
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_cache_miss, type}, state) do
    new_state = update_in(state, [type, :cache_misses], &(&1 + 1))
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      analytics: calculate_stats(state.analytics),
      events: calculate_stats(state.events),
      period_start: state.period_start,
      period_duration_minutes:
        div(System.monotonic_time(:millisecond) - state.period_start, 60000)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:log_summary, state) do
    analytics_stats = calculate_stats(state.analytics)
    events_stats = calculate_stats(state.events)

    # Only log if there's activity
    if analytics_stats.total_requests > 0 or events_stats.total_requests > 0 do
      Logger.info("""
      PostHog Monitor Summary:

      Analytics API:
        Requests: #{analytics_stats.total_requests} (#{analytics_stats.success_count} success, #{analytics_stats.failure_count} failed)
        Success Rate: #{Float.round(analytics_stats.success_rate * 100, 1)}%
        Avg Duration: #{analytics_stats.avg_duration}ms
        Cache Hit Rate: #{Float.round(analytics_stats.cache_hit_rate * 100, 1)}%
        Timeouts: #{Map.get(state.analytics.failures, :timeout, 0)}

      Event Tracking:
        Events Sent: #{events_stats.total_requests} (#{events_stats.success_count} success, #{events_stats.failure_count} failed)
        Success Rate: #{Float.round(events_stats.success_rate * 100, 1)}%
      """)

      # Send alerts if needed
      check_and_alert(analytics_stats, :analytics)
      check_and_alert(events_stats, :events)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:reset_stats, _state) do
    Logger.debug("Resetting PostHog monitor stats")
    {:noreply, initial_state()}
  end

  # Private Functions

  defp initial_state do
    %{
      analytics: %{
        success_count: 0,
        failure_count: 0,
        total_duration: 0,
        max_duration: 0,
        min_duration: 0,
        cache_hits: 0,
        cache_misses: 0,
        failures: %{}
      },
      events: %{
        success_count: 0,
        failure_count: 0,
        total_duration: 0,
        max_duration: 0,
        min_duration: 0,
        cache_hits: 0,
        cache_misses: 0,
        failures: %{}
      },
      period_start: System.monotonic_time(:millisecond)
    }
  end

  defp calculate_stats(data) do
    total = data.success_count + data.failure_count
    cache_total = data.cache_hits + data.cache_misses

    %{
      total_requests: total,
      success_count: data.success_count,
      failure_count: data.failure_count,
      success_rate: if(total > 0, do: data.success_count / total, else: 1.0),
      failure_rate: if(total > 0, do: data.failure_count / total, else: 0.0),
      timeout_rate: if(total > 0, do: Map.get(data.failures, :timeout, 0) / total, else: 0.0),
      avg_duration:
        if(data.success_count > 0, do: div(data.total_duration, data.success_count), else: 0),
      max_duration: data.max_duration,
      min_duration: data.min_duration,
      cache_hit_rate: if(cache_total > 0, do: data.cache_hits / cache_total, else: 0.0),
      failures_by_type: data.failures
    }
  end

  defp categorize_failure(reason) do
    case reason do
      :timeout -> :timeout
      {:request_failed, :timeout} -> :timeout
      {:api_error, 401} -> :auth_error
      {:api_error, 403} -> :auth_error
      {:api_error, 429} -> :rate_limit
      {:api_error, status} when status >= 500 -> :server_error
      :no_api_key -> :config_error
      :no_project_id -> :config_error
      _ -> :other
    end
  end

  defp check_type_health(type_stats, type_name) do
    cond do
      type_stats.failure_rate > 0.5 ->
        {:unhealthy,
         "High #{type_name} failure rate: #{Float.round(type_stats.failure_rate * 100, 1)}%"}

      type_stats.timeout_rate > 0.3 ->
        {:degraded,
         "High #{type_name} timeout rate: #{Float.round(type_stats.timeout_rate * 100, 1)}%"}

      type_stats.avg_duration > 10000 ->
        {:degraded, "Slow #{type_name} response times: #{type_stats.avg_duration}ms average"}

      true ->
        {:healthy, nil}
    end
  end

  defp check_and_alert(stats, type) do
    cond do
      stats.failure_rate > 0.5 ->
        Logger.error(
          "ALERT: PostHog #{type} failure rate above 50% (#{Float.round(stats.failure_rate * 100, 1)}%)"
        )

      # Could send to external monitoring service here

      stats.timeout_rate > 0.3 ->
        Logger.warning(
          "WARNING: PostHog #{type} timeout rate above 30% (#{Float.round(stats.timeout_rate * 100, 1)}%)"
        )

      stats.avg_duration > 15000 ->
        Logger.warning(
          "WARNING: PostHog #{type} average response time above 15s (#{stats.avg_duration}ms)"
        )

      true ->
        :ok
    end
  end
end
