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

  This should be used as an on_mount hook in LiveViews that require auth:
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
  Internal function to assign the current user into the LiveView socket.
  """
  defp assign_current_user(session, socket) do
    assign_new(socket, :current_user, fn ->
      case session do
        %{"access_token" => token} ->
          case Auth.Client.get_user(token) do
            {:ok, user} -> user
            _ -> nil
          end
        _ -> nil
      end
    end)
  end
end
