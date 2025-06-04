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

  require Logger

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
          |> redirect(to: ~p"/auth/login")

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
end
