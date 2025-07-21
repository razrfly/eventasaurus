defmodule EventasaurusApp.Events.SoftDelete do
  @moduledoc """
  Handles soft deletion of events and cascade soft deletion of associated records.
  
  Soft deletion preserves all data while marking records as deleted. This allows for
  data recovery and maintains referential integrity.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.{Repo, Events}
  alias EventasaurusApp.Events.{Event, EventParticipant, EventUser}
  alias EventasaurusApp.Events.{Poll, PollOption, PollVote}
  alias EventasaurusApp.Events.{Ticket, Order}
  require Logger

  @doc """
  Soft deletes an event and all its associated records.
  
  ## Parameters
    - event_id: ID of the event to be soft deleted
    - reason: String explaining why the event is being deleted
    - user_id: ID of the user performing the deletion
  
  ## Returns
    - {:ok, event} on successful deletion
    - {:error, reason} on failure
  """
  def soft_delete_event(event_id, reason, user_id) do
    Repo.transaction(fn ->
      with {:ok, event} <- get_event_safely(event_id),
           :ok <- validate_can_soft_delete(event),
           {:ok, deleted_event} <- do_soft_delete_event(event, reason, user_id),
           :ok <- cascade_soft_delete(event, reason, user_id) do
        
        # Log the soft deletion
        log_soft_deletion(event, user_id, reason)
        deleted_event
      else
        {:error, reason} -> 
          Logger.error("Soft delete failed for event #{event_id}: #{reason}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Restores a soft-deleted event and all its associated records.
  
  ## Parameters
    - event_id: ID of the event to be restored
    - user_id: ID of the user performing the restoration
  
  ## Returns
    - {:ok, event} on successful restoration
    - {:error, reason} on failure
  """
  def restore_event(event_id, user_id) do
    Repo.transaction(fn ->
      with {:ok, event} <- get_deleted_event_safely(event_id),
           {:ok, restored_event} <- do_restore_event(event, user_id),
           :ok <- cascade_restore(event, user_id) do
        
        # Log the restoration
        log_restoration(event, user_id)
        restored_event
      else
        {:error, reason} -> 
          Logger.error("Restore failed for event #{event_id}: #{reason}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Checks if an event can be soft deleted.
  """
  def can_soft_delete?(event_id) do
    with {:ok, event} <- get_event_safely(event_id),
         :ok <- validate_can_soft_delete(event) do
      true
    else
      _ -> false
    end
  end

  # Private helper functions

  defp get_event_safely(event_id) do
    case Events.get_event(event_id) do
      %Event{} = event -> {:ok, event}
      nil -> {:error, :event_not_found}
    end
  end

  defp get_deleted_event_safely(event_id) do
    # Get event including soft-deleted ones
    case Repo.get(Event, event_id) do
      %Event{deleted_at: nil} -> {:error, :event_not_deleted}
      %Event{} = event -> {:ok, event}
      nil -> {:error, :event_not_found}
    end
  end

  defp validate_can_soft_delete(event) do
    cond do
      event.deleted_at != nil ->
        {:error, :already_deleted}
      
      # Add other business rules as needed
      # For example, you might not allow soft deletion of events that are currently active
      # event.status == :confirmed and event.start_at < DateTime.utc_now() ->
      #   {:error, :event_already_started}
      
      true ->
        :ok
    end
  end

  defp do_soft_delete_event(event, reason, user_id) do
    # Use Ecto.SoftDelete.Repo.soft_delete function
    event
    |> Ecto.Changeset.change(%{
      deletion_reason: reason,
      deleted_by_user_id: user_id
    })
    |> Repo.soft_delete()
  end

  defp do_restore_event(event, _user_id) do
    # Clear the soft delete fields
    event
    |> Ecto.Changeset.change(%{
      deleted_at: nil,
      deletion_reason: nil,
      deleted_by_user_id: nil
    })
    |> Repo.update()
  end

  defp cascade_soft_delete(event, reason, user_id) do
    # Soft delete all associated records
    with :ok <- delete_associated_polls(event.id, reason, user_id),
         :ok <- delete_associated_tickets(event.id, reason, user_id),
         :ok <- delete_associated_orders(event.id, reason, user_id),
         :ok <- delete_associated_participants(event.id, reason, user_id),
         :ok <- delete_associated_event_users(event.id, reason, user_id) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp cascade_restore(event, user_id) do
    # Restore all associated records
    with :ok <- restore_associated_polls(event.id, user_id),
         :ok <- restore_associated_tickets(event.id, user_id),
         :ok <- restore_associated_orders(event.id, user_id),
         :ok <- restore_associated_participants(event.id, user_id),
         :ok <- restore_associated_event_users(event.id, user_id) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Poll-related soft deletion

  defp delete_associated_polls(event_id, reason, user_id) do
    # First soft delete poll votes
    from(pv in PollVote,
         join: po in PollOption, on: pv.poll_option_id == po.id,
         join: p in Poll, on: po.poll_id == p.id,
         where: p.event_id == ^event_id and is_nil(pv.deleted_at))
    |> Repo.soft_delete_all(
      deletion_reason: reason,
      deleted_by_user_id: user_id
    )

    # Then soft delete poll options  
    from(po in PollOption,
         join: p in Poll, on: po.poll_id == p.id,
         where: p.event_id == ^event_id and is_nil(po.deleted_at))
    |> Repo.soft_delete_all(
      deletion_reason: reason,
      deleted_by_user_id: user_id
    )

    # Finally soft delete polls
    from(p in Poll, 
         where: p.event_id == ^event_id and is_nil(p.deleted_at))
    |> Repo.soft_delete_all(
      deletion_reason: reason,
      deleted_by_user_id: user_id
    )

    :ok
  end

  defp restore_associated_polls(event_id, _user_id) do
    # Restore polls
    from(p in Poll, 
         where: p.event_id == ^event_id and not is_nil(p.deleted_at))
    |> Repo.update_all(set: [
      deleted_at: nil,
      deletion_reason: nil,
      deleted_by_user_id: nil
    ])

    # Restore poll options
    from(po in PollOption,
         join: p in Poll, on: po.poll_id == p.id,
         where: p.event_id == ^event_id and not is_nil(po.deleted_at))
    |> Repo.update_all(set: [
      deleted_at: nil,
      deletion_reason: nil,
      deleted_by_user_id: nil
    ])

    # Restore poll votes
    from(pv in PollVote,
         join: po in PollOption, on: pv.poll_option_id == po.id,
         join: p in Poll, on: po.poll_id == p.id,
         where: p.event_id == ^event_id and not is_nil(pv.deleted_at))
    |> Repo.update_all(set: [
      deleted_at: nil,
      deletion_reason: nil,
      deleted_by_user_id: nil
    ])

    :ok
  end

  # Ticket-related soft deletion

  defp delete_associated_tickets(event_id, reason, user_id) do
    from(t in Ticket, 
         where: t.event_id == ^event_id and is_nil(t.deleted_at))
    |> Repo.soft_delete_all(
      deletion_reason: reason,
      deleted_by_user_id: user_id
    )

    :ok
  end

  defp restore_associated_tickets(event_id, _user_id) do
    from(t in Ticket, 
         where: t.event_id == ^event_id and not is_nil(t.deleted_at))
    |> Repo.update_all(set: [
      deleted_at: nil,
      deletion_reason: nil,
      deleted_by_user_id: nil
    ])

    :ok
  end

  # Order-related soft deletion

  defp delete_associated_orders(event_id, reason, user_id) do
    from(o in Order, 
         where: o.event_id == ^event_id and is_nil(o.deleted_at))
    |> Repo.soft_delete_all(
      deletion_reason: reason,
      deleted_by_user_id: user_id
    )

    :ok
  end

  defp restore_associated_orders(event_id, _user_id) do
    from(o in Order, 
         where: o.event_id == ^event_id and not is_nil(o.deleted_at))
    |> Repo.update_all(set: [
      deleted_at: nil,
      deletion_reason: nil,
      deleted_by_user_id: nil
    ])

    :ok
  end

  # Participant-related soft deletion

  defp delete_associated_participants(event_id, reason, user_id) do
    from(p in EventParticipant, 
         where: p.event_id == ^event_id and is_nil(p.deleted_at))
    |> Repo.soft_delete_all(
      deletion_reason: reason,
      deleted_by_user_id: user_id
    )

    :ok
  end

  defp restore_associated_participants(event_id, _user_id) do
    from(p in EventParticipant, 
         where: p.event_id == ^event_id and not is_nil(p.deleted_at))
    |> Repo.update_all(set: [
      deleted_at: nil,
      deletion_reason: nil,
      deleted_by_user_id: nil
    ])

    :ok
  end

  # Event user-related soft deletion

  defp delete_associated_event_users(event_id, reason, user_id) do
    from(eu in EventUser, 
         where: eu.event_id == ^event_id and is_nil(eu.deleted_at))
    |> Repo.soft_delete_all(
      deletion_reason: reason,
      deleted_by_user_id: user_id
    )

    :ok
  end

  defp restore_associated_event_users(event_id, _user_id) do
    from(eu in EventUser, 
         where: eu.event_id == ^event_id and not is_nil(eu.deleted_at))
    |> Repo.update_all(set: [
      deleted_at: nil,
      deletion_reason: nil,
      deleted_by_user_id: nil
    ])

    :ok
  end

  # Logging functions

  defp log_soft_deletion(event, user_id, reason) do
    Logger.info("Event soft deleted", %{
      event_id: event.id,
      event_title: event.title,
      user_id: user_id,
      deletion_type: :soft,
      deletion_reason: reason,
      timestamp: DateTime.utc_now()
    })
  end

  defp log_restoration(event, user_id) do
    Logger.info("Event restored", %{
      event_id: event.id,
      event_title: event.title,
      user_id: user_id,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Gets statistics about soft deletion for reporting purposes.
  """
  def get_deletion_stats(opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 30)
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_back * 24 * 60 * 60, :second)

    %{
      total_deleted_events: get_deleted_events_count(cutoff_date),
      total_deleted_tickets: get_deleted_tickets_count(cutoff_date),
      total_deleted_orders: get_deleted_orders_count(cutoff_date),
      total_deleted_participants: get_deleted_participants_count(cutoff_date),
      total_deleted_polls: get_deleted_polls_count(cutoff_date)
    }
  end

  defp get_deleted_events_count(cutoff_date) do
    from(e in Event, 
         where: not is_nil(e.deleted_at) and e.deleted_at >= ^cutoff_date)
    |> Repo.aggregate(:count, :id)
  end

  defp get_deleted_tickets_count(cutoff_date) do
    from(t in Ticket, 
         where: not is_nil(t.deleted_at) and t.deleted_at >= ^cutoff_date)
    |> Repo.aggregate(:count, :id)
  end

  defp get_deleted_orders_count(cutoff_date) do
    from(o in Order, 
         where: not is_nil(o.deleted_at) and o.deleted_at >= ^cutoff_date)
    |> Repo.aggregate(:count, :id)
  end

  defp get_deleted_participants_count(cutoff_date) do
    from(p in EventParticipant, 
         where: not is_nil(p.deleted_at) and p.deleted_at >= ^cutoff_date)
    |> Repo.aggregate(:count, :id)
  end

  defp get_deleted_polls_count(cutoff_date) do
    from(p in Poll, 
         where: not is_nil(p.deleted_at) and p.deleted_at >= ^cutoff_date)
    |> Repo.aggregate(:count, :id)
  end
end