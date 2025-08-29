defmodule EventasaurusWeb.ActivityCreationComponent do
  @moduledoc """
  A reusable LiveView component for creating and editing event activities.
  
  Follows the same design pattern as PollCreationComponent, providing
  a form for manually recording activities that happened during an event.
  
  ## Attributes:
  - event: Event struct (required)
  - user: User struct (required) 
  - show: Boolean to show/hide the modal
  - activity: EventActivity struct for editing (optional, nil for new activities)
  """
  
  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias EventasaurusWeb.RichDataSearchComponent  # For movies/TV only - NOT for places!
  alias EventasaurusApp.DateTimeHelper
  
  @activity_types [
    {"movie_watched", "Movie", "Record a movie that was watched"},
    {"tv_watched", "TV Show", "Record a TV show that was watched"},
    {"game_played", "Game", "Record a game that was played"},
    {"place_visited", "Place", "Record a place visit (restaurant, venue, etc.)"},
    {"book_read", "Book", "Record a book that was read"},
    {"activity_completed", "Other Activity", "Record any other activity"}
  ]
  
  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:show, false)
     |> assign(:current_activity_type, "movie_watched")
     |> assign(:form_data, %{})
     |> assign(:errors, %{})
     |> assign(:selected_movie, nil)
     |> assign(:selected_tv_show, nil)
     |> assign(:selected_place, nil)}
  end
  
  # Helper functions for date/time formatting
  defp format_date(datetime, event) do
    timezone = event.timezone || "UTC"
    {date, _time} = DateTimeHelper.format_for_form(datetime, timezone)
    date || ""
  end
  
  defp format_time(datetime, event) do
    timezone = event.timezone || "UTC"
    {_date, time} = DateTimeHelper.format_for_form(datetime, timezone)
    time || ""
  end
  
  @impl true
  def update(assigns, socket) do
    require Logger
    
    # Determine if we're editing or creating
    activity = assigns[:activity]
    is_editing = activity != nil
    
    # Handle selection actions from RichDataSearchComponent
    socket = case assigns do
      %{action: "movie_selected", data: movie} ->
        Logger.debug("ActivityCreationComponent: Received movie_selected for #{movie.title}")
        assign(socket, :selected_movie, movie)
      
      %{action: "tv_show_selected", data: tv_show} ->
        Logger.debug("ActivityCreationComponent: Received tv_show_selected for #{tv_show.title}")
        assign(socket, :selected_tv_show, tv_show)
      
      %{action: "place_selected", data: place} ->
        Logger.debug("ActivityCreationComponent: Received place_selected for #{place.title}")
        assign(socket, :selected_place, place)
      
      _ ->
        socket
    end
    
    # Set form_data based on editing or creating
    form_data = if is_editing do
      # Pre-populate form with existing activity data
      %{
        "activity_type" => activity.activity_type,
        "title" => activity.metadata["title"] || "",
        "description" => activity.metadata["overview"] || activity.metadata["description"] || "",
        "notes" => activity.metadata["notes"] || "",
        "occurred_date" => format_date(activity.occurred_at || DateTime.utc_now(), assigns.event),
        "occurred_time" => format_time(activity.occurred_at || DateTime.utc_now(), assigns.event),
        "rating" => activity.metadata["rating"] || ""
      }
    else
      # Only set default form_data if it doesn't exist or is empty/incomplete
      existing_form_data = socket.assigns[:form_data] || %{}
      if Map.has_key?(existing_form_data, "occurred_date") && Map.has_key?(existing_form_data, "occurred_time") do
        existing_form_data
      else
        # Use event's start_at for default date and time if available
        event = assigns[:event]
        {default_date, default_time} = case event do
          %{start_at: %DateTime{} = start_at} -> 
            {format_date(start_at, event), format_time(start_at, event)}
          _ -> 
            now = DateTime.utc_now()
            # Use a default event with UTC timezone if event is nil
            default_event = %{timezone: "UTC"}
            {format_date(now, default_event), format_time(now, default_event)}
        end
        
        Map.merge(%{
          "activity_type" => "movie_watched",
          "title" => "",
          "description" => "",
          "notes" => "",
          "occurred_date" => default_date,
          "occurred_time" => default_time
        }, existing_form_data)
      end
    end
    
    # Set current activity type based on form data
    current_activity_type = form_data["activity_type"] || "movie_watched"
    
    # Pre-populate selected items when editing
    {selected_movie, selected_tv_show, selected_place} = if is_editing do
      case activity.activity_type do
        "movie_watched" ->
          selected_movie = if activity.metadata["tmdb_id"] do
            %{
              id: activity.metadata["tmdb_id"],
              title: activity.metadata["title"],
              description: activity.metadata["overview"] || activity.metadata["description"] || "",
              image_url: activity.metadata["poster_url"],
              metadata: activity.metadata
            }
          else
            nil
          end
          {selected_movie, nil, nil}
        
        "tv_watched" ->
          selected_tv_show = if activity.metadata["tmdb_id"] do
            %{
              id: activity.metadata["tmdb_id"],
              title: activity.metadata["title"],
              description: activity.metadata["overview"] || activity.metadata["description"] || "",
              image_url: activity.metadata["poster_url"],
              metadata: activity.metadata
            }
          else
            nil
          end
          {nil, selected_tv_show, nil}
        
        "place_visited" ->
          selected_place = if activity.metadata["place_id"] do
            %{
              id: activity.metadata["place_id"],
              title: activity.metadata["title"],
              metadata: activity.metadata
            }
          else
            nil
          end
          {nil, nil, selected_place}
        
        _ ->
          {nil, nil, nil}
      end
    else
      {nil, nil, nil}
    end

    # Only override selected items if we're editing or they don't exist yet
    socket = if socket.assigns[:selected_movie] == nil && selected_movie != nil do
      assign(socket, :selected_movie, selected_movie)
    else
      socket
    end
    
    socket = if socket.assigns[:selected_tv_show] == nil && selected_tv_show != nil do
      assign(socket, :selected_tv_show, selected_tv_show)
    else
      socket
    end
    
    socket = if socket.assigns[:selected_place] == nil && selected_place != nil do
      assign(socket, :selected_place, selected_place)
    else
      socket
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:activity_types, @activity_types)
     |> assign(:form_data, form_data)
     |> assign(:current_activity_type, current_activity_type)
     |> assign(:is_editing, is_editing)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:show, fn -> false end)}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class={if @show, do: "fixed inset-0 z-50 overflow-y-auto", else: "hidden"} aria-labelledby="modal-title" role="dialog" aria-modal="true">
      <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        <!-- Background overlay -->
        <div
          class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
          phx-click="close_modal"
          phx-target={@myself}
        ></div>
        
        <!-- Modal panel -->
        <div class="inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
          <form phx-submit="submit_activity" phx-target={@myself} phx-change="validate">
            <div class="bg-white px-6 pt-6 pb-4">
              <div class="mb-4">
                <h3 class="text-lg leading-6 font-medium text-gray-900" id="modal-title">
                  <%= if @activity, do: "Edit Activity", else: "Record Activity" %>
                </h3>
                <p class="text-sm text-gray-500">
                  <%= if @activity, do: "Update the activity details", else: "Record an activity that happened during this event" %>
                </p>
              </div>
              
              <div class="space-y-6">
                <!-- Activity Type Selection -->
                <div>
                  <label for="activity_type" class="block text-sm font-medium text-gray-700">
                    Activity Type <span class="text-red-500">*</span>
                  </label>
                  <select
                    name="activity_type"
                    id="activity_type"
                    class="mt-1 block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm rounded-md"
                    value={@form_data["activity_type"]}
                  >
                    <%= for {value, label, _description} <- @activity_types do %>
                      <option value={value} selected={@form_data["activity_type"] == value}>
                        <%= activity_emoji(value) %> <%= label %>
                      </option>
                    <% end %>
                  </select>
                  <%= if @errors[:activity_type] do %>
                    <p class="mt-2 text-sm text-red-600"><%= @errors[:activity_type] %></p>
                  <% end %>
                </div>
                
                <!-- Dynamic fields based on activity type -->
                <%= render_activity_fields(assigns) %>
                
                <!-- Notes field (common to all) -->
                <div>
                  <label for="activity_notes" class="block text-sm font-medium text-gray-700">
                    Notes
                  </label>
                  <textarea
                    name="notes"
                    id="activity_notes"
                    rows="3"
                    class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                    placeholder="Add any additional notes or memories about this activity"
                  ><%= @form_data["notes"] %></textarea>
                </div>
                
                <!-- When it occurred -->
                <div class="grid grid-cols-2 gap-4">
                  <div>
                    <label for="occurred_date" class="block text-sm font-medium text-gray-700">
                      Date
                    </label>
                    <input
                      type="date"
                      name="occurred_date"
                      id="occurred_date"
                      value={@form_data["occurred_date"]}
                      class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                    />
                  </div>
                  <div>
                    <label for="occurred_time" class="block text-sm font-medium text-gray-700">
                      Time
                    </label>
                    <input
                      type="time"
                      name="occurred_time"
                      id="occurred_time"
                      value={@form_data["occurred_time"]}
                      class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                    />
                  </div>
                </div>
                <%= if @errors[:occurred_at] do %>
                  <p class="mt-2 text-sm text-red-600"><%= @errors[:occurred_at] %></p>
                <% end %>
              </div>
            </div>
            
            <div class="bg-gray-50 px-6 py-3 sm:flex sm:flex-row-reverse">
              <button
                type="submit"
                disabled={@loading}
                class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:ml-3 sm:w-auto sm:text-sm disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <%= cond do
                  @loading -> "Saving..."
                  @activity -> "Update Activity"
                  true -> "Save Activity"
                end %>
              </button>
              <button
                type="button"
                phx-click="close_modal"
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
    """
  end
  
  defp render_activity_fields(%{form_data: %{"activity_type" => "movie_watched"}} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-2">
          Search for Movie <span class="text-red-500">*</span>
        </label>
        
        <%= if @selected_movie do %>
          <!-- Show selected movie -->
          <div class="p-4 bg-blue-50 border border-blue-200 rounded-lg">
            <div class="flex items-start space-x-3">
              <%= if @selected_movie.image_url do %>
                <img 
                  src={@selected_movie.image_url} 
                  alt={@selected_movie.title}
                  class="w-16 h-24 object-cover rounded flex-shrink-0"
                />
              <% end %>
              <div class="flex-1">
                <p class="font-medium text-gray-900">
                  <%= @selected_movie.title %>
                  <%= if @selected_movie.metadata["release_date"] do %>
                    (<%= String.slice(@selected_movie.metadata["release_date"], 0..3) %>)
                  <% end %>
                </p>
                <%= if @selected_movie.description && @selected_movie.description != "" do %>
                  <p class="text-sm text-gray-600 mt-2">
                    <%= @selected_movie.description %>
                  </p>
                <% end %>
                <button
                  type="button"
                  phx-click="clear_movie_selection"
                  phx-target={@myself}
                  class="mt-2 text-sm text-blue-600 hover:text-blue-800"
                >
                  Remove movie
                </button>
              </div>
            </div>
          </div>
          
          <!-- Hidden fields to submit movie data -->
          <input type="hidden" name="title" value={@selected_movie.title} />
          <input type="hidden" name="tmdb_id" value={@selected_movie.id} />
          <input type="hidden" name="year" value={@selected_movie.metadata["release_date"] && String.slice(@selected_movie.metadata["release_date"], 0..3)} />
          <input type="hidden" name="poster_url" value={@selected_movie.image_url} />
          <input type="hidden" name="overview" value={@selected_movie.description} />
        <% else %>
          <!-- Show search component -->
          <.live_component
            module={RichDataSearchComponent}
            id={"movie-search-#{@id}"}
            provider={:tmdb}
            content_type={:movie}
            search_placeholder="Search for a movie..."
            result_limit={10}
            show_search={true}
          />
        <% end %>
        
        <%= if @errors[:title] do %>
          <p class="mt-2 text-sm text-red-600"><%= @errors[:title] %></p>
        <% end %>
      </div>
      
    </div>
    """
  end
  
  defp render_activity_fields(%{form_data: %{"activity_type" => "tv_watched"}} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-2">
          Search for TV Show <span class="text-red-500">*</span>
        </label>
        
        <%= if @selected_tv_show do %>
          <!-- Show selected TV show -->
          <div class="p-4 bg-purple-50 border border-purple-200 rounded-lg">
            <div class="flex items-start space-x-3">
              <%= if @selected_tv_show.image_url do %>
                <img 
                  src={@selected_tv_show.image_url} 
                  alt={@selected_tv_show.title}
                  class="w-16 h-24 object-cover rounded flex-shrink-0"
                />
              <% end %>
              <div class="flex-1">
                <p class="font-medium text-gray-900">
                  <%= @selected_tv_show.title %>
                  <%= if @selected_tv_show.metadata["first_air_date"] do %>
                    (<%= String.slice(@selected_tv_show.metadata["first_air_date"], 0..3) %>)
                  <% end %>
                </p>
                <%= if @selected_tv_show.description && @selected_tv_show.description != "" do %>
                  <p class="text-sm text-gray-600 mt-2">
                    <%= @selected_tv_show.description %>
                  </p>
                <% end %>
                <button
                  type="button"
                  phx-click="clear_tv_show_selection"
                  phx-target={@myself}
                  class="mt-2 text-sm text-purple-600 hover:text-purple-800"
                >
                  Remove TV show
                </button>
              </div>
            </div>
          </div>
          
          <!-- Hidden fields to submit TV show data -->
          <input type="hidden" name="title" value={@selected_tv_show.title} />
          <input type="hidden" name="tmdb_id" value={@selected_tv_show.id} />
          <input type="hidden" name="year" value={@selected_tv_show.metadata["first_air_date"] && String.slice(@selected_tv_show.metadata["first_air_date"], 0..3)} />
          <input type="hidden" name="poster_url" value={@selected_tv_show.image_url} />
          <input type="hidden" name="overview" value={@selected_tv_show.description} />
        <% else %>
          <!-- Show search component -->
          <.live_component
            module={RichDataSearchComponent}
            id={"tv-search-#{@id}"}
            provider={:tmdb}
            content_type={:tv}
            search_placeholder="Search for a TV show..."
            result_limit={10}
            show_search={true}
          />
        <% end %>
        
        <%= if @errors[:title] do %>
          <p class="mt-2 text-sm text-red-600"><%= @errors[:title] %></p>
        <% end %>
      </div>
      
    </div>
    """
  end
  
  defp render_activity_fields(%{form_data: %{"activity_type" => "game_played"}} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <label for="game_name" class="block text-sm font-medium text-gray-700">
          Game Name <span class="text-red-500">*</span>
        </label>
        <input
          type="text"
          name="title"
          id="game_name"
          value={@form_data["title"]}
          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
          placeholder="Enter the game name"
          required
        />
        <%= if @errors[:title] do %>
          <p class="mt-2 text-sm text-red-600"><%= @errors[:title] %></p>
        <% end %>
      </div>
      
      <div>
        <label for="game_platform" class="block text-sm font-medium text-gray-700">
          Platform/Type
        </label>
        <select
          name="platform"
          id="game_platform"
          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
        >
          <option value="">Select platform...</option>
          <option value="board_game">Board Game</option>
          <option value="card_game">Card Game</option>
          <option value="video_game">Video Game</option>
          <option value="sport">Sport</option>
          <option value="other">Other</option>
        </select>
      </div>
      
      <div>
        <label for="game_winner" class="block text-sm font-medium text-gray-700">
          Winner(s)
        </label>
        <input
          type="text"
          name="winner"
          id="game_winner"
          value={@form_data["winner"]}
          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
          placeholder="Who won?"
        />
      </div>
    </div>
    """
  end
  
  defp render_activity_fields(%{form_data: %{"activity_type" => "place_visited"}} = assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-2">
          Search for Place <span class="text-red-500">*</span>
        </label>
        
        <%= if @selected_place do %>
          <!-- Show selected place -->
          <div class="p-4 bg-green-50 border border-green-200 rounded-lg">
            <div class="flex items-start space-x-3">
              <div class="flex-shrink-0">
                <%= if @selected_place["photos"] && length(@selected_place["photos"]) > 0 do %>
                  <img 
                    src={List.first(@selected_place["photos"])} 
                    alt={@selected_place["title"]}
                    class="w-16 h-16 object-cover rounded-lg"
                  />
                <% else %>
                  <div class="w-16 h-16 bg-green-100 rounded-lg flex items-center justify-center">
                    <svg class="w-8 h-8 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                    </svg>
                  </div>
                <% end %>
              </div>
              <div class="flex-1">
                <p class="font-medium text-gray-900">
                  <%= @selected_place["title"] %>
                </p>
                <p class="text-sm text-gray-600 mt-1">
                  <%= @selected_place["address"] %>
                </p>
                <% rating = @selected_place["rating"] %>
                <%= if rating do %>
                  <div class="mt-1 flex items-center">
                    <svg class="w-4 h-4 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                    </svg>
                    <span class="ml-1 text-xs text-gray-600"><%= rating %></span>
                  </div>
                <% end %>
                <button
                  type="button"
                  phx-click="clear_place_selection"
                  phx-target={@myself}
                  class="mt-2 text-sm text-green-600 hover:text-green-800"
                >
                  Remove place
                </button>
              </div>
            </div>
          </div>
          
          <!-- Hidden fields to submit place data (SAME structure as polling) -->
          <input type="hidden" name="title" value={@selected_place["title"]} />
          <input type="hidden" name="place_id" value={@selected_place["place_id"]} />
          <input type="hidden" name="address" value={@selected_place["address"]} />
          <input type="hidden" name="google_rating" value={@selected_place["rating"]} />
          <input type="hidden" name="photos" value={Jason.encode!(@selected_place["photos"] || [])} />
          <input type="hidden" name="description" value={@selected_place["address"]} />
        <% else %>
          <!-- Native Google Places Autocomplete -->
          <div class="relative">
            <input
              type="text"
              name="title"
              id={"place-search-#{@id}"}
              placeholder="Search for a restaurant, venue, or any place..."
              phx-hook="PlacesHistorySearch"
              data-location-scope="place"
              data-activity-type="place"
              autocomplete="off"
              class="w-full px-4 py-2 pl-10 pr-4 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
              required
            />
            <div class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none">
              <svg class="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </div>
            <!-- Hidden fields that will be populated by JavaScript -->
            <input type="hidden" id={"place-id-#{@id}"} name="place_id" value="" />
            <input type="hidden" id={"place-address-#{@id}"} name="address" value="" />
            <input type="hidden" id={"place-rating-#{@id}"} name="google_rating" value="" />
            <input type="hidden" id={"place-photos-#{@id}"} name="photos" value="" />
          </div>
          <p class="mt-1 text-xs text-gray-500">Select a place from the dropdown suggestions</p>
        <% end %>
        
        <%= if @errors[:title] do %>
          <p class="mt-2 text-sm text-red-600"><%= @errors[:title] %></p>
        <% end %>
      </div>
      
    </div>
    """
  end
  
  defp render_activity_fields(assigns) do
    # Default fields for other activity types
    ~H"""
    <div class="space-y-4">
      <div>
        <label for="activity_title" class="block text-sm font-medium text-gray-700">
          Activity Name <span class="text-red-500">*</span>
        </label>
        <input
          type="text"
          name="title"
          id="activity_title"
          value={@form_data["title"]}
          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
          placeholder="What did you do?"
          required
        />
        <%= if @errors[:title] do %>
          <p class="mt-2 text-sm text-red-600"><%= @errors[:title] %></p>
        <% end %>
      </div>
      
      <div>
        <label for="activity_description" class="block text-sm font-medium text-gray-700">
          Description
        </label>
        <textarea
          name="description"
          id="activity_description"
          rows="2"
          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
          placeholder="Add more details..."
        ><%= @form_data["description"] %></textarea>
      </div>
    </div>
    """
  end
  
  @impl true
  def handle_event("validate", params, socket) do
    activity_type = params["activity_type"]
    
    # Clear previous selections when changing activity type
    socket = if activity_type && activity_type != socket.assigns.form_data["activity_type"] do
      socket
      |> assign(:selected_movie, nil)
      |> assign(:selected_tv_show, nil)
      |> assign(:selected_place, nil)
    else
      socket
    end
    
    {:noreply,
     socket
     |> assign(:form_data, Map.merge(socket.assigns.form_data, params))
     |> assign(:current_activity_type, activity_type || socket.assigns.current_activity_type)}
  end
  
  @impl true
  def handle_event("submit_activity", params, socket) do
    require Logger
    Logger.debug("ActivityCreationComponent: submit_activity params: #{inspect(params)}")
    Logger.debug("ActivityCreationComponent: user assigned: #{inspect(Map.has_key?(socket.assigns, :user))}")
    
    socket = assign(socket, :loading, true)
    
    # Check if user is assigned
    if !Map.has_key?(socket.assigns, :user) || is_nil(socket.assigns.user) do
      Logger.error("ActivityCreationComponent: No user assigned!")
      {:noreply,
       socket
       |> assign(:loading, false)
       |> assign(:errors, %{general: "User not found. Please refresh the page."})}
    else
      # Determine if we're editing or creating
      activity = socket.assigns[:activity]
      is_editing = activity != nil
      
      # Build metadata from form params
      metadata = build_metadata(params)
      
      # Parse occurred_at using the event's timezone
      event_timezone = socket.assigns.event.timezone || "UTC"
      occurred_at_result = case {Map.get(params, "occurred_date"), Map.get(params, "occurred_time")} do
        {date_str, time_str} when is_binary(date_str) and date_str != "" and is_binary(time_str) and time_str != "" ->
          case DateTimeHelper.parse_user_datetime(date_str, time_str, event_timezone) do
            {:ok, datetime} -> {:ok, datetime}
            {:error, reason} -> {:error, reason}
          end
        _ ->
          {:error, :missing_input}
      end
      
      # Validate datetime before proceeding
      case occurred_at_result do
        {:error, reason} ->
          error_msg = case reason do
            :missing_input -> "Please enter both date and time"
            :invalid_datetime -> "Please enter a valid date and time"
            :nonexistent_datetime -> "This time doesn't exist due to daylight saving time. Please choose a different time."
            :ambiguous_datetime -> "This time occurs twice due to daylight saving time. Please choose a different time to avoid confusion."
            _ -> "Invalid date/time format"
          end
          
          {:noreply,
           socket
           |> assign(:loading, false)
           |> assign(:errors, Map.put(socket.assigns[:errors] || %{}, :occurred_at, error_msg))}
           
        {:ok, occurred_at} ->
          if is_editing do
        # Update existing activity
        activity_attrs = %{
          activity_type: params["activity_type"],
          metadata: metadata,
          occurred_at: occurred_at
        }
        
        Logger.debug("ActivityCreationComponent: Updating activity #{activity.id} with attrs: #{inspect(activity_attrs)}")
        
        case Events.update_event_activity(activity, activity_attrs) do
          {:ok, updated_activity} ->
            Logger.debug("ActivityCreationComponent: Activity updated successfully: #{inspect(updated_activity.id)}")
            # Notify parent component to reload activities
            send(self(), {:reload_activities})
            
            # Notify parent to hide the modal and clear editing state
            send_update(EventasaurusWeb.EventHistoryComponent,
              id: "event-history-#{socket.assigns.event.id}",
              show_activity_creation: false,
              editing_activity: nil
            )
            
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:show, false)
             |> assign(:selected_movie, nil)
             |> assign(:selected_tv_show, nil)
             |> assign(:selected_place, nil)
             |> put_flash(:info, "Activity updated successfully!")}
          
          {:error, changeset} ->
            Logger.error("ActivityCreationComponent: Failed to update activity: #{inspect(changeset.errors)}")
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:errors, %{general: "Failed to update activity. Please try again."})}
        end
      else
        # Create new activity
        activity_attrs = %{
          event_id: socket.assigns.event.id,
          group_id: socket.assigns.event.group_id,
          activity_type: params["activity_type"],
          metadata: metadata,
          occurred_at: occurred_at,
          created_by_id: socket.assigns.user.id,
          source: "manual"
        }
        
        Logger.debug("ActivityCreationComponent: Creating activity with attrs: #{inspect(activity_attrs)}")
        
        case Events.create_event_activity(activity_attrs) do
          {:ok, activity} ->
            Logger.debug("ActivityCreationComponent: Activity created successfully: #{inspect(activity.id)}")
            # Notify parent component to reload activities
            send(self(), {:reload_activities})
            
            # Notify parent to hide the modal and clear editing state
            send_update(EventasaurusWeb.EventHistoryComponent,
              id: "event-history-#{socket.assigns.event.id}",
              show_activity_creation: false,
              editing_activity: nil
            )
            
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:show, false)
             |> assign(:selected_movie, nil)
             |> assign(:selected_tv_show, nil)
             |> assign(:selected_place, nil)
             |> put_flash(:info, "Activity recorded successfully!")}
          
          {:error, changeset} ->
            Logger.error("ActivityCreationComponent: Failed to create activity: #{inspect(changeset.errors)}")
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:errors, %{general: "Failed to save activity. Please try again."})}
        end
      end
      end  # End of case occurred_at_result
    end
  end
  
  @impl true
  def handle_event("close_modal", _, socket) do
    # Notify parent to hide the modal and clear editing state
    send_update(EventasaurusWeb.EventHistoryComponent,
      id: "event-history-#{socket.assigns.event.id}",
      show_activity_creation: false,
      editing_activity: nil
    )
    
    # Reset form when closing modal
    event = socket.assigns[:event]
    {default_date, default_time} = case event do
      %{start_at: %DateTime{} = start_at} -> 
        {format_date(start_at, event), format_time(start_at, event)}
      _ -> 
        now = DateTime.utc_now()
        # Use a default event with UTC timezone if event is nil
        default_event = %{timezone: "UTC"}
        {format_date(now, default_event), format_time(now, default_event)}
    end
    
    {:noreply, 
     socket
     |> assign(:show, false)
     |> assign(:form_data, %{
        "activity_type" => "movie_watched",
        "title" => "",
        "description" => "",
        "notes" => "",
        "occurred_date" => default_date,
        "occurred_time" => default_time
     })
     |> assign(:selected_movie, nil)
     |> assign(:selected_tv_show, nil)
     |> assign(:selected_place, nil)}
  end
  
  @impl true
  def handle_event("clear_movie_selection", _, socket) do
    {:noreply, assign(socket, :selected_movie, nil)}
  end
  
  @impl true
  def handle_event("clear_tv_show_selection", _, socket) do
    {:noreply, assign(socket, :selected_tv_show, nil)}
  end
  
  @impl true
  def handle_event("clear_place_selection", _, socket) do
    {:noreply, assign(socket, :selected_place, nil)}
  end
  
  # Handle place selection from native Google autocomplete
  def handle_event("place_selected", %{"place" => place_data}, socket) do
    {:noreply, assign(socket, :selected_place, place_data)}
  end
  
  
  defp build_metadata(params) do
    base_metadata = %{
      "title" => params["title"] || "",
      "description" => params["description"] || ""
    }
    
    # Add notes if present
    metadata = if params["notes"] && params["notes"] != "" do
      Map.put(base_metadata, "notes", params["notes"])
    else
      base_metadata
    end
    
    # Add activity-specific fields
    case params["activity_type"] do
      "movie_watched" ->
        metadata
        |> maybe_put("year", params["year"])
        |> maybe_put("poster_url", params["poster_url"])
        |> maybe_put("tmdb_id", params["tmdb_id"])
        |> maybe_put("overview", params["overview"])
      
      "tv_watched" ->
        metadata
        |> maybe_put("year", params["year"])
        |> maybe_put("poster_url", params["poster_url"])
        |> maybe_put("tmdb_id", params["tmdb_id"])
        |> maybe_put("overview", params["overview"])
      
      "game_played" ->
        metadata
        |> maybe_put("platform", params["platform"])
        |> maybe_put("winner", params["winner"])
      
      "place_visited" ->
        # Parse photos if it's a JSON string
        photos = case params["photos"] do
          nil -> nil
          "" -> nil
          photos_str when is_binary(photos_str) ->
            case Jason.decode(photos_str) do
              {:ok, photos_list} -> List.first(photos_list)  # Take first photo for display
              _ -> nil
            end
          photos_list when is_list(photos_list) -> List.first(photos_list)
          _ -> nil
        end
        
        metadata
        |> maybe_put("place_id", params["place_id"])
        |> maybe_put("address", params["address"])
        |> maybe_put("google_rating", params["google_rating"])
        |> maybe_put("photo_url", photos)  # Store first photo as photo_url for display
        |> maybe_put("description", params["description"])
      
      _ ->
        metadata
    end
  end
  
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  
  defp activity_emoji("movie_watched"), do: "🎬"
  defp activity_emoji("tv_watched"), do: "📺"
  defp activity_emoji("game_played"), do: "🎮"
  defp activity_emoji("place_visited"), do: "📍"
  defp activity_emoji("book_read"), do: "📚"
  defp activity_emoji(_), do: "✨"
  
end