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

    # For now, we'll skip checking for existing polls since the function doesn't exist
    # This will be handled by the database constraint error message
    existing_polls = []
    existing_poll_types = MapSet.new()

    # Create changeset
    changeset = if is_editing do
      Poll.changeset(poll, %{})
    else
      Poll.changeset(%Poll{}, %{
        event_id: assigns.event.id,
        created_by_id: assigns.user.id,
        phase: "list_building",
        poll_type: "custom",
        voting_system: "binary",
        settings: %{"location_scope" => "place"}
      })
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
     |> assign(:existing_poll_types, existing_poll_types)
     |> assign(:existing_polls, existing_polls)
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
                
                <!-- General error display for database/constraint errors -->
                <%= if @changeset.action && !Enum.empty?(@changeset.errors) do %>
                  <div class="mb-4 p-4 bg-red-50 border border-red-200 rounded-md">
                    <div class="flex">
                      <div class="flex-shrink-0">
                        <svg class="h-5 w-5 text-red-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                        </svg>
                      </div>
                      <div class="ml-3">
                        <h3 class="text-sm font-medium text-red-800">
                          There was an error creating the poll
                        </h3>
                        <div class="mt-2 text-sm text-red-700">
                          <ul class="list-disc list-inside space-y-1">
                            <%= for {field, {message, _}} <- @changeset.errors do %>
                              <li>
                                <%= if field == :poll_type do %>
                                  <%= message %>
                                <% else %>
                                  <%= field |> to_string() |> String.replace("_", " ") |> String.capitalize() %>: <%= message %>
                                <% end %>
                              </li>
                            <% end %>
                          </ul>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>

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
                            <span>Searching near: <%= get_search_location(@changeset, @poll) %></span>
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
                          value={format_datetime_local(@changeset, :list_building_deadline)}
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
                          value={format_datetime_local(@changeset, :voting_deadline)}
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
      Map.merge(%{
        "event_id" => socket.assigns.event.id,
        "created_by_id" => socket.assigns.user.id,
        "phase" => "list_building"
      }, poll_params)
    end

    Poll.changeset(poll, poll_params)
  end

  defp save_poll(socket, poll_params) do
    # Process privacy_settings to convert checkbox values to booleans
    poll_params = process_privacy_settings(poll_params)
    
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

  defp format_datetime_local(changeset, field) do
    case Ecto.Changeset.get_field(changeset, field) do
      %DateTime{} = datetime ->
        datetime
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

end
