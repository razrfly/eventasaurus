defmodule EventasaurusApp.Events.HardDelete do
  @moduledoc """
  Handles hard deletion of events that meet specific eligibility criteria.
  
  Events can only be hard deleted if they have no user participants and minimal engagement.
  This follows the principle: "You can't hard delete an event that has user participants."
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.{Repo, Events, Ticketing}
  alias EventasaurusApp.Events.{Event, EventParticipant}
  alias EventasaurusApp.Events.{Ticket, Order}
  alias EventasaurusApp.Accounts.User
  require Logger

  @doc """
  Checks if an event is eligible for hard deletion based on criteria:
  - Event must have no user participants (primary criterion)
  - Event must have no confirmed orders
  - Event must have no sold tickets
  - Event must have been created by the user requesting deletion (ownership check)
  
  Optional additional safety checks:
  - Event created within reasonable timeframe (default 90 days)
  """
  def eligible_for_hard_delete?(event_id, user_id, opts \\ []) do
    max_age_days = Keyword.get(opts, :max_age_days, 90)
    
    with {:ok, event} <- get_event_safely(event_id),
         :ok <- check_no_participants(event_id),
         :ok <- check_no_confirmed_orders(event_id),
         :ok <- check_no_sold_tickets(event_id),
         :ok <- check_ownership(event, user_id),
         :ok <- check_age_limit(event, max_age_days) do
      {:ok, event}
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, :not_eligible_for_hard_delete}
    end
  end

  @doc """
  Performs hard deletion of an event if it's eligible.
  Returns {:ok, deleted_event} on success or {:error, reason} on failure.
  
  This operation is irreversible and removes the event and all its data permanently.
  """
  def hard_delete_event(event_id, user_id, opts \\ []) do
    case eligible_for_hard_delete?(event_id, user_id, opts) do
      {:ok, event} ->
        # Start a transaction to ensure atomicity
        Repo.transaction(fn ->
          try do
            # Delete associated records in dependency order
            delete_associated_records(event_id)
            
            # Delete the event record itself
            case Repo.delete(event) do
              {:ok, deleted_event} ->
                # Log the hard deletion
                log_hard_deletion(event, user_id)
                deleted_event
                
              {:error, changeset} ->
                Repo.rollback({:error, "Failed to delete event: #{inspect(changeset.errors)}"})
            end
          rescue
            e ->
              Logger.error("Hard delete failed for event #{event_id}: #{Exception.message(e)}")
              Repo.rollback({:error, "Failed to hard delete event: #{Exception.message(e)}"})
          end
        end)
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp get_event_safely(event_id) do
    case Events.get_event(event_id) do
      %Event{} = event -> {:ok, event}
      nil -> {:error, :event_not_found}
    end
  end

  defp check_no_participants(event_id) do
    count = Repo.aggregate(
      from(p in EventParticipant, where: p.event_id == ^event_id),
      :count,
      :id
    )
    
    if count == 0 do
      :ok
    else
      {:error, :has_participants}
    end
  end

  defp check_no_confirmed_orders(event_id) do
    count = Repo.aggregate(
      from(o in Order, 
           where: o.event_id == ^event_id and o.status in ["confirmed", "pending"]),
      :count,
      :id
    )
    
    if count == 0 do
      :ok
    else
      {:error, :has_orders}
    end
  end

  defp check_no_sold_tickets(event_id) do
    # Check all tickets for this event
    ticket_ids = Repo.all(
      from(t in Ticket, 
           where: t.event_id == ^event_id, 
           select: t.id)
    )
    
    # For each ticket, check if any are sold
    sold_count = Enum.reduce(ticket_ids, 0, fn ticket_id, acc ->
      acc + Ticketing.count_sold_tickets(ticket_id)
    end)
    
    if sold_count == 0 do
      :ok
    else
      {:error, :has_sold_tickets}
    end
  end

  defp check_ownership(event, user_id) do
    # Check if user is an organizer of the event
    user = %User{id: user_id}
    
    if Events.user_is_organizer?(event, user) do
      :ok
    else
      {:error, :not_owner}
    end
  end

  defp check_age_limit(event, max_age_days) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-max_age_days * 24 * 60 * 60, :second)
    
    # Convert naive datetime to UTC for comparison if needed
    event_datetime = case event.inserted_at do
      %DateTime{} = dt -> dt
      %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC")
    end
    
    if DateTime.compare(event_datetime, cutoff_date) == :gt do
      :ok
    else
      {:error, :too_old}
    end
  end

  defp delete_associated_records(event_id) do
    # Delete associated records that might not be caught by DB constraints
    # Order matters - delete child records first
    
    # Delete poll votes first
    from(pv in EventasaurusApp.Events.PollVote,
         join: po in EventasaurusApp.Events.PollOption, on: pv.poll_option_id == po.id,
         join: p in EventasaurusApp.Events.Poll, on: po.poll_id == p.id,
         where: p.event_id == ^event_id)
    |> Repo.delete_all()
    
    # Delete poll options
    from(po in EventasaurusApp.Events.PollOption,
         join: p in EventasaurusApp.Events.Poll, on: po.poll_id == p.id,
         where: p.event_id == ^event_id)
    |> Repo.delete_all()
    
    # Delete polls
    from(p in EventasaurusApp.Events.Poll, where: p.event_id == ^event_id)
    |> Repo.delete_all()
    
    # Delete orders (should be empty due to eligibility check, but just in case)
    from(o in Order, where: o.event_id == ^event_id)
    |> Repo.delete_all()
    
    # Delete tickets
    from(t in Ticket, where: t.event_id == ^event_id)
    |> Repo.delete_all()
    
    # Delete event participants (should be empty due to eligibility check)
    from(p in EventParticipant, where: p.event_id == ^event_id)
    |> Repo.delete_all()
    
    # Delete event users (organizers)
    from(eu in EventasaurusApp.Events.EventUser, where: eu.event_id == ^event_id)
    |> Repo.delete_all()
  end

  defp log_hard_deletion(event, user_id) do
    Logger.info("Event hard deleted", %{
      event_id: event.id,
      event_title: event.title,
      user_id: user_id,
      deletion_type: :hard,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Helper function to get a human-readable reason for why an event cannot be hard deleted.
  """
  def get_ineligibility_reason(event_id, user_id, opts \\ []) do
    case eligible_for_hard_delete?(event_id, user_id, opts) do
      {:ok, _event} -> nil
      {:error, :event_not_found} -> "Event not found"
      {:error, :has_participants} -> "Event has user participants and cannot be permanently deleted"
      {:error, :has_orders} -> "Event has confirmed orders and cannot be permanently deleted"
      {:error, :has_sold_tickets} -> "Event has sold tickets and cannot be permanently deleted"
      {:error, :not_owner} -> "Only the event creator can permanently delete this event"
      {:error, :too_old} -> "Event is too old to be permanently deleted"
      {:error, :not_eligible_for_hard_delete} -> "Event is not eligible for permanent deletion"
      {:error, reason} -> "Cannot delete event: #{reason}"
    end
  end
end