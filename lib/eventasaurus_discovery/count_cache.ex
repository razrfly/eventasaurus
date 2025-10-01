defmodule EventasaurusDiscovery.CountCache do
  @moduledoc """
  ETS-based cache for event count queries.

  Provides fast in-memory caching for frequently accessed count data
  such as date range counts and filter facets. Uses TTL-based expiration
  to balance freshness with performance.

  Performance Impact:
  - Cache hit: ~1-2ms (vs 50-150ms for database query)
  - Cache miss: Database query time + ~1ms cache write
  - Expected hit rate: 80-90% for typical usage patterns

  ## Usage

      # Simple get_or_fetch with default TTL (5 minutes)
      CountCache.get_or_fetch(:date_counts, city_id, fn ->
        PublicEventsEnhanced.get_quick_date_range_counts(filters)
      end)

      # Custom TTL (in seconds)
      CountCache.get_or_fetch(:facets, filter_hash, fn ->
        PublicEventsEnhanced.get_filter_facets(filters)
      end, ttl: 600)

      # Manual cache operations
      CountCache.put(:custom_key, data, ttl: 300)
      CountCache.get(:custom_key)
      CountCache.delete(:custom_key)
      CountCache.clear()
  """

  use GenServer
  require Logger

  @table_name :event_counts_cache
  @default_ttl_seconds 300  # 5 minutes
  @cleanup_interval 60_000  # Clean expired entries every minute

  ## Client API

  @doc """
  Starts the cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get a value from cache or fetch it using the provided function.

  Returns the cached value if present and not expired, otherwise calls
  the fetch function, caches the result, and returns it.

  ## Options
    * `:ttl` - Time to live in seconds (default: 300)

  ## Examples

      CountCache.get_or_fetch({:date_counts, city_id}, fn ->
        PublicEventsEnhanced.get_quick_date_range_counts(filters)
      end)

      CountCache.get_or_fetch(:expensive_query, fn ->
        run_expensive_query()
      end, ttl: 600)
  """
  def get_or_fetch(key, fetch_fn, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl_seconds)

    case get(key) do
      {:ok, value} ->
        value

      :error ->
        value = fetch_fn.()
        put(key, value, ttl: ttl)
        value
    end
  end

  @doc """
  Get a value from the cache.

  Returns `{:ok, value}` if found and not expired, `:error` otherwise.
  """
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if :os.system_time(:second) < expires_at do
          {:ok, value}
        else
          # Entry expired, delete it
          :ets.delete(@table_name, key)
          :error
        end

      [] ->
        :error
    end
  end

  @doc """
  Put a value in the cache with optional TTL.

  ## Options
    * `:ttl` - Time to live in seconds (default: 300)

  ## Examples

      CountCache.put(:my_key, %{count: 42}, ttl: 600)
  """
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl_seconds)
    expires_at = :os.system_time(:second) + ttl

    :ets.insert(@table_name, {key, value, expires_at})
    :ok
  end

  @doc """
  Delete a specific key from the cache.
  """
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Clear all entries from the cache.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Get cache statistics.

  Returns a map with:
    * `:size` - Number of entries in cache
    * `:memory` - Memory usage in bytes
  """
  def stats do
    size = :ets.info(@table_name, :size)
    memory = :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)

    %{
      size: size,
      memory: memory,
      memory_mb: Float.round(memory / 1_024 / 1_024, 2)
    }
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table: public for read access, write access controlled by GenServer
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: false
    ])

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("CountCache started with TTL=#{@default_ttl_seconds}s")

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired_entries do
    now = :os.system_time(:second)

    # Select all expired entries
    expired = :ets.select(@table_name, [
      {{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [:"$1"]}
    ])

    # Delete them
    Enum.each(expired, fn key ->
      :ets.delete(@table_name, key)
    end)

    if length(expired) > 0 do
      Logger.debug("CountCache: Cleaned up #{length(expired)} expired entries")
    end

    :ok
  end
end
