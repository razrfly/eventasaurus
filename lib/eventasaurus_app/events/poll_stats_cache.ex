defmodule EventasaurusApp.Events.PollStatsCache do
  @moduledoc """
  In-memory caching for poll statistics to improve performance.

  Uses ETS for fast lookups and reduces database queries for frequently
  accessed poll statistics, especially important for date selection polls
  with many options.
  """

  use GenServer
  require Logger

  @table_name :poll_stats_cache
  # 30 seconds cache TTL
  @cache_ttl 30_000
  # Clean up expired entries every minute
  @cleanup_interval 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets cached poll statistics or computes and caches them.
  """
  def get_stats(poll_id, compute_fn) when is_function(compute_fn, 0) do
    case lookup_cache(poll_id) do
      {:ok, stats} ->
        stats

      :miss ->
        # Compute stats and cache them
        stats = compute_fn.()
        cache_stats(poll_id, stats)
        stats
    end
  end

  @doc """
  Invalidates cache for a specific poll.
  Called when votes are cast or poll is updated.
  """
  def invalidate(poll_id) do
    GenServer.cast(__MODULE__, {:invalidate, poll_id})
  end

  @doc """
  Invalidates all cached statistics.
  """
  def invalidate_all do
    GenServer.cast(__MODULE__, :invalidate_all)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for caching
    table = :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)

    Logger.info("PollStatsCache started with table: #{inspect(table)}")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:invalidate, poll_id}, state) do
    :ets.delete(@table_name, poll_id)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:invalidate_all, state) do
    :ets.delete_all_objects(@table_name)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    Process.send_after(self(), :cleanup, @cleanup_interval)
    {:noreply, state}
  end

  # Private functions

  defp lookup_cache(poll_id) do
    case :ets.lookup(@table_name, poll_id) do
      [{^poll_id, stats, timestamp}] ->
        if fresh?(timestamp) do
          {:ok, stats}
        else
          :ets.delete(@table_name, poll_id)
          :miss
        end

      [] ->
        :miss
    end
  end

  defp cache_stats(poll_id, stats) do
    timestamp = System.system_time(:millisecond)
    :ets.insert(@table_name, {poll_id, stats, timestamp})
  end

  defp fresh?(timestamp) do
    System.system_time(:millisecond) - timestamp < @cache_ttl
  end

  defp cleanup_expired_entries do
    current_time = System.system_time(:millisecond)
    expired_threshold = current_time - @cache_ttl

    # Delete expired entries
    :ets.select_delete(@table_name, [
      {{~c"$1", ~c"$2", ~c"$3"}, [{:<, ~c"$3", expired_threshold}], [true]}
    ])
  end
end
