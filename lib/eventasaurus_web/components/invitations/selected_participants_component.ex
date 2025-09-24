defmodule EventasaurusWeb.Components.Invitations.SelectedParticipantsComponent do
  @moduledoc """
  Component for displaying selected users and emails with remove functionality.
  Shows avatars for users and initials for emails.
  """
  use EventasaurusWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="selected-participants-component">
      <%= if has_participants?(assigns) do %>
        <div class="mb-4">
          <h4 class="text-sm font-medium text-gray-700 mb-2">
            Selected participants (<%= total_count(assigns) %>)
          </h4>

          <%= if length(assigns[:selected_users] || []) > 0 do %>
            <div class="mb-3">
              <p class="text-xs text-gray-500 mb-2">Existing users</p>
              <div class="flex flex-wrap gap-2">
                <%= for user <- assigns[:selected_users] || [] do %>
                  <div class="inline-flex items-center gap-2 px-3 py-1.5 bg-green-50 border border-green-200 rounded-full">
                    <%= if user.avatar_url do %>
                      <img src={user.avatar_url} alt={user.name || user.username} class="w-5 h-5 rounded-full" />
                    <% else %>
                      <div class="w-5 h-5 rounded-full bg-green-300 flex items-center justify-center text-xs font-medium text-white">
                        <%= String.first(user.name || user.username || "?") |> String.upcase() %>
                      </div>
                    <% end %>
                    <span class="text-sm text-gray-700">
                      <%= user.name || user.username %>
                    </span>
                    <button
                      type="button"
                      phx-target={@myself}
                      phx-click="remove_user"
                      phx-value-user-id={user.id}
                      class="text-gray-400 hover:text-red-500 transition-colors"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if length(assigns[:selected_emails] || []) > 0 do %>
            <div>
              <p class="text-xs text-gray-500 mb-2">Email invitations</p>
              <div class="flex flex-wrap gap-2">
                <%= for email <- assigns[:selected_emails] || [] do %>
                  <div class="inline-flex items-center gap-2 px-3 py-1.5 bg-blue-50 border border-blue-200 rounded-full">
                    <div class="w-5 h-5 rounded-full bg-blue-300 flex items-center justify-center text-xs font-medium text-white">
                      <%= String.first(email) |> String.upcase() %>
                    </div>
                    <span class="text-sm text-gray-700">
                      <%= email %>
                    </span>
                    <button
                      type="button"
                      phx-target={@myself}
                      phx-click="remove_email"
                      phx-value-email={email}
                      class="text-gray-400 hover:text-red-500 transition-colors"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-6 bg-gray-50 rounded-lg">
          <p class="text-sm text-gray-500">
            No participants selected yet
          </p>
          <p class="text-xs text-gray-400 mt-1">
            Search for users or add email addresses above
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("remove_user", %{"user-id" => user_id}, socket) do
    send(self(), {:remove_user, String.to_integer(user_id)})
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_email", %{"email" => email}, socket) do
    send(self(), {:remove_email, email})
    {:noreply, socket}
  end

  # Helper functions

  defp has_participants?(assigns) do
    user_count = length(assigns[:selected_users] || [])
    email_count = length(assigns[:selected_emails] || [])
    user_count + email_count > 0
  end

  defp total_count(assigns) do
    user_count = length(assigns[:selected_users] || [])
    email_count = length(assigns[:selected_emails] || [])
    user_count + email_count
  end
end