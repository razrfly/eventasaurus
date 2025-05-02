defmodule EventasaurusWeb.Live.AuthHooks do
  @moduledoc """
  LiveView hooks for authentication and user session management.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias EventasaurusApp.Auth

  @doc """
  Hook for setting current_user assign for all LiveViews.

  This should be used as an on_mount hook in LiveViews:
  ```
  on_mount {EventasaurusWeb.Live.AuthHooks, :assign_current_user}
  ```
  """
  def on_mount(:assign_current_user, _params, session, socket) do
    socket = assign_current_user(session, socket)
    {:cont, socket}
  end

  @doc """
  Hook for requiring authentication in LiveViews.

  This should be used as an on_mount hook in LiveViews that require auth.
  If the user is not authenticated, they will be redirected to the login page.
  ```
  on_mount {EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}
  ```
  """
  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_current_user(session, socket)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  @doc """
  Verifies if the user is authenticated.
  If a user is not authenticated, redirect to the sign in page.

  This should be used as an on_mount hook in LiveViews that require authentication:
  ```
  on_mount {EventasaurusWeb.Live.AuthHooks, :ensure_authenticated}
  ```
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    access_token = socket.assigns[:access_token] || session["access_token"]

    case access_token do
      token when is_binary(token) ->
        case Auth.Client.get_user(token) do
          {:ok, user_data} ->
            user = EventasaurusApp.Accounts.User.from_supabase(user_data)
            {:cont, Phoenix.Component.assign(socket, :current_user, user)}
          _ ->
            socket =
              socket
              |> Phoenix.Component.assign(current_user: nil)
              |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
              |> Phoenix.LiveView.redirect(to: "/login")
            {:halt, socket}
        end
      _ ->
        socket =
          socket
          |> Phoenix.Component.assign(current_user: nil)
          |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
          |> Phoenix.LiveView.redirect(to: "/login")
        {:halt, socket}
    end
  end

  @doc """
  Verifies if the user is NOT authenticated.
  If a user is authenticated, redirect to the dashboard page.

  This should be used as an on_mount hook in LiveViews that should only be accessible to non-authenticated users:
  ```
  on_mount {EventasaurusWeb.Live.AuthHooks, :redirect_if_authenticated}
  ```
  """
  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    access_token = socket.assigns[:access_token] || session["access_token"]

    case access_token do
      token when is_binary(token) ->
        case Auth.Client.get_user(token) do
          {:ok, _user_data} ->
            socket =
              socket
              |> Phoenix.Component.assign(current_user: nil)
              |> Phoenix.LiveView.put_flash(:error, "You must log out to access this page.")
              |> Phoenix.LiveView.redirect(to: "/dashboard")
            {:halt, socket}
          _ ->
            {:cont, socket}
        end
      _ ->
        {:cont, socket}
    end
  end

  # Internal function to assign the current user into the LiveView socket.
  defp assign_current_user(session, socket) do
    assign_new(socket, :current_user, fn ->
      access_token = socket.assigns[:access_token] || session["access_token"]

      case access_token do
        token when is_binary(token) ->
          case Auth.Client.get_user(token) do
            {:ok, user_data} -> EventasaurusApp.Accounts.User.from_supabase(user_data)
            _ -> nil
          end
        _ -> nil
      end
    end)
  end
end
