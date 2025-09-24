defmodule EventasaurusWeb.Components.Invitations.UserSelectorComponent do
  @moduledoc """
  Component for searching and selecting existing Eventasaurus users.
  Provides autocomplete functionality and excludes already-selected users.
  """
  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Accounts

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:searching, false)
     |> assign(:selected_user_ids, MapSet.new())}
  end

  @impl true
  def update(assigns, socket) do
    selected_ids =
      case assigns[:selected_users] do
        nil -> MapSet.new()
        users -> MapSet.new(users, & &1.id)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_user_ids, selected_ids)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="user-selector-component">
      <div class="relative">
        <label class="block text-sm font-medium text-gray-700 mb-2">
          Search for users
        </label>
        <div class="relative">
          <input
            type="text"
            name="query"
            value={@search_query}
            phx-target={@myself}
            phx-change="search_users"
            phx-debounce="300"
            placeholder="Type a name or email..."
            class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500"
          />
          <%= if @searching do %>
            <div class="absolute right-3 top-3">
              <div class="animate-spin h-4 w-4 border-2 border-green-500 rounded-full border-t-transparent"></div>
            </div>
          <% end %>
        </div>

        <%= if length(@search_results) > 0 do %>
          <div class="absolute z-10 w-full mt-1 bg-white border border-gray-200 rounded-md shadow-lg max-h-60 overflow-auto">
            <%= for user <- @search_results do %>
              <button
                type="button"
                phx-target={@myself}
                phx-click="select_user"
                phx-value-user-id={user.id}
                class="w-full px-4 py-2 text-left hover:bg-gray-50 flex items-center gap-3 border-b border-gray-100 last:border-0"
              >
                <div class="flex-shrink-0">
                  <%= if user.avatar_url do %>
                    <img src={user.avatar_url} alt={user.name || user.username} class="w-8 h-8 rounded-full" />
                  <% else %>
                    <div class="w-8 h-8 rounded-full bg-gray-300 flex items-center justify-center text-sm font-medium text-gray-600">
                      <%= String.first(user.name || user.username || "?") |> String.upcase() %>
                    </div>
                  <% end %>
                </div>
                <div class="flex-grow">
                  <div class="font-medium text-gray-900">
                    <%= user.name || user.username %>
                  </div>
                  <div class="text-sm text-gray-500">
                    <%= user.email %>
                  </div>
                </div>
                <%= if MapSet.member?(@selected_user_ids, user.id) do %>
                  <div class="text-green-600">
                    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                    </svg>
                  </div>
                <% end %>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search_users", %{"query" => query}, socket) do
    socket = assign(socket, :search_query, query)

    if String.trim(query) == "" do
      {:noreply, assign(socket, search_results: [], searching: false)}
    else
      # Perform search immediately (no debouncing in LiveComponents)
      exclude_ids = MapSet.to_list(socket.assigns.selected_user_ids)

      results =
        case Accounts.search_users(query, exclude_ids: exclude_ids, limit: 10) do
          {:ok, users} -> users
          _ -> []
        end

      {:noreply,
       socket
       |> assign(:search_results, results)
       |> assign(:searching, false)}
    end
  end

  @impl true
  def handle_event("select_user", %{"user-id" => user_id}, socket) do
    user = Enum.find(socket.assigns.search_results, &(to_string(&1.id) == user_id))

    if user do
      send(self(), {:user_selected, user})

      {:noreply,
       socket
       |> assign(:search_query, "")
       |> assign(:search_results, [])}
    else
      {:noreply, socket}
    end
  end
end