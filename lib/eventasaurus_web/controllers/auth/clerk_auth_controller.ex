defmodule EventasaurusWeb.Auth.ClerkAuthController do
  @moduledoc """
  Controller for Clerk-based authentication routes.

  Clerk handles authentication primarily through its frontend components,
  so this controller is simpler than the Supabase equivalent. It mainly:
  - Renders pages with Clerk components
  - Handles post-authentication redirects
  - Manages logout
  """
  use EventasaurusWeb, :controller
  require Logger

  alias EventasaurusApp.Auth.AuthProvider

  plug :check_clerk_enabled

  @doc """
  Show the Clerk sign-in page.
  Uses Clerk's pre-built SignIn component.
  """
  def login(conn, params) do
    # Get return_to from URL params (CDN-safe, doesn't rely on session)
    # Validate it's a safe internal URL before passing to template
    return_to = get_safe_return_to(params["return_to"])

    conn
    |> assign(:return_to, return_to)
    |> render(:clerk_login)
  end

  # Validate return_to is a safe internal URL (prevents open redirect attacks)
  defp get_safe_return_to(nil), do: nil
  defp get_safe_return_to(""), do: nil
  defp get_safe_return_to(url) when is_binary(url) do
    if valid_internal_url?(url), do: url, else: nil
  end
  defp get_safe_return_to(_), do: nil

  @doc """
  Show the Clerk sign-up page.
  Uses Clerk's pre-built SignUp component.
  """
  def register(conn, params) do
    # Store return URL if provided
    conn = maybe_store_return_to(conn, params["return_to"])

    # Handle event-based signup (Phase I implementation - INVITE ONLY)
    {conn, event} =
      case params["event_id"] do
        nil ->
          # For Clerk, we allow direct signup (can be restricted in Clerk dashboard)
          {conn, nil}

        event_id when is_binary(event_id) ->
          case Integer.parse(event_id) do
            {int_id, ""} ->
              case EventasaurusApp.Events.get_event(int_id) do
                nil ->
                  Logger.warning("Signup attempted for non-existent event: #{event_id}")
                  {put_flash(conn, :error, "Invalid event invitation link."), nil}

                event ->
                  conn = put_session(conn, :signup_event_id, event.id)
                  {conn, event}
              end

            _ ->
              Logger.warning(
                "Signup attempted with invalid event_id format: #{inspect(event_id)}"
              )

              {put_flash(conn, :error, "Invalid event invitation link."), nil}
          end

        _ ->
          {conn, nil}
      end

    conn
    |> assign(:event, event)
    |> render(:clerk_register)
  end

  @doc """
  Handle Clerk logout.
  Clear server session and Clerk's cookies.
  """
  def logout(conn, _params) do
    # Cookie deletion requires matching attributes from when they were set
    # Clerk sets cookies with secure: true in production
    cookie_opts = [
      path: "/",
      http_only: true,
      secure: Application.get_env(:eventasaurus, :environment) == :prod,
      same_site: "Lax"
    ]

    conn
    |> configure_session(drop: true)
    |> delete_resp_cookie("__session", cookie_opts)
    |> delete_resp_cookie("__client_uat", cookie_opts)
    |> put_flash(:info, "You have been logged out")
    |> redirect(to: ~p"/")
  end

  @doc """
  Handle post-authentication callback from Clerk.
  This is called after a user successfully signs in/up with Clerk.
  """
  def callback(conn, params) do
    Logger.debug("Clerk auth callback received: #{inspect(Map.keys(params))}")

    # Get return_to from URL params first (CDN-safe), then fallback to session
    # URL params are preferred because CDN caching can strip Set-Cookie headers
    return_to = get_safe_return_to(params["return_to"]) || get_session(conn, :user_return_to)

    # Check for event signup context
    event_id = get_session(conn, :signup_event_id)

    # Clear session data
    conn =
      conn
      |> delete_session(:user_return_to)
      |> delete_session(:signup_event_id)

    cond do
      event_id ->
        # User signed up via event - redirect to event page
        case EventasaurusApp.Events.get_event(event_id) do
          nil ->
            redirect(conn, to: return_to || ~p"/dashboard")

          event ->
            conn
            |> put_flash(:info, "Account created successfully! Welcome to the event.")
            |> redirect(to: ~p"/#{event.slug}")
        end

      return_to ->
        redirect(conn, to: return_to)

      true ->
        redirect(conn, to: ~p"/dashboard")
    end
  end

  @doc """
  Clerk user profile page.
  Uses Clerk's pre-built UserProfile component.
  """
  def profile(conn, _params) do
    render(conn, :clerk_profile)
  end

  # Private functions

  defp check_clerk_enabled(conn, _opts) do
    if AuthProvider.clerk_enabled?() do
      conn
    else
      conn
      |> put_flash(:error, "Clerk authentication is not enabled.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  defp maybe_store_return_to(conn, nil), do: conn

  defp maybe_store_return_to(conn, return_to) when is_binary(return_to) do
    if valid_internal_url?(return_to) do
      put_session(conn, :user_return_to, return_to)
    else
      Logger.warning("Invalid return URL rejected: #{return_to}")
      conn
    end
  end

  defp maybe_store_return_to(conn, _), do: conn

  defp valid_internal_url?(url) when is_binary(url) do
    if String.starts_with?(url, "/") do
      not String.contains?(url, "//")
    else
      case URI.parse(url) do
        %URI{host: nil} ->
          String.starts_with?(url, "/")

        %URI{host: host, scheme: scheme} when scheme in ["http", "https"] ->
          app_host = EventasaurusWeb.Endpoint.host()
          host == app_host || (host == "localhost" && app_host == "localhost")

        _ ->
          false
      end
    end
  rescue
    _ -> false
  end

  defp valid_internal_url?(_), do: false
end
