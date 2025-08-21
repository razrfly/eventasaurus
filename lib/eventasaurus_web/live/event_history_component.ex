defmodule EventasaurusWeb.EventHistoryComponent do
  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventActivity

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_activity_creation, false)
     |> assign(:editing_activity, nil)
     |> assign(:activity_filter, "all")
     |> assign(:activity_sort, "newest")
     |> assign(:open_activity_menu, nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> load_activities()
      |> calculate_stats()

    {:ok, socket}
  end

  defp load_activities(socket) do
    activities = Events.list_event_activities(socket.assigns.event)
    assign(socket, :activities, activities)
  end

  defp calculate_stats(socket) do
    activities = socket.assigns.activities || []
    
    stats = %{
      total_activities: length(activities),
      movies_watched: Enum.count(activities, &(&1.activity_type == "movie_watched")),
      tv_shows_watched: Enum.count(activities, &(&1.activity_type == "tv_watched")),
      places_visited: Enum.count(activities, &(&1.activity_type in ["restaurant_visited", "place_visited"]))
    }
    
    assign(socket, :stats, stats)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="activity-list-container">
      <!-- Header with Actions and Filters -->
      <div class="bg-white rounded-lg shadow-sm border border-gray-200 mb-6">
        <div class="px-6 py-4 border-b border-gray-200">
          <div class="flex justify-between items-center">
            <div>
              <h2 class="text-lg font-medium text-gray-900">Event History</h2>
              <p class="mt-1 text-sm text-gray-500">Track and manage activities for your event</p>
            </div>
            <button 
              phx-click="show_add_activity" 
              phx-target={@myself}
              class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              <svg class="-ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
              </svg>
              Create Activity
            </button>
          </div>
        </div>

        <!-- Filters and Sorting Controls -->
        <div class="px-6 py-3 bg-gray-50 border-b border-gray-200">
          <div class="flex flex-col sm:flex-row gap-4">
            <!-- Filter Dropdown -->
            <div class="flex-1">
              <label for="activity-filter" class="sr-only">Filter activities</label>
              <select
                id="activity-filter"
                name="activity_filter"
                phx-change="filter_activities"
                phx-target={@myself}
                class="block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"
              >
                <option value="all" selected={@activity_filter == "all"}>All Activities</option>
                <option value="movies" selected={@activity_filter == "movies"}>Movies</option>
                <option value="tv" selected={@activity_filter == "tv"}>TV Shows</option>
                <option value="places" selected={@activity_filter == "places"}>Places</option>
                <option value="manual" selected={@activity_filter == "manual"}>Manual Entries</option>
              </select>
            </div>

            <!-- Sort Dropdown -->
            <div class="flex-1">
              <label for="activity-sort" class="sr-only">Sort activities</label>
              <select
                id="activity-sort"
                name="activity_sort"
                phx-change="sort_activities"
                phx-target={@myself}
                class="block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"
              >
                <option value="newest" selected={@activity_sort == "newest"}>Newest First</option>
                <option value="oldest" selected={@activity_sort == "oldest"}>Oldest First</option>
                <option value="type" selected={@activity_sort == "type"}>By Type</option>
                <option value="name" selected={@activity_sort == "name"}>By Name</option>
              </select>
            </div>
          </div>
        </div>

        <!-- Quick Stats -->
        <div class="px-6 py-3 border-b border-gray-200">
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div class="text-center">
              <div class="text-2xl font-bold text-gray-900">
                <%= @stats.total_activities %>
              </div>
              <div class="text-xs text-gray-500">Total Activities</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold text-purple-600">
                <%= @stats.movies_watched %>
              </div>
              <div class="text-xs text-gray-500">Movies</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold text-blue-600">
                <%= @stats.tv_shows_watched %>
              </div>
              <div class="text-xs text-gray-500">TV Shows</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold text-green-600">
                <%= @stats.places_visited %>
              </div>
              <div class="text-xs text-gray-500">Places</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Activity Cards -->
      <%= if @activities == [] do %>
        <div class="text-center py-12 bg-white rounded-lg shadow-sm border border-gray-200">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No activities yet</h3>
          <p class="mt-1 text-sm text-gray-500">
            Get started by recording what happened during this event.
          </p>
          <div class="mt-6">
            <button
              phx-click="show_add_activity"
              phx-target={@myself}
              class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              <svg class="-ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
              </svg>
              Create Activity
            </button>
          </div>
        </div>
      <% else %>
        <div class="space-y-6">
          <%= for activity <- filter_and_sort_activities(@activities, @activity_filter, @activity_sort) do %>
            <div class="bg-white shadow rounded-lg border border-gray-200">
              <div class="px-6 py-4 border-b border-gray-200">
                <div class="flex items-center justify-between">
                  <div class="flex-1">
                    <h3 class="text-lg font-medium text-gray-900"><%= activity_title(activity) %></h3>
                    <%= if activity_description(activity) != "No description provided" do %>
                      <p class="mt-1 text-sm text-gray-500"><%= activity_description(activity) %></p>
                    <% end %>
                    <div class="mt-2 flex items-center space-x-4 text-sm text-gray-500">
                      <span class="inline-flex items-center">
                        <svg class="mr-1 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.997 1.997 0 013 12V7a2 2 0 012-2z" />
                        </svg>
                        <%= format_activity_type(activity.activity_type) %>
                      </span>
                      <span class="inline-flex items-center">
                        <svg class="mr-1 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                        </svg>
                        <%= format_date(activity.occurred_at || activity.inserted_at) %>
                      </span>
                      <span class="inline-flex items-center">
                        <svg class="mr-1 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                        </svg>
                        <%= activity.created_by.name %>
                      </span>
                    </div>
                  </div>
                  <div class="flex items-center space-x-3">
                    <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", activity_phase_badge_class(activity)]}>
                      <%= format_activity_status(activity) %>
                    </span>
                    <%= if activity.created_by_id == @user.id do %>
                      <div class="relative">
                        <button
                          phx-click="toggle_activity_menu"
                          phx-target={@myself}
                          phx-value-activity-id={activity.id}
                          class="text-gray-400 hover:text-gray-600 p-1"
                          title="More actions"
                        >
                          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z" />
                          </svg>
                        </button>
                        
                        <%= if @open_activity_menu == activity.id do %>
                          <div 
                            phx-click-away="close_activity_menu"
                            phx-target={@myself}
                            class="absolute right-0 z-10 mt-2 w-48 bg-white rounded-md shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none"
                          >
                            <div class="py-1">
                              <button
                                phx-click="edit_activity"
                                phx-target={@myself}
                                phx-value-activity-id={activity.id}
                                class="flex items-center w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 text-left"
                              >
                                <svg class="mr-3 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                                </svg>
                                Edit Activity
                              </button>
                              <button
                                phx-click="delete_activity"
                                phx-target={@myself}
                                phx-value-activity-id={activity.id}
                                data-confirm="Are you sure you want to delete this activity? This action cannot be undone."
                                class="flex items-center w-full px-4 py-2 text-sm text-red-700 hover:bg-red-50 text-left"
                              >
                                <svg class="mr-3 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                                </svg>
                                Delete Activity
                              </button>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>

              <%= if activity.metadata["poster_url"] || activity.metadata["image_url"] do %>
                <div class="px-6 py-4">
                  <img 
                    src={activity.metadata["poster_url"] || activity.metadata["image_url"]} 
                    alt={activity_title(activity)}
                    class="w-24 h-36 object-cover rounded-lg"
                  />
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Activity Creation Modal -->
      <.live_component
        module={EventasaurusWeb.ActivityCreationComponent}
        id={"activity-creation-#{@event.id}"}
        event={@event}
        user={@user}
        show={@show_activity_creation}
      />
      
      <!-- Activity Edit Modal -->
      <%= if @editing_activity do %>
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
          <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
            <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity" aria-hidden="true"></div>
            <span class="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true">&#8203;</span>
            <div class="inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
              <form phx-submit="update_activity" phx-target={@myself}>
                <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                  <div class="sm:flex sm:items-start">
                    <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left w-full">
                      <h3 class="text-lg leading-6 font-medium text-gray-900" id="modal-title">
                        Edit Activity
                      </h3>
                      <div class="mt-4 space-y-4">
                        <%= if @editing_activity.activity_type in ["movie_watched", "tv_watched"] do %>
                          <div>
                            <label for="title" class="block text-sm font-medium text-gray-700">Title</label>
                            <input 
                              type="text" 
                              name="title" 
                              id="title"
                              value={@editing_activity.metadata["title"]}
                              class="mt-1 focus:ring-indigo-500 focus:border-indigo-500 block w-full shadow-sm sm:text-sm border-gray-300 rounded-md"
                            />
                          </div>
                        <% end %>
                        
                        <div>
                          <label for="notes" class="block text-sm font-medium text-gray-700">Notes</label>
                          <textarea 
                            name="notes" 
                            id="notes" 
                            rows="4"
                            class="mt-1 focus:ring-indigo-500 focus:border-indigo-500 block w-full shadow-sm sm:text-sm border-gray-300 rounded-md"
                          ><%= @editing_activity.metadata["notes"] %></textarea>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="bg-gray-50 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                  <button 
                    type="submit"
                    class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:ml-3 sm:w-auto sm:text-sm"
                  >
                    Save Changes
                  </button>
                  <button 
                    type="button"
                    phx-click="cancel_edit"
                    phx-target={@myself}
                    class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Event handlers
  @impl true
  def handle_event("show_add_activity", _params, socket) do
    {:noreply, assign(socket, :show_activity_creation, true)}
  end

  @impl true
  def handle_event("filter_activities", %{"activity_filter" => filter}, socket) do
    {:noreply, assign(socket, :activity_filter, filter)}
  end

  @impl true
  def handle_event("sort_activities", %{"activity_sort" => sort}, socket) do
    {:noreply, assign(socket, :activity_sort, sort)}
  end

  @impl true
  def handle_event("toggle_activity_menu", %{"activity-id" => activity_id}, socket) do
    activity_id = String.to_integer(activity_id)
    
    new_menu_state = if socket.assigns.open_activity_menu == activity_id do
      nil
    else
      activity_id
    end
    
    {:noreply, assign(socket, :open_activity_menu, new_menu_state)}
  end

  @impl true
  def handle_event("close_activity_menu", _params, socket) do
    {:noreply, assign(socket, :open_activity_menu, nil)}
  end

  @impl true
  def handle_event("edit_activity", %{"activity-id" => activity_id}, socket) do
    activity_id = String.to_integer(activity_id)
    activity = Enum.find(socket.assigns.activities, &(&1.id == activity_id))
    
    if activity && activity.created_by_id == socket.assigns.user.id do
      {:noreply, 
       socket
       |> assign(:editing_activity, activity)
       |> assign(:open_activity_menu, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_activity", %{"activity-id" => activity_id}, socket) do
    activity_id = String.to_integer(activity_id)
    activity = Enum.find(socket.assigns.activities, &(&1.id == activity_id))
    
    if activity && activity.created_by_id == socket.assigns.user.id do
      case Events.delete_event_activity(activity) do
        {:ok, _deleted_activity} ->
          socket = 
            socket
            |> load_activities()
            |> calculate_stats()
            |> assign(:open_activity_menu, nil)
          send(self(), {:activity_deleted, activity})
          {:noreply, socket}
        
        {:error, _changeset} ->
          send(self(), {:show_error, "Failed to delete activity"})
          {:noreply, socket |> assign(:open_activity_menu, nil)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_activity, nil)}
  end

  @impl true
  def handle_event("update_activity", params, socket) do
    activity = socket.assigns.editing_activity
    
    if activity && activity.created_by_id == socket.assigns.user.id do
      updated_metadata = Map.merge(activity.metadata || %{}, %{
        "notes" => params["notes"],
        "title" => params["title"]
      })
      
      case Events.update_event_activity(activity, %{metadata: updated_metadata}) do
        {:ok, _updated_activity} ->
          socket = 
            socket
            |> assign(:editing_activity, nil)
            |> load_activities()
            |> calculate_stats()
          {:noreply, socket}
        
        {:error, _changeset} ->
          send(self(), {:show_error, "Failed to update activity"})
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Helper functions
  defp filter_and_sort_activities(activities, filter, sort) do
    activities
    |> filter_activities(filter)
    |> sort_activities(sort)
  end

  defp filter_activities(activities, "all"), do: activities
  defp filter_activities(activities, "movies") do
    Enum.filter(activities, &(&1.activity_type == "movie_watched"))
  end
  defp filter_activities(activities, "tv") do
    Enum.filter(activities, &(&1.activity_type == "tv_watched"))
  end
  defp filter_activities(activities, "places") do
    Enum.filter(activities, &(&1.activity_type in ["restaurant_visited", "place_visited"]))
  end
  defp filter_activities(activities, "manual") do
    Enum.filter(activities, &(&1.source == "manual"))
  end
  defp filter_activities(activities, _), do: activities

  defp sort_activities(activities, "newest") do
    Enum.sort_by(activities, & &1.inserted_at, {:desc, NaiveDateTime})
  end
  defp sort_activities(activities, "oldest") do
    Enum.sort_by(activities, & &1.inserted_at, {:asc, NaiveDateTime})
  end
  defp sort_activities(activities, "type") do
    Enum.sort_by(activities, & &1.activity_type)
  end
  defp sort_activities(activities, "name") do
    Enum.sort_by(activities, &activity_title/1)
  end
  defp sort_activities(activities, _), do: activities

  defp activity_title(%EventActivity{} = activity) do
    case activity.activity_type do
      "movie_watched" -> activity.metadata["title"] || "Movie watched"
      "tv_watched" -> activity.metadata["title"] || "TV show watched"
      "game_played" -> activity.metadata["game_name"] || activity.metadata["title"] || "Game played"
      "book_read" -> activity.metadata["title"] || "Book read"
      "restaurant_visited" -> activity.metadata["name"] || activity.metadata["title"] || "Restaurant visited"
      "place_visited" -> activity.metadata["name"] || activity.metadata["title"] || "Place visited"
      "activity_completed" -> activity.metadata["title"] || "Activity completed"
      _ -> activity.metadata["title"] || "Activity"
    end
  end

  defp activity_description(activity) do
    activity.metadata["notes"] || activity.metadata["description"] || "No description provided"
  end

  defp format_activity_type("movie_watched"), do: "Movie"
  defp format_activity_type("tv_watched"), do: "TV Show"
  defp format_activity_type("game_played"), do: "Game"
  defp format_activity_type("book_read"), do: "Book"
  defp format_activity_type("restaurant_visited"), do: "Restaurant"
  defp format_activity_type("place_visited"), do: "Place"
  defp format_activity_type(_), do: "Activity"

  defp format_activity_status(_activity), do: "Completed"

  defp activity_phase_badge_class(_activity), do: "bg-green-100 text-green-800"

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end
  defp format_date(_), do: ""
end