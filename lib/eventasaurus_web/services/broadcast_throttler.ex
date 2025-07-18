defmodule EventasaurusWeb.Services.BroadcastThrottler do
  @moduledoc """
  Throttles broadcast updates to prevent server overload during high activity.
  
  This service provides throttling mechanisms for poll statistics updates,
  ensuring that broadcasts are sent at reasonable intervals even during
  rapid voting activity.
  """
  
  use GenServer
  require Logger
  
  # Default throttling interval in milliseconds
  @default_throttle_ms 500
  
  # Maximum number of total pending broadcasts allowed
  # When this limit is reached, the oldest pending broadcast will be dropped
  @max_pending_broadcasts 50
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Throttles a poll statistics broadcast, ensuring it's not sent too frequently.
  
  If a broadcast was recently sent for this poll, it will be queued and sent
  after the throttle interval expires.
  """
  def throttle_poll_stats_broadcast(poll_id, stats, event_id) do
    GenServer.cast(__MODULE__, {:throttle_broadcast, poll_id, {stats, event_id}, :poll_stats})
  end
  
  @doc """
  Throttles a poll update broadcast for general poll changes.
  """
  def throttle_poll_update_broadcast(poll_id, event_type, event_id) do
    GenServer.cast(__MODULE__, {:throttle_broadcast, poll_id, {event_type, event_id}, :poll_update})
  end
  
  @doc """
  Forces an immediate broadcast, bypassing throttling.
  Used for critical updates that shouldn't be delayed.
  """
  def force_broadcast(poll_id, data, type) do
    GenServer.cast(__MODULE__, {:force_broadcast, poll_id, data, type})
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    throttle_ms = Keyword.get(opts, :throttle_ms, @default_throttle_ms)
    
    state = %{
      throttle_ms: throttle_ms,
      last_broadcast: %{},
      pending_broadcasts: %{},
      timers: %{},
      queue_times: %{},  # Track when each broadcast was queued
      start_time: System.monotonic_time(:millisecond)  # Track when the server started
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:throttle_broadcast, poll_id, data, type}, state) do
    now = System.monotonic_time(:millisecond)
    last_broadcast_time = Map.get(state.last_broadcast, poll_id, 0)
    time_since_last = now - last_broadcast_time
    
    if time_since_last >= state.throttle_ms do
      # Enough time has passed, broadcast immediately
      Logger.debug("BroadcastThrottler: Broadcasting immediately for poll #{poll_id} (time since last: #{time_since_last}ms)")
      do_broadcast(poll_id, data, type)
      new_state = %{state | last_broadcast: Map.put(state.last_broadcast, poll_id, now)}
      {:noreply, new_state}
    else
      # Too soon, queue the broadcast
      Logger.debug("BroadcastThrottler: Throttling broadcast for poll #{poll_id} (time since last: #{time_since_last}ms)")
      new_state = queue_broadcast(state, poll_id, data, type)
      {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_cast({:force_broadcast, poll_id, data, type}, state) do
    do_broadcast(poll_id, data, type)
    now = System.monotonic_time(:millisecond)
    new_state = %{state | last_broadcast: Map.put(state.last_broadcast, poll_id, now)}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:send_queued_broadcast, poll_id}, state) do
    case Map.get(state.pending_broadcasts, poll_id) do
      nil ->
        # No pending broadcast, clean up timer and queue time
        new_state = %{state | 
          timers: Map.delete(state.timers, poll_id),
          queue_times: Map.delete(state.queue_times, poll_id)
        }
        {:noreply, new_state}
      
      {data, type} ->
        # Send the queued broadcast
        do_broadcast(poll_id, data, type)
        
        now = System.monotonic_time(:millisecond)
        new_state = %{state |
          last_broadcast: Map.put(state.last_broadcast, poll_id, now),
          pending_broadcasts: Map.delete(state.pending_broadcasts, poll_id),
          timers: Map.delete(state.timers, poll_id),
          queue_times: Map.delete(state.queue_times, poll_id)
        }
        {:noreply, new_state}
    end
  end
  
  ## Private Functions
  
  defp queue_broadcast(state, poll_id, data, type) do
    # Cancel existing timer if there is one and remove from pending broadcasts
    {_existing_timer, cleaned_state} = if Map.has_key?(state.timers, poll_id) do
      timer = Map.get(state.timers, poll_id)
      if timer, do: Process.cancel_timer(timer)
      
      # Remove the existing pending broadcast for this poll
      cleaned = %{state |
        pending_broadcasts: Map.delete(state.pending_broadcasts, poll_id),
        timers: Map.delete(state.timers, poll_id),
        queue_times: Map.delete(state.queue_times, poll_id)
      }
      {timer, cleaned}
    else
      {nil, state}
    end
    
    # Check if we already have too many pending broadcasts globally
    # (after removing any existing broadcast for this poll)
    total_pending_count = map_size(cleaned_state.pending_broadcasts)
    new_state = if total_pending_count >= @max_pending_broadcasts do
      Logger.warning("BroadcastThrottler: Too many pending broadcasts (#{total_pending_count}), dropping oldest")
      # Find and drop the oldest pending broadcast
      drop_oldest_pending_broadcast(cleaned_state)
    else
      cleaned_state
    end
    
    # Schedule the broadcast
    time_to_wait = calculate_wait_time(new_state, poll_id)
    timer_ref = Process.send_after(self(), {:send_queued_broadcast, poll_id}, time_to_wait)
    
    # Track when this broadcast was queued
    now = System.monotonic_time(:millisecond)
    
    Logger.debug("BroadcastThrottler: Queuing broadcast for poll #{poll_id}, will send in #{time_to_wait}ms")
    
    %{new_state |
      pending_broadcasts: Map.put(new_state.pending_broadcasts, poll_id, {data, type}),
      timers: Map.put(new_state.timers, poll_id, timer_ref),
      queue_times: Map.put(new_state.queue_times, poll_id, now)
    }
  end
  
  defp calculate_wait_time(state, poll_id) do
    now = System.monotonic_time(:millisecond)
    # For polls that have never broadcast, use a time before the server started
    # This ensures they can broadcast immediately on first attempt
    default_time = state.start_time - state.throttle_ms - 1
    last_broadcast_time = Map.get(state.last_broadcast, poll_id, default_time)
    time_since_last = now - last_broadcast_time
    
    max(0, state.throttle_ms - time_since_last)
  end
  
  defp drop_oldest_pending_broadcast(state) do
    # Find the oldest pending broadcast based on actual queue times
    oldest_poll_id = state.pending_broadcasts
    |> Map.keys()
    |> Enum.min_by(fn poll_id -> 
      # Use the actual queue time, defaulting to 0 (very old) if not found
      # This ensures broadcasts without queue times are dropped first
      Map.get(state.queue_times, poll_id, 0)
    end, fn -> nil end)
    
    if oldest_poll_id do
      # Cancel the timer for the oldest broadcast
      timer = Map.get(state.timers, oldest_poll_id)
      if timer, do: Process.cancel_timer(timer)
      
      %{state |
        pending_broadcasts: Map.delete(state.pending_broadcasts, oldest_poll_id),
        timers: Map.delete(state.timers, oldest_poll_id),
        queue_times: Map.delete(state.queue_times, oldest_poll_id)
      }
    else
      state
    end
  end
  
  defp do_broadcast(poll_id, data, type) do
    Logger.debug("BroadcastThrottler: Broadcasting for poll #{poll_id}, type: #{inspect(type)}")
    
    case type do
      :poll_stats ->
        {stats, event_id} = data
        # Broadcast poll statistics update
        Phoenix.PubSub.broadcast(
          Eventasaurus.PubSub,
          "polls:#{poll_id}:stats",
          {:poll_stats_updated, stats}
        )
        
        # Also broadcast to event channel
        Phoenix.PubSub.broadcast(
          Eventasaurus.PubSub,
          "events:#{event_id}:polls",
          {:poll_stats_updated, poll_id, stats}
        )
        
        Logger.debug("BroadcastThrottler: Sent poll_stats broadcast for poll #{poll_id} to event #{event_id}")
      
      :poll_update ->
        {event_type, event_id} = data
        # Broadcast general poll update
        Phoenix.PubSub.broadcast(
          Eventasaurus.PubSub,
          "polls:#{poll_id}",
          {event_type, %{poll_id: poll_id}}
        )
        
        # Also broadcast to event channel for real-time event updates
        Phoenix.PubSub.broadcast(
          Eventasaurus.PubSub,
          "events:#{event_id}",
          {:poll_updated, %{poll_id: poll_id}}
        )
        
        Logger.debug("BroadcastThrottler: Sent poll_update broadcast for poll #{poll_id}, event_type: #{inspect(event_type)}")
    end
  end
  
  @doc """
  Gets current throttling statistics for monitoring.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      throttle_ms: state.throttle_ms,
      active_polls: map_size(state.last_broadcast),
      pending_broadcasts: map_size(state.pending_broadcasts),
      active_timers: map_size(state.timers)
    }
    
    {:reply, stats, state}
  end
end