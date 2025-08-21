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
     |> assign(:show_activity_menu, nil)
     |> assign(:selected_activities, [])}
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
    <div>
      <div class="bg-white rounded-lg shadow-sm border border-gray-200">
      <!-- Header with Stats and Actions -->
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex justify-between items-center">
          <div>
            <h2 class="text-lg font-bold text-gray-900">Event History</h2>
            <p class="text-sm text-gray-500">Track and manage activities for your event</p>
          </div>
          <div class="flex items-center gap-4">
            <button 
              phx-click="show_add_activity" 
              phx-target={@myself}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
              </svg>
              Record Activity
            </button>
          </div>
        </div>
      </div>

      <!-- Activity Analytics and Filters -->
      <div class="px-6 py-4 bg-gray-50 border-b border-gray-200">
        <!-- Quick Stats -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
          <div class="text-center">
            <div class="text-lg font-bold text-indigo-600">
              <%= @stats.total_activities %>
            </div>
            <div class="text-xs text-gray-500">Total Activities</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-bold text-purple-600">
              <%= @stats.movies_watched %>
            </div>
            <div class="text-xs text-gray-500">Movies</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-bold text-blue-600">
              <%= @stats.tv_shows_watched %>
            </div>
            <div class="text-xs text-gray-500">TV Shows</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-bold text-green-600">
              <%= @stats.places_visited %>
            </div>
            <div class="text-xs text-gray-500">Places</div>
          </div>
        </div>
      </div>

      <!-- Filtering and Sorting Controls -->
      <div class="px-6 py-3 bg-gray-50 border-b border-gray-200 flex items-center justify-between">
        <form phx-change="filter_activities" phx-target={@myself} class="flex flex-wrap items-center gap-3">
          <div class="text-sm font-medium text-gray-700">Filter by:</div>
          
          <!-- Filter Dropdown -->
          <div class="relative">
            <select 
              name="activity_filter" 
              value={@activity_filter}
              class="appearance-none bg-white border border-gray-300 rounded-md pl-3 pr-8 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500" 
              style="background-image: none !important;"
            >
              <option value="all">All Activities</option>
              <option value="movies">Movies</option>
              <option value="tv">TV Shows</option>
              <option value="places">Places</option>
              <option value="manual">Manual Entries</option>
            </select>
            <svg class="absolute right-2 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400 pointer-events-none" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd"></path>
            </svg>
          </div>
          
          <!-- Sort Dropdown -->
          <div class="relative">
            <select 
              name="activity_sort" 
              value={@activity_sort}
              class="appearance-none bg-white border border-gray-300 rounded-md pl-3 pr-8 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500" 
              style="background-image: none !important;"
            >
              <option value="newest">Newest First</option>
              <option value="oldest">Oldest First</option>
              <option value="type">By Type</option>
              <option value="name">By Name</option>
            </select>
            <svg class="absolute right-2 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400 pointer-events-none" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd"></path>
            </svg>
          </div>
        </form>
        
        <!-- Right side actions -->
        <div class="flex items-center gap-3">
          <!-- Select All Checkbox -->
          <div class="flex items-center gap-2">
            <input
              type="checkbox"
              phx-click="toggle_select_all"
              phx-target={@myself}
              checked={length(@selected_activities || []) == length(filter_and_sort_activities(@activities, @activity_filter, @activity_sort))}
              class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
            />
            <label class="text-sm text-gray-700">Select All</label>
          </div>
        </div>
      </div>

      <!-- Batch Operations Bar -->
      <%= if length(@selected_activities || []) > 0 do %>
        <div class="px-6 py-3 bg-indigo-50 border-b border-indigo-200 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="text-sm font-medium text-indigo-900">
              <%= length(@selected_activities || []) %> activit<%= if length(@selected_activities || []) == 1, do: "y", else: "ies" %> selected
            </span>
            <button
              phx-click="clear_selection"
              phx-target={@myself}
              class="text-sm text-indigo-600 hover:text-indigo-800"
            >
              Clear
            </button>
          </div>
          <div class="flex items-center gap-2">
            <button
              phx-click="batch_delete_activities"
              phx-target={@myself}
              data-confirm={"Are you sure you want to delete #{length(@selected_activities || [])} activit#{if length(@selected_activities || []) == 1, do: "y", else: "ies"}? This cannot be undone."}
              class="inline-flex items-center px-3 py-1 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
            >
              Delete Selected
            </button>
          </div>
        </div>
      <% end %>

      <!-- Activity List -->
      <%= if @activities == [] do %>
        <div class="text-center py-12">
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
              Record Activity
            </button>
          </div>
        </div>
      <% else %>
        <div class="divide-y divide-gray-200">
          <%= for activity <- filter_and_sort_activities(@activities, @activity_filter, @activity_sort) do %>
            <div class="px-6 py-4 hover:bg-gray-50 transition-colors" phx-click="close_activity_menu" phx-target={@myself}>
              <div class="flex items-center justify-between">
                <!-- Checkbox -->
                <div class="flex items-center gap-3 mr-3">
                  <input
                    type="checkbox"
                    phx-click="toggle_activity_selection"
                    phx-value-activity_id={activity.id}
                    phx-target={@myself}
                    checked={activity.id in (@selected_activities || [])}
                    class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                  />
                </div>
                
                <!-- Activity Info (matching user info structure) -->
                <div class="flex items-center gap-3 flex-1 min-w-0">
                  <!-- Activity Type Icon -->
                  <div class={["h-10 w-10 rounded-full flex items-center justify-center flex-shrink-0", activity_icon_bg_class(activity.activity_type)]}>
                    <%= activity_icon_svg(activity.activity_type) %>
                  </div>
                  <div class="min-w-0 flex-1">
                    <div class="flex items-center gap-2 mb-1">
                      <div class="font-medium text-gray-900 truncate">
                        <%= activity_title(activity) %>
                      </div>
                      <!-- Activity Type Badge -->
                      <span class={["inline-flex items-center px-2 py-1 rounded-full text-xs font-medium", activity_type_badge_class(activity.activity_type)]}>
                        <%= format_activity_type(activity.activity_type) %>
                      </span>
                    </div>
                    <div class="text-sm text-gray-500 truncate">
                      <%= if activity.metadata["overview"] || activity.metadata["description"] || activity.metadata["notes"] do %>
                        <%= activity.metadata["overview"] || activity.metadata["description"] || activity.metadata["notes"] %>
                      <% else %>
                        No description provided
                      <% end %>
                    </div>
                    <!-- Activity Details -->
                    <div class="text-xs text-gray-400 mt-1">
                      Created <%= format_relative_date(activity.inserted_at) %>
                      by <%= activity.created_by.name %>
                      <%= if activity.metadata["release_date"] do %>
                        • <%= format_release_year(activity.metadata["release_date"]) %>
                      <% end %>
                    </div>
                  </div>
                  
                  <!-- Movie/TV Poster -->
                  <%= if activity.metadata["poster_url"] do %>
                    <div class="flex-shrink-0 ml-4 mr-6">
                      <img 
                        src={activity.metadata["poster_url"]} 
                        alt={activity_title(activity)}
                        class="w-12 h-16 object-cover rounded-md"
                      />
                    </div>
                  <% end %>
                </div>

                <!-- Status and Actions (matching guests structure) -->
                <div class="flex items-center gap-6 flex-shrink-0">
                  <div class="text-right">
                    <div class="flex items-center gap-2 justify-end mb-1">
                      <div class="text-sm text-gray-500">
                        <%= format_short_date(activity.occurred_at || activity.inserted_at) %>
                      </div>
                      <!-- Status Badge -->
                      <span class={["inline-flex items-center px-2 py-1 rounded-full text-xs font-medium", activity_phase_badge_class(activity)]}>
                        <%= format_activity_status(activity) %>
                      </span>
                      <%= if activity.metadata["rating"] do %>
                        <div class="text-sm font-medium text-gray-900">
                          ⭐ <%= activity.metadata["rating"] %>/10
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <!-- Actions Menu (matching guests actions) -->
                  <div class="relative">
                    <button 
                      phx-click="toggle_activity_menu" 
                      phx-target={@myself}
                      phx-value-activity-id={activity.id}
                      phx-click-away="close_activity_menu"
                      class="p-2 text-gray-400 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded-full" 
                      aria-label="Activity actions"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z"></path>
                      </svg>
                    </button>
                    
                    <!-- Dropdown Menu -->
                    <%= if @show_activity_menu == activity.id do %>
                      <div class="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none" role="menu">
                        <%= if activity.created_by_id == @user.id do %>
                          <button
                            phx-click="edit_activity"
                            phx-target={@myself}
                            phx-value-activity-id={activity.id}
                            class="block w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                            role="menuitem"
                          >
                            Edit Activity
                          </button>
                          <button
                            phx-click="delete_activity"
                            phx-target={@myself}
                            phx-value-activity-id={activity.id}
                            data-confirm="Are you sure you want to delete this activity? This action cannot be undone."
                            class="block w-full px-4 py-2 text-left text-sm text-red-700 hover:bg-gray-100"
                            role="menuitem"
                          >
                            Delete Activity
                          </button>
                        <% else %>
                          <div class="px-4 py-2 text-sm text-gray-500">
                            No actions available
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
      </div>

      <!-- Activity Creation/Edit Modal -->
    <.live_component
      module={EventasaurusWeb.ActivityCreationComponent}
      id={"activity-creation-#{@event.id}"}
      event={@event}
      user={@user}
      show={@show_activity_creation}
      activity={@editing_activity}
    />
    </div>
    """
  end

  # Event handlers
  @impl true
  def handle_event("show_add_activity", _params, socket) do
    {:noreply, assign(socket, show_activity_creation: true, editing_activity: nil)}
  end

  @impl true
  def handle_event("filter_activities", %{"activity_filter" => filter, "activity_sort" => sort}, socket) do
    {:noreply, assign(socket, activity_filter: filter, activity_sort: sort)}
  end

  @impl true
  def handle_event("filter_activities", %{"activity_filter" => filter}, socket) do
    {:noreply, assign(socket, :activity_filter, filter)}
  end

  @impl true
  def handle_event("filter_activities", %{"activity_sort" => sort}, socket) do
    {:noreply, assign(socket, :activity_sort, sort)}
  end

  @impl true
  def handle_event("toggle_activity_menu", %{"activity-id" => activity_id}, socket) do
    activity_id = String.to_integer(activity_id)
    current_menu = socket.assigns.show_activity_menu
    
    new_menu = if current_menu == activity_id, do: nil, else: activity_id
    {:noreply, assign(socket, :show_activity_menu, new_menu)}
  end

  @impl true
  def handle_event("close_activity_menu", _params, socket) do
    {:noreply, assign(socket, :show_activity_menu, nil)}
  end

  @impl true
  def handle_event("edit_activity", %{"activity-id" => activity_id}, socket) do
    activity_id = String.to_integer(activity_id)
    activity = Enum.find(socket.assigns.activities, &(&1.id == activity_id))
    
    if activity && activity.created_by_id == socket.assigns.user.id do
      {:noreply, assign(socket, editing_activity: activity, show_activity_creation: true, show_activity_menu: nil)}
    else
      {:noreply, assign(socket, :show_activity_menu, nil)}
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
            |> assign(:show_activity_menu, nil)
            |> load_activities()
            |> calculate_stats()
          send(self(), {:activity_deleted, activity})
          {:noreply, socket}
        
        {:error, _changeset} ->
          send(self(), {:show_error, "Failed to delete activity"})
          {:noreply, assign(socket, :show_activity_menu, nil)}
      end
    else
      {:noreply, assign(socket, :show_activity_menu, nil)}
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

  defp format_date(%NaiveDateTime{} = ndt) do
    ndt
    |> NaiveDateTime.to_date()
    |> Calendar.strftime("%B %d, %Y")
  end
  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end
  defp format_date(_), do: ""

  defp format_short_date(%NaiveDateTime{} = ndt) do
    ndt
    |> NaiveDateTime.to_date()
    |> Calendar.strftime("%m/%d")
  end
  defp format_short_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%m/%d")
  end
  defp format_short_date(_), do: ""

  defp format_relative_date(%NaiveDateTime{} = ndt) do
    date = NaiveDateTime.to_date(ndt)
    today = Date.utc_today()
    days_diff = Date.diff(today, date)
    
    cond do
      days_diff == 0 -> "today"
      days_diff == 1 -> "1d ago"
      days_diff < 30 -> "#{days_diff}d ago"
      days_diff < 365 -> "#{div(days_diff, 30)}mo ago"
      true -> "#{div(days_diff, 365)}y ago"
    end
  end
  defp format_relative_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_naive()
    |> format_relative_date()
  end
  defp format_relative_date(_), do: ""

  defp format_release_year(release_date) when is_binary(release_date) do
    String.slice(release_date, 0, 4)
  end
  defp format_release_year(_), do: ""

  defp activity_icon_svg("movie_watched") do
    assigns = %{}
    ~H"""
    <svg class="h-5 w-5 text-white" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm3 2l.01.01L7 5l.01.01L7 5l.01.01L7 5l.01.01L7 5l.01.01L7 5l.01.01L7 5h.01L7 5V3zm1 0h2v2H8V5zm0 0V3h2v2H8zm4-2v2h-2V3h2zm-2 4V5h2v2h-2z" clip-rule="evenodd" />
    </svg>
    """
  end

  defp activity_icon_svg("tv_watched") do
    assigns = %{}
    ~H"""
    <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
    </svg>
    """
  end

  defp activity_icon_svg("game_played") do
    assigns = %{}
    ~H"""
    <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 4a2 2 0 114 0v1a1 1 0 001 1h3a1 1 0 011 1v3a1 1 0 01-1 1h-1a2 2 0 100 4h1a1 1 0 011 1v3a1 1 0 01-1 1h-3a1 1 0 01-1-1v-1a2 2 0 10-4 0v1a1 1 0 01-1 1H7a1 1 0 01-1-1v-3a1 1 0 011-1h1a2 2 0 100-4H7a1 1 0 01-1-1V7a1 1 0 011-1h3a1 1 0 001-1V4z" />
    </svg>
    """
  end

  defp activity_icon_svg("restaurant_visited") do
    assigns = %{}
    ~H"""
    <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 6l3 1m0 0l-3 9a5.002 5.002 0 006.001 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5.002 5.002 0 006.001 0M18 7l3 9m-3-9l-6-2m0-2v2m0 16V5m0 16l3-1m-3 1l-3-1" />
    </svg>
    """
  end

  defp activity_icon_svg("place_visited") do
    assigns = %{}
    ~H"""
    <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
    </svg>
    """
  end

  defp activity_icon_svg("book_read") do
    assigns = %{}
    ~H"""
    <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.246 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
    </svg>
    """
  end

  defp activity_icon_svg(_) do
    assigns = %{}
    ~H"""
    <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
    </svg>
    """
  end

  @impl true
  def handle_event("toggle_activity_selection", %{"activity_id" => activity_id}, socket) do
    activity_id = String.to_integer(activity_id)
    selected_activities = socket.assigns.selected_activities || []

    updated_selected =
      if activity_id in selected_activities do
        Enum.reject(selected_activities, &(&1 == activity_id))
      else
        [activity_id | selected_activities]
      end

    {:noreply, assign(socket, :selected_activities, updated_selected)}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    filtered_activities = filter_and_sort_activities(socket.assigns.activities, socket.assigns.activity_filter, socket.assigns.activity_sort)
    all_activity_ids = Enum.map(filtered_activities, & &1.id)

    updated_selected =
      if length(socket.assigns.selected_activities) == length(all_activity_ids) do
        []
      else
        all_activity_ids
      end

    {:noreply, assign(socket, :selected_activities, updated_selected)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_activities, [])}
  end

  @impl true
  def handle_event("batch_delete_activities", _params, socket) do
    require Logger
    selected_activities = socket.assigns.selected_activities || []

    activities_to_delete =
      socket.assigns.activities
      |> Enum.filter(&(&1.id in selected_activities))

    results = Enum.map(activities_to_delete, fn activity ->
      case Events.delete_event_activity(activity) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, activity.id, reason}
      end
    end)
    
    failures = Enum.filter(results, &match?({:error, _, _}, &1))
    
    if length(failures) > 0 do
      Logger.warning("Failed to delete some activities: #{inspect(failures)}")
    end

    # Reload activities after deletion
    socket =
      socket
      |> assign(:selected_activities, [])
      |> load_activities()
      |> calculate_stats()

    message =
      case length(activities_to_delete) do
        1 -> "1 activity deleted successfully"
        count -> "#{count} activities deleted successfully"
      end

    {:noreply, put_flash(socket, :info, message)}
  end

  defp activity_icon_bg_class("movie_watched"), do: "bg-purple-500"
  defp activity_icon_bg_class("tv_watched"), do: "bg-blue-500"
  defp activity_icon_bg_class("game_played"), do: "bg-green-500"
  defp activity_icon_bg_class("restaurant_visited"), do: "bg-orange-500"
  defp activity_icon_bg_class("place_visited"), do: "bg-indigo-500"
  defp activity_icon_bg_class("book_read"), do: "bg-yellow-500"
  defp activity_icon_bg_class(_), do: "bg-gray-500"

  defp activity_type_badge_class("movie_watched"), do: "bg-purple-100 text-purple-800"
  defp activity_type_badge_class("tv_watched"), do: "bg-blue-100 text-blue-800"
  defp activity_type_badge_class("game_played"), do: "bg-green-100 text-green-800"
  defp activity_type_badge_class("restaurant_visited"), do: "bg-orange-100 text-orange-800"
  defp activity_type_badge_class("place_visited"), do: "bg-indigo-100 text-indigo-800"
  defp activity_type_badge_class("book_read"), do: "bg-yellow-100 text-yellow-800"
  defp activity_type_badge_class(_), do: "bg-gray-100 text-gray-800"
end