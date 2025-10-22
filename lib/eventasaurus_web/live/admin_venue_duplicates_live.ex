defmodule EventasaurusWeb.AdminVenueDuplicatesLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Venues

  @impl true
  def mount(_params, _session, socket) do
    # Note: Authentication is handled by the router pipeline
    # Dev: no auth required (dev admin scope)
    # Production: admin auth required (oban_admin pipeline)
    duplicate_groups = Venues.find_duplicate_groups()

    {:ok,
     socket
     |> assign(:duplicate_groups, duplicate_groups)
     |> assign(:selected_group, nil)
     |> assign(:selected_primary, nil)
     |> assign(:merge_in_progress, false)
     |> assign(:page_title, "Manage Duplicate Venues")}
  end

  @impl true
  def handle_event("select_group", %{"group_index" => index_str}, socket) do
    case Integer.parse(index_str) do
      {index, ""} ->
        group = Enum.at(socket.assigns.duplicate_groups, index)
        primary_venue = List.first(group.venues)

        {:noreply,
         socket
         |> assign(:selected_group, group)
         |> assign(:selected_primary, primary_venue.id)}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid group selection")}
    end
  end

  @impl true
  def handle_event("select_primary", %{"venue_id" => venue_id_str}, socket) do
    case Integer.parse(venue_id_str) do
      {venue_id, ""} ->
        {:noreply, assign(socket, :selected_primary, venue_id)}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid venue selection")}
    end
  end

  @impl true
  def handle_event("merge_venues", _params, socket) do
    group = socket.assigns.selected_group
    primary_id = socket.assigns.selected_primary

    if group && primary_id do
      duplicate_ids =
        group.venues
        |> Enum.reject(&(&1.id == primary_id))
        |> Enum.map(& &1.id)

      socket = assign(socket, :merge_in_progress, true)

      case Venues.merge_venues(primary_id, duplicate_ids) do
        {:ok, _merged_venue} ->
          # Refresh duplicate groups
          updated_groups = Venues.find_duplicate_groups()

          {:noreply,
           socket
           |> assign(:duplicate_groups, updated_groups)
           |> assign(:selected_group, nil)
           |> assign(:selected_primary, nil)
           |> assign(:merge_in_progress, false)
           |> put_flash(:info, "Successfully merged #{length(duplicate_ids)} duplicate venues")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:merge_in_progress, false)
           |> put_flash(:error, "Failed to merge venues: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select venues to merge")}
    end
  end

  @impl true
  def handle_event("cancel_merge", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_group, nil)
     |> assign(:selected_primary, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          Manage Duplicate Venues
        </h1>
        <p class="mt-2 text-gray-600 dark:text-gray-400">
          Found <%= length(@duplicate_groups) %> groups of duplicate venues
        </p>
      </div>

      <%= if @selected_group do %>
        <!-- Merge Confirmation Panel -->
        <div class="mb-8 bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-700 rounded-lg p-6">
          <h2 class="text-xl font-bold text-yellow-900 dark:text-yellow-100 mb-4">
            Confirm Merge
          </h2>

          <div class="space-y-4">
            <div>
              <h3 class="font-semibold text-gray-900 dark:text-white mb-2">
                Select Primary Venue (to keep):
              </h3>
              <div class="space-y-2">
                <%= for venue <- @selected_group.venues do %>
                  <label class={"flex items-start gap-3 p-3 border rounded cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 #{if @selected_primary == venue.id, do: "bg-blue-50 dark:bg-blue-900/20 border-blue-500"}"}>
                    <input
                      type="radio"
                      name="primary_venue"
                      value={venue.id}
                      checked={@selected_primary == venue.id}
                      phx-click="select_primary"
                      phx-value-venue_id={venue.id}
                      class="mt-1"
                    />
                    <div class="flex-1">
                      <div class="font-medium text-gray-900 dark:text-white">
                        ID: <%= venue.id %> - <%= venue.name %>
                      </div>
                      <div class="text-sm text-gray-600 dark:text-gray-400">
                        <%= venue.address %>
                      </div>
                      <div class="text-xs text-gray-500 dark:text-gray-500 mt-1">
                        Provider IDs: <%= map_size(venue.provider_ids || %{}) %> |
                        Images: <%= length(venue.venue_images || []) %>
                      </div>
                    </div>
                  </label>
                <% end %>
              </div>
            </div>

            <div class="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded p-4">
              <h4 class="font-semibold text-gray-900 dark:text-white mb-2">Merge Details:</h4>
              <ul class="text-sm text-gray-600 dark:text-gray-400 space-y-1">
                <li>• <%= length(@selected_group.venues) - 1 %> duplicate venues will be deleted</li>
                <li>• All events and groups will be reassigned to primary venue</li>
                <li>• Provider IDs will be merged (no duplicates)</li>
                <li>• Venue images will be combined</li>
                <li>• This action cannot be undone</li>
              </ul>
            </div>

            <div class="flex gap-3">
              <button
                phx-click="merge_venues"
                disabled={@merge_in_progress || is_nil(@selected_primary)}
                class="px-6 py-2 bg-red-600 text-white rounded hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <%= if @merge_in_progress, do: "Merging...", else: "Confirm Merge" %>
              </button>
              <button
                phx-click="cancel_merge"
                disabled={@merge_in_progress}
                class="px-6 py-2 bg-gray-300 dark:bg-gray-700 text-gray-900 dark:text-white rounded hover:bg-gray-400 dark:hover:bg-gray-600"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Duplicate Groups List -->
      <%= if length(@duplicate_groups) == 0 do %>
        <div class="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-700 rounded-lg p-6 text-center">
          <svg
            class="mx-auto h-12 w-12 text-green-600 dark:text-green-400"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M5 13l4 4L19 7"
            />
          </svg>
          <h3 class="mt-4 text-lg font-semibold text-green-900 dark:text-green-100">
            No Duplicates Found
          </h3>
          <p class="mt-2 text-green-700 dark:text-green-300">
            All venues are unique based on current detection thresholds.
          </p>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for {group, index} <- Enum.with_index(@duplicate_groups) do %>
            <div class="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-6 shadow-sm">
              <div class="flex items-start justify-between mb-4">
                <div>
                  <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
                    Duplicate Group #<%= index + 1 %>
                  </h3>
                  <p class="text-sm text-gray-600 dark:text-gray-400">
                    <%= length(group.venues) %> venues in this group
                  </p>
                </div>
                <button
                  phx-click="select_group"
                  phx-value-group_index={index}
                  disabled={!is_nil(@selected_group)}
                  class="px-4 py-2 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Merge This Group
                </button>
              </div>

              <div class="space-y-3">
                <%= for venue <- group.venues do %>
                  <div class="border border-gray-200 dark:border-gray-700 rounded p-4 hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <div class="flex items-start justify-between">
                      <div class="flex-1">
                        <div class="font-medium text-gray-900 dark:text-white">
                          ID: <%= venue.id %> - <%= venue.name %>
                        </div>
                        <div class="text-sm text-gray-600 dark:text-gray-400 mt-1">
                          <%= venue.address %>
                        </div>
                        <div class="text-sm text-gray-500 dark:text-gray-500 mt-2">
                          Coords: <%= Float.round(venue.latitude, 6) %>, <%= Float.round(
                            venue.longitude,
                            6
                          ) %>
                        </div>
                        <div class="text-xs text-gray-500 dark:text-gray-500 mt-1">
                          Provider IDs: <%= map_size(venue.provider_ids || %{}) %> |
                          Images: <%= length(venue.venue_images || []) %> |
                          Slug: <%= venue.slug %>
                        </div>
                      </div>
                    </div>

                    <!-- Show distances to other venues in group -->
                    <div class="mt-3 pt-3 border-t border-gray-200 dark:border-gray-700">
                      <div class="text-xs text-gray-600 dark:text-gray-400">
                        <span class="font-semibold">Distances to others:</span>
                        <%= for other <- group.venues, other.id != venue.id do %>
                          <% distance = Map.get(
                            group.distances,
                            if(venue.id < other.id,
                              do: {venue.id, other.id},
                              else: {other.id, venue.id}
                            )
                          ) %>
                          <% similarity = Map.get(
                            group.similarities,
                            if(venue.id < other.id,
                              do: {venue.id, other.id},
                              else: {other.id, venue.id}
                            )
                          ) %>
                          <span class="inline-block mr-3">
                            ID <%= other.id %>: <%= if distance,
                              do: "#{Float.round(distance, 1)}m",
                              else: "N/A" %>, <%= if similarity,
                              do: "#{Float.round(similarity * 100, 0)}%",
                              else: "N/A" %> similar
                          </span>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
