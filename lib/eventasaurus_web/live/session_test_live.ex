defmodule EventasaurusWeb.SessionTestLive do
  @moduledoc """
  A simple LiveView for testing session management functionality.

  This LiveView demonstrates:
  - Cross-tab session synchronization
  - Real-time auth state updates via PubSub
  - Session validation and refresh
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Auth
  alias EventasaurusWeb.Live.AuthHooks

  require Logger

  # Use the enhanced auth hook with session sync
  on_mount {AuthHooks, :assign_auth_user_with_session_sync}

  @impl true
  def mount(_params, _session, socket) do
    Logger.debug("SessionTestLive mounted with auth_user: #{inspect(socket.assigns[:auth_user])}")

    socket =
      socket
      |> assign(:session_info, get_session_info(socket))
      |> assign(:last_activity, DateTime.utc_now())
      |> assign(:tab_id, generate_tab_id())

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh_session", _params, socket) do
    Logger.info("Manual session refresh requested")

    # Simulate session refresh
    case socket.assigns[:auth_user] do
      %{"id" => user_id} ->
        Auth.broadcast_auth_event(user_id, :session_refreshed, %{
          user_data: socket.assigns.auth_user,
          timestamp: DateTime.utc_now()
        })

        socket =
          socket
          |> assign(:last_activity, DateTime.utc_now())
          |> put_flash(:info, "Session refreshed successfully")

        {:noreply, socket}

      _ ->
        socket = put_flash(socket, :error, "No active session to refresh")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("test_logout", _params, socket) do
    Logger.info("Test logout requested")

    case socket.assigns[:auth_user] do
      %{"id" => user_id} ->
        Auth.broadcast_auth_event(user_id, :logged_out)
        {:noreply, socket}

      _ ->
        socket = put_flash(socket, :error, "No active session to logout")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("auth_state_changed", params, socket) do
    Logger.info("Auth state changed from another tab: #{inspect(params)}")

    case params do
      %{"event" => "logout"} ->
                 socket =
           socket
           |> assign(:auth_user, nil)
           |> assign(:user, nil)
           |> put_flash(:info, "You were logged out in another tab")
           |> push_navigate(to: ~p"/auth/login")

        {:noreply, socket}

      %{"event" => "session_expired"} ->
                 socket =
           socket
           |> assign(:auth_user, nil)
           |> assign(:user, nil)
           |> put_flash(:error, "Your session expired in another tab")
           |> push_navigate(to: ~p"/auth/login")

        {:noreply, socket}

      _ ->
        socket =
          socket
          |> assign(:last_activity, DateTime.utc_now())
          |> put_flash(:info, "Session synchronized with other tabs")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:auth_event, event, metadata}, socket) do
    Logger.info("Received auth event: #{event} with metadata: #{inspect(metadata)}")
    AuthHooks.handle_auth_event(event, metadata, socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6" phx-hook="AuthSyncHook" id="session-test">
      <div class="bg-white shadow-lg rounded-lg p-6">
        <h1 class="text-2xl font-bold text-gray-900 mb-6">Session Management Test</h1>

        <!-- Session Status -->
        <div class="mb-6 p-4 bg-gray-50 rounded-lg">
          <h2 class="text-lg font-semibold text-gray-800 mb-3">Session Status</h2>

          <%= if @auth_user do %>
            <div class="space-y-2">
              <p class="text-green-600 font-medium">✅ Authenticated</p>
              <p class="text-sm text-gray-600">User ID: <%= @auth_user["id"] %></p>
              <p class="text-sm text-gray-600">Email: <%= @auth_user["email"] %></p>
              <p class="text-sm text-gray-600">Tab ID: <%= @tab_id %></p>
              <p class="text-sm text-gray-600">Last Activity: <%= Calendar.strftime(@last_activity, "%H:%M:%S") %></p>
            </div>
          <% else %>
            <p class="text-red-600 font-medium">❌ Not authenticated</p>
          <% end %>
        </div>

        <!-- Session Info -->
        <div class="mb-6 p-4 bg-blue-50 rounded-lg">
          <h2 class="text-lg font-semibold text-gray-800 mb-3">Session Information</h2>
          <pre class="text-xs text-gray-600 overflow-auto"><%= inspect(@session_info, pretty: true) %></pre>
        </div>

        <!-- Test Actions -->
        <div class="space-y-4">
          <h2 class="text-lg font-semibold text-gray-800">Test Actions</h2>

          <div class="flex flex-wrap gap-3">
            <button
              phx-click="refresh_session"
              class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
            >
              Refresh Session
            </button>

            <button
              phx-click="test_logout"
              class="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 transition-colors"
            >
              Test Logout Broadcast
            </button>

            <a
              href="/auth/logout"
              class="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 transition-colors"
            >
              Real Logout
            </a>
          </div>
        </div>

        <!-- Instructions -->
        <div class="mt-8 p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
          <h3 class="text-md font-semibold text-yellow-800 mb-2">Testing Instructions</h3>
          <ul class="text-sm text-yellow-700 space-y-1">
            <li>• Open this page in multiple tabs to test cross-tab synchronization</li>
            <li>• Click "Test Logout Broadcast" to simulate logout in one tab</li>
            <li>• Click "Refresh Session" to test session refresh broadcasting</li>
            <li>• Watch the browser console for detailed logging</li>
            <li>• Check localStorage for 'auth_state_change' entries</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp get_session_info(socket) do
    %{
      auth_user_present: not is_nil(socket.assigns[:auth_user]),
      user_present: not is_nil(socket.assigns[:user]),
      session_sync_enabled: socket.assigns[:session_sync_enabled] || false,
      flash_messages: socket.assigns.flash
    }
  end

  defp generate_tab_id do
    "tab_" <>
    (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)) <>
    "_" <> Integer.to_string(System.system_time(:millisecond))
  end
end
