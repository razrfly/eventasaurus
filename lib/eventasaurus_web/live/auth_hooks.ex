defmodule EventasaurusWeb.Live.AuthHooks do
  @moduledoc """
  Authentication hooks for Phoenix LiveView.

  This module provides hooks for handling user authentication in LiveViews.
  It manages the dual user assignment pattern:

  - `@auth_user`: Raw authentication data from Clerk JWT (internal use only)
  - `@user`: Processed local database User struct (for templates and business logic)

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

  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Auth.Clerk.JWT, as: ClerkJWT
  alias EventasaurusApp.Auth.Clerk.Sync, as: ClerkSync

  require Logger

  # Environment checks for dev/test mode that work in production
  defp dev_mode?, do: Application.get_env(:eventasaurus, :environment) == :dev
  defp test_mode?, do: Application.get_env(:eventasaurus, :environment) == :test

  @doc """
  Handles different authentication mount hooks.

  Available hooks:
  - `:assign_auth_user` - Assigns authenticated user data to socket
  - `:require_authenticated_user` - Requires authentication, redirects if not found
  - `:assign_auth_user_and_theme` - Assigns user data and theme information
  """
  def on_mount(:assign_auth_user, _params, session, socket) do
    # First assign auth_user, then use the UPDATED socket for the user assignment
    socket_with_auth = assign_auth_user(socket, session)

    socket =
      assign_new(socket_with_auth, :user, fn ->
        # Use socket_with_auth.assigns, not the original socket.assigns
        case socket_with_auth.assigns[:auth_user] do
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

      auth_user ->
        # Process auth_user into a proper User struct for templates and business logic
        # Use assign (not assign_new) to ensure the value is always set correctly
        user =
          case ensure_user_struct(auth_user) do
            {:ok, user} -> user
            {:error, _} -> nil
          end

        {:cont, assign(socket, :user, user)}
    end
  end

  def on_mount(:assign_auth_user_and_theme, _params, session, socket) do
    # First assign auth_user, then use the UPDATED socket for the user assignment
    socket_with_auth = assign_auth_user(socket, session)

    socket =
      socket_with_auth
      |> assign_new(:user, fn ->
        # Use socket_with_auth.assigns, not the original socket.assigns
        case socket_with_auth.assigns[:auth_user] do
          nil ->
            nil

          auth_user ->
            case ensure_user_struct(auth_user) do
              {:ok, user} -> user
              {:error, _} -> nil
            end
        end
      end)
      |> assign(:theme, :minimal)

    {:cont, socket}
  end

  # Private function to assign auth_user from session or connect_params
  # Priority: session > connect_params (clerk_token)
  defp assign_auth_user(socket, session) do
    result =
      cond do
        # Test mode: directly load user from session (set by test helpers)
        test_mode?() && session["current_user_id"] ->
          EventasaurusApp.Repo.get(EventasaurusApp.Accounts.User, session["current_user_id"])

        # Dev mode login: directly load the user from database
        dev_mode?() && session["dev_mode_login"] == true && session["current_user_id"] ->
          case EventasaurusApp.Repo.get(EventasaurusApp.Accounts.User, session["current_user_id"]) do
            nil ->
              Logger.warning("DEV MODE: User #{session["current_user_id"]} not found - stale session")
              nil

            user ->
              user
          end

        # Production: Get user from Clerk session first
        true ->
          case get_clerk_auth_user(session) do
            nil ->
              # Session auth failed - try connect_params token (for CDN-cached pages)
              get_user_from_connect_params(socket)

            user ->
              user
          end
      end

    Phoenix.Component.assign(socket, :auth_user, result)
  end

  # Get user from Clerk JWT token passed via LiveSocket connect_params
  # This handles CDN-cached pages where Phoenix session cookie wasn't set
  # but Clerk's __session cookie is available on the client
  defp get_user_from_connect_params(socket) do
    # connect_params only available when socket is connected (not during static render)
    if connected?(socket) do
      case get_connect_params(socket) do
        %{"clerk_token" => token} when is_binary(token) and token != "" ->
          verify_and_get_user(token)

        _ ->
          nil
      end
    else
      nil
    end
  end

  # Verify Clerk JWT and get/sync the user
  defp verify_and_get_user(token) do
    case ClerkJWT.verify_token(token) do
      {:ok, claims} ->
        # Try to get existing user first (faster, no sync)
        case ClerkSync.get_user(claims) do
          {:ok, user} ->
            user

          {:error, :not_found} ->
            # User doesn't exist yet - sync will create them
            case ClerkSync.sync_user(claims) do
              {:ok, user} -> user
              {:error, _reason} -> nil
            end

          {:error, _reason} ->
            nil
        end

      {:error, reason} ->
        Logger.debug("Clerk token verification failed: #{inspect(reason)}")
        nil
    end
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

  # Helper function to ensure we have a proper User struct
  # This handles the conversion from Clerk auth data to local User struct
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}

  # Handle Clerk JWT claims (has "sub" key for Clerk user ID)
  defp ensure_user_struct(%{"sub" => _clerk_id} = clerk_claims) do
    alias EventasaurusApp.Auth.Clerk.Sync, as: ClerkSync
    ClerkSync.sync_user(clerk_claims)
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
