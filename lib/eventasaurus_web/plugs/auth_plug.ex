defmodule EventasaurusWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plugs for Phoenix controllers.

  This module provides plugs for handling Clerk authentication in controllers.
  It manages the user assignment pattern:

  - `conn.assigns.auth_user`: Clerk JWT claims (internal use only)
  - Controllers should process this into a local User struct for business logic

  ## Available Plugs

  1. `fetch_auth_user` - Loads the authenticated user from Clerk JWT and assigns to conn
  2. `require_authenticated_user` - Ensures a user is authenticated or redirects to login
  3. `redirect_if_user_is_authenticated` - Redirects authenticated users away from auth pages
  """

  import Plug.Conn
  import Phoenix.Controller

  use Phoenix.VerifiedRoutes,
    endpoint: EventasaurusWeb.Endpoint,
    router: EventasaurusWeb.Router,
    statics: EventasaurusWeb.static_paths()

  require Logger

  @doc """
  Fetches the authenticated user from Clerk JWT and assigns to `conn.assigns.auth_user`.

  Extracts JWT from `__session` cookie or Authorization header and verifies it.

  ## Usage

      plug :fetch_auth_user
  """
  def fetch_auth_user(conn, _opts) do
    # For readonly sessions (cacheable anonymous requests), treat as anonymous
    # Session is still available for reading (CSRF tokens), but we know user is anonymous
    if conn.assigns[:readonly_session] do
      assign(conn, :auth_user, nil)
    else
      # If dev auth bypass already set the user, skip everything
      # Also check session for dev_mode_login as a fallback (in case DevAuthPlug already set auth_user)
      cond do
        conn.assigns[:dev_mode_auth] ->
          # DevAuthPlug already handled this
          conn

        get_session(conn, :dev_mode_login) == true && conn.assigns[:auth_user] ->
          # DevAuthPlug set auth_user but maybe dev_mode_auth wasn't set - keep the existing auth_user
          conn

        true ->
          fetch_clerk_auth_user(conn)
      end
    end
  end

  # Clerk authentication flow
  defp fetch_clerk_auth_user(conn) do
    alias EventasaurusApp.Auth.Clerk.JWT

    case get_clerk_token(conn) do
      nil ->
        Logger.warning("[AUTH DEBUG] No Clerk token found in cookie for path: #{conn.request_path}")
        assign(conn, :auth_user, nil)

      token ->
        # Log token info (first/last 10 chars only for security)
        token_preview = "#{String.slice(token, 0, 10)}...#{String.slice(token, -10, 10)}"
        Logger.info("[AUTH DEBUG] Found Clerk token for path: #{conn.request_path}, token: #{token_preview}")

        case JWT.verify_token(token) do
          {:ok, claims} ->
            Logger.info("[AUTH DEBUG] Token verified for path: #{conn.request_path}, clerk_id: #{claims["sub"]}")

            assign(conn, :auth_user, claims)

          {:error, reason} ->
            Logger.warning("[AUTH DEBUG] Token verification FAILED for path: #{conn.request_path}, reason: #{inspect(reason)}")
            assign(conn, :auth_user, nil)
        end
    end
  end

  # Get Clerk token from cookie or Authorization header
  defp get_clerk_token(conn) do
    # Try Authorization header first (for API requests)
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        token

      _ ->
        # Fall back to __session cookie (for browser requests)
        conn = fetch_cookies(conn)
        conn.cookies["__session"]
    end
  end

  @doc """
  Processes the auth_user into a local User struct and assigns to `conn.assigns.user`.

  This plug takes the raw auth data from `:auth_user` and converts it into a
  proper User struct for use in templates and business logic.

  ## Usage

      plug :assign_user_struct
  """
  def assign_user_struct(conn, _opts) do
    case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, user} ->
        conn = assign(conn, :user, user)

        # Skip session write if session is readonly for caching
        if conn.assigns[:readonly_session] do
          conn
        else
          put_session(conn, "current_user_id", user.id)
        end

      {:error, _} ->
        assign(conn, :user, nil)
    end
  end

  @doc """
  Requires that a user is authenticated.

  If no authenticated user is found in `conn.assigns.auth_user`, redirects to login page.

  ## Usage

      plug :require_authenticated_user
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:auth_user] do
      # Clerk tokens are verified each request, no proactive refresh needed
      Logger.info("[AUTH DEBUG] require_authenticated_user PASSED for path: #{conn.request_path}")
      conn
    else
      Logger.warning("[AUTH DEBUG] require_authenticated_user FAILED for path: #{conn.request_path} - redirecting to /auth/login")
      # Use URL param for return_to (survives CDN caching which strips Set-Cookie headers)
      return_to = if conn.method == "GET", do: current_path(conn), else: nil
      login_path = build_login_path_with_return(return_to)
      Logger.info("[AUTH DEBUG] Redirecting to #{login_path}")

      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: login_path)
      |> halt()
    end
  end

  # Build login path with return_to URL parameter (survives CDN caching)
  defp build_login_path_with_return(nil), do: ~p"/auth/login"
  defp build_login_path_with_return(return_to) do
    # URL encode the return_to path to handle special characters
    encoded = URI.encode(return_to, &URI.char_unreserved?/1)
    "/auth/login?return_to=#{encoded}"
  end

  @doc """
  Requires that a user is authenticated for API requests.

  If no authenticated user is found, returns JSON error.

  ## Usage

      plug :require_authenticated_api_user
  """
  def require_authenticated_api_user(conn, _opts) do
    if conn.assigns[:auth_user] do
      # Clerk tokens were already verified in fetch_auth_user
      conn
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
  Validates user permissions for specific actions.

  This plug checks if the authenticated user has the required permissions
  for the requested action.

  ## Usage

      plug :require_permission, action: :manage_events
      plug :require_permission, action: :search_users, resource: :event
  """
  def require_permission(conn, opts) do
    action = Keyword.get(opts, :action)
    resource = Keyword.get(opts, :resource)

    case validate_user_permission(conn.assigns[:user], action, resource, conn.params) do
      :ok ->
        conn

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
  data integrity.

  ## Usage

      plug :sanitize_and_validate_input
  """
  def sanitize_and_validate_input(conn, _opts) do
    case sanitize_request_params(conn.params) do
      {:ok, sanitized_params} ->
        if params_were_modified?(conn.params, sanitized_params) do
          log_security_event(conn, "input_sanitized", %{
            original_params: sanitize_params_for_logging(conn.params),
            sanitized_params: sanitize_params_for_logging(sanitized_params)
          })
        end

        %{conn | params: sanitized_params}

      {:error, errors} ->
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
  Redirects authenticated users away from auth pages.

  With Clerk authentication, password recovery is handled by Clerk's hosted UI.
  If a `return_to` URL parameter is present, redirects there (for CDN-compatible auth flow).
  Otherwise, redirects to the dashboard.

  ## Usage

      plug :redirect_if_user_is_authenticated_except_recovery
  """
  def redirect_if_user_is_authenticated_except_recovery(conn, _opts) do
    if conn.assigns[:auth_user] do
      # Check for return_to URL param (CDN-compatible redirect after login)
      return_to = get_safe_return_to(conn)
      Logger.info("[AUTH DEBUG] redirect_if_authenticated: User IS authenticated at #{conn.request_path} - redirecting to #{return_to}")

      conn
      |> redirect(to: return_to)
      |> halt()
    else
      Logger.info("[AUTH DEBUG] redirect_if_authenticated: User NOT authenticated at #{conn.request_path} - allowing access")
      conn
    end
  end

  # Get return_to from URL params with security validation
  # Only allows internal paths (must start with /) to prevent open redirect attacks
  defp get_safe_return_to(conn) do
    case conn.query_params["return_to"] do
      nil ->
        ~p"/dashboard"

      "" ->
        ~p"/dashboard"

      return_to ->
        # Security: Only allow internal paths (starting with /)
        # Decode the URL-encoded path first
        decoded = URI.decode(return_to)

        if String.starts_with?(decoded, "/") and not String.starts_with?(decoded, "//") do
          Logger.info("[AUTH DEBUG] Using return_to from URL param: #{decoded}")
          decoded
        else
          Logger.warning("[AUTH DEBUG] Rejected unsafe return_to value: #{return_to}")
          ~p"/dashboard"
        end
    end
  end

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%EventasaurusApp.Accounts.User{} = user), do: {:ok, user}

  # Handle Clerk JWT claims (has "sub" key for Clerk user ID)
  defp ensure_user_struct(%{"sub" => _clerk_id} = clerk_claims) do
    alias EventasaurusApp.Auth.Clerk.Sync, as: ClerkSync
    ClerkSync.sync_user(clerk_claims)
  end

  defp ensure_user_struct(_), do: {:error, :invalid_user_data}

  # Enhanced permission validation with role-based access control
  defp validate_user_permission(nil, _action, _resource, _params),
    do: {:error, "User not authenticated"}

  defp validate_user_permission(user, action, resource, params) do
    case {action, resource} do
      {:search_users, _} ->
        if user.email && user.name do
          :ok
        else
          {:error, "Complete profile required for user search"}
        end

      {:manage_events, _} ->
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
    sanitized =
      value
      |> String.trim()
      |> String.replace(~r/[<>\"'&%]/, "")
      |> String.replace(~r/javascript:/i, "")
      |> String.replace(~r/data:/i, "")
      |> String.replace(~r/vbscript:/i, "")
      |> String.replace(~r/on\w+\s*=/i, "")
      |> String.replace(~r/\s+/, " ")
      |> String.slice(0, 100)

    if String.length(sanitized) >= 2 do
      {:ok, sanitized}
    else
      {:error, "Search query must be at least 2 characters"}
    end
  end

  defp sanitize_value(key, value) when key in ["page", "per_page", "event_id"] do
    case safe_parse_positive_integer(value, nil) do
      nil -> {:error, "Must be a positive integer"}
      int when int > 0 and int <= 10000 -> {:ok, int}
      _ -> {:error, "Must be a positive integer within reasonable limits"}
    end
  end

  defp sanitize_value(key, value)
       when key in ["title", "description", "name"] and is_binary(value) do
    sanitized =
      value
      |> String.trim()
      |> sanitize_html_content()
      |> String.slice(0, 255)

    {:ok, sanitized}
  end

  defp sanitize_value(key, value)
       when key in ["website_url", "callback_url", "redirect_url"] and is_binary(value) do
    if String.match?(value, ~r/^https?:\/\/[\w\-\.]+(:\d+)?(\/.*)?$/i) do
      {:ok, value}
    else
      {:error, "Must be a valid HTTP/HTTPS URL"}
    end
  end

  defp sanitize_value(key, value) when key in ["email"] and is_binary(value) do
    if String.match?(value, ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/) do
      {:ok, String.downcase(String.trim(value))}
    else
      {:error, "Must be a valid email address"}
    end
  end

  defp sanitize_value(_key, value), do: {:ok, value}

  defp sanitize_html_content(content) when is_binary(content) do
    content
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/javascript:/i, "")
    |> String.replace(~r/data:/i, "")
    |> String.replace(~r/vbscript:/i, "")
    |> String.replace(~r/on\w+\s*=/i, "")
    |> String.replace(~r/[<>\"'&%]/, "")
  end

  defp safe_parse_positive_integer(value, _default) when is_integer(value) and value > 0,
    do: value

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

    Logger.warning("Security Event: #{event_type}",
      event_type: event_type,
      user_id: user_id,
      remote_ip: remote_ip,
      user_agent: user_agent,
      path: conn.request_path,
      method: conn.method,
      details: details,
      timestamp: DateTime.utc_now()
    )
  end

  defp params_were_modified?(original_params, sanitized_params) do
    original_params != sanitized_params
  end

  defp sanitize_params_for_logging(params) when is_map(params) do
    params
    |> Enum.map(fn {key, value} -> {key, sanitize_value_for_logging(key, value)} end)
    |> Enum.into(%{})
  end

  defp sanitize_value_for_logging(key, _value)
       when key in ["password", "token", "secret", "key"] do
    "[REDACTED]"
  end

  defp sanitize_value_for_logging(key, value) when key in ["email"] and is_binary(value) do
    case String.split(value, "@") do
      [user, domain] when byte_size(user) > 2 ->
        "#{String.slice(user, 0, 2)}***@#{domain}"

      _ ->
        "***@***"
    end
  end

  defp sanitize_value_for_logging(_key, value) when is_binary(value) and byte_size(value) > 100 do
    "#{String.slice(value, 0, 100)}... [TRUNCATED]"
  end

  defp sanitize_value_for_logging(_key, value), do: value

  defp get_remote_ip(conn) do
    EventasaurusApp.IPExtractor.get_ip_from_conn(conn)
  end
end
