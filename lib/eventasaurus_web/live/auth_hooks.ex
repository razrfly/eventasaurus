defmodule EventasaurusWeb.Live.AuthHooks do
  @moduledoc """
  Authentication hooks for Phoenix LiveView.

  This module provides hooks for handling user authentication in LiveViews.
  It manages the dual user assignment pattern:

  - `@auth_user`: Raw authentication data from Supabase or Clerk (internal use only)
  - `@user`: Processed local database User struct (for templates and business logic)

  ## Clerk vs Supabase

  When Clerk is enabled, authentication is handled via JWT tokens in the `__session`
  cookie, verified and processed by `ClerkAuthPlug`. The session will contain
  `clerk_user_id` instead of `access_token`.

  ## Usage

  Add to your LiveView:

      on_mount {EventasaurusWeb.Live.AuthHooks, :assign_auth_user}

  Or for authenticated routes:

      on_mount {EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}
  """

  import Phoenix.Component
  import Phoenix.LiveView

  use Phoenix.VerifiedRoutes,
    endpoint: EventasaurusWeb.Endpoint,
    router: EventasaurusWeb.Router,
    statics: EventasaurusWeb.static_paths()

  alias EventasaurusApp.Auth
  alias EventasaurusApp.Auth.AuthProvider
  alias EventasaurusApp.Auth.Client
  alias EventasaurusApp.Accounts

  require Logger

  # Compile-time check for dev mode that works in production
  defp dev_mode?, do: Application.get_env(:eventasaurus, :environment) == :dev

  @doc """
  Handles different authentication mount hooks.

  Available hooks:
  - `:assign_auth_user` - Assigns authenticated user data to socket
  - `:require_authenticated_user` - Requires authentication, redirects if not found
  - `:assign_auth_user_and_theme` - Assigns user data and theme information
  """
  def on_mount(:assign_auth_user, _params, session, socket) do
    socket =
      socket
      |> assign_auth_user(session)
      |> assign_new(:user, fn ->
        case socket.assigns[:auth_user] do
          nil ->
            nil

          auth_user ->
            case ensure_user_struct(auth_user) do
              {:ok, user} -> user
              {:error, _} -> nil
            end
        end
      end)

    {:cont, socket}
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_auth_user(socket, session)

    case socket.assigns[:auth_user] do
      nil ->
        socket =
          socket
          |> maybe_put_flash(:error, "You must log in to access this page.")
          |> redirect(to: ~p"/auth/login")

        {:halt, socket}

      _auth_user ->
        # Also assign the processed user for convenience
        socket =
          assign_new(socket, :user, fn ->
            case ensure_user_struct(socket.assigns.auth_user) do
              {:ok, user} -> user
              {:error, _} -> nil
            end
          end)

        {:cont, socket}
    end
  end

  def on_mount(:assign_auth_user_and_theme, _params, session, socket) do
    socket =
      socket
      |> assign_auth_user(session)
      |> assign_new(:user, fn ->
        case socket.assigns[:auth_user] do
          nil ->
            nil

          auth_user ->
            case ensure_user_struct(auth_user) do
              {:ok, user} -> user
              {:error, _} -> nil
            end
        end
      end)
      |> assign(:theme, "light")

    {:cont, socket}
  end

  # Private function to assign auth_user from session
  defp assign_auth_user(socket, session) do
    assign_new(socket, :auth_user, fn ->
      # Check for dev mode login FIRST (dev only)
      if dev_mode?() && session["dev_mode_login"] == true && session["current_user_id"] do
        # Dev mode: directly load the user from database
        user_id = session["current_user_id"]

        case EventasaurusApp.Repo.get(EventasaurusApp.Accounts.User, user_id) do
          nil -> nil
          # Return the User struct directly for dev mode
          user -> user
        end
      else
        # Route to appropriate auth provider
        if AuthProvider.clerk_enabled?() do
          get_clerk_auth_user(session)
        else
          get_supabase_auth_user(session)
        end
      end
    end)
  end

  # Get auth user from Clerk session
  # For Clerk, the plug stores the user in the session after sync
  defp get_clerk_auth_user(session) do
    # The ClerkAuthPlug syncs the user and stores the user_id in session
    # We also check for a direct user_id from conn.assigns that might be passed through
    cond do
      # If we have a current_user_id from Clerk sync, load the user
      user_id = session["current_user_id"] ->
        case Accounts.get_user(user_id) do
          nil -> nil
          user -> user
        end

      # Fallback: check for Clerk claims in session (shouldn't happen in normal flow)
      _clerk_claims = session["clerk_user_claims"] ->
        # This would need ClerkSync, but normally the plug handles this
        nil

      true ->
        nil
    end
  end

  # Get auth user from Supabase session
  defp get_supabase_auth_user(session) do
    # Normal production authentication flow
    # Get the token from the session
    token = session["access_token"]
    refresh_token = session["refresh_token"]
    token_expires_at = session["token_expires_at"]

    if token do
      # Check if we need to refresh the token
      if refresh_token && token_expires_at && should_refresh_token?(token_expires_at) do
        case Client.refresh_token(refresh_token) do
          {:ok, auth_data} ->
            # Token refreshed successfully, extract and use the new token
            new_access_token = get_token_value(auth_data, "access_token")

            if new_access_token do
              # Use the NEW token to get user data
              Logger.debug("Token refreshed successfully in LiveView, using new token")
              get_user_with_token(new_access_token)
            else
              # Couldn't extract new token, fall back to old token
              Logger.warning("Failed to extract new access token from refresh response")
              get_user_with_token(token)
            end

          {:error, reason} ->
            # Refresh failed, token is likely expired or invalid
            Logger.warning("Token refresh failed in LiveView: #{inspect(reason)}")
            # Return nil to treat user as unauthenticated
            # The next HTTP request will clear the session properly
            nil
        end
      else
        # Token not near expiry or no refresh token
        get_user_with_token(token)
      end
    else
      nil
    end
  end

  defp get_user_with_token(token) do
    # Use the AuthHelper for all tokens (both test and real)
    # The AuthHelper will delegate to TestClient in test environment
    case Auth.AuthHelper.get_current_user(token) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp should_refresh_token?(expires_at_iso) when is_binary(expires_at_iso) do
    case DateTime.from_iso8601(expires_at_iso) do
      {:ok, expires_at, _} ->
        # Refresh if token expires in next 10 minutes
        refresh_threshold = DateTime.utc_now() |> DateTime.add(600, :second)
        DateTime.compare(refresh_threshold, expires_at) == :gt

      _ ->
        # If we can't parse the expiry, don't try to refresh
        false
    end
  end

  defp should_refresh_token?(_), do: false

  # Helper to extract token value from various response formats
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
  # This handles the conversion from Supabase or Clerk auth data to local User struct
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}

  # Handle Clerk JWT claims (has "sub" key for Clerk user ID)
  defp ensure_user_struct(%{"sub" => _clerk_id} = clerk_claims) do
    alias EventasaurusApp.Auth.Clerk.Sync, as: ClerkSync
    ClerkSync.sync_user(clerk_claims)
  end

  # Handle Supabase auth data (has "id" key for Supabase user ID)
  defp ensure_user_struct(%{"id" => supabase_id, "email" => email} = auth_data) do
    name = Map.get(auth_data, "user_metadata", %{}) |> Map.get("name", "")

    case Accounts.get_user_by_supabase_id(supabase_id) do
      nil ->
        # Create new user if doesn't exist
        case Accounts.create_user(%{
               supabase_id: supabase_id,
               email: email,
               name: name
             }) do
          {:ok, user} -> {:ok, user}
          {:error, _} -> {:error, :user_creation_failed}
        end

      user ->
        {:ok, user}
    end
  end

  defp ensure_user_struct(_), do: {:error, :invalid_user_data}

  # Helper function to only set flash if it doesn't already exist
  defp maybe_put_flash(socket, key, message) do
    case socket.assigns.flash[key] do
      nil -> put_flash(socket, key, message)
      _existing -> socket
    end
  end
end
