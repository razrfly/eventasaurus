defmodule EventasaurusApp.Auth.Monitor do
  @moduledoc """
  Authentication monitoring and logging module for Eventasaurus.

  Provides structured logging for authentication events to enable monitoring,
  alerting, and analysis of the authentication system.
  """

  require Logger

  @doc """
  Log authentication registration attempts with structured data for monitoring
  """
  def log_registration_attempt(event_id, email, name, result, metadata \\ %{}) do
    Logger.info("Auth registration attempt", %{
      event: "registration_attempt",
      event_id: event_id,
      email_domain: extract_email_domain(email),
      user_name: name,
      result: result,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id(),
      metadata: metadata
    })
  end

  @doc """
  Log successful email sends with delivery tracking info
  """
  def log_email_sent(email, message_id \\ nil, metadata \\ %{}) do
    Logger.info("Auth email sent", %{
      event: "email_sent",
      email_domain: extract_email_domain(email),
      message_id: message_id || generate_correlation_id(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id(),
      metadata: metadata
    })
  end

  @doc """
  Log authentication callback attempts (email confirmation links)
  """
  def log_callback_attempt(access_token, result, user_id \\ nil, metadata \\ %{}) do
    Logger.info("Auth callback attempt", %{
      event: "callback_attempt",
      token_prefix: String.slice(access_token, 0, 8),
      result: result,
      user_id: user_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id(),
      metadata: metadata
    })
  end

  @doc """
  Log authentication errors with context for debugging
  """
  def log_error(error_type, details, context \\ %{}) do
    Logger.error("Auth error occurred", %{
      event: "auth_error",
      error_type: error_type,
      details: sanitize_error_details(details),
      context: context,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id()
    })
  end

  @doc """
  Log successful user creation after email confirmation
  """
  def log_user_created(user_id, email, event_context \\ %{}) do
    Logger.info("User created after confirmation", %{
      event: "user_created",
      user_id: user_id,
      email_domain: extract_email_domain(email),
      event_context: event_context,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id()
    })
  end

  @doc """
  Log session creation events
  """
  def log_session_created(user_id, session_type \\ "email_confirmation") do
    Logger.info("Session created", %{
      event: "session_created",
      user_id: user_id,
      session_type: session_type,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id()
    })
  end

  @doc """
  Log performance metrics for authentication operations
  """
  def log_performance_metric(operation, duration_ms, metadata \\ %{}) do
    Logger.info("Auth performance metric", %{
      event: "performance_metric",
      operation: operation,
      duration_ms: duration_ms,
      metadata: metadata,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id()
    })
  end

  @doc """
  Log suspicious or unusual authentication activity
  """
  def log_suspicious_activity(activity_type, details, risk_level \\ "medium") do
    Logger.warning("Suspicious auth activity detected", %{
      event: "suspicious_activity",
      activity_type: activity_type,
      details: details,
      risk_level: risk_level,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id()
    })
  end

  @doc """
  Log rate limiting events
  """
  def log_rate_limit(identifier, limit_type, current_count, limit) do
    Logger.warning("Rate limit triggered", %{
      event: "rate_limit",
      identifier: hash_identifier(identifier),
      limit_type: limit_type,
      current_count: current_count,
      limit: limit,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      correlation_id: generate_correlation_id()
    })
  end

  # Private helper functions

  defp extract_email_domain(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.last()
  end
  defp extract_email_domain(_), do: "unknown"

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16()
    |> String.downcase()
  end

  defp sanitize_error_details(details) when is_binary(details) do
    # Remove sensitive information from error details
    details
    |> String.replace(~r/password[:\s]*[^\s,}]+/i, "password: [REDACTED]")
    |> String.replace(~r/token[:\s]*[^\s,}]+/i, "token: [REDACTED]")
    |> String.replace(~r/secret[:\s]*[^\s,}]+/i, "secret: [REDACTED]")
  end
  defp sanitize_error_details(details), do: details

  defp hash_identifier(identifier) when is_binary(identifier) do
    # Hash sensitive identifiers (like email/IP) for privacy
    :crypto.hash(:sha256, identifier)
    |> Base.encode16()
    |> String.slice(0, 12)
    |> String.downcase()
  end
  defp hash_identifier(identifier), do: inspect(identifier)
end
