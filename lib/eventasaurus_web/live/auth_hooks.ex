defmodule EventasaurusWeb.Live.AuthHooks do
  @moduledoc """
  Authentication hooks for Phoenix LiveView.

  This module provides hooks for handling user authentication in LiveViews.
  It manages the dual user assignment pattern:

  - `@auth_user`: Raw authentication data from Supabase (internal use only)
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

  alias EventasaurusApp.Auth
  alias EventasaurusApp.Accounts
  alias Phoenix.PubSub

  require Logger

  @doc """
  Handles different authentication mount hooks.

  Available hooks:
  - `:assign_auth_user` - Assigns authenticated user data to socket
  - `:require_authenticated_user` - Requires authentication, redirects if not found
  - `:assign_auth_user_and_theme` - Assigns user data and theme information
  - `:assign_auth_user_with_session_sync` - Assigns user data and sets up session synchronization
  """
  def on_mount(:assign_auth_user, _params, session, socket) do
    socket =
      socket
      |> assign_auth_user(session)
      |> assign_new(:user, fn ->
        case socket.assigns[:auth_user] do
          nil -> nil
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
          |> push_navigate(to: ~p"/auth/login")

        {:halt, socket}

      _auth_user ->
        # Also assign the processed user for convenience
        socket = assign_new(socket, :user, fn ->
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
          nil -> nil
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

  def on_mount(:assign_auth_user_with_session_sync, _params, session, socket) do
    socket =
      socket
      |> assign_auth_user_with_validation(session)
      |> assign_new(:user, fn ->
        case socket.assigns[:auth_user] do
          nil -> nil
          auth_user ->
            case ensure_user_struct(auth_user) do
              {:ok, user} ->
                # Subscribe to auth events for this user
                setup_auth_subscription(user.id)
                user
              {:error, reason} ->
                Logger.warning("Failed to ensure user struct: #{inspect(reason)}")
                nil
            end
        end
      end)
      |> assign(:session_sync_enabled, true)

    {:cont, socket}
  end

  # Private function to assign auth_user from session
  defp assign_auth_user(socket, session) do
    assign_new(socket, :auth_user, fn ->
      # Get the token from the session
      token = session["access_token"]

      if token do
        # Use the AuthHelper for all tokens (both test and real)
        # The AuthHelper will delegate to TestClient in test environment
        case Auth.AuthHelper.get_current_user(token) do
          {:ok, user} -> user
          _ -> nil
        end
      else
        nil
      end
    end)
  end

  # Enhanced version with session validation and error handling
  defp assign_auth_user_with_validation(socket, session) do
    assign_new(socket, :auth_user, fn ->
      token = session["access_token"]
      refresh_token = session["refresh_token"]

      cond do
        is_nil(token) ->
          Logger.debug("No access token found in session")
          nil

        is_valid_token?(token) ->
          case Auth.AuthHelper.get_current_user(token) do
            {:ok, user} ->
              Logger.debug("Successfully validated session for user: #{inspect(user["email"])}")
              user
            {:error, reason} ->
              Logger.warning("Failed to get current user: #{inspect(reason)}")
              attempt_token_refresh(refresh_token)
          end

        true ->
          Logger.debug("Token appears invalid, attempting refresh")
          attempt_token_refresh(refresh_token)
      end
    end)
  end

  # Set up PubSub subscription for auth events
  defp setup_auth_subscription(user_id) do
    topic = "user_auth:#{user_id}"
    PubSub.subscribe(EventasaurusApp.PubSub, topic)
    Logger.debug("Subscribed to auth events for user: #{user_id}")
  end

  # Basic token validation (can be enhanced)
  defp is_valid_token?(token) when is_binary(token) do
    # Basic checks - token should be a valid JWT format
    case String.split(token, ".") do
      [_header, _payload, _signature] -> true
      _ -> false
    end
  end
  defp is_valid_token?(_), do: false

  # Attempt to refresh the session token
  defp attempt_token_refresh(nil) do
    Logger.debug("No refresh token available")
    nil
  end
  defp attempt_token_refresh(refresh_token) do
    case Auth.refresh_session(refresh_token) do
      {:ok, %{"access_token" => new_token}} ->
        Logger.debug("Successfully refreshed session token")
        case Auth.AuthHelper.get_current_user(new_token) do
          {:ok, user} -> user
          {:error, reason} ->
            Logger.warning("Failed to get user with refreshed token: #{inspect(reason)}")
            nil
        end
      {:error, reason} ->
        Logger.warning("Failed to refresh session: #{inspect(reason)}")
        nil
    end
  end

  # Helper function to ensure we have a proper User struct
  # This handles the conversion from Supabase auth data to local User struct
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}

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

  @doc """
  Handle authentication events from PubSub.

  This function should be called from LiveView modules that use auth hooks.
  Add this to your LiveView:

      def handle_info({:auth_event, event, metadata}, socket) do
        EventasaurusWeb.Live.AuthHooks.handle_auth_event(event, metadata, socket)
      end
  """
  def handle_auth_event(:logged_out, _metadata, socket) do
    Logger.info("User logged out in another tab, redirecting")

    socket =
      socket
      |> assign(:auth_user, nil)
      |> assign(:user, nil)
      |> put_flash(:info, "You have been logged out")
      |> push_event("auth_updated", %{event: "logout", timestamp: System.system_time(:millisecond)})
      |> push_navigate(to: ~p"/auth/login")

    {:noreply, socket}
  end

  def handle_auth_event(:session_expired, _metadata, socket) do
    Logger.info("Session expired, redirecting to login")

    socket =
      socket
      |> assign(:auth_user, nil)
      |> assign(:user, nil)
      |> put_flash(:error, "Your session has expired. Please log in again.")
      |> push_event("auth_updated", %{event: "session_expired", timestamp: System.system_time(:millisecond)})
      |> push_navigate(to: ~p"/auth/login")

    {:noreply, socket}
  end

  def handle_auth_event(:session_refreshed, metadata, socket) do
    Logger.info("Session refreshed")

    # Update the auth_user if new user data is provided
    socket = case Map.get(metadata, :user_data) do
      nil -> socket
      user_data -> assign(socket, :auth_user, user_data)
    end

    socket =
      socket
      |> push_event("auth_updated", %{event: "session_refreshed", timestamp: System.system_time(:millisecond)})

    {:noreply, socket}
  end

  def handle_auth_event(:logged_in, metadata, socket) do
    Logger.info("User logged in")

    # Update auth state if user data is provided
    socket = case Map.get(metadata, :user_data) do
      nil -> socket
      user_data ->
        socket
        |> assign(:auth_user, user_data)
        |> assign_new(:user, fn ->
          case ensure_user_struct(user_data) do
            {:ok, user} -> user
            {:error, _} -> nil
          end
        end)
    end

    socket =
      socket
      |> push_event("auth_updated", %{event: "logged_in", timestamp: System.system_time(:millisecond)})

    {:noreply, socket}
  end

  def handle_auth_event(event, metadata, socket) do
    Logger.debug("Unhandled auth event: #{inspect(event)} with metadata: #{inspect(metadata)}")
    {:noreply, socket}
  end
end
