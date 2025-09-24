defmodule EventasaurusApp.EventStateMachine do
  @moduledoc """
  State machine logic for determining event status based on attributes.

  This module provides functions to infer the appropriate event status
  based on the presence of meaningful data fields, following the clean
  state management design where status is derived from actual data
  rather than redundant boolean flags.

  Includes ETS-based caching for computed phase performance optimization.
  """

  require Logger

  @cache_table :event_phase_cache
  # 5 minutes TTL
  @cache_ttl_seconds 300

  @doc """
  Starts the ETS cache table for computed phases.

  This should be called during application startup.
  """
  def init_cache do
    try do
      :ets.new(@cache_table, [:set, :public, :named_table])
      Logger.info("EventStateMachine: Phase cache initialized")
      :ok
    catch
      :error, :badarg ->
        # Table already exists
        Logger.debug("EventStateMachine: Phase cache already exists")
        :ok
    end
  end

  @doc """
  Clears the phase cache.

  Useful for testing or when you want to force recalculation.
  """
  def clear_cache do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ok

      _tid ->
        :ets.delete_all_objects(@cache_table)
        Logger.debug("EventStateMachine: Phase cache cleared")
        :ok
    end
  end

  @doc """
  Infers the appropriate event status based on the provided attributes.

  The function follows a priority order:
  1. :canceled - if canceled_at is present
  2. :polling - if polling_deadline is present
  3. :threshold - if threshold_count is present
  4. :confirmed - default for normal events

  ## Examples

      iex> EventasaurusApp.EventStateMachine.infer_status(%{canceled_at: ~U[2024-01-01 00:00:00Z]})
      :canceled

      iex> EventasaurusApp.EventStateMachine.infer_status(%{polling_deadline: ~U[2024-01-01 00:00:00Z]})
      :polling

      iex> EventasaurusApp.EventStateMachine.infer_status(%{threshold_count: 10})
      :threshold

      iex> EventasaurusApp.EventStateMachine.infer_status(%{title: "Regular Event"})
      :confirmed
  """
  def infer_status(attrs) when is_map(attrs) do
    cond do
      # Canceled state has highest priority
      has_value?(attrs, :canceled_at) or has_value?(attrs, "canceled_at") ->
        :canceled

      # Polling state - when polling is enabled with a deadline
      has_value?(attrs, :polling_deadline) or has_value?(attrs, "polling_deadline") ->
        :polling

      # Threshold state - when a threshold count is set
      has_value?(attrs, :threshold_count) or has_value?(attrs, "threshold_count") ->
        :threshold

      # Default to confirmed for normal events
      true ->
        :confirmed
    end
  end

  def infer_status(%EventasaurusApp.Events.Event{} = event) do
    infer_status(Map.from_struct(event))
  end

  @doc """
  Checks if the inferred status matches the current status.

  This is useful for validation to ensure the status field
  aligns with the state implied by the data fields.

  ## Examples

      iex> attrs = %{status: :polling, polling_deadline: ~U[2024-01-01 00:00:00Z]}
      iex> EventasaurusApp.EventStateMachine.status_matches?(attrs)
      true

      iex> attrs = %{status: :confirmed, threshold_count: 10}
      iex> EventasaurusApp.EventStateMachine.status_matches?(attrs)
      false
  """
  def status_matches?(attrs) when is_map(attrs) do
    current_status =
      case get_status(attrs) do
        s when is_binary(s) ->
          try do
            String.to_existing_atom(s)
          rescue
            ArgumentError -> :__invalid__
          end
        s -> s
      end

    inferred_status = infer_status(attrs)
    current_status == inferred_status
  end

  @doc """
  Auto-corrects the status field to match the inferred status.

  ## Examples

      iex> attrs = %{status: :confirmed, threshold_count: 10}
      iex> EventasaurusApp.EventStateMachine.auto_correct_status(attrs)
      %{status: :threshold, threshold_count: 10}
  """
  def auto_correct_status(attrs) when is_map(attrs) do
    inferred_status = infer_status(attrs)

    # Use the appropriate key type based on the existing map
    # Remove any existing status keys and set the correct one
    cleaned_attrs = attrs |> Map.delete(:status) |> Map.delete("status")

    # If the map has atom keys, use atom; otherwise use string
    if Enum.any?(Map.keys(attrs), &is_atom/1) do
      Map.put(cleaned_attrs, :status, inferred_status)
    else
      Map.put(cleaned_attrs, "status", to_string(inferred_status))
    end
  end

  # Private helper functions

  # Checks if a field has a meaningful value (not nil, not empty string)
  defp has_value?(map, key) do
    case Map.get(map, key) do
      nil -> false
      "" -> false
      _value -> true
    end
  end

  # Gets the current status from attrs, supporting both atom and string keys
  defp get_status(attrs) do
    Map.get(attrs, :status) || Map.get(attrs, "status")
  end

  @doc """
  Computes the current phase of an event based on its status, attributes, and current time.

  Phases represent the runtime state of an event and are derived from:
  - Current event status (explicit state)
  - Time-based conditions (start/end times, deadlines)
  - Business logic (threshold requirements, ticketing)

  ## Phases:
  - `:planning` - Initial phase, event being planned
  - `:polling` - Event is actively polling for interest
  - `:awaiting_confirmation` - Polling deadline passed, awaiting organizer decision
  - `:prepaid_confirmed` - Threshold met with prepayment
  - `:ticketing` - Event confirmed and tickets are being sold
  - `:open` - Event confirmed and open for attendance
  - `:ended` - Event has completed
  - `:canceled` - Event was canceled

  ## Examples

      iex> event = %Event{status: :draft, start_at: ~U[2024-12-01 18:00:00Z]}
      iex> EventStateMachine.computed_phase(event)
      :planning

      iex> event = %Event{status: :polling, polling_deadline: ~U[2024-01-01 00:00:00Z]}
      iex> EventStateMachine.computed_phase(event)
      :awaiting_confirmation
  """
  def computed_phase(%EventasaurusApp.Events.Event{} = event) do
    computed_phase_with_cache(event, DateTime.utc_now())
  end

  @doc """
  Computes the current phase with caching for performance.

  Uses ETS cache with TTL to optimize repeated phase computations
  for the same event.
  """
  def computed_phase_with_cache(
        %EventasaurusApp.Events.Event{} = event,
        %DateTime{} = current_time
      ) do
    cache_key = build_cache_key(event, current_time)

    case get_from_cache(cache_key) do
      {:hit, phase} ->
        Logger.debug("EventStateMachine: Cache hit for event #{event.id}")
        phase

      :miss ->
        phase = computed_phase_uncached(event, current_time)
        put_in_cache(cache_key, phase)
        Logger.debug("EventStateMachine: Cache miss for event #{event.id}, computed #{phase}")
        phase
    end
  end

  @doc """
  Computes phase without caching (for testing and direct computation).
  """
  def computed_phase_uncached(%EventasaurusApp.Events.Event{} = event, %DateTime{} = current_time) do
    cond do
      # Canceled events are always in canceled phase
      event.status == :canceled ->
        :canceled

      # Events that have ended
      event.ends_at && DateTime.compare(current_time, event.ends_at) == :gt ->
        :ended

      # Polling deadline has passed but event is not yet confirmed
      event.status == :polling &&
        event.polling_deadline &&
          DateTime.compare(current_time, event.polling_deadline) == :gt ->
        :awaiting_confirmation

      # Confirmed events with ticketing enabled
      event.status == :confirmed && is_ticketed?(event) ->
        :ticketing

      # Confirmed events without ticketing
      event.status == :confirmed ->
        :open

      # Threshold events where threshold has been met
      event.status == :threshold && threshold_met?(event) ->
        :prepaid_confirmed

      # Currently polling for interest
      event.status == :polling ->
        :polling

      # Threshold state (awaiting enough participants)
      event.status == :threshold ->
        :awaiting_confirmation

      # Draft events are in planning phase
      event.status == :draft ->
        :planning

      # Default phase for other states
      true ->
        :planning
    end
  end

  @doc """
  Computes the current phase of an event at a specific point in time.

  This version allows for testing with specific timestamps and bypasses cache.
  """
  def computed_phase(%EventasaurusApp.Events.Event{} = event, %DateTime{} = current_time) do
    computed_phase_uncached(event, current_time)
  end

  @doc """
  Checks if an event has met its threshold requirements.
  Returns true if the event meets its threshold criteria, false otherwise.
  """
  def threshold_met?(%EventasaurusApp.Events.Event{threshold_type: threshold_type} = event)
      when threshold_type in ["attendee_count", "revenue", "both"] do
    case threshold_type do
      "attendee_count" ->
        valid_threshold?(event.threshold_count) &&
          get_current_attendee_count(event) >= event.threshold_count

      "revenue" ->
        valid_threshold?(event.threshold_revenue_cents) &&
          get_current_revenue(event) >= event.threshold_revenue_cents

      "both" ->
        valid_threshold?(event.threshold_count) &&
          valid_threshold?(event.threshold_revenue_cents) &&
          get_current_attendee_count(event) >= event.threshold_count &&
          get_current_revenue(event) >= event.threshold_revenue_cents
    end
  end

  # Default case for backward compatibility or unknown threshold types
  def threshold_met?(%EventasaurusApp.Events.Event{} = event) do
    # Default to attendee_count behavior for backward compatibility
    if valid_threshold?(event.threshold_count) do
      current_count = get_current_attendee_count(event)
      current_count >= event.threshold_count
    else
      false
    end
  end

  # Helper function to validate threshold values
  defp valid_threshold?(value) when is_nil(value), do: false
  defp valid_threshold?(value) when is_integer(value), do: value > 0
  defp valid_threshold?(_), do: false

  @doc """
  Checks if an event has ticketing functionality enabled.

  Uses the is_ticketed field on the event to determine if ticketing is enabled.
  """
  def is_ticketed?(%EventasaurusApp.Events.Event{is_ticketed: is_ticketed}) do
    is_ticketed == true
  end

  @doc """
  Gets the current attendee count for an event.

  Counts confirmed ticket holders for the event.
  """
  def get_current_attendee_count(%EventasaurusApp.Events.Event{} = event) do
    alias EventasaurusApp.Events.EventParticipant
    alias EventasaurusApp.Repo
    import Ecto.Query

    from(p in EventParticipant,
      where:
        p.event_id == ^event.id and
          p.role == :ticket_holder and
          p.status == :confirmed_with_order,
      select: count(p.id)
    )
    |> Repo.one()
    # Return 0 if no participants found
    |> Kernel.||(0)
  end

  @doc """
  Gets the current revenue for an event.

  Sums the total_cents from all confirmed orders for the event.
  """
  def get_current_revenue(%EventasaurusApp.Events.Event{} = event) do
    alias EventasaurusApp.Events.Order
    alias EventasaurusApp.Repo
    import Ecto.Query

    from(o in Order,
      where: o.event_id == ^event.id and o.status == "confirmed",
      select: sum(o.total_cents)
    )
    |> Repo.one()
    # Return 0 if no orders found
    |> Kernel.||(0)
  end

  @doc """
  Checks if a computed phase matches the expected phase.

  Useful for conditional logic and testing.

  ## Examples

      iex> event = %Event{status: :polling, polling_deadline: ~U[2024-12-01 00:00:00Z]}
      iex> EventStateMachine.phase_matches?(event, :polling)
      true
  """
  def phase_matches?(%EventasaurusApp.Events.Event{} = event, expected_phase) do
    computed_phase(event) == expected_phase
  end

  @doc """
  Returns all possible phases an event can be in.
  """
  def all_phases do
    [
      :planning,
      :polling,
      :awaiting_confirmation,
      :prepaid_confirmed,
      :ticketing,
      :open,
      :ended,
      :canceled
    ]
  end

  @doc """
  Checks if a phase is a terminal phase (event lifecycle has ended).
  """
  def terminal_phase?(phase) when phase in [:ended, :canceled], do: true
  def terminal_phase?(_phase), do: false

  @doc """
  Checks if a phase represents an active event (attendees can still join/interact).
  """
  def active_phase?(phase) when phase in [:ticketing, :open, :prepaid_confirmed], do: true
  def active_phase?(_phase), do: false

  # Private cache helper functions

  defp build_cache_key(%EventasaurusApp.Events.Event{} = event, %DateTime{} = current_time) do
    # Build a cache key that includes relevant event attributes and time bucket
    # Use 5-minute time buckets to balance cache hit rate with freshness
    time_bucket = DateTime.to_unix(current_time) |> div(@cache_ttl_seconds)

    key_attrs = %{
      id: event.id,
      status: event.status,
      polling_deadline: event.polling_deadline,
      threshold_count: event.threshold_count,
      canceled_at: event.canceled_at,
      ends_at: event.ends_at,
      time_bucket: time_bucket
    }

    :erlang.phash2(key_attrs)
  end

  defp get_from_cache(cache_key) do
    case :ets.whereis(@cache_table) do
      :undefined ->
        init_cache()
        :miss

      _tid ->
        case :ets.lookup(@cache_table, cache_key) do
          [{^cache_key, phase, timestamp}] ->
            if cache_entry_valid?(timestamp) do
              {:hit, phase}
            else
              :ets.delete(@cache_table, cache_key)
              :miss
            end

          [] ->
            :miss
        end
    end
  end

  defp put_in_cache(cache_key, phase) do
    case :ets.whereis(@cache_table) do
      :undefined ->
        init_cache()
        put_in_cache(cache_key, phase)

      _tid ->
        timestamp = System.os_time(:second)
        :ets.insert(@cache_table, {cache_key, phase, timestamp})
        :ok
    end
  end

  defp cache_entry_valid?(timestamp) do
    current_time = System.os_time(:second)
    current_time - timestamp < @cache_ttl_seconds
  end
end
