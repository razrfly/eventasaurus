defmodule EventasaurusApp.Events.Delete do
  @moduledoc """
  Unified deletion context for events, handling both hard and soft deletion
  with proper permissions, business logic, and audit logging.
  
  This module provides a single entry point for event deletion, automatically
  determining whether to perform a hard or soft deletion based on event criteria.
  """

  alias EventasaurusApp.{Repo, Events}
  alias EventasaurusApp.Events.{Event, HardDelete, SoftDelete}
  alias EventasaurusApp.Accounts.User
  require Logger

  @type deletion_result :: {:ok, :hard_deleted} | {:ok, :soft_deleted} | {:error, atom() | String.t()}

  @doc """
  Deletes an event using the appropriate method (hard or soft delete).
  
  ## Parameters
    - event_id: ID of the event to delete
    - user_id: ID of the user performing the deletion
    - reason: String explaining why the event is being deleted
    
  ## Returns
    - {:ok, :hard_deleted} - Event was permanently deleted
    - {:ok, :soft_deleted} - Event was soft deleted
    - {:error, reason} - Deletion failed
    
  ## Examples
  
      iex> Delete.delete_event(123, 456, "Event cancelled")
      {:ok, :soft_deleted}
      
      iex> Delete.delete_event(999, 456, "Not found")
      {:error, :event_not_found}
  """
  @spec delete_event(integer() | String.t(), integer() | String.t(), String.t()) :: deletion_result()
  def delete_event(event_id, user_id, reason) when is_binary(reason) do
    with {:ok, event} <- get_event_safely(event_id),
         {:ok, user} <- get_user_safely(user_id),
         :ok <- check_permission(event, user),
         result <- perform_deletion(event, user, reason) do
      
      # Log the successful deletion
      log_deletion_attempt(event, user, reason, result)
      result
    else
      {:error, reason} = error ->
        # Log the failed deletion attempt
        log_deletion_attempt(event_id, user_id, reason, error)
        error
    end
  end

  def delete_event(_event_id, _user_id, reason) when not is_binary(reason) do
    {:error, :invalid_reason}
  end

  @doc """
  Determines the appropriate deletion method for an event.
  
  Returns :hard if the event is eligible for hard deletion, :soft otherwise.
  """
  @spec deletion_method(Event.t(), User.t()) :: :hard | :soft
  def deletion_method(%Event{} = event, %User{} = user) do
    case HardDelete.eligible_for_hard_delete?(event.id, user.id) do
      {:ok, _} -> :hard
      {:error, _} -> :soft
    end
  end

  @doc """
  Returns a human-readable explanation of why an event would be soft deleted
  instead of hard deleted.
  """
  @spec soft_delete_reason(Event.t(), User.t()) :: String.t() | nil
  def soft_delete_reason(%Event{} = event, %User{} = user) do
    HardDelete.get_ineligibility_reason(event.id, user.id)
  end

  # Private functions

  defp get_event_safely(event_id) do
    case Events.get_event(event_id) do
      %Event{} = event -> {:ok, event}
      nil -> {:error, :event_not_found}
    end
  end

  defp get_user_safely(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  defp check_permission(%Event{} = event, %User{} = user) do
    # Check if user is an organizer of the event
    if Events.user_is_organizer?(event, user) do
      :ok
    else
      {:error, :permission_denied}
    end
  end

  defp perform_deletion(%Event{} = event, %User{} = user, reason) do
    case deletion_method(event, user) do
      :hard ->
        perform_hard_deletion(event, user, reason)
      
      :soft ->
        perform_soft_deletion(event, user, reason)
    end
  end

  defp perform_hard_deletion(%Event{} = event, %User{} = user, reason) do
    case HardDelete.hard_delete_event(event.id, user.id) do
      {:ok, _deleted_event} ->
        Logger.info("Event hard deleted", %{
          event_id: event.id,
          user_id: user.id,
          reason: reason
        })
        {:ok, :hard_deleted}
      
      {:error, error_reason} ->
        # If hard delete fails, fall back to soft delete
        Logger.warning("Hard delete failed, falling back to soft delete", %{
          event_id: event.id,
          user_id: user.id,
          error: error_reason
        })
        perform_soft_deletion(event, user, reason)
    end
  end

  defp perform_soft_deletion(%Event{} = event, %User{} = user, reason) do
    case SoftDelete.soft_delete_event(event.id, reason, user.id) do
      {:ok, _deleted_event} ->
        Logger.info("Event soft deleted", %{
          event_id: event.id,
          user_id: user.id,
          reason: reason
        })
        {:ok, :soft_deleted}
      
      {:error, error_reason} ->
        Logger.error("Soft delete failed", %{
          event_id: event.id,
          user_id: user.id,
          error: error_reason
        })
        {:error, error_reason}
    end
  end

  # Audit logging functions

  defp log_deletion_attempt(event_or_id, user_or_id, reason, result) do
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
      reason: reason,
      result: format_result(result),
      timestamp: DateTime.utc_now()
    }

    case result do
      {:ok, _} ->
        Logger.info("Event deletion attempt successful", log_entry)
      
      {:error, _} ->
        Logger.error("Event deletion attempt failed", log_entry)
    end

    # In a production system, you would also write this to a dedicated audit log table
    # audit_log_to_database(log_entry)
  end

  defp format_result({:ok, type}), do: to_string(type)
  defp format_result({:error, reason}), do: "error: #{inspect(reason)}"

  # Commented out for now - would be implemented as part of Task 13 (Audit Trail)
  # defp audit_log_to_database(log_entry) do
  #   %EventDeletionAudit{}
  #   |> EventDeletionAudit.changeset(log_entry)
  #   |> Repo.insert()
  # end
end