defmodule EventasaurusWeb.Live.AuthHooks do
  @moduledoc """
  Authentication hooks for LiveView.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  require Logger


  @doc """
  Hooks for LiveView authentication.

  Two hooks are provided:
  - `:assign_current_user`: Assigns the current user but doesn't enforce authentication
  - `:require_authenticated_user`: Requires authentication or redirects to login page

  Usage examples:
  ```
  on_mount {EventasaurusWeb.Live.AuthHooks, :assign_current_user}
  # or
  on_mount {EventasaurusWeb.Live.AuthHooks, :require_authenticated_user}
  ```
  """
  def on_mount(:assign_current_user, _params, session, socket) do
    Logger.debug("AuthHooks.on_mount(:assign_current_user) called with session: #{inspect(session)}")
    {:cont, assign_current_user(session, socket)}
  end

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = assign_current_user(session, socket)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect(to: "/login")

      {:halt, socket}
    end
  end

  def on_mount(:assign_current_user_and_theme, _params, session, socket) do
    socket = assign_current_user(session, socket)
    socket = assign_theme_from_event(session, socket)
    {:cont, socket}
  end

  # Internal function to assign the current user into the LiveView socket.
  defp assign_current_user(session, socket) do
    assign_new(socket, :current_user, fn ->
      Logger.debug("AuthHooks.assign_current_user called with session: #{inspect(session)}")

      case session do
        %{"access_token" => token} ->
          auth_client = Application.get_env(:eventasaurus, :auth_client, EventasaurusApp.Auth.Client)
          Logger.debug("Using auth client: #{inspect(auth_client)} for token: #{inspect(token)}")

          case auth_client.get_user(token) do
            {:ok, user} ->
              Logger.debug("Auth client returned user: #{inspect(user)}")
              user
            error ->
              Logger.debug("Auth client returned error: #{inspect(error)}")
              nil
          end
        _ ->
          Logger.debug("No access_token in session")
          nil
      end
    end)
  end


  # Internal function to assign theme information from event slug
  defp assign_theme_from_event(session, socket) do
    case session do
      %{"live_socket_path" => path} ->
        # Extract slug from path like "/event-slug"
        slug = String.trim_leading(path, "/")

        case EventasaurusApp.Events.get_event_by_slug(slug) do
          nil ->
            socket

          event ->
            assign(socket, :event_theme, %{
              primary_color: event.primary_color || "#3B82F6",
              secondary_color: event.secondary_color || "#1E40AF",
              accent_color: event.accent_color || "#F59E0B"
            })
        end

      _ ->
        socket
    end
  end


end
