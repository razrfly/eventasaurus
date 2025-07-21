defmodule EventasaurusApp.Events.Restore do
  @moduledoc """
  Handles restoration of soft-deleted events and their associated records.
  
  This module provides functionality to restore soft-deleted events back to active status,
  including all related records (participants, polls, tickets, orders, etc.).
  Includes eligibility validation, conflict resolution, and authorization checks.
  """

  import Ecto.Query
  
  alias EventasaurusApp.{Repo, Events}
  alias EventasaurusApp.Events.{Event, EventParticipant, EventUser, Poll, PollOption, PollVote}
  alias EventasaurusApp.Events.{Ticket, Order}
  alias EventasaurusApp.Accounts.User
  require Logger

  @type restore_result :: {:ok, Event.t()} | {:error, atom() | String.t()}

  @doc """
  Restores a soft-deleted event and all its associated records.
  
  ## Parameters
    - event_id: ID of the soft-deleted event to restore
    - user_id: ID of the user performing the restoration
    
  ## Returns
    - {:ok, event} - Event was successfully restored
    - {:error, reason} - Restoration failed
    
  ## Examples
  
      iex> Restore.restore_event(123, 456)
      {:ok, %Event{}}
      
      iex> Restore.restore_event(999, 456)
      {:error, :event_not_found}
  """
  @spec restore_event(integer() | String.t(), integer() | String.t()) :: restore_result()
  def restore_event(event_id, user_id) do
    Repo.transaction(fn ->
      with {:ok, event} <- get_soft_deleted_event(event_id),
           {:ok, user} <- get_user(user_id),
           :ok <- check_authorization(event, user),
           :ok <- validate_restoration_eligibility(event),
           :ok <- check_conflicts(event),
           {:ok, restored_event} <- perform_restoration(event, user) do
        
        log_restoration_attempt(event, user, :success)
        restored_event
      else
        {:error, reason} ->
          log_restoration_attempt(event_id, user_id, {:error, reason})
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, event} -> {:ok, event}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks if an event is eligible for restoration.
  
  Returns {:ok, event} if eligible, {:error, reason} if not.
  """
  @spec eligible_for_restoration?(integer() | String.t()) :: {:ok, Event.t()} | {:error, atom() | String.t()}
  def eligible_for_restoration?(event_id) do
    with {:ok, event} <- get_soft_deleted_event(event_id),
         :ok <- validate_restoration_eligibility(event) do
      {:ok, event}
    end
  end

  @doc """
  Gets restoration statistics.
  
  Returns information about restored events for reporting purposes.
  """
  @spec get_restoration_stats(keyword()) :: map()
  def get_restoration_stats(opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 30)
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_back * 24 * 60 * 60, :second)
    
    # This would track restoration events in a dedicated audit table
    # For now, return basic stats structure
    %{
      total_restored: 0,
      restored_in_period: 0,
      period_days: days_back,
      cutoff_date: cutoff_date
    }
  end

  # Private functions

  defp get_soft_deleted_event(event_id) do
    case Events.get_event(event_id, include_deleted: true) do
      %Event{deleted_at: nil} ->
        {:error, :event_not_deleted}
      
      %Event{deleted_at: deleted_at} = event when not is_nil(deleted_at) ->
        {:ok, event}
      
      nil ->
        {:error, :event_not_found}
    end
  end

  defp get_user(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  defp check_authorization(%Event{} = event, %User{} = user) do
    # Check if user is an organizer of the event
    if Events.user_is_organizer?(event, user) do
      :ok
    else
      # TODO: Add admin authorization check here
      {:error, :permission_denied}
    end
  end

  defp validate_restoration_eligibility(%Event{} = event) do
    cond do
      # Check if event was deleted too long ago (e.g., 90 days)
      restoration_window_expired?(event) ->
        {:error, :restoration_window_expired}
      
      # Add other eligibility checks here if needed
      true ->
        :ok
    end
  end

  defp restoration_window_expired?(%Event{deleted_at: deleted_at}) do
    # Allow restoration within 90 days
    window_days = 90
    expiry_date = DateTime.add(deleted_at, window_days * 24 * 60 * 60, :second)
    DateTime.compare(DateTime.utc_now(), expiry_date) == :gt
  end

  defp check_conflicts(%Event{} = event) do
    # Check for slug conflicts
    case Events.get_event_by_slug(event.slug) do
      nil -> :ok
      %Event{id: id} when id != event.id -> {:error, :slug_conflict}
      _ -> :ok
    end
    
    # Could add more conflict checks here:
    # - Title conflicts within same user
    # - Date conflicts for venue
    # - etc.
  end

  defp perform_restoration(%Event{} = event, %User{} = user) do
    Logger.info("Starting restoration process", %{
      event_id: event.id,
      user_id: user.id,
      event_title: event.title
    })
    
    # Restore the main event
    {:ok, restored_event} = event
    |> Event.changeset(%{})
    |> Ecto.Changeset.put_change(:deleted_at, nil)
    |> Ecto.Changeset.put_change(:deletion_reason, nil)
    |> Ecto.Changeset.put_change(:deleted_by_user_id, nil)
    |> Repo.update()
    
    # Restore associated records
    restore_associated_records(event.id)
    
    Logger.info("Event restored successfully", %{
      event_id: event.id,
      user_id: user.id
    })
    
    {:ok, restored_event}
  end

  defp restore_associated_records(event_id) do
    # Restore EventParticipants
    {restore_count, _} = Repo.update_all(
      from(ep in EventParticipant, 
           where: ep.event_id == ^event_id and not is_nil(ep.deleted_at)),
      set: [deleted_at: nil, deletion_reason: nil, deleted_by_user_id: nil]
    )
    Logger.debug("Restored #{restore_count} event participants")

    # Restore EventUsers  
    {restore_count, _} = Repo.update_all(
      from(eu in EventUser,
           where: eu.event_id == ^event_id and not is_nil(eu.deleted_at)),
      set: [deleted_at: nil, deletion_reason: nil, deleted_by_user_id: nil]
    )
    Logger.debug("Restored #{restore_count} event users")

    # Restore Polls
    {restore_count, _} = Repo.update_all(
      from(p in Poll,
           where: p.event_id == ^event_id and not is_nil(p.deleted_at)),
      set: [deleted_at: nil, deletion_reason: nil, deleted_by_user_id: nil]
    )
    Logger.debug("Restored #{restore_count} polls")

    # Restore PollOptions (for polls belonging to this event)
    {restore_count, _} = Repo.update_all(
      from(po in PollOption,
           join: p in Poll, on: po.poll_id == p.id,
           where: p.event_id == ^event_id and not is_nil(po.deleted_at)),
      set: [deleted_at: nil, deletion_reason: nil, deleted_by_user_id: nil]
    )
    Logger.debug("Restored #{restore_count} poll options")

    # Restore PollVotes (for poll options belonging to polls of this event)
    {restore_count, _} = Repo.update_all(
      from(pv in PollVote,
           join: po in PollOption, on: pv.poll_option_id == po.id,
           join: p in Poll, on: po.poll_id == p.id,
           where: p.event_id == ^event_id and not is_nil(pv.deleted_at)),
      set: [deleted_at: nil, deletion_reason: nil, deleted_by_user_id: nil]
    )
    Logger.debug("Restored #{restore_count} poll votes")

    # Restore Tickets
    {restore_count, _} = Repo.update_all(
      from(t in Ticket,
           where: t.event_id == ^event_id and not is_nil(t.deleted_at)),
      set: [deleted_at: nil, deletion_reason: nil, deleted_by_user_id: nil]
    )
    Logger.debug("Restored #{restore_count} tickets")

    # Restore Orders
    {restore_count, _} = Repo.update_all(
      from(o in Order,
           where: o.event_id == ^event_id and not is_nil(o.deleted_at)),
      set: [deleted_at: nil, deletion_reason: nil, deleted_by_user_id: nil]
    )
    Logger.debug("Restored #{restore_count} orders")
    
    :ok
  end

  # Audit logging functions

  defp log_restoration_attempt(event_or_id, user_or_id, result) do
    event_id = case event_or_id do
      %Event{id: id} -> id
      id when is_integer(id) or is_binary(id) -> id
    end

    user_id = case user_or_id do
      %User{id: id} -> id
      id when is_integer(id) or is_binary(id) -> id
    end

    log_entry = %{
      event_id: event_id,
      user_id: user_id,
      result: format_result(result),
      timestamp: DateTime.utc_now()
    }

    case result do
      :success ->
        Logger.info("Event restoration attempt successful", log_entry)
      
      {:error, _} ->
        Logger.error("Event restoration attempt failed", log_entry)
    end

    # In a production system, you would also write this to a dedicated audit log table
    # audit_log_to_database(log_entry)
  end

  defp format_result(:success), do: "success"
  defp format_result({:error, reason}), do: "error: #{inspect(reason)}"

  # Commented out for now - would be implemented as part of comprehensive audit system
  # defp audit_log_to_database(log_entry) do
  #   %EventRestorationAudit{}
  #   |> EventRestorationAudit.changeset(log_entry)
  #   |> Repo.insert()
  # end
end