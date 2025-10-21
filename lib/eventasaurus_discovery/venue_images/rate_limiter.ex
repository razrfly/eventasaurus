defmodule EventasaurusDiscovery.VenueImages.RateLimiter do
  @moduledoc """
  Rate limiting for venue image providers using ETS-based token bucket algorithm.

  Tracks API usage per provider to prevent exceeding rate limits.

  ## Usage

      # Check if request is allowed
      case RateLimiter.check_rate_limit(provider) do
        :ok ->
          # Proceed with API call
        {:error, :rate_limited} ->
          # Skip provider or wait
      end

  ## Configuration

  Rate limits are read from provider metadata:
  - rate_limits.per_second
  - rate_limits.per_minute
  - rate_limits.per_hour

  ## Implementation

  Uses ETS table to track request counts with sliding window.
  Cleanup happens automatically via TTL on records.
  """

  use GenServer
  require Logger

  @table_name :venue_images_rate_limits
  @cleanup_interval :timer.minutes(5)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if a provider is within rate limits.

  Returns :ok if request allowed, {:error, :rate_limited} if exceeded.
  """
  def check_rate_limit(provider) when is_map(provider) do
    rate_limits = get_rate_limits(provider)

    if Enum.empty?(rate_limits) do
      # No rate limits configured, allow request
      :ok
    else
      check_limits(provider.name, rate_limits)
    end
  end

  @doc """
  Records a request for rate limit tracking.
  """
  def record_request(provider_name) when is_binary(provider_name) do
    GenServer.cast(__MODULE__, {:record_request, provider_name})
  end

  @doc """
  Atomically checks limits and records one request if allowed.

  Returns :ok if allowed and recorded, {:error, :rate_limited} if blocked.
  This prevents race conditions from separate check + record calls.
  """
  def allow_and_record(provider) when is_map(provider) do
    # Normalize provider name to string for consistency
    name = to_string(provider.name)
    rate_limits = get_rate_limits(provider)

    if Enum.empty?(rate_limits) do
      # No limits configured - use atomic call for consistency
      GenServer.call(__MODULE__, {:allow_and_record, name, []})
    else
      GenServer.call(__MODULE__, {:allow_and_record, name, rate_limits})
    end
  end

  @doc """
  Gets current usage stats for a provider.
  """
  def get_stats(provider_name) when is_binary(provider_name) do
    GenServer.call(__MODULE__, {:get_stats, provider_name})
  end

  @doc """
  Resets rate limit counters for a provider (admin function).
  """
  def reset_limits(provider_name) when is_binary(provider_name) do
    GenServer.call(__MODULE__, {:reset_limits, provider_name})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for tracking requests
    :ets.new(@table_name, [:named_table, :public, :bag, read_concurrency: true])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:record_request, provider_name}, state) do
    now = System.system_time(:second)
    :ets.insert(@table_name, {provider_name, now})
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_stats, provider_name}, _from, state) do
    now = System.system_time(:second)

    stats = %{
      last_second: count_requests(provider_name, now - 1, now),
      last_minute: count_requests(provider_name, now - 60, now),
      last_hour: count_requests(provider_name, now - 3600, now)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:allow_and_record, provider_name, rate_limits}, _from, state) do
    case check_limits(provider_name, rate_limits) do
      :ok ->
        now = System.system_time(:second)
        :ets.insert(@table_name, {provider_name, now})
        {:reply, :ok, state}

      {:error, :rate_limited} = err ->
        {:reply, err, state}
    end
  end

  @impl true
  def handle_call({:reset_limits, provider_name}, _from, state) do
    :ets.match_delete(@table_name, {provider_name, :_})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_records()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp get_rate_limits(provider) do
    metadata = provider.metadata || %{}

    rate_limits_map =
      get_in(metadata, ["rate_limits"]) ||
        get_in(metadata, [:rate_limits]) ||
        %{}

    [
      per_second: get_limit(rate_limits_map, "per_second"),
      per_minute: get_limit(rate_limits_map, "per_minute"),
      per_hour: get_limit(rate_limits_map, "per_hour")
    ]
    |> Enum.reject(fn {_key, val} -> is_nil(val) end)
  end

  defp get_limit(rate_limits, key) do
    get_in(rate_limits, [key]) || get_in(rate_limits, [String.to_existing_atom(key)])
  rescue
    ArgumentError -> nil
  end

  defp check_limits(provider_name, rate_limits) do
    now = System.system_time(:second)

    Enum.reduce_while(rate_limits, :ok, fn {period, limit}, _acc ->
      {start_time, period_name} =
        case period do
          :per_second -> {now - 1, "second"}
          :per_minute -> {now - 60, "minute"}
          :per_hour -> {now - 3600, "hour"}
        end

      count = count_requests(provider_name, start_time, now)

      if count >= limit do
        Logger.warning(
          "⚠️ Rate limit exceeded for #{provider_name}: #{count}/#{limit} per #{period_name}"
        )

        {:halt, {:error, :rate_limited}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp count_requests(provider_name, start_time, end_time) do
    :ets.select_count(
      @table_name,
      [
        {
          {provider_name, :"$1"},
          [
            {:andalso, {:>=, :"$1", start_time}, {:"=<", :"$1", end_time}}
          ],
          [true]
        }
      ]
    )
  end

  defp cleanup_old_records do
    # Remove records older than 1 hour
    cutoff = System.system_time(:second) - 3600

    deleted =
      :ets.select_delete(
        @table_name,
        [
          {
            {:"$1", :"$2"},
            [{:<, :"$2", cutoff}],
            [true]
          }
        ]
      )

    if deleted > 0 do
      Logger.debug("🧹 Cleaned up #{deleted} old rate limit records")
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
