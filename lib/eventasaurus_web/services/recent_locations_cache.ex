defmodule EventasaurusWeb.Services.RecentLocationsCache do
  @moduledoc """
  GenServer-based cache for recent locations to improve performance.

  This cache reduces database load by storing recent location queries for a configurable TTL.
  The cache is designed to be:
  - Memory-efficient (automatic expiration)
  - Fast (in-memory lookup)
  - Fault-tolerant (graceful degradation if cache is unavailable)
  """
  use GenServer
  require Logger

  # Cache TTL: 5 minutes (configurable)
  @default_ttl :timer.minutes(5)
  @cache_name __MODULE__

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @cache_name)
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    GenServer.start_link(__MODULE__, %{ttl: ttl}, name: name)
  end

  @doc """
  Get recent locations for a user from cache, or fetch and cache if not present.

  Returns `{:ok, locations}` on success, `{:error, reason}` on failure.
  Falls back to direct database query if cache is unavailable.
  """
  def get_recent_locations(user_id, opts \\ []) do
    cache_key = build_cache_key(user_id, opts)

    case get_from_cache(cache_key) do
      {:ok, locations} ->
        Logger.debug("Cache hit for user #{user_id} recent locations")
        {:ok, locations}
      {:error, :not_found} ->
        Logger.debug("Cache miss for user #{user_id} recent locations")
        fetch_and_cache(user_id, opts, cache_key)
      {:error, reason} ->
        Logger.warn("Cache error for user #{user_id}: #{inspect(reason)}, falling back to DB")
        # Fallback to direct database query
        EventasaurusApp.Events.get_recent_locations_for_user(user_id, opts)
    end
  end

  @doc """
  Invalidate cache for a specific user.
  Useful when user creates new events or venues.
  """
  def invalidate_user_cache(user_id) do
    GenServer.cast(@cache_name, {:invalidate_user, user_id})
  end

  @doc """
  Clear all cached data.
  """
  def clear_cache do
    GenServer.cast(@cache_name, :clear_all)
  end

  @doc """
  Get cache statistics for monitoring.
  """
  def get_stats do
    GenServer.call(@cache_name, :get_stats)
  end

  # Private client helpers

  defp get_from_cache(cache_key) do
    try do
      case GenServer.call(@cache_name, {:get, cache_key}, 1000) do
        {:ok, _locations} = result -> result
        :not_found -> {:error, :not_found}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, {:noproc, _} -> {:error, :cache_unavailable}
    end
  end

    defp fetch_and_cache(user_id, opts, cache_key) do
    start_time = System.monotonic_time()

    case EventasaurusApp.Events.get_recent_locations_for_user(user_id, opts) do
      locations when is_list(locations) ->
        # Cache the result
        GenServer.cast(@cache_name, {:put, cache_key, locations})

        # Log performance metrics
        duration = System.monotonic_time() - start_time
        duration_ms = System.convert_time_unit(duration, :native, :millisecond)
        Logger.info("Recent locations DB query completed in #{duration_ms}ms for user #{user_id}")

        # Record metrics in monitor
        try do
          EventasaurusWeb.Services.RecentLocationsMonitor.record_db_query(user_id, duration_ms, length(locations))
        rescue
          _ -> :ok  # Don't let monitoring failures break the cache
        end

        {:ok, locations}
      error ->
        Logger.error("Failed to fetch recent locations for user #{user_id}: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  defp build_cache_key(user_id, opts) do
    # Create a deterministic cache key based on user_id and options
    limit = Keyword.get(opts, :limit, 5)
    exclude_event_ids = Keyword.get(opts, :exclude_event_ids, []) |> Enum.sort()

    "user_#{user_id}_limit_#{limit}_exclude_#{Enum.join(exclude_event_ids, "_")}"
  end

  # Server implementation

  @impl true
  def init(state) do
    Logger.info("Starting Recent Locations Cache with TTL: #{state.ttl}ms")
    {:ok, Map.merge(state, %{cache: %{}, stats: %{hits: 0, misses: 0, evictions: 0}})}
  end

  @impl true
  def handle_call({:get, cache_key}, _from, state) do
    case Map.get(state.cache, cache_key) do
      nil ->
        new_stats = Map.update(state.stats, :misses, 1, &(&1 + 1))
        {:reply, :not_found, %{state | stats: new_stats}}
      {locations, _expiry} ->
        new_stats = Map.update(state.stats, :hits, 1, &(&1 + 1))
        {:reply, {:ok, locations}, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    cache_size = map_size(state.cache)
    extended_stats = Map.merge(state.stats, %{cache_size: cache_size, ttl: state.ttl})
    {:reply, extended_stats, state}
  end

  @impl true
  def handle_cast({:put, cache_key, locations}, state) do
    expiry_time = System.monotonic_time() + state.ttl
    new_cache = Map.put(state.cache, cache_key, {locations, expiry_time})

    # Schedule expiration
    Process.send_after(self(), {:expire, cache_key}, state.ttl)

    {:noreply, %{state | cache: new_cache}}
  end

  @impl true
  def handle_cast({:invalidate_user, user_id}, state) do
    # Remove all cache entries for this user
    user_pattern = "user_#{user_id}_"

    new_cache = state.cache
    |> Enum.reject(fn {key, _} -> String.starts_with?(key, user_pattern) end)
    |> Map.new()

    evictions = map_size(state.cache) - map_size(new_cache)
    new_stats = Map.update(state.stats, :evictions, evictions, &(&1 + evictions))

    Logger.debug("Invalidated #{evictions} cache entries for user #{user_id}")
    {:noreply, %{state | cache: new_cache, stats: new_stats}}
  end

  @impl true
  def handle_cast(:clear_all, state) do
    evictions = map_size(state.cache)
    new_stats = Map.update(state.stats, :evictions, evictions, &(&1 + evictions))

    Logger.info("Cleared all cache entries (#{evictions} items)")
    {:noreply, %{state | cache: %{}, stats: new_stats}}
  end

  @impl true
  def handle_info({:expire, cache_key}, state) do
    new_cache = Map.delete(state.cache, cache_key)
    new_stats = Map.update(state.stats, :evictions, 1, &(&1 + 1))

    {:noreply, %{state | cache: new_cache, stats: new_stats}}
  end
end
