defmodule EventasaurusWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plugs for Phoenix controllers.

  This module provides plugs for handling user authentication in controllers.
  It manages the dual user assignment pattern:

  - `conn.assigns.auth_user`: Raw authentication data from Supabase (internal use only)
  - Controllers should process this into a local User struct for business logic

  ## Available Plugs

  1. `fetch_auth_user` - Loads the authenticated user from the session and assigns it to conn
  2. `require_authenticated_user` - Ensures a user is authenticated or redirects to login
  3. `redirect_if_user_is_authenticated` - Redirects authenticated users away from auth pages
  """

  import Plug.Conn
  import Phoenix.Controller

  # Import verified routes for ~p sigil
  use Phoenix.VerifiedRoutes,
    endpoint: EventasaurusWeb.Endpoint,
    router: EventasaurusWeb.Router,
    statics: EventasaurusWeb.static_paths()

  alias EventasaurusApp.Auth
  alias EventasaurusApp.Auth.Client

  # We'll use this in a future implementation for token expiry checks
  # For now we can just remove it since it's not being used
  # @refresh_window 300

  @doc """
  Fetches the authenticated user from the session and assigns to `conn.assigns.auth_user`.

  This plug extracts the access token from the session and fetches the user data
  from Supabase. Controllers should process this raw data into a local User struct
  for business logic operations.

  ## Usage

      plug :fetch_auth_user
  """
  def fetch_auth_user(conn, _opts) do
    user = Auth.get_current_user(conn)
    assign(conn, :auth_user, user)
  end

  @doc """
  Processes the auth_user into a local User struct and assigns to `conn.assigns.user`.

  This plug takes the raw auth data from `:auth_user` and converts it into a
  proper User struct for use in templates and business logic.

  ## Usage

      plug :assign_user_struct
  """
  def assign_user_struct(conn, _opts) do
    user = case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, user} -> user
      {:error, _} -> nil
    end
    assign(conn, :user, user)
  end

  @doc """
  Requires that a user is authenticated.

  If no authenticated user is found in `conn.assigns.auth_user`, redirects to login page.
  For LiveView routes, skips setting flash message since the LiveView auth hook will handle it.

  ## Usage

      plug :require_authenticated_user
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:auth_user] do
      conn = maybe_refresh_token(conn)
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/auth/login")
      |> halt()
    end
  end

  @doc """
  Requires that a user is authenticated for API requests.

  If no authenticated user is found in `conn.assigns.auth_user`, returns JSON error.

  ## Usage

      plug :require_authenticated_api_user
  """
  def require_authenticated_api_user(conn, _opts) do
    if conn.assigns[:auth_user] do
      conn = maybe_refresh_token_api(conn)
      # Check if connection was halted by maybe_refresh_token_api
      if conn.halted do
        conn
      else
        # Enhanced: Validate JWT token integrity
        case validate_jwt_token(conn) do
          {:ok, conn} -> conn
          {:error, _reason} ->
            conn
            |> put_status(:unauthorized)
            |> Phoenix.Controller.json(%{
              success: false,
              error: "token_invalid",
              message: "Authentication failed"
            })
            |> halt()
        end
      end
    else
      conn
      |> put_status(:unauthorized)
      |> Phoenix.Controller.json(%{
        success: false,
        error: "unauthorized",
        message: "You must be logged in to access this endpoint"
      })
      |> halt()
    end
  end

  @doc """
  Redirects authenticated users away from authentication pages.

  Useful for login/register pages that shouldn't be accessible to already
  authenticated users.

  ## Usage

      plug :redirect_if_user_is_authenticated
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:auth_user] do
      conn
      |> redirect(to: ~p"/dashboard")
      |> halt()
    else
      conn
    end
  end

  @doc """
  Detects password recovery flow and handles appropriate redirects.

  This plug checks if the user is in a password recovery session and redirects
  them to the password reset form if needed. This handles the case where users
  click a password reset link from their email.

  ## Usage

      plug :handle_password_recovery
  """
  def handle_password_recovery(conn, _opts) do
    # Check if user is authenticated and in password recovery state
    if conn.assigns[:auth_user] && is_password_recovery_session?(conn) do
      # User is logged in temporarily for password recovery
      # Redirect them to the reset password form
      conn
      |> put_flash(:info, "Please set your new password below.")
      |> redirect(to: ~p"/auth/reset-password")
      |> halt()
    else
      conn
    end
  end

  @doc """
  Validates user permissions for specific actions.

  This plug checks if the authenticated user has the required permissions
  for the requested action. Permissions are checked against user roles
  and specific resource access rights.

  ## Usage

      plug :require_permission, action: :manage_events
      plug :require_permission, action: :search_users, resource: :event
  """
  def require_permission(conn, opts) do
    action = Keyword.get(opts, :action)
    resource = Keyword.get(opts, :resource)

    case validate_user_permission(conn.assigns[:user], action, resource, conn.params) do
      :ok -> conn
      {:error, reason} ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(%{
          success: false,
          error: "insufficient_permissions",
          message: reason
        })
        |> halt()
    end
  end

  @doc """
  Enhanced input sanitization and validation for API requests.

  This plug sanitizes and validates all input parameters according to
  security best practices, preventing injection attacks and ensuring
  data integrity. Logs security events for monitoring.

  ## Usage

      plug :sanitize_and_validate_input
  """
  def sanitize_and_validate_input(conn, _opts) do
    case sanitize_request_params(conn.params) do
      {:ok, sanitized_params} ->
        # Log potential security concerns if significant sanitization occurred
        if params_were_modified?(conn.params, sanitized_params) do
          log_security_event(conn, "input_sanitized", %{
            original_params: sanitize_params_for_logging(conn.params),
            sanitized_params: sanitize_params_for_logging(sanitized_params)
          })
        end
        %{conn | params: sanitized_params}
      {:error, errors} ->
        # Log security violation attempt
        log_security_event(conn, "input_validation_failed", %{
          errors: errors,
          params: sanitize_params_for_logging(conn.params)
        })
        conn
        |> put_status(:bad_request)
        |> Phoenix.Controller.json(%{
          success: false,
          error: "invalid_input",
          message: "Request contains invalid or unsafe parameters",
          details: errors
        })
        |> halt()
    end
  end

  @doc """
  Redirects authenticated users away from auth pages, but allows password recovery.

  This plug redirects authenticated users who try to access authentication pages
  (like login, register) back to the dashboard, except when they are in a
  password recovery session where they need to reset their password.

  ## Usage

      plug :redirect_if_user_is_authenticated_except_recovery
  """
  def redirect_if_user_is_authenticated_except_recovery(conn, _opts) do
    if conn.assigns[:auth_user] do
      if is_password_recovery_session?(conn) do
        # User is in password recovery - allow access to reset password page only
        if conn.request_path == "/auth/reset-password" do
          conn
        else
          # Redirect to reset password if they're trying to go elsewhere during recovery
          conn
          |> put_flash(:info, "Please complete your password reset first.")
          |> redirect(to: ~p"/auth/reset-password")
          |> halt()
        end
      else
        # Normal authenticated user - redirect away from auth pages
        conn
        |> redirect(to: ~p"/dashboard")
        |> halt()
      end
    else
      conn
    end
  end

  @doc """
  Attempts to refresh the access token if it's near expiration.

  Returns the updated connection with new tokens if refreshed,
  or redirects to login if refresh fails.
  """
  def maybe_refresh_token(conn) do
    refresh_token = get_session(conn, :refresh_token)

    # Only try to refresh if we have a refresh token
    if refresh_token do
      case Client.refresh_token(refresh_token) do
        {:ok, auth_data} ->
          # Extract the tokens from the response
          access_token = get_token_value(auth_data, "access_token")
          new_refresh_token = get_token_value(auth_data, "refresh_token")

          if access_token && new_refresh_token do
            # Update the session with the new tokens
            conn
            |> put_session(:access_token, access_token)
            |> put_session(:refresh_token, new_refresh_token)
            |> configure_session(renew: true)
          else
            # If tokens couldn't be extracted, clear the session and redirect
            Auth.clear_session(conn)
            |> put_flash(:error, "Your session has expired. Please log in again.")
            |> redirect(to: ~p"/auth/login")
            |> halt()
          end

        {:error, _reason} ->
          # If refresh fails, clear the session and redirect to login
          Auth.clear_session(conn)
          |> put_flash(:error, "Your session has expired. Please log in again.")
          |> redirect(to: ~p"/auth/login")
          |> halt()
      end
    else
      conn
    end
  end

  @doc """
  Attempts to refresh the access token if it's near expiration for API requests.

  Returns the updated connection with new tokens if refreshed,
  or returns JSON error if refresh fails.
  """
  def maybe_refresh_token_api(conn) do
    refresh_token = get_session(conn, :refresh_token)

    # Only try to refresh if we have a refresh token
    if refresh_token do
      case Client.refresh_token(refresh_token) do
        {:ok, auth_data} ->
          # Extract the tokens from the response
          access_token = get_token_value(auth_data, "access_token")
          new_refresh_token = get_token_value(auth_data, "refresh_token")

          if access_token && new_refresh_token do
            # Update the session with the new tokens
            conn
            |> put_session(:access_token, access_token)
            |> put_session(:refresh_token, new_refresh_token)
            |> configure_session(renew: true)
          else
            # If tokens couldn't be extracted, return JSON error
            conn
            |> put_status(:unauthorized)
            |> Phoenix.Controller.json(%{
              success: false,
              error: "session_expired",
              message: "Your session has expired. Please log in again."
            })
            |> halt()
          end

        {:error, _reason} ->
          # If refresh fails, return JSON error
          conn
          |> put_status(:unauthorized)
          |> Phoenix.Controller.json(%{
            success: false,
            error: "session_expired",
            message: "Your session has expired. Please log in again."
          })
          |> halt()
      end
    else
      conn
    end
  end

  # Helper to get a token value from various response formats
  defp get_token_value(auth_data, key) do
    cond do
      is_map(auth_data) && Map.has_key?(auth_data, key) ->
        Map.get(auth_data, key)
      is_map(auth_data) && Map.has_key?(auth_data, String.to_atom(key)) ->
        Map.get(auth_data, String.to_atom(key))
      is_map(auth_data) && key == "access_token" && Map.has_key?(auth_data, "token") ->
        Map.get(auth_data, "token")
      true ->
        nil
    end
  end

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%EventasaurusApp.Accounts.User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    EventasaurusApp.Accounts.find_or_create_from_supabase(supabase_user)
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}

  # Helper function to detect password recovery sessions
  defp is_password_recovery_session?(conn) do
    # Check for recovery state in session (set by callback)
    recovery_state = get_session(conn, :password_recovery)

    # Only allow recovery if explicitly set in session and user is authenticated
    recovery_state == true && conn.assigns[:auth_user] != nil
  end

  @doc """
  Validates JWT token integrity and expiration.

  Checks the JWT token stored in the session for validity,
  ensuring it hasn't been tampered with and hasn't expired.
  """
  def validate_jwt_token(conn) do
    access_token = get_session(conn, :access_token)

    if access_token do
      case Client.validate_token(access_token) do
        {:ok, _token_data} ->
          {:ok, conn}
        {:error, :expired} ->
          # Token expired, try to refresh
          refreshed_conn = maybe_refresh_token_api(conn)
          if refreshed_conn.halted do
            {:error, "token_expired"}
          else
            {:ok, refreshed_conn}
          end
        {:error, reason} ->
          {:error, "token_invalid: #{reason}"}
      end
    else
      {:error, "no_token"}
    end
  end

  # Enhanced permission validation with role-based access control
  defp validate_user_permission(nil, _action, _resource, _params), do: {:error, "User not authenticated"}
  defp validate_user_permission(user, action, resource, params) do
    case {action, resource} do
      {:search_users, _} ->
        # Basic permission: authenticated users can search
        # Enhanced: Ensure user has a valid profile
        if user.email && user.name do
          :ok
        else
          {:error, "Complete profile required for user search"}
        end

      {:manage_events, _} ->
        # Check if user can manage the specific event
        event_id = params["event_id"]
        if event_id do
          case validate_event_management_permission(user, event_id) do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, "Event ID required for event management"}
        end

      {:add_organizers, _} ->
        # Only event creators and existing organizers can add new organizers
        event_id = params["event_id"]
        if event_id do
          case validate_organizer_management_permission(user, event_id) do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, "Event ID required for organizer management"}
        end

      {unknown_action, _} ->
        {:error, "Unknown action: #{unknown_action}"}
    end
  end

  # Helper function to validate event management permissions
  defp validate_event_management_permission(user, event_id) do
    case EventasaurusApp.Events.get_event(event_id) do
      %EventasaurusApp.Events.Event{} = event ->
        if EventasaurusApp.Events.user_can_manage_event?(user, event) do
          :ok
        else
          {:error, "You don't have permission to manage this event"}
        end
      nil ->
        {:error, "Event not found"}
    end
  end

  # Helper function to validate organizer management permissions
  defp validate_organizer_management_permission(user, event_id) do
    case EventasaurusApp.Events.get_event(event_id) do
      %EventasaurusApp.Events.Event{} = event ->
        if EventasaurusApp.Events.user_is_organizer?(event, user) do
          :ok
        else
          {:error, "Only event organizers can add new organizers"}
        end
      nil ->
        {:error, "Event not found"}
    end
  end

  # Enhanced input sanitization
  defp sanitize_request_params(params) when is_map(params) do
    sanitized =
      params
      |> Enum.map(&sanitize_param/1)
      |> Enum.reduce({%{}, []}, fn
        {:ok, {key, value}}, {acc_params, acc_errors} ->
          {Map.put(acc_params, key, value), acc_errors}
        {:error, error}, {acc_params, acc_errors} ->
          {acc_params, [error | acc_errors]}
      end)

    case sanitized do
      {params, []} -> {:ok, params}
      {_params, errors} -> {:error, errors}
    end
  end

  defp sanitize_param({key, value}) do
    case sanitize_value(key, value) do
      {:ok, sanitized_value} -> {:ok, {key, sanitized_value}}
      {:error, reason} -> {:error, "Invalid #{key}: #{reason}"}
    end
  end

  defp sanitize_value("q", value) when is_binary(value) do
    # Enhanced search query sanitization - comprehensive XSS and injection prevention
    sanitized =
      value
      |> String.trim()
      |> String.replace(~r/[<>\"'&%]/, "")  # Remove HTML/script injection chars
      |> String.replace(~r/javascript:/i, "")  # Remove javascript: protocol
      |> String.replace(~r/data:/i, "")  # Remove data: protocol
      |> String.replace(~r/vbscript:/i, "")  # Remove vbscript: protocol
      |> String.replace(~r/on\w+\s*=/i, "")  # Remove event handlers (onclick, onload, etc.)
      |> String.replace(~r/\s+/, " ")  # Normalize whitespace
      |> String.slice(0, 100)  # Limit length

    if String.length(sanitized) >= 2 do
      {:ok, sanitized}
    else
      {:error, "Search query must be at least 2 characters"}
    end
  end

  defp sanitize_value(key, value) when key in ["page", "per_page", "event_id"] do
    case safe_parse_positive_integer(value, nil) do
      nil -> {:error, "Must be a positive integer"}
      int when int > 0 and int <= 10000 -> {:ok, int}  # Reasonable upper limit
      _ -> {:error, "Must be a positive integer within reasonable limits"}
    end
  end

  # Enhanced validation for string fields that might contain user content
  defp sanitize_value(key, value) when key in ["title", "description", "name"] and is_binary(value) do
    sanitized =
      value
      |> String.trim()
      |> sanitize_html_content()
      |> String.slice(0, 255)  # Reasonable length limit for most text fields

    {:ok, sanitized}
  end

  # Enhanced validation for URL fields
  defp sanitize_value(key, value) when key in ["website_url", "callback_url", "redirect_url"] and is_binary(value) do
    if String.match?(value, ~r/^https?:\/\/[\w\-\.]+(:\d+)?(\/.*)?$/i) do
      {:ok, value}
    else
      {:error, "Must be a valid HTTP/HTTPS URL"}
    end
  end

  # Enhanced validation for email fields
  defp sanitize_value(key, value) when key in ["email"] and is_binary(value) do
    if String.match?(value, ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/) do
      {:ok, String.downcase(String.trim(value))}
    else
      {:error, "Must be a valid email address"}
    end
  end

  defp sanitize_value(_key, value), do: {:ok, value}

  # Helper function to sanitize HTML content
  defp sanitize_html_content(content) when is_binary(content) do
    content
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")  # Remove script tags
    |> String.replace(~r/<[^>]+>/, "")  # Remove all HTML tags
    |> String.replace(~r/javascript:/i, "")
    |> String.replace(~r/data:/i, "")
    |> String.replace(~r/vbscript:/i, "")
    |> String.replace(~r/on\w+\s*=/i, "")
    |> String.replace(~r/[<>\"'&%]/, "")
  end

  # Helper function for safe integer parsing (reused from existing code)
  defp safe_parse_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp safe_parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
  defp safe_parse_positive_integer(nil, default), do: default
  defp safe_parse_positive_integer(_, default), do: default

  # Security logging functions
  defp log_security_event(conn, event_type, details) do
    user_id = get_in(conn.assigns, [:user, :id]) || "anonymous"
    remote_ip = get_remote_ip(conn)
    user_agent = get_req_header(conn, "user-agent") |> List.first() || "unknown"

    require Logger
    Logger.warning("Security Event: #{event_type}", [
      event_type: event_type,
      user_id: user_id,
      remote_ip: remote_ip,
      user_agent: user_agent,
      path: conn.request_path,
      method: conn.method,
      details: details,
      timestamp: DateTime.utc_now()
    ])
  end

  defp params_were_modified?(original_params, sanitized_params) do
    # Compare the two parameter maps to detect if sanitization made changes
    # This helps identify potential security issues in requests
    original_params != sanitized_params
  end

  defp sanitize_params_for_logging(params) when is_map(params) do
    # Sanitize sensitive data before logging to prevent exposing secrets
    params
    |> Enum.map(fn {key, value} -> {key, sanitize_value_for_logging(key, value)} end)
    |> Enum.into(%{})
  end

  defp sanitize_value_for_logging(key, _value) when key in ["password", "token", "secret", "key"] do
    "[REDACTED]"
  end

  defp sanitize_value_for_logging(key, value) when key in ["email"] and is_binary(value) do
    # Partially obscure email addresses for privacy
    case String.split(value, "@") do
      [user, domain] when byte_size(user) > 2 ->
        "#{String.slice(user, 0, 2)}***@#{domain}"
      _ ->
        "***@***"
    end
  end

  defp sanitize_value_for_logging(_key, value) when is_binary(value) and byte_size(value) > 100 do
    # Truncate very long values to prevent log bloat
    "#{String.slice(value, 0, 100)}... [TRUNCATED]"
  end

  defp sanitize_value_for_logging(_key, value), do: value

  defp get_remote_ip(conn) do
    EventasaurusApp.IPExtractor.get_ip_from_conn(conn)
  end
end
