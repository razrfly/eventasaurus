defmodule EventasaurusApp.AuditLogger do
  @moduledoc """
  Audit logging for sensitive operations in the polling system.
  
  Logs important events like vote casting, poll creation/modification,
  and administrative actions for security and compliance.
  """

  require Logger

  @doc """
  Logs poll-related audit events.
  """
  def log_poll_event(event_type, poll_id, user_id, metadata \\ %{}) do
    audit_data = %{
      event_type: event_type,
      resource_type: "poll",
      resource_id: poll_id,
      user_id: user_id,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      ip_address: get_client_ip(metadata)
    }

    Logger.info("AUDIT: #{event_type}", audit_data)
    
    # Store in database if needed for compliance
    # store_audit_record(audit_data)
  end

  @doc """
  Logs vote-related audit events.
  """
  def log_vote_event(event_type, poll_id, option_id, user_id, metadata \\ %{}) do
    audit_data = %{
      event_type: event_type,
      resource_type: "vote",
      resource_id: "#{poll_id}:#{option_id}",
      user_id: user_id,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      ip_address: get_client_ip(metadata)
    }

    Logger.info("AUDIT: #{event_type}", audit_data)
    
    # Store in database if needed for compliance
    # store_audit_record(audit_data)
  end

  @doc """
  Logs administrative actions on polls.
  """
  def log_admin_event(event_type, resource_type, resource_id, admin_user_id, metadata \\ %{}) do
    audit_data = %{
      event_type: event_type,
      resource_type: resource_type,
      resource_id: resource_id,
      user_id: admin_user_id,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      ip_address: get_client_ip(metadata),
      admin_action: true
    }

    Logger.warning("ADMIN_AUDIT: #{event_type}", audit_data)
    
    # Store in database if needed for compliance
    # store_audit_record(audit_data)
  end

  @doc """
  Logs security-related events like rate limiting, validation failures.
  """
  def log_security_event(event_type, user_id, metadata \\ %{}) do
    audit_data = %{
      event_type: event_type,
      resource_type: "security",
      user_id: user_id,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      ip_address: get_client_ip(metadata),
      security_event: true
    }

    Logger.warning("SECURITY_AUDIT: #{event_type}", audit_data)
    
    # Store in database if needed for compliance
    # store_audit_record(audit_data)
  end

  # Common audit events

  def log_poll_created(poll_id, user_id, metadata \\ %{}) do
    log_poll_event("poll_created", poll_id, user_id, metadata)
  end

  def log_poll_updated(poll_id, user_id, changes, metadata \\ %{}) do
    log_poll_event("poll_updated", poll_id, user_id, Map.put(metadata, :changes, changes))
  end

  def log_poll_deleted(poll_id, user_id, metadata \\ %{}) do
    log_poll_event("poll_deleted", poll_id, user_id, metadata)
  end

  def log_poll_phase_changed(poll_id, user_id, from_phase, to_phase, metadata \\ %{}) do
    log_poll_event("poll_phase_changed", poll_id, user_id, 
      Map.merge(metadata, %{from_phase: from_phase, to_phase: to_phase}))
  end

  def log_vote_cast(poll_id, option_id, user_id, vote_data, metadata \\ %{}) do
    log_vote_event("vote_cast", poll_id, option_id, user_id, 
      Map.put(metadata, :vote_data, vote_data))
  end

  def log_vote_updated(poll_id, option_id, user_id, old_vote, new_vote, metadata \\ %{}) do
    log_vote_event("vote_updated", poll_id, option_id, user_id, 
      Map.merge(metadata, %{old_vote: old_vote, new_vote: new_vote}))
  end

  def log_vote_deleted(poll_id, option_id, user_id, metadata \\ %{}) do
    log_vote_event("vote_deleted", poll_id, option_id, user_id, metadata)
  end

  def log_rate_limit_exceeded(user_id, poll_id, metadata \\ %{}) do
    log_security_event("rate_limit_exceeded", user_id, 
      Map.put(metadata, :poll_id, poll_id))
  end

  def log_validation_failed(user_id, validation_type, metadata \\ %{}) do
    log_security_event("validation_failed", user_id, 
      Map.put(metadata, :validation_type, validation_type))
  end

  def log_unauthorized_access(user_id, resource_type, resource_id, metadata \\ %{}) do
    log_security_event("unauthorized_access", user_id, 
      Map.merge(metadata, %{resource_type: resource_type, resource_id: resource_id}))
  end

  @doc """
  Logs group-related audit events.
  """
  def log_group_event(event_type, group_id, user_id, metadata \\ %{}) do
    audit_data = %{
      event_type: event_type,
      resource_type: "group",
      resource_id: group_id,
      user_id: user_id,
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      ip_address: get_client_ip(metadata)
    }

    Logger.info("AUDIT: #{event_type}", audit_data)
    
    # Store in database if needed for compliance
    # store_audit_record(audit_data)
  end

  @doc """
  Logs group membership-related audit events.
  """
  def log_group_membership_event(event_type, group_id, target_user_id, acting_user_id, metadata \\ %{}) do
    audit_data = %{
      event_type: event_type,
      resource_type: "group_membership",
      resource_id: "#{group_id}:#{target_user_id}",
      user_id: acting_user_id,
      metadata: Map.put(metadata, :target_user_id, target_user_id),
      timestamp: DateTime.utc_now(),
      ip_address: get_client_ip(metadata)
    }

    Logger.info("AUDIT: #{event_type}", audit_data)
    
    # Store in database if needed for compliance
    # store_audit_record(audit_data)
  end

  # Group-specific audit events

  def log_group_created(group_id, user_id, metadata \\ %{}) do
    log_group_event("group_created", group_id, user_id, metadata)
  end

  def log_group_updated(group_id, user_id, changes, metadata \\ %{}) do
    log_group_event("group_updated", group_id, user_id, Map.put(metadata, :changes, changes))
  end

  def log_group_deleted(group_id, user_id, metadata \\ %{}) do
    log_group_event("group_deleted", group_id, user_id, metadata)
  end

  def log_member_added(group_id, target_user_id, acting_user_id, role, metadata \\ %{}) do
    log_group_membership_event("member_added", group_id, target_user_id, acting_user_id,
      Map.put(metadata, :role, role))
  end

  def log_member_removed(group_id, target_user_id, acting_user_id, reason, metadata \\ %{}) do
    log_group_membership_event("member_removed", group_id, target_user_id, acting_user_id,
      Map.put(metadata, :reason, reason))
  end

  def log_member_role_changed(group_id, target_user_id, acting_user_id, from_role, to_role, metadata \\ %{}) do
    log_group_membership_event("member_role_changed", group_id, target_user_id, acting_user_id,
      Map.merge(metadata, %{from_role: from_role, to_role: to_role}))
  end

  def log_group_sync(group_id, acting_user_id, results, metadata \\ %{}) do
    # Ensure results has required keys with defaults
    safe_results = %{
      added: results[:added] || 0,
      already_members: results[:already_members] || 0
    }
    
    log_group_event("group_sync_completed", group_id, acting_user_id,
      Map.merge(metadata, %{
        sync_results: safe_results,
        added_count: safe_results[:added],
        already_members_count: safe_results[:already_members]
      }))
  end

  def log_event_sync(group_id, event_id, acting_user_id, results, metadata \\ %{}) do
    # Ensure results has required keys with defaults
    safe_results = %{
      added: results[:added] || 0,
      already_members: results[:already_members] || 0
    }
    
    log_group_event("event_sync_completed", group_id, acting_user_id,
      Map.merge(metadata, %{
        event_id: event_id,
        sync_results: safe_results,
        added_count: safe_results[:added],
        already_members_count: safe_results[:already_members]
      }))
  end

  # Private functions

  defp get_client_ip(metadata) do
    case metadata do
      %{ip_address: ip} -> ip
      %{conn: conn} -> get_ip_from_conn(conn)
      _ -> "unknown"
    end
  end

  defp get_ip_from_conn(conn) do
    EventasaurusApp.IPExtractor.get_ip_from_conn(conn)
  end

  # Uncomment and implement if database audit storage is needed
  # defp store_audit_record(audit_data) do
  #   # Store audit record in database
  #   # EventasaurusApp.Repo.insert(%AuditLog{
  #   #   event_type: audit_data.event_type,
  #   #   resource_type: audit_data.resource_type,
  #   #   resource_id: audit_data.resource_id,
  #   #   user_id: audit_data.user_id,
  #   #   metadata: audit_data.metadata,
  #   #   timestamp: audit_data.timestamp,
  #   #   ip_address: audit_data.ip_address
  #   # })
  # end
end