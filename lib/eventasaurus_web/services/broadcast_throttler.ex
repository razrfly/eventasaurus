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
  
  # Maximum number of pending broadcasts per poll
  @max_pending_per_poll 5
  
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
      timers: %{}
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
      do_broadcast(poll_id, data, type)
      new_state = %{state | last_broadcast: Map.put(state.last_broadcast, poll_id, now)}
      {:noreply, new_state}
    else
      # Too soon, queue the broadcast
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
        # No pending broadcast, clean up timer
        new_timers = Map.delete(state.timers, poll_id)
        {:noreply, %{state | timers: new_timers}}
      
      {data, type} ->
        # Send the queued broadcast
        do_broadcast(poll_id, data, type)
        
        now = System.monotonic_time(:millisecond)
        new_state = %{state |
          last_broadcast: Map.put(state.last_broadcast, poll_id, now),
          pending_broadcasts: Map.delete(state.pending_broadcasts, poll_id),
          timers: Map.delete(state.timers, poll_id)
        }
        {:noreply, new_state}
    end
  end
  
  ## Private Functions
  
  defp queue_broadcast(state, poll_id, data, type) do
    # Cancel existing timer if there is one
    existing_timer = Map.get(state.timers, poll_id)
    if existing_timer do
      Process.cancel_timer(existing_timer)
    end
    
    # Check if we already have too many pending broadcasts for this poll
    pending_count = map_size(state.pending_broadcasts)
    if pending_count >= @max_pending_per_poll do
      Logger.warning("Too many pending broadcasts for poll #{poll_id}, dropping oldest")
    end
    
    # Schedule the broadcast
    time_to_wait = calculate_wait_time(state, poll_id)
    timer_ref = Process.send_after(self(), {:send_queued_broadcast, poll_id}, time_to_wait)
    
    %{state |
      pending_broadcasts: Map.put(state.pending_broadcasts, poll_id, {data, type}),
      timers: Map.put(state.timers, poll_id, timer_ref)
    }
  end
  
  defp calculate_wait_time(state, poll_id) do
    now = System.monotonic_time(:millisecond)
    last_broadcast_time = Map.get(state.last_broadcast, poll_id, 0)
    time_since_last = now - last_broadcast_time
    
    max(0, state.throttle_ms - time_since_last)
  end
  
  defp do_broadcast(poll_id, data, type) do
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