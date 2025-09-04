defmodule EventasaurusWeb.PollCreationComponent do
  @moduledoc """
  A reusable LiveView component for creating new polls.

  Provides a comprehensive form for poll creation with support for different poll types,
  voting systems, deadline management, and configuration options. Handles validation
  and integrates with the Events context for poll creation.

  ## Attributes:
  - event: Event struct (required)
  - user: User struct (required)
  - show: Boolean to show/hide the modal
  - poll: Poll struct for editing (optional, nil for new polls)
  - changeset: Ecto changeset for form state
  - loading: Whether a form submission is in progress

  ## Usage:
      <.live_component
        module={EventasaurusWeb.PollCreationComponent}
        id="poll-creation-modal"
        event={@event}
        user={@user}
        show={@show_poll_creation}
        poll={@editing_poll}
        loading={@loading}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Poll
  alias EventasaurusApp.DateTimeHelper
  import EventasaurusWeb.PollView, only: [poll_emoji: 1]

  @poll_types [
    {"custom", "General", "Create a custom poll"},
    {"movie", "Movie", "Vote on movies to watch"},
    {"places", "Place", "Pick places to visit"},
    {"time", "Time/Schedule", "Schedule events"},
    {"date_selection", "DateTime", "Vote on possible dates"}
  ]

  @voting_systems [
    {"binary", "Yes/Maybe/No", "Quick consensus on individual options - great for simple decisions where participants might be unsure"},
    {"approval", "Approval", "Select multiple acceptable options - perfect when you want to find all viable choices"},
    {"ranked", "Ranked Choice", "Rank options in order of preference - ideal for finding the most preferred single option"},
    {"star", "Star Rating", "Rate options from 1 to 5 stars - best for detailed feedback and comparison"}
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:show, false)
     |> assign(:poll, nil)
     |> assign(:show_advanced_options, false)
     |> assign(:show_voting_guidelines, false)
     |> assign(:current_poll_type, "custom")}
  end

  @impl true
  def update(assigns, socket) do
    # Determine if we're editing or creating
    poll = assigns[:poll]
    is_editing = poll != nil

    # Create changeset
    changeset = if is_editing do
      Poll.changeset(poll, %{})
    else
      # Auto-populate from event venue if available
      initial_settings = %{"location_scope" => "place"}
      
      # Check if venue exists on the event
      venue = case assigns.event do
        %{venue: %{} = v} -> v
        _ -> nil
      end
      
      initial_settings = if venue do
        # Set location scope based on venue type - EXACTLY like ActivityCreationComponent
        location_scope = case venue.venue_type do
          "city" -> "city"
          "region" -> "region"
          _ -> "place"
        end
        
        # Add venue location data if coordinates exist
        settings_with_location = Map.put(initial_settings, "location_scope", location_scope)
        
        # Only provide location data for physical venues - EXACTLY like ActivityCreationComponent
        if venue.venue_type in ["venue", "city", "region"] && venue.latitude && venue.longitude do
          # Use venue name (or address if no name) as the search location display
          search_location_display = venue.name || venue.address || venue.city
          
          settings_with_location
          |> Map.put("search_location", search_location_display)
          |> Map.put("search_location_data", %{
            "geometry" => %{
              "lat" => venue.latitude,
              "lng" => venue.longitude
            },
            "city" => venue.city,
            "name" => venue.name || venue.address
          })
        else
          settings_with_location
        end
      else
        initial_settings
      end
      
      # Create a poll struct with the venue-enhanced settings
      new_poll = %Poll{
        event_id: assigns.event.id,
        created_by_id: assigns.user.id,
        phase: "list_building",
        poll_type: "custom",
        voting_system: "binary",
        settings: initial_settings  # Now contains venue data if available
      }
      
      # Create changeset from the populated struct
      Poll.changeset(new_poll, %{})
    end

    # Determine current poll type for UI display
    current_poll_type = if is_editing do
      poll.poll_type
    else
      Ecto.Changeset.get_field(changeset, :poll_type) || "custom"
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:is_editing, is_editing)
     |> assign(:changeset, changeset)
     |> assign(:current_poll_type, current_poll_type)
     |> assign(:poll_types, @poll_types)
     |> assign(:voting_systems, @voting_systems)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:show, fn -> false end)
     |> assign_new(:show_voting_guidelines, fn -> false end)}
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
            <.form for={@changeset} phx-submit="submit_poll" phx-target={@myself} phx-change="validate" :let={f}>
              <div class="bg-white px-6 pt-6 pb-4">
                <div class="mb-4">
                  <h3 class="text-lg leading-6 font-medium text-gray-900" id="modal-title">
                    <%= if @is_editing, do: "Edit Poll", else: "Create New Poll" %>
                  </h3>
                  <p class="text-sm text-gray-500">
                    <%= if @is_editing, do: "Update poll details and settings", else: "Set up a new poll for your event participants" %>
                  </p>
                </div>

                <div class="space-y-6">
                  <!-- Poll Title -->
                  <div>
                    <label for="poll_title" class="block text-sm font-medium text-gray-700">
                      Poll Title <span class="text-red-500">*</span>
                    </label>
                    <input
                      type="text"
                      name="poll[title]"
                      id="poll_title"
                      value={Phoenix.HTML.Form.input_value(f, :title)}
                      class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                      placeholder="What should participants vote on?"
                    />
                    <%= if error = @changeset.errors[:title] do %>
                      <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                    <% end %>
                  </div>

                  <!-- Poll Description -->
                  <div>
                    <label for="poll_description" class="block text-sm font-medium text-gray-700">
                      Description
                    </label>
                    <textarea
                      name="poll[description]"
                      id="poll_description"
                      rows="3"
                      class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                      placeholder="Provide additional context or instructions (optional)"
                    ><%= Phoenix.HTML.Form.input_value(f, :description) %></textarea>
                    <%= if error = @changeset.errors[:description] do %>
                      <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                    <% end %>
                  </div>

                  <!-- Poll Type Selection -->
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-3">
                      Poll Type <span class="text-red-500">*</span>
                    </label>
                    <div class="grid grid-cols-2 gap-3">
                      <%= for {value, label, description} <- @poll_types do %>
                        <label class="relative">
                          <input
                            type="radio"
                            name="poll[poll_type]"
                            value={value}
                            checked={Phoenix.HTML.Form.input_value(f, :poll_type) == value}
                            class="sr-only peer"
                          />
                          <div class="p-3 border-2 border-gray-200 rounded-lg cursor-pointer transition-all peer-checked:border-indigo-500 peer-checked:bg-indigo-50 hover:border-gray-300">
                            <div class="flex items-center">
                              <span class="text-lg mr-2"><%= poll_emoji(value) %></span>
                              <div>
                                <div class="text-sm font-medium text-gray-900"><%= label %></div>
                                <div class="text-xs text-gray-500"><%= description %></div>
                              </div>
                            </div>
                          </div>
                        </label>
                      <% end %>
                    </div>
                    <%= if error = @changeset.errors[:poll_type] do %>
                      <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                    <% end %>
                  </div>

                  <!-- Location Scope Selection (for places polls) -->
                  <%= if @current_poll_type == "places" do %>
                    <div>
                      <label for="location_scope" class="block text-sm font-medium text-gray-700 mb-2">
                        Location Scope <span class="text-red-500">*</span>
                      </label>
                      <div class="relative">
                        <select
                          name="poll[settings][location_scope]"
                          id="location_scope"
                          class="block w-full pl-3 pr-10 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm bg-white"
                        >
                          <option value="" disabled selected={get_current_location_scope(@changeset, @poll) == ""}>Select location scope...</option>
                          <%= for scope <- Poll.location_scopes() do %>
                            <option value={scope} selected={get_current_location_scope(@changeset, @poll) == scope}><%= Poll.location_scope_display(scope) %></option>
                          <% end %>
                        </select>
                        <div class="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none">
                          <svg class="w-5 h-5 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
                          </svg>
                        </div>
                      </div>
                      <p class="mt-2 text-sm text-gray-500">
                        Choose the geographical scope for location suggestions in this poll.
                      </p>
                    </div>
                    
                    <!-- Optional Search Location (only for Specific Places) -->
                    <%= if get_current_location_scope(@changeset, @poll) == "place" do %>
                      <div class="mt-4">
                        <label class="block text-sm font-medium text-gray-700 mb-2">
                          Search Location (optional)
                          <span class="text-xs text-gray-500 ml-2">Choose a city to find nearby places</span>
                        </label>
                        
                        <div class="relative">
                          <input
                            type="text"
                            id="poll_search_location"
                            name="poll[settings][search_location]"
                            value={get_search_location(@changeset, @poll)}
                            class="block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm pr-10"
                            placeholder="Search for a city..."
                            autocomplete="off"
                            phx-hook="CitySearch"
                          />
                          <input
                            type="hidden"
                            id="poll_search_location_data"
                            name="poll[settings][search_location_data]"
                            value={get_search_location_data(@changeset, @poll)}
                          />
                          <div class="absolute inset-y-0 right-0 flex items-center pr-3">
                            <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/>
                            </svg>
                          </div>
                        </div>
                        
                        <!-- Location Context Display -->
                        <%= if get_search_location(@changeset, @poll) do %>
                          <div class="mt-2 text-sm text-indigo-600 flex items-center">
                            <svg class="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                              <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"/>
                            </svg>
                            <span>
                              Searching near: <%= get_search_location(@changeset, @poll) %>
                              <%= if is_using_event_venue(@changeset, @poll, @event) do %>
                                <span class="text-xs text-gray-500">(event location)</span>
                              <% end %>
                            </span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>

                  <!-- Voting System Selection -->
                  <div>
                    <label for="voting_system" class="block text-sm font-medium text-gray-700 mb-2">
                      Voting System <span class="text-red-500">*</span>
                    </label>
                    <div class="relative">
                      <select
                        name="poll[voting_system]"
                        id="voting_system"
                        class="block w-full pl-3 pr-10 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm bg-white"
                        style="-webkit-appearance: none; -moz-appearance: none; appearance: none; background-image: none;"
                      >
                        <option value="" disabled={true} selected={Phoenix.HTML.Form.input_value(f, :voting_system) == nil}>Select a voting system...</option>
                        <%= for {value, label, description} <- @voting_systems do %>
                          <option
                            value={value}
                            selected={Phoenix.HTML.Form.input_value(f, :voting_system) == value}
                            title={description}
                          >
                            <%= label %>
                          </option>
                        <% end %>
                      </select>
                      <div class="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none">
                        <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                        </svg>
                      </div>
                    </div>
                    <%= if error = @changeset.errors[:voting_system] do %>
                      <p class="mt-2 text-sm text-red-600"><%= elem(error, 0) %></p>
                    <% end %>

                    <!-- Voting System Guidelines Toggle -->
                    <div class="mt-3">
                      <button
                        type="button"
                        phx-click="toggle_voting_guidelines"
                        phx-target={@myself}
                        class="flex items-center text-sm text-blue-600 hover:text-blue-800 transition-colors"
                      >
                        <svg class={[
                          "w-4 h-4 mr-1 transition-transform",
                          if(@show_voting_guidelines, do: "rotate-90", else: "rotate-0")
                        ]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                        </svg>
                        💡 Choosing the Right Voting System
                      </button>

                      <%= if @show_voting_guidelines do %>
                        <div class="mt-2 bg-blue-50 border border-blue-200 rounded-md p-4">
                          <div class="space-y-2 text-xs text-blue-800">
                            <div>
                              <strong>Yes/Maybe/No:</strong> Best for quick decisions where people might be uncertain. The "maybe" option captures neutral feelings and helps identify lukewarm support.
                            </div>
                            <div>
                              <strong>Approval:</strong> Use when you want to find all acceptable options. Great for gathering multiple venues, activities, or any scenario where several choices could work.
                            </div>
                            <div>
                              <strong>Ranked Choice:</strong> Perfect for finding the single most preferred option. Ideal for choosing one movie, one restaurant, or one date from multiple possibilities.
                            </div>
                            <div>
                              <strong>Star Rating:</strong> Best when you want detailed feedback and comparison. Use for rating experiences, evaluating options with nuanced opinions, or when quality assessment matters.
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <!-- Advanced Options Toggle -->
                  <div class="border-t pt-4">
                    <button
                      type="button"
                      phx-click="toggle_advanced_options"
                      phx-target={@myself}
                      class="flex items-center justify-between w-full text-left text-sm font-medium text-gray-700 hover:text-gray-900 transition-colors"
                    >
                      <span>Advanced Options</span>
                      <svg class={[
                        "w-4 h-4 transition-transform",
                        if(@show_advanced_options, do: "rotate-180", else: "rotate-0")
                      ]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                      </svg>
                    </button>
                  </div>

                  <%= if @show_advanced_options do %>
                    <!-- Configuration Options -->
                    <div class="bg-gray-50 p-4 rounded-lg">
                      <h4 class="text-sm font-medium text-gray-900 mb-3">Configuration</h4>

                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <!-- Max Options Per User -->
                      <div>
                        <label for="max_options_per_user" class="block text-sm font-medium text-gray-700">
                          Max Options Per User
                        </label>
                        <input
                          type="number"
                          name="poll[max_options_per_user]"
                          id="max_options_per_user"
                          value={Phoenix.HTML.Form.input_value(f, :max_options_per_user) || 3}
                          min="1"
                          max="10"
                          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                        <p class="mt-1 text-xs text-gray-500">How many options each user can suggest</p>
                      </div>

                      <!-- Max Rankings (for ranked choice polls only) -->
                      <%= if Phoenix.HTML.Form.input_value(f, :voting_system) == "ranked" do %>
                        <div>
                          <label for="max_rankings" class="block text-sm font-medium text-gray-700">
                            Max Rankings Per Voter
                          </label>
                          <div class="mt-1 relative">
                            <select
                              name="poll[settings][max_rankings]"
                              id="max_rankings"
                              class="block w-full pl-3 pr-10 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm bg-white"
                            >
                              <%= for option <- Poll.max_rankings_options() do %>
                                <option
                                  value={option}
                                  selected={get_max_rankings_setting(@changeset, @poll) == option}
                                >
                                  <%= Poll.max_rankings_display(option) %>
                                </option>
                              <% end %>
                            </select>
                            <div class="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none">
                              <svg class="w-5 h-5 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
                              </svg>
                            </div>
                          </div>
                          <p class="mt-1 text-xs text-gray-500">Limit how many choices users can rank (improves performance)</p>
                        </div>
                      <% end %>

                      <!-- Auto Finalize -->
                      <div class="flex items-center justify-between">
                        <div>
                          <label for="auto_finalize" class="text-sm font-medium text-gray-700">
                            Auto Finalize
                          </label>
                          <p class="text-xs text-gray-500">Automatically close poll after voting deadline</p>
                        </div>
                        <input
                          type="checkbox"
                          name="poll[auto_finalize]"
                          id="auto_finalize"
                          checked={Phoenix.HTML.Form.input_value(f, :auto_finalize)}
                          class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                        />
                      </div>
                    </div>
                  </div>

                  <!-- Privacy Settings -->
                  <div class="bg-purple-50 p-4 rounded-lg mt-4">
                    <h4 class="text-sm font-medium text-gray-900 mb-3">Privacy Settings</h4>
                    
                    <div class="space-y-3">
                      <!-- Show Suggester Names -->
                      <div class="flex items-center justify-between">
                        <div>
                          <label for="show_suggester_names" class="text-sm font-medium text-gray-700">
                            Show Suggester Names
                          </label>
                          <p class="text-xs text-gray-500">Display who suggested each option</p>
                        </div>
                        <input
                          type="checkbox"
                          name="poll[privacy_settings][show_suggester_names]"
                          id="show_suggester_names"
                          checked={get_privacy_setting(@changeset, "show_suggester_names", true)}
                          class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                        />
                      </div>
                    </div>
                  </div>

                  <!-- Deadlines -->
                  <div class="bg-blue-50 p-4 rounded-lg">
                    <h4 class="text-sm font-medium text-gray-900 mb-3">Deadlines (Optional)</h4>

                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <!-- List Building Deadline -->
                      <div>
                        <label for="list_building_deadline" class="block text-sm font-medium text-gray-700">
                          List Building Deadline
                        </label>
                        <input
                          type="datetime-local"
                          name="poll[list_building_deadline]"
                          id="list_building_deadline"
                          value={format_datetime_local(@changeset, :list_building_deadline, @event)}
                          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                        <p class="mt-1 text-xs text-gray-500">When to stop accepting new options</p>
                      </div>

                      <!-- Voting Deadline -->
                      <div>
                        <label for="voting_deadline" class="block text-sm font-medium text-gray-700">
                          Voting Deadline
                        </label>
                        <input
                          type="datetime-local"
                          name="poll[voting_deadline]"
                          id="voting_deadline"
                          value={format_datetime_local(@changeset, :voting_deadline, @event)}
                          class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                        <p class="mt-1 text-xs text-gray-500">When to stop accepting votes</p>
                      </div>
                    </div>
                  </div>
                  <% end %>
                </div>
              </div>



              <!-- Form Actions -->
              <div class="bg-gray-50 px-6 py-4 flex flex-col sm:flex-row sm:space-x-3 space-y-3 sm:space-y-0 sm:justify-end">
                <button
                  type="button"
                  phx-click="close_modal"
                  phx-target={@myself}
                  class="w-full sm:w-auto inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:text-sm"
                  disabled={@loading}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="w-full sm:w-auto inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:text-sm disabled:opacity-50 disabled:cursor-not-allowed"
                  disabled={@loading}
                >
                  <%= if @loading do %>
                    <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <%= if @is_editing, do: "Updating...", else: "Creating..." %>
                  <% else %>
                    <%= if @is_editing, do: "Update Poll", else: "Create Poll" %>
                  <% end %>
                </button>
              </div>
            </.form>
          </div>
        </div>
    </div>
    """
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    send(self(), {:close_poll_creation_modal})
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_advanced_options", _params, socket) do
    {:noreply, assign(socket, :show_advanced_options, !socket.assigns.show_advanced_options)}
  end

  @impl true
  def handle_event("toggle_voting_guidelines", _params, socket) do
    {:noreply, assign(socket, :show_voting_guidelines, !socket.assigns.show_voting_guidelines)}
  end

  @impl true
  def handle_event("validate", %{"poll" => poll_params}, socket) do
    changeset = create_changeset(socket, poll_params)
    current_poll_type = poll_params["poll_type"] || "custom"
    {:noreply, assign(socket, changeset: changeset, current_poll_type: current_poll_type)}
  end



  @impl true
  def handle_event("submit_poll", %{"poll" => poll_params}, socket) do
    socket = assign(socket, :loading, true)

    case save_poll(socket, poll_params) do
      {:ok, poll} ->
        message = if socket.assigns.is_editing, do: "Poll updated successfully!", else: "Poll created successfully!"
        send(self(), {:poll_saved, poll, message})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:changeset, changeset)}
    end
  end

  # Private functions

  defp create_changeset(socket, poll_params) do
    poll = socket.assigns.poll || %Poll{}

    # Merge default values for new polls
    poll_params = if socket.assigns.is_editing do
      poll_params
    else
      # Get venue-based settings if not already in poll_params
      poll_params_with_defaults = Map.merge(%{
        "event_id" => socket.assigns.event.id,
        "created_by_id" => socket.assigns.user.id,
        "phase" => "list_building"
      }, poll_params)
      
      # If settings are not in params or are minimal, add venue-based settings
      poll_params_with_defaults = 
        if !Map.has_key?(poll_params_with_defaults, "settings") || 
           !Map.has_key?(poll_params_with_defaults["settings"] || %{}, "search_location") do
          venue_settings = get_venue_settings(socket.assigns.event)
          
          current_settings = Map.get(poll_params_with_defaults, "settings", %{})
          updated_settings = Map.merge(venue_settings, current_settings)
          
          Map.put(poll_params_with_defaults, "settings", updated_settings)
        else
          poll_params_with_defaults
        end
      
      poll_params_with_defaults
    end

    Poll.changeset(poll, poll_params)
  end
  
  defp get_venue_settings(event) do
    venue = case event do
      %{venue: %{} = v} -> v
      _ -> nil
    end
    
    if venue do
      # Set location scope based on venue type - EXACTLY like ActivityCreationComponent
      location_scope = case venue.venue_type do
        "city" -> "city"
        "region" -> "region"
        _ -> "place"
      end
      
      # Build settings with venue data
      settings = %{"location_scope" => location_scope}
      
      # Only provide location data for physical venues - EXACTLY like ActivityCreationComponent
      if venue.venue_type in ["venue", "city", "region"] && venue.latitude && venue.longitude do
        # Use venue name (or address if no name) as the search location display
        search_location_display = venue.name || venue.address || venue.city
        
        settings
        |> Map.put("search_location", search_location_display)
        |> Map.put("search_location_data", %{
          "geometry" => %{
            "lat" => venue.latitude,
            "lng" => venue.longitude
          },
          "city" => venue.city,
          "name" => venue.name || venue.address
        })
      else
        settings
      end
    else
      %{"location_scope" => "place"}
    end
  end

  defp save_poll(socket, poll_params) do
    # Process privacy_settings to convert checkbox values to booleans
    poll_params = process_privacy_settings(poll_params)
    
    # Parse datetime fields with event timezone
    poll_params = parse_datetime_fields(poll_params, socket.assigns.event)
    
    if socket.assigns.is_editing do
      Events.update_poll(socket.assigns.poll, poll_params)
    else
      # Ensure required fields for new polls
      poll_params = Map.merge(poll_params, %{
        "event_id" => socket.assigns.event.id,
        "created_by_id" => socket.assigns.user.id,
        "phase" => "list_building"
      })

      Events.create_poll(poll_params)
    end
  end
  
  defp process_privacy_settings(poll_params) do
    case Map.get(poll_params, "privacy_settings") do
      nil -> 
        # No privacy settings provided, set default
        Map.put(poll_params, "privacy_settings", %{"show_suggester_names" => true})
      settings when is_map(settings) ->
        # Convert checkbox values ("on" = checked, missing = unchecked) to booleans
        # If the checkbox is unchecked, it won't be in the params at all
        processed_settings = %{
          "show_suggester_names" => Map.get(settings, "show_suggester_names") == "on"
        }
        
        Map.put(poll_params, "privacy_settings", processed_settings)
      _ -> 
        poll_params
    end
  end

  defp parse_datetime_fields(params, event) do
    timezone = event.timezone || "UTC"
    
    params
    |> parse_datetime_field("list_building_deadline", timezone)
    |> parse_datetime_field("voting_deadline", timezone)
  end
  
  defp parse_datetime_field(params, field, timezone) do
    case Map.get(params, field) do
      nil -> params
      "" -> Map.put(params, field, nil)
      datetime_str when is_binary(datetime_str) ->
        # datetime-local inputs provide YYYY-MM-DDTHH:MM format without timezone
        case DateTimeHelper.parse_datetime_local(datetime_str, timezone) do
          {:ok, datetime} -> Map.put(params, field, datetime)
          {:error, _} -> params  # Keep original value, let changeset handle validation
        end
      _ -> params
    end
  end
  
  defp format_datetime_local(changeset, field, event) do
    case Ecto.Changeset.get_field(changeset, field) do
      %DateTime{} = datetime ->
        # Convert to event timezone if available
        timezone = if event && event.timezone, do: event.timezone, else: "UTC"
        shifted = DateTimeHelper.utc_to_timezone(datetime, timezone)
        
        # Format for datetime-local input (YYYY-MM-DDTHH:MM)
        shifted
        |> DateTime.to_naive()
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)  # Remove seconds for datetime-local input

      nil -> ""
      _ -> ""
    end
  end

  defp get_privacy_setting(changeset, key, default) do
    case Ecto.Changeset.get_field(changeset, :privacy_settings) do
      nil -> default
      settings when is_map(settings) ->
        Map.get(settings, key, default)
      _ -> default
    end
  end

  # Helper function to get current location scope from changeset or poll
  defp get_current_location_scope(changeset, poll) do
    # Try to get from changeset first (if form has been submitted)
    case Ecto.Changeset.get_field(changeset, :settings) do
      %{"location_scope" => scope} when is_binary(scope) -> scope
      _ -> 
        # Fall back to poll's current scope (for editing) or default
        if poll do
          Poll.get_location_scope(poll)
        else
          "place"  # Default for new polls
        end
    end
  end

  # Helper function to get search location from changeset or poll
  defp get_search_location(changeset, poll) do
    case Ecto.Changeset.get_field(changeset, :settings) do
      %{"search_location" => location} when is_binary(location) -> location
      _ ->
        if poll && poll.settings do
          Map.get(poll.settings, "search_location")
        else
          nil
        end
    end
  end

  # Helper function to get search location data from changeset or poll
  defp get_search_location_data(changeset, poll) do
    case Ecto.Changeset.get_field(changeset, :settings) do
      %{"search_location_data" => data} when is_binary(data) -> data
      %{"search_location_data" => data} when is_map(data) -> Jason.encode!(data)
      _ ->
        if poll && poll.settings do
          case Map.get(poll.settings, "search_location_data") do
            data when is_map(data) -> Jason.encode!(data)
            data when is_binary(data) -> data
            _ -> ""
          end
        else
          ""
        end
    end
  end
  
  # Helper to check if we're using the event venue location
  defp is_using_event_venue(changeset, poll, event) do
    # For edited polls, check if they were never manually changed
    if poll && poll.id do
      false  # Existing polls might have been manually changed
    else
      # For new polls, check if location matches venue
      search_location = get_search_location(changeset, nil)
      event.venue && search_location && 
        (search_location == event.venue.city || search_location == event.venue.name)
    end
  end

  # Helper function to get max rankings setting from changeset or poll
  defp get_max_rankings_setting(changeset, poll) do
    settings = Ecto.Changeset.get_field(changeset, :settings) || %{}
    case Map.get(settings, "max_rankings") do
      v when is_integer(v) -> v
      v when is_binary(v) ->
        case Integer.parse(v) do
          {int, ""} when int in [3, 5, 7] -> int
          _ -> fallback_max_rankings(poll)
        end
      _ -> fallback_max_rankings(poll)
    end
  end

  defp fallback_max_rankings(nil), do: 3
  defp fallback_max_rankings(poll), do: Poll.get_max_rankings(poll)

end
