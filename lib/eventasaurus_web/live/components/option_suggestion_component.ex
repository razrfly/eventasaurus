defmodule EventasaurusWeb.OptionSuggestionComponent do
  @moduledoc """
  A reusable LiveView component for managing poll options during the list building phase.

  Allows users to suggest new options, view existing suggestions, and provides moderation
  controls for poll creators. Supports both text-based options and API-enriched content
  for different poll types (movies, books, places, etc.).

  ## Attributes:
  - poll: Poll struct with preloaded options (required)
  - user: User struct (required)
  - is_creator: Boolean indicating if user is the poll creator
  - loading: Whether an operation is in progress
  - changeset: Ecto changeset for the option form
  - suggestion_form_visible: Whether to show the suggestion form

  ## Usage:
      <.live_component
        module={EventasaurusWeb.OptionSuggestionComponent}
        id="option-suggestions"
        poll={@poll}
        user={@user}
        is_creator={@is_creator}
        loading={@loading}
      />
  """

  use EventasaurusWeb, :live_component
  require Logger
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.PollOption
  alias EventasaurusWeb.Services.{MovieDataService, PlacesDataService, RichDataManager}
  alias EventasaurusWeb.Services.PollPubSubService
  alias EventasaurusWeb.Utils.TimeUtils
  alias EventasaurusWeb.Adapters.DatePollAdapter

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:suggestion_form_visible, false)
     |> assign(:editing_option_id, nil)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:search_loading, false)
     |> assign(:selected_dates, [])
     |> assign(:existing_dates, [])  # Track existing dates for calendar display
     # NEW: Time selection state
     |> assign(:time_enabled, false)
     |> assign(:selected_date_for_time, nil)
     |> assign(:date_time_slots, %{})}
  end

  @impl true
  def update(assigns, socket) do
    # Handle special actions first
    cond do
      assigns[:action] == :movie_rich_data_loaded ->
        # Update form with rich TMDB data using the same logic as PublicMoviePollComponent
        movie_id = assigns.selected_result.id
        rich_data = assigns.rich_data

        # Use MovieDataService to prepare consistent data (same as PublicMoviePollComponent)
        prepared_data = MovieDataService.prepare_movie_option_data(movie_id, rich_data)

        changeset = create_option_changeset(socket, prepared_data)

        {:ok,
         socket
         |> assign(:changeset, changeset)
         |> assign(:loading_rich_data, false)}

      assigns[:action] == :movie_rich_data_error ->
        # Fallback to basic result data if TMDB fetch fails
        changeset = create_option_changeset(socket, %{
          "title" => assigns.selected_result.title,
          "description" => assigns.selected_result.description || "",
          "external_id" => to_string(assigns.selected_result.id)
        })

        {:ok,
         socket
         |> assign(:changeset, changeset)
         |> assign(:loading_rich_data, false)}

      assigns[:calendar_event] ->
        # Handle calendar events sent from EventManageLive
        {_event_name, dates} = assigns.calendar_event

        # Process the calendar event (similar to handle_info)
        socket = assign(socket, :selected_dates, dates)

        {:ok, socket}

      assigns[:event] == "save_date_time_slots" ->
        # Handle time slot updates from TimeSlotPickerComponent
        date = assigns.date
        time_slots = assigns.time_slots

        # Update the date_time_slots in the socket
        current_slots = socket.assigns[:date_time_slots] || %{}
        updated_slots = Map.put(current_slots, date, time_slots)

        {:ok, assign(socket, :date_time_slots, updated_slots)}

      true ->
        # Normal update flow
        # Create changeset for new option
        changeset = PollOption.changeset(%PollOption{}, %{
          poll_id: assigns.poll.id,
          suggested_by_id: assigns.user.id,
          status: "active"
        })

        # Calculate user's suggestion count
        user_suggestion_count = case assigns.poll.poll_options do
          %Ecto.Association.NotLoaded{} -> 0
          poll_options when is_list(poll_options) ->
            Enum.count(poll_options, fn option ->
              option.suggested_by_id == assigns.user.id && option.status == "active"
            end)
          _ -> 0
        end

        # Check if user can suggest more options
        # Must be in a phase that allows suggestions AND within user limits
        suggestions_allowed_by_phase = suggestions_allowed_for_phase?(assigns.poll.phase)

        {max_options, can_suggest_more} =
          if assigns.is_creator do
            # Organizers can add unlimited options but only in appropriate phases
            {nil, suggestions_allowed_by_phase}
          else
            max_opts = assigns.poll.max_options_per_user || 3
            # Regular users need both phase permission AND to be under their limit
            {max_opts, suggestions_allowed_by_phase && user_suggestion_count < max_opts}
          end

        # Extract existing dates for date_selection polls
        existing_dates = if assigns.poll.poll_type == "date_selection" do
          extract_dates_from_poll_options(assigns.poll.poll_options)
        else
          []
        end

        {:ok,
         socket
         |> assign(assigns)
         |> assign(:changeset, changeset)
         |> assign(:user_suggestion_count, user_suggestion_count)
         |> assign(:can_suggest_more, can_suggest_more)
         |> assign(:max_options, max_options)
         |> assign(:suggestions_allowed_by_phase, suggestions_allowed_by_phase)
         |> assign(:phase_suggestion_message, get_phase_suggestion_message(assigns.poll.phase))
         |> assign(:existing_dates, existing_dates)
         |> assign_new(:loading, fn -> false end)
         |> assign_new(:suggestion_form_visible, fn -> false end)
         |> assign_new(:editing_option_id, fn -> nil end)
         |> assign_new(:edit_changeset, fn -> nil end)
         |> assign_new(:loading_rich_data, fn -> false end)
         |> assign_new(:show_phase_dropdown, fn -> false end)
         |> assign_new(:search_query, fn -> "" end)
         |> assign_new(:search_results, fn -> [] end)
         |> assign_new(:search_loading, fn -> false end)
         |> then(fn socket ->
           # Handle editing mode after all other assigns are set
           if Map.get(assigns, :editing_option_id) do
             option = case assigns.poll.poll_options do
               %Ecto.Association.NotLoaded{} -> nil
               poll_options when is_list(poll_options) ->
                 Enum.find(poll_options, fn opt -> opt.id == assigns.editing_option_id end)
               _ -> nil
             end

             if option do
               edit_changeset = PollOption.changeset(option, %{})
               socket
               |> assign(:editing_option_id, assigns.editing_option_id)
               |> assign(:edit_changeset, edit_changeset)
             else
               socket |> assign(:editing_option_id, nil)
             end
           else
             socket
           end
         end)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Add Option Button Area -->
      <div class="px-6 py-3 bg-gray-50 border-b border-gray-200">
        <div class="flex items-center justify-between">
          <div class="text-sm text-gray-500">
            <%= if @is_creator do %>
              <%= @user_suggestion_count %> options added
            <% else %>
              <%= @user_suggestion_count %>/<%= @max_options %> suggestions used
            <% end %>
          </div>
          <%= if @can_suggest_more do %>
            <button
              type="button"
              phx-click="toggle_suggestion_form"
              phx-target={@myself}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              <svg class="-ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
              </svg>
              <%= suggest_button_text(@poll.poll_type) %>
            </button>
          <% else %>
            <div class="text-sm text-gray-500 font-medium">
              <%= cond do %>
                <% @phase_suggestion_message != nil -> %>
                  <!-- Phase-based restriction message -->
                  <div class="flex items-center">
                    <svg class="w-4 h-4 mr-1 text-amber-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
                    </svg>
                    <span class="text-amber-600"><%= @phase_suggestion_message %></span>
                  </div>
                <% true -> %>
                  <!-- User limit reached message -->
                  Limit reached (<%= @max_options %> suggestions)
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Suggestion Form -->
      <%= if @suggestion_form_visible do %>
        <div class="px-6 py-4 bg-gray-50 border-b border-gray-200 form-container-mobile suggestion-form">
          <.form for={@changeset} phx-submit="submit_suggestion" phx-target={@myself} phx-change="validate_suggestion">
            <div class="space-y-4">

              <!-- City Selector (only for places poll type) -->
              <%= if @poll.poll_type == "places" do %>
                <div class="relative">
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Search Location (optional)
                    <span class="text-xs text-gray-500 ml-2">Choose a city to find nearby places</span>
                  </label>

                  <div class="relative">
                    <input
                      type="text"
                      class="city-selector-input block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm pr-10"
                      placeholder="Search for a city..."
                      autocomplete="off"
                    />
                    <div class="absolute inset-y-0 right-0 flex items-center pr-3">
                      <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/>
                      </svg>
                    </div>

                    <!-- City Dropdown -->
                    <div class="city-selector-dropdown hidden absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm">
                      <!-- Recent Cities -->
                      <div class="px-3 py-2 bg-gray-50 border-b">
                        <div class="text-xs font-medium text-gray-500 mb-2">RECENT CITIES</div>
                        <div class="recent-cities-container">
                          <!-- Recent cities will be populated by JavaScript -->
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- Location Context Display -->
                  <div class="city-display hidden mt-2 text-sm text-indigo-600 flex items-center">
                    <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/>
                    </svg>
                    <span>Searching near your location</span>
                  </div>
                </div>
              <% end %>

              <!-- Auto-complete title input -->
              <%= if @poll.poll_type == "time" do %>
                <!-- Time selector for time polls -->
                <div class="relative">
                  <label for="option_title" class="block text-sm font-medium text-gray-700">
                    Time <span class="text-red-500">*</span>
                  </label>
                  <select
                    name="poll_option[title]"
                    id="option_title"
                    class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                    required
                  >
                    <option value="" disabled selected={Map.get(@changeset.changes, :title, Map.get(@changeset.data, :title, "")) == ""}>Select a time...</option>
                    <%= for time_option <- time_options() do %>
                      <option value={time_option.value} selected={Map.get(@changeset.changes, :title, Map.get(@changeset.data, :title, "")) == time_option.value}>
                        <%= time_option.display %>
                      </option>
                    <% end %>
                  </select>
                  <%= if @changeset.errors[:title] do %>
                    <p class="mt-2 text-sm text-red-600"><%= translate_error(@changeset.errors[:title]) %></p>
                  <% end %>
                </div>
              <% else %>
                <%= if @poll.poll_type == "date_selection" do %>
                  <!-- Calendar interface for date selection polls -->
                  <div class="space-y-4">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-3">
                        📅 Select a Date <span class="text-red-500">*</span>
                      </label>
                      <p class="text-sm text-gray-600 mb-4">
                        Choose a date for people to vote on. You can add multiple dates by creating separate suggestions.
                      </p>
                    </div>

                    <!-- Calendar Component -->
                    <div class="border border-gray-200 rounded-lg bg-white p-4">
                      <.live_component
                        module={EventasaurusWeb.CalendarComponent}
                        id={"date-suggestion-calendar-#{@id}"}
                        selected_dates={@selected_dates || []}
                        existing_dates={@existing_dates || []}
                        year={Date.utc_today().year}
                        month={Date.utc_today().month}
                        compact={false}
                        allow_multiple={true}
                        min_date={Date.utc_today()}
                        on_date_select="calendar_date_selected"
                        target={@myself}
                      />
                    </div>

                    <!-- NEW: Time Selection Toggle -->
                    <div class="mt-4 space-y-4">
                      <div class="flex items-center justify-between">
                        <div class="flex items-center space-x-3">
                          <div class="flex items-center">
                            <input
                              id="time-enabled-toggle"
                              type="checkbox"
                              phx-click="toggle_time_selection"
                              phx-target={@myself}
                              checked={@time_enabled}
                              class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                            />
                            <label for="time-enabled-toggle" class="ml-2 flex items-center cursor-pointer">
                              <span class="text-lg mr-2">⏰</span>
                              <span class="text-sm font-medium text-gray-700">Specify times</span>
                            </label>
                          </div>
                        </div>
                      </div>

                      <p class="text-sm text-gray-600">
                        Optionally add specific time slots to your date suggestions
                      </p>

                      <!-- Time Configuration Interface -->
                      <%= if @time_enabled and @selected_date_for_time do %>
                        <div class="mt-4 p-4 bg-white rounded-lg border border-gray-200">
                          <div class="flex items-center justify-between mb-3">
                            <h5 class="text-sm font-medium text-gray-900">
                              Configure times for <%= @selected_date_for_time %>
                            </h5>
                            <button
                              type="button"
                              phx-click="cancel_time_config"
                              phx-target={@myself}
                              class="text-gray-400 hover:text-gray-600"
                            >
                              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                              </svg>
                            </button>
                          </div>

                          <!-- Time Slot Picker Component -->
                          <.live_component
                            module={EventasaurusWeb.TimeSlotPickerComponent}
                            id={"time-picker-#{@selected_date_for_time}"}
                            date={@selected_date_for_time}
                            existing_slots={@date_time_slots[@selected_date_for_time] || []}
                            on_save="save_date_time_slots"
                            target={@myself}
                          />
                        </div>
                      <% end %>

                      <!-- Date Options with Time Display -->
                      <%= if length(@selected_dates || []) > 0 do %>
                        <div class="space-y-2">
                          <%= for date <- (@selected_dates || []) do %>
                            <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg transition-all duration-300 transform hover:scale-[1.02] hover:shadow-md">
                              <div class="flex items-center space-x-3">
                                <div class="flex-shrink-0">
                                  <div class="w-2 h-2 bg-indigo-600 rounded-full"></div>
                                </div>
                                <div>
                                  <span class="text-sm font-medium text-gray-900">
                                    <%= format_date_for_display(date) %>
                                  </span>
                                  <%= if @time_enabled && Map.has_key?(@date_time_slots, Date.to_iso8601(date)) do %>
                                    <div class="flex flex-wrap gap-1 mt-1">
                                      <%= for time_slot <- Map.get(@date_time_slots, Date.to_iso8601(date), []) do %>
                                        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800">
                                          <%= TimeUtils.format_time_12hour(time_slot["start_time"]) %> - <%= TimeUtils.format_time_12hour(time_slot["end_time"]) %>
                                        </span>
                                      <% end %>
                                    </div>
                                  <% end %>
                                </div>
                              </div>
                              <%= if @time_enabled do %>
                                <button
                                  type="button"
                                  phx-click="configure_date_time"
                                  phx-value-date={Date.to_iso8601(date)}
                                  phx-target={@myself}
                                  class="text-sm text-indigo-600 hover:text-indigo-800 font-medium"
                                >
                                  <%= if Map.has_key?(@date_time_slots, Date.to_iso8601(date)) do %>
                                    Edit times
                                  <% else %>
                                    Add times
                                  <% end %>
                                </button>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>

                    <!-- Hidden field to store the selected date as the option title -->
                    <%= if length(@selected_dates || []) > 0 do %>
                      <input
                        type="hidden"
                        name="poll_option[title]"
                        value={format_date_for_option_title(List.first(@selected_dates))}
                      />
                    <% end %>
                  </div>
                <% else %>
                  <!-- Regular option input for other poll types -->
                  <div class="relative">
                    <label for="option_title" class="block text-sm font-medium text-gray-700">
                      <%= option_title_label(@poll.poll_type) %> <span class="text-red-500">*</span>
                    </label>
                  <div class="mt-1 relative">
                    <%= if should_use_api_search?(@poll.poll_type) do %>
                      <%= if @poll.poll_type == "movie" do %>
                        <input
                          type="text"
                          name="poll_option[title]"
                          id="option_title"
                          value={if @search_query != "", do: @search_query, else: Map.get(@changeset.changes, :title, Map.get(@changeset.data, :title, ""))}
                          placeholder={option_title_placeholder(@poll.poll_type)}
                          phx-change="search_movies"
                          phx-target={@myself}
                          phx-debounce="300"
                          autocomplete="off"
                          class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                      <% else %>
                        <input
                          type="text"
                          name="poll_option[title]"
                          id="option_title"
                          value={Map.get(@changeset.changes, :title, Map.get(@changeset.data, :title, ""))}
                          placeholder={option_title_placeholder(@poll.poll_type)}
                          phx-debounce="300"
                          phx-hook="PlacesSuggestionSearch"
                          autocomplete="off"
                          class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                      <% end %>
                    <% else %>
                      <input
                        type="text"
                        name="poll_option[title]"
                        id="option_title"
                        value={Map.get(@changeset.changes, :title, Map.get(@changeset.data, :title, ""))}
                        placeholder={option_title_placeholder(@poll.poll_type)}
                        class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                      />
                    <% end %>

                    <!-- Loading indicator removed - now handled by Google Places autocomplete -->

                    <!-- Remove the complex dropdown logic as it's now handled by Google Places -->

                    <!-- Movie search results dropdown -->
                    <%= if @poll.poll_type == "movie" and length(@search_results) > 0 do %>
                      <div class="absolute z-50 mt-1 w-full bg-white border border-gray-300 rounded-md shadow-lg max-h-60 overflow-y-auto">
                        <%= for movie <- @search_results do %>
                          <div class="flex items-center p-3 hover:bg-gray-50 cursor-pointer border-b border-gray-100 last:border-b-0"
                               phx-click="select_movie"
                               phx-value-movie-id={movie.id}
                               phx-target={@myself}>
                            <% image_url = get_movie_poster_url(movie) %>
                            <%= if image_url do %>
                              <img src={image_url} alt={movie.title} class="w-10 h-14 object-cover rounded mr-3 flex-shrink-0" />
                            <% else %>
                              <div class="w-10 h-14 bg-gray-200 rounded mr-3 flex-shrink-0 flex items-center justify-center">
                                <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4V2a1 1 0 011-1h4a1 1 0 011 1v2"/>
                                </svg>
                              </div>
                            <% end %>
                            <div class="flex-1 min-w-0">
                              <h4 class="font-medium text-gray-900 truncate"><%= movie.title %></h4>
                              <%= if movie.metadata && movie.metadata["release_date"] do %>
                                <p class="text-sm text-gray-600"><%= String.slice(movie.metadata["release_date"], 0, 4) %></p>
                              <% end %>
                              <%= if is_binary(movie.description) && String.length(movie.description) > 0 do %>
                                <p class="text-xs text-gray-500 mt-1 line-clamp-2"><%= movie.description %></p>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    <% end %>

                    <!-- Loading indicator for movie search -->
                    <%= if @poll.poll_type == "movie" and @search_loading do %>
                      <div class="absolute right-3 top-9 flex items-center">
                        <svg class="animate-spin h-4 w-4 text-indigo-600" fill="none" viewBox="0 0 24 24">
                          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                        </svg>
                      </div>
                    <% end %>

                    <%= if @changeset.errors[:title] do %>
                      <p class="mt-2 text-sm text-red-600"><%= translate_error(@changeset.errors[:title]) %></p>
                    <% end %>
                  </div>
                </div>
                <% end %>
              <% end %>

              <!-- Description field -->
              <%= if @poll.poll_type != "time" do %>
                <div>
                  <label for="option_description" class="block text-sm font-medium text-gray-700">
                    Description (optional)
                  </label>
                  <textarea
                    name="poll_option[description]"
                    id="option_description"
                    rows="2"
                    placeholder={option_description_placeholder(@poll.poll_type)}
                    class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                  ><%= Map.get(@changeset.changes, :description, Map.get(@changeset.data, :description, "")) %></textarea>
                </div>
              <% end %>

              <!-- Hidden fields for rich data (external_id, external_data, image_url) -->
              <%= if Map.has_key?(@changeset.changes, :external_id) do %>
                <input type="hidden" name="poll_option[external_id]" value={@changeset.changes.external_id} />
              <% end %>
              <%= if Map.has_key?(@changeset.changes, :image_url) do %>
                <input type="hidden" name="poll_option[image_url]" value={@changeset.changes.image_url} />
              <% end %>
              <%= if Map.has_key?(@changeset.changes, :external_data) do %>
                <input type="hidden" name="poll_option[external_data]" value={safe_json_encode(@changeset.changes.external_data)} />
              <% end %>

              <!-- Button area -->
              <div class="flex items-center justify-between">
                <div class="text-sm text-gray-500">
                  <%= if @is_creator do %>
                    <%= @user_suggestion_count %> options added
                  <% else %>
                    <%= @user_suggestion_count %>/<%= @max_options %> suggestions used
                  <% end %>
                </div>
                <div class="flex space-x-3">
                  <button
                    type="button"
                    phx-click="cancel_suggestion"
                    phx-target={@myself}
                    class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 cancel-button touch-target"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={@loading}
                    class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 suggestion-button touch-target"
                  >
                    <%= if @loading do %>
                      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 714 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      <%= if @poll.poll_type == "date_selection", do: "Adding Dates...", else: "Adding..." %>
                    <% else %>
                      <%= if @poll.poll_type == "date_selection" do %>
                        <%= if length(@selected_dates || []) > 0 do %>
                          Add <%= length(@selected_dates) %> <%= ngettext("Date", "Dates", length(@selected_dates)) %>
                        <% else %>
                          Select Dates
                        <% end %>
                      <% else %>
                        Add Suggestion
                      <% end %>
                    <% end %>
                  </button>
                </div>
              </div>
            </div>
          </.form>

          <!-- Mobile loading overlay -->
          <%= if @loading do %>
            <div class="mobile-loading-overlay md:hidden">
              <div class="mobile-loading-spinner"></div>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Options List -->
      <div
        class="divide-y divide-gray-200 min-h-[100px] relative"
        phx-hook={if @poll.poll_type in ["time", "date_selection"], do: "", else: "PollOptionDragDrop"}
        data-can-reorder={if(@is_creator && @poll.poll_type not in ["time", "date_selection"], do: "true", else: "false")}
        id={"option-list-#{@id}"}
      >
        <%= if safe_poll_options_empty?(@poll.poll_options) do %>
          <!-- Enhanced Empty State -->
          <div class="px-6 py-16 text-center">
            <!-- Poll type specific icon -->
            <div class="mx-auto w-20 h-20 bg-indigo-100 rounded-full flex items-center justify-center mb-6">
              <%= case @poll.poll_type do %>
                <% "movie" -> %>
                  <svg class="w-10 h-10 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4V2C7 1.45 7.45 1 8 1s1 .45 1 1v2h4V2c0-.55.45-1 1-1s1 .45 1 1v2h1c1.1 0 2 .9 2 2v14c0 1.1-.9 2-2 2H6c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2h1z"/>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                  </svg>
                <% "places" -> %>
                  <svg class="w-10 h-10 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/>
                  </svg>
                <% "time" -> %>
                  <svg class="w-10 h-10 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                  </svg>
                <% _ -> %>
                  <svg class="w-10 h-10 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"/>
                  </svg>
              <% end %>
            </div>

            <h3 class="text-xl font-semibold text-gray-900 mb-2">
              <%= get_empty_state_title(@poll.poll_type) %>
            </h3>

            <p class="text-gray-600 mb-2 max-w-md mx-auto">
              <%= get_empty_state_description(@poll.poll_type, @poll.voting_system) %>
            </p>

            <!-- Contextual guidance -->
            <div class="text-sm text-gray-500 mb-8 max-w-lg mx-auto">
              <%= get_empty_state_guidance(@poll.poll_type) %>
            </div>

            <!-- Large Call-to-Action Button -->
            <%= if @can_suggest_more do %>
              <button
                type="button"
                phx-click="toggle_suggestion_form"
                phx-target={@myself}
                class="inline-flex items-center px-8 py-4 border border-transparent text-lg font-medium rounded-lg shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors duration-200"
              >
                <svg class="-ml-1 mr-3 h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
                </svg>
                <%= get_empty_state_button_text(@poll.poll_type) %>
              </button>

              <!-- Secondary helpful text -->
              <p class="mt-4 text-sm text-gray-500">
                <%= get_empty_state_help_text(@poll.poll_type) %>
              </p>
            <% else %>
              <div class="text-center p-6 bg-gray-50 rounded-lg max-w-md mx-auto">
                <p class="text-gray-700 font-medium">You've reached your limit</p>
                <p class="text-sm text-gray-500 mt-1">
                  You can suggest up to <%= @max_options %> options. Ask others to add more suggestions!
                </p>
              </div>
            <% end %>
          </div>
        <% else %>
          <div data-role="options-container">
            <%= for option <- sort_poll_options(@poll.poll_options, @poll.poll_type) do %>
              <div
                class="px-6 py-4 transition-all duration-200 ease-out option-card mobile-optimized-animation hover:bg-gray-50 focus-within:ring-2 focus-within:ring-indigo-500 focus-within:ring-offset-2"
                data-draggable={if(@is_creator && @poll.poll_type not in ["time", "date_selection"], do: "true", else: "false")}
                data-option-id={option.id}
              >
                <!-- Edit Form (only shown when editing this specific option) -->
                <%= if @editing_option_id == option.id && @edit_changeset do %>
                  <.form for={@edit_changeset} phx-submit="save_edit" phx-target={@myself} phx-change="validate_edit">
                    <div class="space-y-4">
                      <input type="hidden" name="option_id" value={option.id} />

                      <%= if @poll.poll_type == "date_selection" do %>
                        <!-- For date selection polls, show the date as read-only -->
                        <div>
                          <label class="block text-sm font-medium text-gray-700">
                            Date
                          </label>
                          <div class="mt-1 p-3 bg-gray-50 border border-gray-300 rounded-md">
                            <div class="flex items-center">
                              <svg class="w-5 h-5 mr-2 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                              </svg>
                              <span class="text-sm text-gray-900"><%= option.title %></span>
                            </div>
                          </div>
                          <p class="mt-1 text-xs text-gray-500">Date options cannot be changed after creation</p>
                          <!-- Keep the title in a hidden field to maintain form data -->
                          <input type="hidden" name="poll_option[title]" value={option.title} />
                        </div>
                      <% else %>
                        <!-- Regular title input for other poll types -->
                        <div>
                          <label for={"edit_title_#{option.id}"} class="block text-sm font-medium text-gray-700">
                            Title <span class="text-red-500">*</span>
                          </label>
                          <input
                            type="text"
                            name="poll_option[title]"
                            id={"edit_title_#{option.id}"}
                            value={@edit_changeset.changes[:title] || option.title}
                            class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                          />
                          <%= if error = @edit_changeset.errors[:title] do %>
                            <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                          <% end %>
                        </div>
                      <% end %>

                      <%= if @poll.poll_type != "time" do %>
                        <div>
                          <label for={"edit_description_#{option.id}"} class="block text-sm font-medium text-gray-700">
                            Description (optional)
                          </label>
                          <textarea
                            name="poll_option[description]"
                            id={"edit_description_#{option.id}"}
                            rows="2"
                            class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                          ><%= @edit_changeset.changes[:description] || option.description || "" %></textarea>
                        </div>
                      <% end %>

                      <%= if @participants do %>
                        <div>
                          <label for={"edit_suggested_by_#{option.id}"} class="block text-sm font-medium text-gray-700">
                            Suggested by
                          </label>
                          <select
                            name="poll_option[suggested_by_id]"
                            id={"edit_suggested_by_#{option.id}"}
                            class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                          >
                            <!-- Event Organizer/Creator (current user, since only organizers can edit) -->
                            <option
                              value={@user.id}
                              selected={(@edit_changeset.changes[:suggested_by_id] || option.suggested_by_id) == @user.id}
                            >
                              <%= @user.name || @user.username || @user.email %> (Organizer)
                            </option>

                            <!-- Event Participants -->
                            <%= for participant <- @participants do %>
                              <!-- Skip if this participant is the same as the organizer to avoid duplicates -->
                              <%= if participant.user_id != @user.id do %>
                                <option
                                  value={participant.user_id}
                                  selected={(@edit_changeset.changes[:suggested_by_id] || option.suggested_by_id) == participant.user_id}
                                >
                                  <%= participant.user.name || participant.user.username || participant.user.email %>
                                </option>
                              <% end %>
                            <% end %>
                          </select>
                        </div>
                      <% end %>

                      <%= if @is_creator do %>
                        <div class="flex items-center">
                          <input
                            type="checkbox"
                            name="poll_option[status]"
                            id={"edit_hidden_#{option.id}"}
                            value="hidden"
                            checked={(@edit_changeset.changes[:status] || option.status) == "hidden"}
                            class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                          />
                          <label for={"edit_hidden_#{option.id}"} class="ml-2 block text-sm text-gray-900">
                            Hide this option from participants
                          </label>
                        </div>
                      <% end %>

                      <div class="flex space-x-3">
                        <button
                          type="submit"
                          class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_edit"
                          phx-target={@myself}
                          class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  </.form>
                <% else %>
                  <!-- Normal Option Display -->
                  <div class="flex items-start justify-between">
                    <!-- Drag handle for creators -->
                    <%= if @is_creator && @poll.poll_type not in ["time", "date_selection"] do %>
                      <div class="drag-handle mr-3 mt-1 flex-shrink-0 touch-target" title="Drag to reorder">
                        <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
                          <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z"/>
                        </svg>
                      </div>
                    <% end %>

                    <div class="flex-1 min-w-0">
                      <div class="flex">
                        <!-- Movie thumbnail -->
                        <%= if option.image_url do %>
                          <img
                            src={option.image_url}
                            alt={"#{option.title} poster"}
                            class="w-16 h-24 object-cover rounded-md shadow-sm mr-4 flex-shrink-0"
                            loading="lazy"
                          />
                        <% end %>

                        <div class="flex-1 min-w-0">
                          <div class="flex items-center">
                            <h4 class="text-sm font-medium text-gray-900 truncate">
                              <%= cond do %>
                                <% @poll.poll_type == "time" -> %>
                                  <%= format_time_for_display(option.title) %>
                                <% @poll.poll_type == "date_selection" -> %>
                                  <span class="inline-flex items-center group">
                                    <svg class="w-4 h-4 mr-1 text-gray-500 group-hover:text-indigo-600 transition-colors duration-200" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                                    </svg>
                                    <span class="group-hover:text-indigo-600 transition-colors duration-200"><%= option.title %></span>
                                  </span>
                                <% true -> %>
                                  <%= option.title %>
                              <% end %>
                            </h4>
                            <%= if option.status == "hidden" do %>
                              <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                                Hidden
                              </span>
                            <% end %>
                          </div>

                          <%= if option.description do %>
                            <p class="mt-1 text-sm text-gray-500"><%= option.description %></p>
                          <% end %>

                          <div class="mt-2 flex items-center text-xs text-gray-500">
                            <span>Suggested by <%= option.suggested_by.name || option.suggested_by.username %></span>
                            <span class="mx-1">•</span>
                            <span><%= format_relative_time(option.inserted_at) %></span>
                            <%= if @poll.poll_type not in ["time", "date_selection"] do %>
                              <span class="mx-1">•</span>
                              <span>Order: <%= option.order_index %></span>
                            <% end %>
                          </div>
                        </div>
                      </div>
                    </div>

                  <!-- Option Actions -->
                  <div class="ml-4 flex-shrink-0 flex items-center space-x-2 option-card-actions">
                    <%= if @is_creator || option.suggested_by_id == @user.id do %>
                      <!-- Edit option button -->
                      <button
                        type="button"
                        phx-click="edit_option"
                        phx-value-option-id={option.id}
                        phx-target={@myself}
                        class="text-indigo-600 hover:text-indigo-900 text-sm font-medium touch-target interactive-element"
                      >
                        Edit
                      </button>
                    <% end %>

                    <%= if @is_creator do %>
                      <!-- Remove option button -->
                      <button
                        type="button"
                        phx-click="remove_option"
                        phx-value-option-id={option.id}
                        phx-target={@myself}
                        data-confirm="Are you sure you want to remove this option? This action cannot be undone."
                        class="text-red-600 hover:text-red-900 text-sm font-medium touch-target interactive-element"
                      >
                        Remove
                      </button>
                    <% end %>
                  </div>
                </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Phase Info Footer -->
      <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
        <div class="flex items-center justify-between">
          <div class="text-sm text-gray-500">
            <%= safe_poll_options_count(@poll.poll_options) %> <%= option_type_text(@poll.poll_type) %> suggested
            <%= if @poll.list_building_deadline do %>
              • Deadline: <%= format_deadline(@poll.list_building_deadline) %>
            <% end %>
          </div>

                                <%= if @is_creator && safe_poll_options_count(@poll.poll_options) > 0 && @poll.phase != "closed" do %>
            <div class="relative inline-block text-left" phx-click-away="close_phase_dropdown" phx-target={@myself}>
              <div>
                <button
                  type="button"
                  phx-click="toggle_phase_dropdown"
                  phx-target={@myself}
                  class="inline-flex items-center justify-center w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                  id="phase-menu-button"
                  aria-expanded={to_string(Map.get(assigns, :show_phase_dropdown, false))}
                  aria-haspopup="true"
                >
                  <svg class="-ml-1 mr-2 h-4 w-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <%= if @poll.phase in ["voting", "voting_with_suggestions", "voting_only"] do %>
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    <% else %>
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4" />
                    <% end %>
                  </svg>
                  <%= get_phase_display_name(@poll.phase) %>
                  <svg class={"-mr-1 ml-2 h-5 w-5 transition-transform #{if Map.get(assigns, :show_phase_dropdown, false), do: "rotate-180", else: ""}"} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                    <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
                  </svg>
                </button>
              </div>

              <div
                class={"origin-top-right absolute right-0 mt-2 w-56 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5 focus:outline-none z-10 #{if Map.get(assigns, :show_phase_dropdown, false), do: "", else: "hidden"}"}
                role="menu"
                aria-orientation="vertical"
                aria-labelledby="phase-menu-button"
                tabindex="-1"
              >
                <div class="py-1" role="none">
                  <!-- Phase transitions based on current phase -->
                  <%= case @poll.phase do %>
                    <% "list_building" -> %>
                      <!-- From list_building, can go to either voting phase or close -->
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="voting_with_suggestions"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-gray-400 group-hover:text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                        <div>
                          <div>Start Voting</div>
                          <div class="text-xs text-gray-500">+ add suggestions</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="voting_only"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-gray-400 group-hover:text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                        <div>
                          <div>Voting Only</div>
                          <div class="text-xs text-gray-500">no suggestions</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="closed"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-red-400 group-hover:text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                        <div>
                          <div>Close Poll</div>
                          <div class="text-xs text-gray-500">skip voting</div>
                        </div>
                      </button>

                    <% "voting_with_suggestions" -> %>
                      <!-- From voting_with_suggestions, can switch to voting only, close, or back to building (if no votes) -->
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="voting_only"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-amber-400 group-hover:text-amber-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728L5.636 5.636m12.728 12.728L5.636 5.636" />
                        </svg>
                        <div>
                          <div>Disable Suggestions</div>
                          <div class="text-xs text-gray-500">voting only</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="list_building"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-blue-400 group-hover:text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4" />
                        </svg>
                        <div>
                          <div>Back to Building</div>
                          <div class="text-xs text-gray-500">if no votes yet</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="closed"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-red-400 group-hover:text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                        <div>
                          <div>Close Poll</div>
                          <div class="text-xs text-gray-500">end voting</div>
                        </div>
                      </button>

                    <% "voting_only" -> %>
                      <!-- From voting_only, can enable suggestions, go back to building (if no votes), or close -->
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="voting_with_suggestions"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-green-400 group-hover:text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                        </svg>
                        <div>
                          <div>Enable Suggestions</div>
                          <div class="text-xs text-gray-500">+ add suggestions</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="list_building"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-blue-400 group-hover:text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4" />
                        </svg>
                        <div>
                          <div>Back to Building</div>
                          <div class="text-xs text-gray-500">if no votes yet</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="closed"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-red-400 group-hover:text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                        <div>
                          <div>Close Poll</div>
                          <div class="text-xs text-gray-500">end voting</div>
                        </div>
                      </button>

                    <% "voting" -> %>
                      <!-- Legacy voting phase - can go back to building, upgrade to enhanced phases, or close -->
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="voting_with_suggestions"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-green-400 group-hover:text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                        </svg>
                        <div>
                          <div>Enhanced Voting</div>
                          <div class="text-xs text-gray-500">+ add suggestions</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="voting_only"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-amber-400 group-hover:text-amber-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728L5.636 5.636m12.728 12.728L5.636 5.636" />
                        </svg>
                        <div>
                          <div>Voting Only</div>
                          <div class="text-xs text-gray-500">no suggestions</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="list_building"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-blue-400 group-hover:text-blue-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4" />
                        </svg>
                        <div>
                          <div>Back to Building</div>
                          <div class="text-xs text-gray-500">if no votes yet</div>
                        </div>
                      </button>
                      <button
                        type="button"
                        phx-click="change_poll_phase"
                        phx-value-phase="closed"
                        phx-target={@myself}
                        class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
                        role="menuitem"
                      >
                        <svg class="mr-2 h-4 w-4 text-red-400 group-hover:text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                        <div>
                          <div>Close Poll</div>
                          <div class="text-xs text-gray-500">end voting</div>
                        </div>
                      </button>

                    <% "closed" -> %>
                      <!-- Closed phase - no transitions allowed -->
                      <div class="px-3 py-2 text-sm text-gray-500 text-center">
                        <div>Poll is closed</div>
                        <div class="text-xs">No further changes allowed</div>
                      </div>

                    <% _ -> %>
                      <!-- Unknown phases -->
                      <div class="px-3 py-2 text-sm text-gray-500 text-center">
                        <div>Unknown phase</div>
                        <div class="text-xs">Contact support</div>
                      </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_suggestion_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:suggestion_form_visible, !socket.assigns.suggestion_form_visible)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:selected_dates, [])
     # Clear time selection state when toggling form
     |> assign(:time_enabled, false)
     |> assign(:selected_date_for_time, nil)
     |> assign(:date_time_slots, %{})}
  end

  # NEW: Time selection event handlers
  @impl true
  def handle_event("toggle_time_selection", _params, socket) do
    {:noreply, assign(socket, :time_enabled, !socket.assigns.time_enabled)}
  end

  @impl true
  def handle_event("configure_date_time", %{"date" => date_string}, socket) do
    {:noreply, assign(socket, :selected_date_for_time, date_string)}
  end

  @impl true
  def handle_event("save_date_time_slots", %{"date" => date_string, "time_slots" => time_slots}, socket) do
    updated_slots = Map.put(socket.assigns.date_time_slots, date_string, time_slots)
    {:noreply,
     socket
     |> assign(:date_time_slots, updated_slots)
     |> assign(:selected_date_for_time, nil)}
  end

  @impl true
  def handle_event("cancel_time_config", _params, socket) do
    {:noreply, assign(socket, :selected_date_for_time, nil)}
  end



  @impl true
  def handle_event("cancel_suggestion", _params, socket) do
    changeset = PollOption.changeset(%PollOption{}, %{
      poll_id: socket.assigns.poll.id,
      suggested_by_id: socket.assigns.user.id,
      status: "active"
    })

    {:noreply,
     socket
     |> assign(:suggestion_form_visible, false)
     |> assign(:changeset, changeset)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:selected_dates, [])
     # Clear time selection state when cancelling
     |> assign(:time_enabled, false)
     |> assign(:selected_date_for_time, nil)
     |> assign(:date_time_slots, %{})}
  end

  @impl true
  def handle_event("search_movies", %{"poll_option" => %{"title" => query}} = _params, socket) do
    # Only search if this is a movie poll
    if socket.assigns.poll.poll_type == "movie" do
      if String.length(String.trim(query)) >= 2 do
        # Set loading state
        socket = assign(socket, :search_loading, true)

        # Use the centralized RichDataManager system (same as PublicMoviePollComponent)
        search_options = %{
          providers: [:tmdb],
          limit: 5,
          content_type: :movie
        }

        case RichDataManager.search(query, search_options) do
          {:ok, results_by_provider} ->
            # Extract movie results from TMDB provider
            movie_results = case Map.get(results_by_provider, :tmdb) do
              {:ok, results} when is_list(results) -> results
              {:ok, result} -> [result]
              _ -> []
            end

            {:noreply,
             socket
             |> assign(:search_query, query)
             |> assign(:search_results, movie_results)
             |> assign(:search_loading, false)}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:search_query, query)
             |> assign(:search_results, [])
             |> assign(:search_loading, false)}
        end
      else
        {:noreply,
         socket
         |> assign(:search_query, query)
         |> assign(:search_results, [])
         |> assign(:search_loading, false)}
      end
    else
      {:noreply, socket}
    end
  end

  # Fallback handler for search_movies in case parameters don't match expected format
  @impl true
  def handle_event("search_movies", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_movie", %{"movie-id" => movie_id}, socket) do
    # Find the selected movie in search results
    movie_data = socket.assigns.search_results
    |> Enum.find(fn movie ->
      # Handle both string and integer movie_id formats
      case Integer.parse(movie_id) do
        {id, _} -> movie.id == id
        :error -> to_string(movie.id) == movie_id
      end
    end)

    if movie_data do
      # Set loading state for rich data
      socket = assign(socket, :loading_rich_data, true)

      # Use the centralized RichDataManager to get detailed movie data
      case RichDataManager.get_cached_details(:tmdb, movie_data.id, :movie) do
        {:ok, rich_movie_data} ->
          # Use the shared MovieDataService to prepare movie data consistently
          prepared_data = MovieDataService.prepare_movie_option_data(
            movie_data.id,
            rich_movie_data
          )

          # Create changeset with the rich data
          changeset = create_option_changeset(socket, prepared_data)

          {:noreply,
           socket
           |> assign(:changeset, changeset)
           |> assign(:loading_rich_data, false)
           |> assign(:search_results, [])
           |> assign(:search_query, "")}

        {:error, _reason} ->
          # Fallback to basic movie data if rich data fetch fails
          fallback_data = %{
            "title" => movie_data.title,
            "description" => movie_data.description || "",
            "external_id" => to_string(movie_data.id)
          }

          changeset = create_option_changeset(socket, fallback_data)

          {:noreply,
           socket
           |> assign(:changeset, changeset)
           |> assign(:loading_rich_data, false)
           |> assign(:search_results, [])
           |> assign(:search_query, "")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_suggestion", %{"poll_option" => option_params}, socket) do
    changeset = create_option_changeset(socket, option_params)
    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("submit_suggestion", %{"poll_option" => option_params}, socket) do
    socket = assign(socket, :loading, true)

    # Log submission for debugging if needed
    require Logger
    Logger.debug("Submitting suggestion for poll type: #{socket.assigns.poll.poll_type}, selected dates count: #{length(socket.assigns.selected_dates || [])}")

    # Special handling for date_selection polls
    if socket.assigns.poll.poll_type == "date_selection" && length(socket.assigns.selected_dates) > 0 do
      # Create multiple poll options, one for each selected date
      results = socket.assigns.selected_dates
      |> Enum.map(fn selected_date ->
        # Create metadata structure for date_selection polls using proper builder
        date_metadata_base = EventasaurusApp.Events.DateMetadata.build_date_metadata(
          selected_date,
          [display_date: format_date_for_display(selected_date)]
        )

        # Add time slot information if time is enabled
        date_metadata = if socket.assigns.time_enabled do
          date_iso = Date.to_iso8601(selected_date)
          time_slots = Map.get(socket.assigns.date_time_slots, date_iso, [])

          # Only set time_enabled true if there are actually time slots
          if length(time_slots) > 0 do
            Map.merge(date_metadata_base, %{
              "time_enabled" => true,
              "time_slots" => time_slots,
              "all_day" => false
            })
          else
            Map.merge(date_metadata_base, %{
              "time_enabled" => false,
              "all_day" => true,
              "time_slots" => []
            })
          end
        else
          Map.merge(date_metadata_base, %{
            "time_enabled" => false,
            "all_day" => true,
            "time_slots" => []
          })
        end

        # Create params for this specific date
        date_params = Map.merge(option_params, %{
          "title" => format_date_for_option_title(selected_date),
          "description" => option_params["description"] || "",
          "metadata" => date_metadata  # Pass as map, not JSON string!
        })

        result = save_option(socket, date_params)
        Logger.debug("Date save result: #{selected_date} -> #{inspect(result)}")
        result
      end)

      # Log the batch save results
      Logger.debug("Batch date save results: #{inspect(results)}")

      # Check if all saves were successful
      successful_options = results
        |> Enum.filter(fn result ->
          case result do
            {:ok, _} -> true
            _ -> false
          end
        end)
        |> Enum.map(fn {:ok, option} -> option end)

      failed_count = length(results) - length(successful_options)

      Logger.debug("Date saves completed: #{length(successful_options)}/#{length(socket.assigns.selected_dates)} successful, #{failed_count} failed")

      if length(successful_options) == length(socket.assigns.selected_dates) do
        # All dates saved successfully
        poll = socket.assigns.poll
        user = socket.assigns.user

        # Broadcast for each successful option
        Enum.each(successful_options, fn option ->
          duplicate_options = check_for_duplicates(poll, option)
          if length(duplicate_options) > 0 do
            PollPubSubService.broadcast_duplicate_detected(poll, option, duplicate_options, user)
          else
            PollPubSubService.broadcast_option_suggested(poll, option, user)
          end
          send(self(), {:option_suggested, option})
        end)

        # Reset form after successful submission
        changeset = PollOption.changeset(%PollOption{}, %{
          poll_id: socket.assigns.poll.id,
          suggested_by_id: socket.assigns.user.id,
          status: "active"
        })

        # Show success message
        success_message = case length(successful_options) do
          1 -> "Date added successfully!"
          n -> "#{n} dates added successfully!"
        end

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:suggestion_form_visible, false)
         |> assign(:selected_dates, [])  # Clear selected dates after successful submission
         # Clear time selection state after successful submission
         |> assign(:time_enabled, false)
         |> assign(:selected_date_for_time, nil)
         |> assign(:date_time_slots, %{})
         |> assign(:changeset, changeset)
         |> assign(:loading_rich_data, false)
         |> put_flash(:info, success_message)}
      else
        # Handle errors - show which dates failed
        failed_results = results
          |> Enum.with_index()
          |> Enum.filter(fn {result, _} ->
            case result do
              {:ok, _} -> false
              _ -> true
            end
          end)
          |> Enum.map(fn {result, index} ->
            date = Enum.at(socket.assigns.selected_dates, index)
            case result do
              {:error, %{suggestion_limit: [message]}} -> {date, message}
              {:error, changeset} -> {date, changeset}
              _ -> {date, "Unknown error"}
            end
          end)

        Logger.error("Failed to save dates: #{inspect(failed_results |> Enum.map(fn
          {date, changeset} when is_map(changeset) and is_map_key(changeset, :errors) -> {date, changeset.errors}
          {date, message} -> {date, message}
        end))}")

        # Check if any errors are suggestion limit errors
        suggestion_limit_errors = failed_results
          |> Enum.any?(fn {_, error} -> is_binary(error) && String.contains?(error, "suggestion limit") end)

        error_message = if suggestion_limit_errors do
          "You have reached your suggestion limit. Please remove some suggestions before adding new ones."
        else
          "Failed to save #{failed_count} date(s). Please try again."
        end

        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, error_message)}
      end
    else
      # Non-date polls - use original single option logic
      enriched_params = extract_rich_data_from_changeset(socket.assigns.changeset, option_params)

      case save_option(socket, enriched_params) do
        {:ok, option} ->
          # Broadcast option suggestion via PubSub
          poll = socket.assigns.poll
          user = socket.assigns.user

          # Check for duplicates if the service is available
          duplicate_options = check_for_duplicates(poll, option)

          if length(duplicate_options) > 0 do
            PollPubSubService.broadcast_duplicate_detected(poll, option, duplicate_options, user)
          else
            PollPubSubService.broadcast_option_suggested(poll, option, user)
          end

          send(self(), {:option_suggested, option})

          # Reset form
          changeset = PollOption.changeset(%PollOption{}, %{
            poll_id: socket.assigns.poll.id,
            suggested_by_id: socket.assigns.user.id,
            status: "active"
          })

          {:noreply,
           socket
           |> assign(:loading, false)
           |> assign(:suggestion_form_visible, false)
           |> assign(:selected_dates, [])  # Clear selected dates after successful submission
           # Clear time selection state after successful submission
           |> assign(:time_enabled, false)
           |> assign(:selected_date_for_time, nil)
           |> assign(:date_time_slots, %{})
           |> assign(:changeset, changeset)
           |> assign(:loading_rich_data, false)}

        {:error, %{suggestion_limit: [message]}} ->
          {:noreply,
           socket
           |> assign(:loading, false)
           |> put_flash(:error, message)}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(:loading, false)
           |> assign(:changeset, changeset)}
      end
    end
  end

  @impl true
  def handle_event("remove_option", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        case Events.get_poll_option(option_id_int) do
          nil ->
            send(self(), {:show_error, "Option not found"})
            {:noreply, socket}

          poll_option ->
            case Events.delete_poll_option(poll_option) do
              {:ok, _} ->
                # For option removal, we could broadcast a bulk moderation action
                # or handle it as a special case
                send(self(), {:option_removed, option_id})
                {:noreply, socket}

              {:error, _} ->
                send(self(), {:show_error, "Failed to remove option"})
                {:noreply, socket}
            end
        end

      {:error, _} ->
        send(self(), {:show_error, "Invalid option ID"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edit_option", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        option = case socket.assigns.poll.poll_options do
          %Ecto.Association.NotLoaded{} -> nil
          poll_options when is_list(poll_options) ->
            Enum.find(poll_options, fn opt -> opt.id == option_id_int end)
          _ -> nil
        end

        if option do
          edit_changeset = PollOption.changeset(option, %{})
          {:noreply,
           socket
           |> assign(:editing_option_id, option_id_int)
           |> assign(:edit_changeset, edit_changeset)}
        else
          send(self(), {:show_error, "Option not found"})
          {:noreply, socket}
        end
      {:error, _reason} ->
        send(self(), {:show_error, "Invalid option ID"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_option_id, nil)}
  end

  @impl true
  def handle_event("validate_edit", %{"poll_option" => option_params}, socket) do
    # Add nil check before accessing editing_option_id
    if socket.assigns.editing_option_id do
      option = case socket.assigns.poll.poll_options do
        %Ecto.Association.NotLoaded{} -> nil
        poll_options when is_list(poll_options) ->
          Enum.find(poll_options, fn opt -> opt.id == socket.assigns.editing_option_id end)
        _ -> nil
      end

      if option do
        changeset = PollOption.changeset(option, option_params)
        {:noreply, assign(socket, :edit_changeset, changeset)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_edit", %{"poll_option" => option_params, "option_id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        case Events.get_poll_option(option_id_int) do
          %PollOption{} = option ->
            # Handle status field - checkbox sends "hidden" when checked, nothing when unchecked
            updated_params = case Map.get(option_params, "status") do
              "hidden" -> option_params
              _ -> Map.put(option_params, "status", "active")
            end

            case Events.update_poll_option(option, updated_params) do
              {:ok, updated_option} ->
                # Broadcast visibility change if status changed
                if option.status != updated_option.status do
                  status_atom = case updated_option.status do
                    "hidden" -> :hidden
                    "active" -> :shown
                    _ -> :shown
                  end

                  PollPubSubService.broadcast_option_visibility_changed(
                    socket.assigns.poll,
                    updated_option,
                    status_atom,
                    socket.assigns.user
                  )
                end

                send(self(), {:option_updated, updated_option})
                {:noreply, assign(socket, :editing_option_id, nil)}

              {:error, changeset} ->
                {:noreply, assign(socket, :edit_changeset, changeset)}
            end

          nil ->
            {:noreply, put_flash(socket, :error, "Option not found")}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Invalid option ID")}
    end
  end

  @impl true
  def handle_event("toggle_phase_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_phase_dropdown, !Map.get(socket.assigns, :show_phase_dropdown, false))}
  end

  @impl true
  def handle_event("close_phase_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_phase_dropdown, false)}
  end

  @impl true
  def handle_event("change_poll_phase", %{"phase" => new_phase}, socket) do
    old_phase = socket.assigns.poll.phase

    case Events.transition_poll_phase(socket.assigns.poll, new_phase) do
      {:ok, poll} ->
        # Broadcast phase change via PubSub
        PollPubSubService.broadcast_poll_phase_changed(
          poll,
          old_phase,
          new_phase,
          socket.assigns.user
        )

        phase_message = case new_phase do
          "voting_with_suggestions" -> "Voting phase started! Users can vote and add suggestions."
          "voting_only" -> "Voting phase started! Suggestions are now disabled."
          "voting" -> "Voting phase started!"  # Legacy support
          "list_building" -> "Switched back to building phase"
          "closed" -> "Poll has been closed"
          _ -> "Poll phase changed"
        end

        send(self(), {:poll_phase_changed, poll, phase_message})
        {:noreply, assign(socket, :show_phase_dropdown, false)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to change poll phase"})
        {:noreply, assign(socket, :show_phase_dropdown, false)}
    end
  end

  @impl true
  def handle_event("reorder_option", params, socket) do
    # Defensive parameter validation - this is the root cause of crashes
    with {:ok, dragged_id} <- validate_param(params, "dragged_option_id"),
         {:ok, target_id} <- validate_param(params, "target_option_id"),
         {:ok, direction} <- validate_param(params, "direction"),
         true <- socket.assigns.is_creator do

      case Events.reorder_poll_option(dragged_id, target_id, direction) do
        {:ok, updated_poll} ->
          # Broadcast options reordered via PubSub
          PollPubSubService.broadcast_options_reordered(
            socket.assigns.poll,
            updated_poll.poll_options,
            socket.assigns.user
          )

          # Success - LiveView will receive poll update via PubSub
          send(self(), {:option_reordered, "Options reordered successfully"})
          {:noreply, socket}

        {:error, reason} ->
          # Send rollback command to JavaScript hook and show error
          socket = push_event(socket, "rollback_order", %{})
          send(self(), {:show_error, "Failed to reorder options: #{reason}"})
          {:noreply, socket}
      end
    else
            {:error, field} ->
        # Invalid parameters - send rollback
        socket = push_event(socket, "rollback_order", %{})
        send(self(), {:show_error, "Invalid parameter: #{field}"})
        {:noreply, socket}

      false ->
        # User doesn't have permission - send rollback
        socket = push_event(socket, "rollback_order", %{})
        send(self(), {:show_error, "You don't have permission to reorder options"})
        {:noreply, socket}
    end
  end

  # Calendar functionality event handlers for date_selection polls
  @impl true
  def handle_event("calendar_date_selected", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        # For suggestion form, we only allow one date at a time
        {:noreply, assign(socket, :selected_dates, [date])}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_date", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        current_dates = socket.assigns.selected_dates || []

        updated_dates = if date in current_dates do
          # Remove date if already selected
          List.delete(current_dates, date)
        else
          # Add date if not selected (for suggestion form, limit to one date)
          [date]
        end

        # Log date toggle for debugging
        Logger.debug("Date toggled: #{date_string} -> #{inspect(updated_dates)}")

        {:noreply, assign(socket, :selected_dates, updated_dates)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

    # Handle calendar events sent from CalendarComponent
  def handle_info({:calendar_event, "calendar_date_selected", %{dates: dates}}, socket) do
    {:noreply, assign(socket, :selected_dates, dates)}
  end





  # Private helper functions

  # Create changeset for option validation - handles date_selection polls specially
  defp create_option_changeset(socket, option_params) do
    base_changeset = PollOption.changeset(%PollOption{}, %{
      poll_id: socket.assigns.poll.id,
      suggested_by_id: socket.assigns.user.id,
      status: "active"
    })

    # For date_selection polls, enhance params with selected date info
    enhanced_params = if socket.assigns.poll.poll_type == "date_selection" && length(socket.assigns.selected_dates) > 0 do
      selected_date = List.first(socket.assigns.selected_dates)

      # Create metadata structure for date_selection polls
      date_metadata_base = %{
        "date" => Date.to_iso8601(selected_date),
        "display_date" => format_date_for_display(selected_date),
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      # Add time slot information if time is enabled
      date_metadata = if socket.assigns.time_enabled do
        date_iso = Date.to_iso8601(selected_date)
        time_slots = Map.get(socket.assigns.date_time_slots, date_iso, [])

        # Only set time_enabled true if there are actually time slots
        if length(time_slots) > 0 do
          Map.merge(date_metadata_base, %{
            "time_enabled" => true,
            "time_slots" => time_slots,
            "all_day" => false
          })
        else
          Map.merge(date_metadata_base, %{
            "time_enabled" => false,
            "all_day" => true,
            "time_slots" => []
          })
        end
      else
        Map.merge(date_metadata_base, %{
          "time_enabled" => false,
          "all_day" => true,
          "time_slots" => []
        })
      end

      # Override the option params with date-specific data
      Map.merge(option_params, %{
        "title" => format_date_for_option_title(selected_date),
        "description" => option_params["description"] || "",
        "metadata" => date_metadata  # Pass as map, not JSON string!
      })
    else
      option_params
    end

    PollOption.changeset(base_changeset.data, enhanced_params)
  end

  # Defensive parameter validation to prevent crashes
  defp validate_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      nil -> {:error, "#{key} is missing"}
      "" -> {:error, "#{key} is empty"}
      value when is_binary(value) -> {:ok, value}
      value when is_integer(value) -> {:ok, to_string(value)}
      _other -> {:error, "#{key} has invalid type"}
    end
  end

  defp validate_param(_params, key), do: {:error, "params is not a map for #{key}"}



  defp extract_rich_data_from_changeset(changeset, option_params) do
    require Logger

    # For movie polls, the changeset may contain rich TMDB data that was loaded
    # but not included in the HTML form. Extract and merge it.
    case changeset do
      %Ecto.Changeset{changes: changes} ->
        # Extract rich data fields from changeset if present
        external_id = Map.get(changes, :external_id)
        external_data = Map.get(changes, :external_data)
        image_url = Map.get(changes, :image_url)

        Logger.debug("Extracting rich data from changeset:")
        Logger.debug("  external_id: #{inspect(external_id)}")
        Logger.debug("  external_data present: #{inspect(external_data != nil)}")
        Logger.debug("  image_url: #{inspect(image_url)}")

        # Merge with form params, giving priority to rich data from changeset over form
        enriched_params = option_params
        |> maybe_put_param("external_id", external_id)
        |> maybe_put_param("external_data", external_data)
        |> maybe_put_param("image_url", image_url)
        |> decode_external_data_if_needed()

        Logger.debug("Enriched params after extraction:")
        Logger.debug("  has external_id: #{inspect(Map.has_key?(enriched_params, "external_id"))}")
        Logger.debug("  has external_data: #{inspect(Map.has_key?(enriched_params, "external_data"))}")
        Logger.debug("  has image_url: #{inspect(Map.has_key?(enriched_params, "image_url"))}")

        enriched_params

      _ ->
        Logger.debug("No changeset or changeset without changes")
        option_params |> decode_external_data_if_needed()
    end
  end

  defp decode_external_data_if_needed(params) do
    # Handle the case where external_data comes as a JSON string from the form
    case Map.get(params, "external_data") do
      data when is_binary(data) ->
        case Jason.decode(data) do
          {:ok, decoded} -> Map.put(params, "external_data", decoded)
          {:error, _} -> params
        end
      _ ->
        params
    end
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, ""), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  # Template helper functions
  
  # Sort poll options based on poll type
  defp sort_poll_options(poll_options, poll_type) do
    options = safe_poll_options(poll_options)
    
    case poll_type do
      "date_selection" ->
        # Sort date selection polls chronologically
        Enum.sort_by(options, fn option ->
          case DatePollAdapter.extract_date_from_option(option) do
            {:ok, date} -> date
            _ -> ~D[9999-12-31]  # Put invalid dates at the end
          end
        end, Date)
      
      "time" ->
        # Sort time polls by their time value
        Enum.sort_by(options, fn option ->
          TimeUtils.parse_time_for_sort(option.title)
        end)
      
      _ ->
        # For other poll types, keep the existing order (by order_index)
        options
    end
  end



  # Helper function to safely handle poll_options that might be NotLoaded
  defp safe_poll_options(%Ecto.Association.NotLoaded{}), do: []
  defp safe_poll_options(poll_options) when is_list(poll_options), do: poll_options
  defp safe_poll_options(_), do: []

  # Helper function to safely get the count of poll options
  defp safe_poll_options_count(%Ecto.Association.NotLoaded{}), do: 0
  defp safe_poll_options_count(poll_options) when is_list(poll_options), do: length(poll_options)
  defp safe_poll_options_count(_), do: 0

  # Helper function to safely check if poll options are empty
  defp safe_poll_options_empty?(%Ecto.Association.NotLoaded{}), do: true
  defp safe_poll_options_empty?(poll_options) when is_list(poll_options), do: Enum.empty?(poll_options)
  defp safe_poll_options_empty?(_), do: true

  # Helper function to calculate user's current suggestion count
  defp calculate_user_suggestion_count(%Ecto.Association.NotLoaded{}, _user_id), do: 0
  defp calculate_user_suggestion_count(poll_options, user_id) when is_list(poll_options) do
    Enum.count(poll_options, fn option ->
      option.suggested_by_id == user_id && option.status == "active"
    end)
  end
  defp calculate_user_suggestion_count(_, _user_id), do: 0



  defp save_option(socket, option_params) do
    require Logger

    # Check suggestion limit for non-creators
    if !socket.assigns.is_creator && socket.assigns.poll.max_options_per_user do
      user_suggestion_count = calculate_user_suggestion_count(socket.assigns.poll.poll_options, socket.assigns.user.id)
      if user_suggestion_count >= socket.assigns.poll.max_options_per_user do
        Logger.warning("User #{socket.assigns.user.id} attempted to exceed suggestion limit #{socket.assigns.poll.max_options_per_user}")
        {:error, %{suggestion_limit: ["You have reached your suggestion limit of #{socket.assigns.poll.max_options_per_user}"]}}
      else
        do_save_option(socket, option_params)
      end
    else
      do_save_option(socket, option_params)
    end
  end

  defp do_save_option(socket, option_params) do
    # Ensure ALL movie options get consistent data structure with fallback logic
    option_params = if socket.assigns.poll.poll_type == "movie" &&
                      Map.has_key?(option_params, "external_data") &&
                      not is_nil(option_params["external_data"]) &&
                      not has_enhanced_description?(option_params["description"]) do

      # Apply MovieDataService for movie options
      movie_id = option_params["external_id"] ||
                 get_in(option_params, ["external_data", "id"]) ||
                 get_in(option_params, ["external_data", :id])
      rich_data = option_params["external_data"]

      Logger.debug("Admin interface applying MovieDataService fallback for movie_id: #{movie_id}")

      if movie_id && rich_data do
        prepared_data = MovieDataService.prepare_movie_option_data(movie_id, rich_data)

        # Preserve any user-provided custom title/description over generated ones
        final_data = prepared_data
        |> maybe_preserve_user_input("title", option_params["title"])
        |> maybe_preserve_user_input("description", option_params["description"])

        Logger.debug("MovieDataService fallback applied successfully")
        final_data
      else
        Logger.debug("MovieDataService fallback skipped - missing movie_id or rich_data")
        option_params
      end
    else
      # Handle places options with PlacesDataService
      if socket.assigns.poll.poll_type == "places" &&
         Map.has_key?(option_params, "external_data") &&
         not is_nil(option_params["external_data"]) do

        Logger.debug("Processing places option with PlacesDataService")

        # Parse external_data if it's a JSON string
        external_data = case option_params["external_data"] do
          data when is_binary(data) ->
            case Jason.decode(data) do
              {:ok, decoded} -> decoded
              {:error, _} -> option_params["external_data"]
            end
          data -> data
        end

        if external_data && is_map(external_data) do
          prepared_data = PlacesDataService.prepare_place_option_data(external_data)

          # Preserve any user-provided custom title/description over generated ones
          final_data = prepared_data
          |> maybe_preserve_user_input("title", option_params["title"])
          |> maybe_preserve_user_input("description", option_params["description"])

          Logger.debug("PlacesDataService applied successfully for place: #{final_data["title"]}")
          final_data
        else
          Logger.debug("PlacesDataService skipped - invalid external_data")
          option_params
        end
      else
        # Non-movie/places options or already properly prepared options
        option_params
      end
    end

    final_option_params = Map.merge(option_params, %{
      "poll_id" => socket.assigns.poll.id,
      "suggested_by_id" => socket.assigns.user.id,
      "status" => "active"
    })

    Logger.debug("Admin interface saving option with title: #{final_option_params["title"]}")
    Logger.debug("Admin interface image_url: #{inspect(final_option_params["image_url"])}")
    Logger.debug("Admin interface external_id: #{inspect(final_option_params["external_id"])}")
    Logger.debug("Admin interface description preview: #{String.slice(final_option_params["description"] || "", 0, 100)}...")

    Events.create_poll_option(final_option_params, [poll_type: socket.assigns.poll.poll_type])
  end

  # Helper to detect if description has been enhanced (contains director/year pattern)
  defp has_enhanced_description?(description) when is_binary(description) do
    String.contains?(description, " • Directed by ") || String.contains?(description, " • ")
  end
  defp has_enhanced_description?(_), do: false

  # Helper to preserve user input over generated content
  defp maybe_preserve_user_input(prepared_data, key, user_value) when is_binary(user_value) and user_value != "" do
    Map.put(prepared_data, key, user_value)
  end
  defp maybe_preserve_user_input(prepared_data, _key, _user_value), do: prepared_data

  # Helper function to extract poster URL from movie data
  defp get_movie_poster_url(movie) do
    cond do
      # Check if movie has image_url field (fallback/legacy)
      Map.has_key?(movie, :image_url) && movie.image_url ->
        movie.image_url

      # Check if movie has images array (new structure)
      Map.has_key?(movie, :images) && is_list(movie.images) ->
        poster_image = Enum.find(movie.images, fn image ->
          Map.get(image, :type) == :poster
        end)
        if poster_image, do: Map.get(poster_image, :url), else: nil

      # Check metadata for poster_path (legacy TMDB structure)
      movie.metadata && movie.metadata["poster_path"] ->
        "https://image.tmdb.org/t/p/w92#{movie.metadata["poster_path"]}"

      true ->
        nil
    end
  end

  # UI helper functions

  defp suggest_button_text(poll_type) do
    case poll_type do
      "movie" -> "Suggest Movie"
      "places" -> "Suggest Place"
          "time" -> "Add Time"
      _ -> "Add Option"
    end
  end

  defp option_title_label(poll_type) do
    case poll_type do
      "movie" -> "Movie Title"
      "places" -> "Place Name"
          "time" -> "Time"
      _ -> "Option Title"
    end
  end

  defp option_title_placeholder(poll_type) do
    case poll_type do
      "movie" -> "Start typing to search movies..."
      "places" -> "Start typing to search places..."
          "time" -> "Select a time..."
      _ -> "Enter your option (e.g., Option A, Choice 1, etc.)"
    end
  end

  defp option_description_placeholder(poll_type) do
    case poll_type do
      "movie" -> "Brief plot summary or why you recommend it..."
      "places" -> "Cuisine type, location, or special notes..."
          "time" -> "" # No description for time polls
      _ -> "Additional details or context..."
    end
  end

  defp option_type_text(poll_type) do
    case poll_type do
      "movie" -> "movies"
      "places" -> "places"
      "time" -> "times"
      "date_selection" -> "dates"
      _ -> "options"
    end
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()

    # Convert NaiveDateTime to DateTime if needed
    datetime_utc = case datetime do
      %DateTime{} = dt -> dt
      %NaiveDateTime{} = ndt ->
        case DateTime.from_naive(ndt, "Etc/UTC") do
          {:ok, dt} -> dt
          {:error, _} -> DateTime.utc_now()
        end
      _ ->
        # Log unexpected type for debugging
        require Logger
        Logger.warning("Unexpected datetime type in format_relative_time: #{inspect(datetime)}")
        DateTime.utc_now()
    end

    diff = DateTime.diff(now, datetime_utc, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp format_deadline(deadline) do
    case deadline do
      %DateTime{} = dt ->
        dt
        |> DateTime.to_date()
        |> Date.to_string()

      _ -> "Not set"
    end
  end

  defp check_for_duplicates(_poll, _option) do
    # For now, return empty list - duplicate detection can be enhanced later
    # In a full implementation, this would use the DuplicateDetectionService
    []
  end

  defp safe_string_to_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp safe_string_to_integer(_), do: {:error, :invalid_input}

  # Helper function to determine if a poll type should use API search
  defp should_use_api_search?(poll_type) do
    poll_type in ["movie", "places", "time"]
  end

  # New helper functions for empty state
  defp get_empty_state_title(poll_type) do
    case poll_type do
      "movie" -> "No Movies Suggested Yet"
      "places" -> "No Places Suggested Yet"
          "time" -> "No Times Suggested Yet"
      _ -> "No Options Suggested Yet"
    end
  end

  defp get_empty_state_description(poll_type, voting_system) do
    type_text = option_type_text(poll_type)

    case voting_system do
      "binary" -> "Be the first to suggest #{type_text} for yes/no voting!"
      "approval" -> "Be the first to suggest #{type_text} for approval voting!"
      "ranked" -> "Be the first to suggest #{type_text} for ranked choice voting!"
      "star" -> "Be the first to suggest #{type_text} for star rating!"
      _ -> "Be the first to suggest #{type_text} to vote on!"
    end
  end

  defp get_empty_state_guidance(poll_type) do
    case poll_type do
      "movie" -> "Suggest movies that you love or think others would enjoy. Add a brief description for others to understand your choice."
      "places" -> "Suggest places that are popular or unique. Add details like cuisine, location, or special notes."
      "time" -> "Suggest times that work for you. Times will be automatically sorted for easy comparison."
      "date_selection" -> "Suggest possible dates for the event. Each date will be voted on separately with yes/maybe/no preferences."
      _ -> "Suggest options that you think are great. Add a description to help others understand your choice."
    end
  end

  defp get_empty_state_button_text(poll_type) do
    case poll_type do
      "movie" -> "Suggest a Movie"
      "places" -> "Suggest a Place"
      "time" -> "Add a Time"
      "date_selection" -> "Add a Date"
      _ -> "Add an Option"
    end
  end

  defp get_empty_state_help_text(poll_type) do
    case poll_type do
      "movie" -> "You can suggest up to 3 movies. Encourage others to add more suggestions!"
      "places" -> "You can suggest up to 3 places. Encourage others to add more suggestions!"
      "time" -> "You can suggest up to 3 times. Encourage others to add more suggestions!"
      _ -> "You can suggest up to 3 options. Encourage others to add more suggestions!"
    end
  end

  # Helper function to safely encode JSON data
  defp safe_json_encode(data) do
    case Jason.encode(data) do
      {:ok, json} -> json
      {:error, _} -> "{}"
    end
  end

  # Helper function to generate time options for time polls
  defp time_options() do
    # Start at 10:00 AM (10:00) and go through 11:30 PM (23:30)
    # 30-minute increments
    10..23
    |> Enum.flat_map(fn hour ->
      [
        %{value: TimeUtils.format_time_value(hour, 0), display: TimeUtils.format_time_display(hour, 0)},
        %{value: TimeUtils.format_time_value(hour, 30), display: TimeUtils.format_time_display(hour, 30)}
      ]
    end)
  end



  defp format_time_for_display(time) do
    # Parse time string like "17:30" and convert to 12-hour format
    case TimeUtils.parse_time_string(time) do
      {:ok, {hour, minute}} ->
        TimeUtils.format_time_display(hour, minute)
      {:error, _} ->
        time # Return original if parsing fails
    end
  end

  # Helper function to check if suggestions are allowed in the current phase
  defp suggestions_allowed_for_phase?(phase) do
    case phase do
      "list_building" -> true
      "voting_with_suggestions" -> true
      "voting" -> true  # Legacy support - treat as voting_with_suggestions
      "voting_only" -> false
      "closed" -> false
      _ -> false
    end
  end

  # Helper function to get phase-specific messaging
  defp get_phase_suggestion_message(phase) do
    case phase do
      "voting_only" -> "Suggestions are disabled during voting-only phase"
      "closed" -> "This poll is closed - no more suggestions allowed"
      _ -> nil
    end
  end

  # Helper function to get user-friendly phase display names
  defp get_phase_display_name(phase) do
    case phase do
      "list_building" -> "Building Phase"
      "voting_with_suggestions" -> "Voting (with suggestions)"
      "voting_only" -> "Voting (suggestions disabled)"
      "voting" -> "Voting Phase"  # Legacy support
      "closed" -> "Closed"
      _ -> "Poll Phase"
    end
  end

  # Date formatting helper functions for date_selection polls
  defp format_date_for_display(date) do
    case date do
      %Date{} = d ->
        d
        |> Date.to_string()
        |> then(fn date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, parsed_date} ->
              month_name = case parsed_date.month do
                1 -> "January"
                2 -> "February"
                3 -> "March"
                4 -> "April"
                5 -> "May"
                6 -> "June"
                7 -> "July"
                8 -> "August"
                9 -> "September"
                10 -> "October"
                11 -> "November"
                12 -> "December"
              end
              "#{month_name} #{parsed_date.day}, #{parsed_date.year}"
            _ -> date_str
          end
        end)
      _ -> "Invalid date"
    end
  end

  defp format_date_for_option_title(date) do
    # Format as a human-readable title for the poll option
    case date do
      %Date{} = d -> format_date_for_display(d)
      _ -> "Invalid date"
    end
  end

  # Extract dates from poll options for calendar display
  defp extract_dates_from_poll_options(poll_options) do
    case poll_options do
      %Ecto.Association.NotLoaded{} -> []
      poll_options when is_list(poll_options) ->
        poll_options
        |> Enum.map(fn option ->
          case DatePollAdapter.extract_date_from_option(option) do
            {:ok, date} -> date
            _ -> nil
          end
        end)
        |> Enum.filter(& &1)
        |> Enum.sort(Date)
      _ -> []
    end
  end
end
