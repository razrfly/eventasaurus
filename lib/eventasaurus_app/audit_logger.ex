defmodule EventasaurusApp.AuditLogger do
  @moduledoc """
  Centralized audit logging for security-sensitive operations.

  Logs important actions to both application logs and optionally to
  a persistent audit trail for compliance and security monitoring.
  """

  require Logger

  @doc """
  Logs authentication attempts with outcome.
  """
  def log_auth_attempt(email, ip_address, success, reason \\ nil) do
    metadata = %{
      action: "auth_attempt",
      email: mask_email(email),
      ip_address: ip_address,
      success: success,
      reason: reason,
      timestamp: DateTime.utc_now()
    }

    if success do
      Logger.info("Successful authentication", metadata)
    else
      Logger.warning("Failed authentication attempt", metadata)
    end
  end

  @doc """
  Logs poll creation with creator information.
  """
  def log_poll_create(poll_id, event_id, user_id, poll_type) do
    metadata = %{
      action: "poll_create",
      poll_id: poll_id,
      event_id: event_id,
      user_id: user_id,
      poll_type: poll_type,
      timestamp: DateTime.utc_now()
    }

    Logger.info("Poll created", metadata)
  end

  @doc """
  Logs poll deletion for audit trail.
  """
  def log_poll_delete(poll_id, event_id, user_id, reason \\ nil) do
    metadata = %{
      action: "poll_delete",
      poll_id: poll_id,
      event_id: event_id,
      user_id: user_id,
      reason: reason,
      timestamp: DateTime.utc_now()
    }

    Logger.warning("Poll deleted", metadata)
  end

  @doc """
  Logs vote manipulation detection.
  """
  def log_vote_manipulation_attempt(poll_id, user_id, ip_address, details) do
    metadata = %{
      action: "vote_manipulation_attempt",
      poll_id: poll_id,
      user_id: user_id,
      ip_address: ip_address,
      details: details,
      timestamp: DateTime.utc_now()
    }

    Logger.error("Vote manipulation attempt detected", metadata)
  end

  @doc """
  Logs rate limit violations for pattern detection.
  """
  def log_rate_limit_violation(endpoint, identifier, limit_type) do
    metadata = %{
      action: "rate_limit_violation",
      endpoint: endpoint,
      identifier: identifier,
      limit_type: limit_type,
      timestamp: DateTime.utc_now()
    }

    Logger.warning("Rate limit exceeded", metadata)
  end

  @doc """
  Logs permission violations for security monitoring.
  """
  def log_permission_violation(user_id, resource_type, resource_id, attempted_action) do
    metadata = %{
      action: "permission_violation",
      user_id: user_id,
      resource_type: resource_type,
      resource_id: resource_id,
      attempted_action: attempted_action,
      timestamp: DateTime.utc_now()
    }

    Logger.error("Permission violation attempted", metadata)
  end

  @doc """
  Logs event state transitions for accountability.
  """
  def log_event_state_change(event_id, user_id, from_state, to_state) do
    metadata = %{
      action: "event_state_change",
      event_id: event_id,
      user_id: user_id,
      from_state: from_state,
      to_state: to_state,
      timestamp: DateTime.utc_now()
    }

    Logger.info("Event state changed", metadata)
  end

  @doc """
  Logs bulk operations for monitoring abuse.
  """
  def log_bulk_operation(operation_type, user_id, count, details \\ %{}) do
    metadata = %{
      action: "bulk_operation",
      operation_type: operation_type,
      user_id: user_id,
      count: count,
      details: details,
      timestamp: DateTime.utc_now()
    }

    if count > 100 do
      Logger.warning("Large bulk operation performed", metadata)
    else
      Logger.info("Bulk operation performed", metadata)
    end
  end

  # Privacy-safe email masking
  defp mask_email(email) when is_binary(email) do
    case String.split(email, "@", parts: 2) do
      [local, domain] ->
        masked_local = String.slice(local, 0, 2) <> "***"
        "#{masked_local}@#{domain}"

      _ ->
        "***@invalid"
    end
  end

  defp mask_email(_), do: "***@unknown"
end

