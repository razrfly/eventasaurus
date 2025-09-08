defmodule EventasaurusWeb.EventPollIntegrationComponent do
  @moduledoc """
  A comprehensive LiveView component that integrates polling functionality
  into the existing event management system.

  This component extends existing event LiveViews with polling capabilities,
  providing seamless integration with event creation, editing, and management flows.
  It serves as the main orchestrator for all polling-related features within events.

  ## Attributes:
  - event: Event struct with preloaded polls and related data (required)
  - current_user: Current user struct for permission checks (required)
  - integration_mode: How to integrate polls into the event view (default: "embedded")
    - "embedded" - Polls section within event details
    - "tab" - Separate tab in event navigation
    - "sidebar" - Sidebar panel for quick access
  - show_creation_prompt: Whether to show poll creation suggestions (default: true)
  - compact_mode: Whether to use compact displays (default: false)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.EventPollIntegrationComponent}
        id="event-polls"
        event={@event}
        current_user={@current_user}
        integration_mode="embedded"
        show_creation_prompt={true}
        compact_mode={false}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias EventasaurusWeb.Services.PollPubSubService
  alias EventasaurusWeb.Utils.PollPhaseUtils

  # Import the other polling components
  alias EventasaurusWeb.PollCreationComponent
  alias EventasaurusWeb.OptionSuggestionComponent

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:active_view, "overview")
     |> assign(:selected_poll, nil)
     |> assign(:showing_creation_modal, false)
     |> assign(:showing_poll_details, false)
     |> assign(:error_message, nil)
     |> assign(:success_message, nil)
     |> assign(:loading, false)
     |> assign(:integration_stats, %{})
     |> assign(:polls, [])
     |> assign(:poll_filter, "all")
     |> assign(:poll_sort, "newest")
     |> assign(:selected_polls, [])
     |> assign(:open_poll_menu, nil)
     |> assign(:reorder_mode, false)
     |> assign(:reordered_polls, [])}
  end

  @impl true
  def update(assigns, socket) do
    # Handle partial updates - if event is not in assigns, keep the existing one
    event = assigns[:event] || socket.assigns[:event]
    current_user = assigns[:current_user] || socket.assigns[:current_user]

    # Only proceed if we have the required data
    if event && current_user do
      # Get polls from assigns (loaded separately in parent LiveView)
      polls = assigns[:polls] || socket.assigns[:polls] || []

      # Subscribe to real-time updates for all polls in this event
      if connected?(socket) do
        # Subscribe to event-level poll updates using the new PubSub service
        PollPubSubService.subscribe_to_event_polls(event.id)

        # Also subscribe to each individual poll for detailed updates
        for poll <- polls do
          PollPubSubService.subscribe_to_poll(poll.id)
        end
      end

      # Calculate integration statistics using the polls data
      integration_stats = calculate_integration_stats_with_polls(polls)

      # Determine user permissions
      can_create_polls = Events.can_create_poll?(current_user, event)
      is_organizer = Events.user_is_organizer?(event, current_user)

      # Handle editing poll - show creation modal when editing_poll is set, unless explicitly set to false
      showing_creation_modal =
        case assigns[:showing_creation_modal] do
          # Explicitly set to false, don't show modal
          false -> false
          # Explicitly set to true, show modal
          true -> true
          # Use default logic
          nil -> socket.assigns[:showing_creation_modal] || assigns[:editing_poll] != nil
        end

      # Use parent's show_poll_details state if provided
      active_view =
        if Map.get(assigns, :show_poll_details, false) do
          "poll_details"
        else
          Map.get(socket.assigns, :active_view, "overview")
        end

      # Always prioritize parent's selected_poll, then refresh with updated data
      updated_selected_poll =
        case assigns[:selected_poll] do
          %{id: poll_id} ->
            # Find the poll with matching ID in the updated polls list to get fresh data
            Enum.find(polls, fn poll -> poll.id == poll_id end) || assigns[:selected_poll]

          _ ->
            assigns[:selected_poll]
        end

      {:ok,
       socket
       |> assign(assigns)
       |> assign(:event, event)
       |> assign(:current_user, current_user)
       |> assign(:polls, polls)
       |> assign_new(:integration_mode, fn -> "embedded" end)
       |> assign_new(:show_creation_prompt, fn -> true end)
       |> assign_new(:compact_mode, fn -> false end)
       |> assign_new(:open_poll_menu, fn -> nil end)
       |> assign_new(:selected_polls, fn -> [] end)
       |> assign(:poll_filter, assigns[:poll_filter] || socket.assigns[:poll_filter] || "all")
       |> assign(:poll_sort, assigns[:poll_sort] || socket.assigns[:poll_sort] || "newest")
       |> assign(:integration_stats, integration_stats)
       |> assign(:can_create_polls, can_create_polls)
       |> assign(:is_organizer, is_organizer)
       |> assign(:showing_creation_modal, showing_creation_modal)
       |> assign(:active_view, active_view)
       |> assign(:selected_poll, updated_selected_poll)}
    else
      # If we don't have required data, just assign what we have and wait for full update
      {:ok, assign(socket, assigns)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="event-poll-integration-component">
      <%= if assigns[:show_poll_details] && assigns[:selected_poll] do %>
        <!-- Poll Details View -->
        <div class="bg-white border-t border-gray-200">
          <!-- Back Button -->
          <div class="px-6 py-4 border-b border-gray-200">
            <button
              type="button"
              class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700"
              phx-click="back_to_overview"
              phx-target={@myself}
            >
              <svg class="mr-2 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" />
              </svg>
              Back to Polls
            </button>
          </div>

          <!-- Unified Poll & Suggestion Header -->
          <div class="px-6 py-4 border-b border-gray-200">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <h2 class="text-lg font-semibold text-gray-900"><%= @selected_poll.title %></h2>
                <%= if @selected_poll.description && @selected_poll.description != "" do %>
                  <p class="mt-1 text-sm text-gray-600"><%= @selected_poll.description %></p>
                <% end %>
                <div class="mt-2 flex items-center gap-3">
                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                    <%= PollPhaseUtils.format_poll_type(to_string(Map.get(@selected_poll, :poll_type, "poll"))) %>
                  </span>
                  <span class="text-xs text-gray-500">
                    <%= if @selected_poll.inserted_at do %>
                      Created <%= format_relative_time(@selected_poll.inserted_at) %>
                    <% else %>
                      Created recently
                    <% end %>
                  </span>
                </div>
                <!-- Suggestion Description -->
                <p class="mt-3 text-sm text-gray-500">
                  Add <%= String.downcase(to_string(Map.get(@selected_poll, :poll_type, "options"))) %> for
                  <%= case Map.get(@selected_poll, :voting_system, "binary") do %>
                    <% "binary" -> %> yes/no voting
                    <% "approval" -> %> approval voting
                    <% "ranked" -> %> ranked choice voting
                    <% "star" -> %> star rating
                    <% _ -> %> voting
                  <% end %>
                </p>
              </div>
            </div>
          </div>

          <!-- Poll Options Component -->
          <.live_component
            module={OptionSuggestionComponent}
            id={"poll-options-#{@selected_poll.id}"}
            poll={@selected_poll}
            user={@current_user}
            poll_id={@selected_poll.id}
            event={@event}
            user_id={@current_user.id}
            can_suggest={true}
            is_creator={@is_organizer}
            participants={@participants}
          />
        </div>
      <% else %>
        <!-- Poll List View -->
        <%= if @polls && length(@polls) > 0 do %>
          <!-- Filtering and Sorting Controls -->
          <div class="px-6 py-3 bg-gray-50 border-b border-gray-200 flex items-center justify-between">
            <form phx-change="filter_polls" phx-target={@myself} class="flex flex-wrap items-center gap-3">
              <div class="text-sm font-medium text-gray-700">Filter by:</div>
              
              <!-- Filter Dropdown -->
              <div class="relative">
                <select
                  name="poll_filter"
                  value={@poll_filter || "all"}
                  class="appearance-none bg-white border border-gray-300 rounded-md pl-3 pr-8 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  style="background-image: none !important;"
                >
                  <option value="all">All Polls</option>
                  <option value="active">Active Only</option>
                  <option value="closed">Closed Only</option>
                  <option value="date_selection">Date Polls</option>
                  <option value="general">General Polls</option>
                </select>
                <svg class="absolute right-2 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400 pointer-events-none" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
                </svg>
              </div>
              
              <!-- Sort Dropdown -->
              <div class="relative">
                <select
                  name="poll_sort"
                  value={@poll_sort || "newest"}
                  class="appearance-none bg-white border border-gray-300 rounded-md pl-3 pr-8 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  style="background-image: none !important;"
                >
                  <option value="newest">Newest First</option>
                  <option value="oldest">Oldest First</option>
                  <option value="most_votes">Most Votes</option>
                  <option value="least_votes">Least Votes</option>
                  <option value="name">Name (A-Z)</option>
                </select>
                <svg class="absolute right-2 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400 pointer-events-none" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
                </svg>
              </div>
              
              <!-- Clear Filters -->
              <%= if @poll_filter != "all" || @poll_sort != "newest" do %>
                <button
                  phx-click="clear_poll_filters"
                  phx-target={@myself}
                  type="button"
                  class="inline-flex items-center px-2 py-1 text-xs font-medium text-gray-600 bg-gray-100 rounded hover:bg-gray-200"
                >
                  <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                  Clear
                </button>
              <% end %>
            </form>
            
            <!-- Right side actions -->
            <div class="flex items-center gap-3">
              <!-- Reorder Polls Button (for organizers only) -->
              <%= if @is_organizer && length(@polls || []) > 1 do %>
                <button
                  phx-click="toggle_reorder_mode"
                  phx-target={@myself}
                  type="button"
                  class={"inline-flex items-center px-3 py-1 border rounded-md text-sm font-medium #{if @reorder_mode, do: "border-blue-500 text-blue-700 bg-blue-50", else: "border-gray-300 text-gray-700 bg-white hover:bg-gray-50"}"}
                >
                  <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4" />
                  </svg>
                  <%= if @reorder_mode, do: "Done Reordering", else: "Reorder Polls" %>
                </button>
              <% end %>
              
              <!-- Select All Checkbox -->
              <div class="flex items-center gap-2">
                <input
                  type="checkbox"
                  phx-click="toggle_select_all"
                  phx-target={@myself}
                  checked={length(@selected_polls || []) == length(get_filtered_polls(@polls || [], @poll_filter))}
                  class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                />
                <label class="text-sm text-gray-700">Select All</label>
              </div>
            </div>
          </div>
          
          <!-- Batch Operations Bar -->
          <%= if length(@selected_polls || []) > 0 do %>
            <div class="px-6 py-3 bg-indigo-50 border-b border-indigo-200 flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium text-indigo-900">
                  <%= length(@selected_polls || []) %> poll<%= if length(@selected_polls || []) > 1, do: "s" %> selected
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
                  phx-click="batch_close_polls"
                  phx-target={@myself}
                  data-confirm={"Are you sure you want to close #{length(@selected_polls || [])} poll(s)?"}
                  class="inline-flex items-center px-3 py-1 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700"
                >
                  Close Selected
                </button>
                <button
                  phx-click="batch_delete_polls"
                  phx-target={@myself}
                  data-confirm={"Are you sure you want to delete #{length(@selected_polls || [])} poll(s)? This cannot be undone."}
                  class="inline-flex items-center px-3 py-1 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                >
                  Delete Selected
                </button>
              </div>
            </div>
          <% end %>
          
          <!-- Match the exact guests tab structure -->
          <div class="divide-y divide-gray-200">
        <% polls_to_display = if @reorder_mode, do: @reordered_polls, else: get_sorted_polls(get_filtered_polls(@polls || [], @poll_filter), @poll_sort) %>
        <%= for {poll, index} <- Enum.with_index(polls_to_display) do %>
          <div class="px-6 py-4 hover:bg-gray-50 transition-colors">
            <div class="flex items-center justify-between">
              <!-- Reorder Controls or Checkbox -->
              <div class="flex items-center gap-3 mr-3">
                <%= if @reorder_mode do %>
                  <!-- Reorder controls -->
                  <div class="flex flex-col gap-1">
                    <button
                      phx-click="move_poll_up"
                      phx-value-poll_id={poll.id}
                      phx-target={@myself}
                      disabled={index == 0}
                      class={"p-1 rounded #{if index == 0, do: "text-gray-300 cursor-not-allowed", else: "text-gray-500 hover:text-indigo-600 hover:bg-indigo-50"}"}
                      title="Move up"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />
                      </svg>
                    </button>
                    <button
                      phx-click="move_poll_down"
                      phx-value-poll_id={poll.id}
                      phx-target={@myself}
                      disabled={index == length(polls_to_display) - 1}
                      class={"p-1 rounded #{if index == length(polls_to_display) - 1, do: "text-gray-300 cursor-not-allowed", else: "text-gray-500 hover:text-indigo-600 hover:bg-indigo-50"}"}
                      title="Move down"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>
                  </div>
                  <div class="text-sm font-medium text-gray-500">
                    #<%= index + 1 %>
                  </div>
                <% else %>
                  <!-- Regular checkbox -->
                  <input
                    type="checkbox"
                    phx-click="toggle_poll_selection"
                    phx-value-poll_id={poll.id}
                    phx-target={@myself}
                    checked={poll.id in (@selected_polls || [])}
                    class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                  />
                <% end %>
              </div>
              
              <!-- Poll Info (matching user info structure) -->
              <div class="flex items-center gap-3 flex-1 min-w-0">
                <!-- Poll Type Specific Icon -->
                <div class="h-10 w-10 rounded-full bg-indigo-100 flex items-center justify-center flex-shrink-0">
                  <%= render_poll_type_icon(poll.poll_type) %>
                </div>
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-2 mb-1">
                    <div
                      class="font-medium text-gray-900 truncate cursor-pointer hover:text-indigo-600 transition-colors"
                      phx-click="view_poll_details"
                      phx-value-poll_id={poll.id}
                      phx-target={@myself}
                      title="Click to view poll details"
                    >
                      <%= poll.title %>
                    </div>
                    <!-- Poll Type Badge (matching source badge) -->
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                      <%= PollPhaseUtils.format_poll_type(to_string(Map.get(poll, :poll_type, "poll"))) %>
                    </span>
                    <!-- Voting System Badge -->
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
                      <%= case Map.get(poll, :voting_system, "binary") do %>
                        <% "binary" -> %>Yes/No
                        <% "approval" -> %>Approval
                        <% "ranked" -> %>Ranked Choice
                        <% "star" -> %>Star Rating
                        <% _ -> %>Voting
                      <% end %>
                    </span>
                  </div>
                  <div class="text-sm text-gray-500 truncate">
                    <%= poll.description || "No description provided" %>
                  </div>
                  <!-- Poll Creation Details (matching invitation details) -->
                  <div class="text-xs text-gray-400 mt-1">
                    <%= if poll.inserted_at do %>
                      Created <%= format_relative_time(poll.inserted_at) %>
                    <% else %>
                      Created recently
                    <% end %>
                    <%= case Map.get(poll, :created_by) do %>
                      <% %{name: name} when is_binary(name) -> %>by <%= name %>
                      <% _ -> %>
                    <% end %>
                  </div>
                </div>
              </div>

              <!-- Status and Actions (matching guests structure) -->
              <div class="flex items-center gap-4 flex-shrink-0">
                <div class="text-right">
                  <div class="flex items-center gap-2 justify-end mb-1">
                    <div class="text-sm text-gray-500">
                      <%= if poll.inserted_at do %>
                        <%= Calendar.strftime(poll.inserted_at, "%m/%d") %>
                      <% else %>
                        --/--
                      <% end %>
                    </div>
                    <!-- Status Badge -->
                    <% phase = poll && Map.get(poll, :phase, "list_building") || "list_building" %>
                    <% {status_text, status_class} = get_poll_status_badge_data(phase) %>
                    <span class={"inline-flex items-center px-2 py-1 rounded-full text-xs font-medium #{status_class}"}>
                      <%= status_text %>
                    </span>
                    <!-- Vote Count Indicator -->
                    <div class="text-sm font-medium text-gray-900">
                      <%= get_poll_vote_count(poll) %> votes
                    </div>
                  </div>
                  
                  <!-- Quick Action Buttons -->
                  <div class="flex items-center gap-1 mt-1">
                    <!-- View Results Button -->
                    <button
                      phx-click="view_poll_details"
                      phx-value-poll_id={poll.id}
                      phx-target={@myself}
                      class="p-1 text-gray-400 hover:text-indigo-600 transition-colors"
                      title="View Results"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                      </svg>
                    </button>
                    
                    <%= if can_manage_poll?(poll, @current_user, @event) do %>
                      <!-- Edit Button -->
                      <button
                        phx-click="edit_poll"
                        phx-value-poll_id={poll.id}
                        phx-target={@myself}
                        class="p-1 text-gray-400 hover:text-blue-600 transition-colors"
                        title="Edit Poll"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                        </svg>
                      </button>
                    <% end %>
                    
                    <%= if can_close_poll?(poll, @current_user, @event) do %>
                      <!-- Close Poll Button -->
                      <button
                        phx-click="close_poll"
                        phx-value-poll_id={poll.id}
                        phx-target={@myself}
                        class="p-1 text-gray-400 hover:text-red-600 transition-colors"
                        title="Close Poll"
                        data-confirm="Are you sure you want to close this poll? This action cannot be undone."
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                        </svg>
                      </button>
                    <% end %>
                  </div>
                </div>

                <!-- Actions Menu (matching guests actions) -->
                <div class="relative">
                  <button
                    phx-click="toggle_poll_menu"
                    phx-value-poll_id={poll.id}
                    phx-target={@myself}
                    class="p-2 text-gray-400 hover:text-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded-full"
                    aria-label="Poll actions"
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z" />
                    </svg>
                  </button>

                  <%= if @open_poll_menu == poll.id do %>
                    <div
                      phx-click-away="close_poll_menu"
                      phx-target={@myself}
                      class="absolute right-0 z-10 mt-2 w-48 bg-white rounded-md shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none"
                    >
                      <div class="py-1">
                        <button
                          phx-click="view_poll_details"
                          phx-value-poll_id={poll.id}
                          phx-target={@myself}
                          class="flex items-center w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                        >
                          <svg class="w-4 h-4 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                          </svg>
                          View Details
                        </button>

                        <%= if can_manage_poll?(poll, @current_user, @event) do %>
                          <button
                            phx-click="edit_poll"
                            phx-value-poll_id={poll.id}
                            phx-target={@myself}
                            class="flex items-center w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                          >
                            <svg class="w-4 h-4 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                            </svg>
                            Edit Poll
                          </button>
                        <% end %>

                        <%= if can_close_poll?(poll, @current_user, @event) do %>
                          <button
                            phx-click="close_poll"
                            phx-value-poll_id={poll.id}
                            phx-target={@myself}
                            class="flex items-center w-full px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                          >
                            <svg class="w-4 h-4 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                            </svg>
                            Close Poll
                          </button>
                        <% end %>

                        <%= if can_delete_poll?(poll, @current_user, @event) do %>
                          <button
                            phx-click="delete_poll"
                            phx-value-poll_id={poll.id}
                            phx-target={@myself}
                            data-confirm="Are you sure you want to delete this poll?"
                            class="flex items-center w-full px-4 py-2 text-sm text-red-700 hover:bg-red-50"
                          >
                            <svg class="w-4 h-4 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                            </svg>
                            Delete
                          </button>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
          </div>
        <% else %>
          <!-- Empty State -->
          <div class="px-6 py-12 text-center">
            <div class="mx-auto w-16 h-16 bg-indigo-100 rounded-full flex items-center justify-center mb-4">
              <svg class="w-8 h-8 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
              </svg>
            </div>
            <h3 class="text-lg font-medium text-gray-900 mb-2">No polls yet</h3>
            <p class="text-sm text-gray-600 mb-6">
              Create your first poll to gather input from event participants.
            </p>
            <button
              phx-click="show_creation_modal"
              phx-target={@myself}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
              </svg>
              Create Your First Poll
            </button>
          </div>
        <% end %>

      <!-- Poll Creation Modal -->
      <%= if @showing_creation_modal do %>
        <.live_component
          module={PollCreationComponent}
          id="poll-creation-modal"
          event={@event}
          user={@current_user}
          show={true}
          poll={@editing_poll}
        />
      <% end %>
      <% end %>
    </div>
    """
  end

  # UNUSED FUNCTIONS - Commented out to fix compile warnings
  # These functions were part of a more complex UI system with different view modes
  # Keeping them commented for potential future use

  # # Render Integration Header
  # defp render_integration_header(assigns) do
  #   ~H"""
  #   <div class={"header-section #{if @integration_mode == "sidebar", do: "sidebar-header", else: "main-header"}"}>
  #     <div class="flex items-center justify-between">
  #       <div>
  #         <h2 class={"font-semibold #{if @integration_mode == "sidebar", do: "text-lg text-gray-900", else: "text-2xl text-gray-900"}"}>
  #           <span class="inline-flex items-center">
  #             <svg class="mr-2 h-5 w-5 text-indigo-600" fill="currentColor" viewBox="0 0 20 20">
  #               <path fill-rule="evenodd" d="M10 2a4 4 0 00-4 4v1H5a1 1 0 00-.994.89l-1 9A1 1 0 004 18h12a1 1 0 00.994-1.11l-1-9A1 1 0 0015 7h-1V6a4 4 0 00-4-4zM8 6V5a2 2 0 114 0v1H8zm2 6a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1z" clip-rule="evenodd" />
  #             </svg>
  #             Event Polls
  #           </span>
  #         </h2>

  #         <%= unless @integration_mode == "sidebar" do %>
  #           <p class="text-sm text-gray-600 mt-1">
  #             Collaborative polling for <%= @event.title %>
  #           </p>
  #         <% end %>
  #       </div>

  #       <!-- Quick Stats -->
  #       <div class="flex items-center space-x-4 text-sm">
  #         <%= if length(@polls || []) > 0 do %>
  #           <div class="flex items-center space-x-4">
  #             <div class="text-center">
  #               <div class="text-lg font-semibold text-gray-900"><%= @integration_stats.total_polls %></div>
  #               <div class="text-gray-500">Polls</div>
  #             </div>
  #             <div class="text-center">
  #               <div class="text-lg font-semibold text-gray-900"><%= @integration_stats.active_polls %></div>
  #               <div class="text-gray-500">Active</div>
  #             </div>
  #             <div class="text-center">
  #               <div class="text-lg font-semibold text-gray-900"><%= @integration_stats.total_votes %></div>
  #               <div class="text-gray-500">Votes</div>
  #             </div>
  #           </div>
  #         <% end %>

  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  # # Render Navigation Tabs (for tab and sidebar modes)
  # defp render_navigation_tabs(assigns) do
  #   ~H"""
  #   <nav class="border-b border-gray-200 mt-4">
  #     <div class="-mb-px flex space-x-8">
  #       <%= for {view, label, icon} <- get_navigation_items(@integration_stats) do %>
  #         <button
  #           type="button"
  #           class={get_tab_classes(@active_view == view)}
  #           phx-click="change_view"
  #           phx-value-view={view}
  #           phx-target={@myself}
  #         >
  #           <svg class="-ml-0.5 mr-2 h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
  #             <path d={icon}/>
  #           </svg>
  #           <%= label %>
  #         </button>
  #       <% end %>
  #     </div>
  #   </nav>
  #   """
  # end

  # # Render Overview Section
  # defp render_overview_section(assigns) do
  #   ~H"""
  #   <div class="overview-section space-y-6">
  #     <!-- Polls List -->
  #     <%= if length(@polls || []) > 0 do %>
  #       <.live_component
  #         module={PollListComponent}
  #         id="event-polls-list"
  #         event={@event}
  #         polls={@polls}
  #         user={@current_user}
  #         show_creator_controls={@is_organizer}
  #         loading={false}
  #       />
  #     <% else %>
  #       <%= render_empty_state(assigns) %>
  #     <% end %>

  #     <!-- Quick Creation Prompt -->
  #     <%= if @show_creation_prompt and @can_create_polls and length(@polls || []) == 0 do %>
  #       <%= render_creation_prompt(assigns) %>
  #     <% end %>
  #   </div>
  #   """
  # end

  # # Render Creation Section
  # defp render_creation_section(assigns) do
  #   ~H"""
  #   <div class="creation-section">
  #     <div class="max-w-4xl mx-auto">
  #       <div class="bg-white shadow sm:rounded-lg">
  #         <div class="px-4 py-5 sm:p-6">
  #           <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
  #             Create a New Poll
  #           </h3>
  #           <p class="text-sm text-gray-600 mb-6">
  #             Set up a collaborative poll for your event participants. Choose from different poll types
  #             and voting systems to gather input from your community.
  #           </p>

  #           <!-- Creation Form/Component Would Go Here -->
  #           <div class="text-center py-8 text-gray-500">
  #             <button
  #               type="button"
  #               class="inline-flex items-center px-4 py-2 border border-transparent text-base font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
  #               phx-click="show_creation_modal"
  #               phx-target={@myself}
  #             >
  #               <svg class="-ml-1 mr-3 h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
  #                 <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
  #               </svg>
  #               Create Poll
  #             </button>
  #           </div>
  #         </div>
  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  # # Render Management Section (for organizers)
  # defp render_management_section(assigns) do
  #   ~H"""
  #   <div class="management-section space-y-6">
  #     <%= if @is_organizer do %>
  #       <!-- Poll Management Dashboard -->
  #       <div class="bg-white shadow sm:rounded-lg">
  #         <div class="px-4 py-5 sm:p-6">
  #           <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
  #             Poll Management Dashboard
  #           </h3>

  #           <!-- Management Actions -->
  #           <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
  #             <div class="bg-blue-50 rounded-lg p-4">
  #               <h4 class="font-medium text-blue-900">Active Polls</h4>
  #               <p class="text-2xl font-bold text-blue-600"><%= @integration_stats.active_polls %></p>
  #               <p class="text-sm text-blue-700">Currently accepting votes</p>
  #             </div>

  #             <div class="bg-green-50 rounded-lg p-4">
  #               <h4 class="font-medium text-green-900">Completed Polls</h4>
  #               <p class="text-2xl font-bold text-green-600"><%= @integration_stats.completed_polls %></p>
  #               <p class="text-sm text-green-700">Results available</p>
  #             </div>

  #             <div class="bg-purple-50 rounded-lg p-4">
  #               <h4 class="font-medium text-purple-900">Total Participation</h4>
  #               <p class="text-2xl font-bold text-purple-600"><%= @integration_stats.total_votes %></p>
  #               <p class="text-sm text-purple-700">Votes across all polls</p>
  #             </div>
  #           </div>

  #           <!-- Poll List with Management Actions -->
  #           <%= if length(@polls || []) > 0 do %>
  #             <div class="space-y-4">
  #               <%= for poll <- @polls do %>
  #                 <div class="border border-gray-200 rounded-lg p-4">
  #                   <div class="flex items-center justify-between">
  #                     <div>
  #                       <h5 class="font-medium text-gray-900"><%= poll.title %></h5>
  #                       <p class="text-sm text-gray-600"><%= poll.description %></p>
  #                       <div class="flex items-center space-x-4 text-xs text-gray-500 mt-2">
  #                         <span class={"inline-flex items-center px-2 py-1 rounded-full text-xs font-medium #{get_status_classes(poll.phase)}"}>
  #                           <%= String.replace(poll.phase, "_", " ") |> String.capitalize() %>
  #                         </span>
  #                         <span><%= length(poll.poll_options || []) %> options</span>
  #                         <span><%= length(poll.poll_votes || []) %> votes</span>
  #                       </div>
  #                     </div>

  #                     <div class="flex items-center space-x-2">
  #                       <button
  #                         type="button"
  #                         class="text-sm text-indigo-600 hover:text-indigo-500"
  #                         phx-click="view_poll_details"
  #                         phx-value-poll-id={poll.id}
  #                         phx-target={@myself}
  #                       >
  #                         View Details
  #                       </button>

  #                       <button
  #                         type="button"
  #                         class="text-sm text-gray-600 hover:text-gray-500"
  #                         phx-click="moderate_poll"
  #                         phx-value-poll-id={poll.id}
  #                         phx-target={@myself}
  #                       >
  #                         Moderate
  #                       </button>
  #                     </div>
  #                   </div>
  #                 </div>
  #               <% end %>
  #             </div>
  #           <% else %>
  #             <div class="text-center py-8 text-gray-500">
  #               <p>No polls created yet for this event.</p>
  #             </div>
  #           <% end %>
  #         </div>
  #       </div>
  #     <% else %>
  #       <div class="text-center py-8 text-gray-500">
  #         <p>You need organizer permissions to access poll management.</p>
  #       </div>
  #     <% end %>
  #   </div>
  #   """
  # end

  # # Render Analytics Section
  # defp render_analytics_section(assigns) do
  #   ~H"""
  #   <div class="analytics-section space-y-6">
  #     <div class="bg-white shadow sm:rounded-lg">
  #       <div class="px-4 py-5 sm:p-6">
  #         <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
  #           Event Polling Analytics
  #         </h3>

  #         <!-- Overall Statistics -->
  #         <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
  #           <div class="bg-gray-50 rounded-lg p-4 text-center">
  #             <div class="text-2xl font-bold text-gray-900"><%= @integration_stats.total_polls %></div>
  #             <div class="text-sm text-gray-600">Total Polls</div>
  #           </div>
  #           <div class="bg-gray-50 rounded-lg p-4 text-center">
  #             <div class="text-2xl font-bold text-gray-900"><%= @integration_stats.total_options %></div>
  #             <div class="text-sm text-gray-600">Total Options</div>
  #           </div>
  #           <div class="bg-gray-50 rounded-lg p-4 text-center">
  #             <div class="text-2xl font-bold text-gray-900"><%= @integration_stats.total_votes %></div>
  #             <div class="text-sm text-gray-600">Total Votes</div>
  #           </div>
  #           <div class="bg-gray-50 rounded-lg p-4 text-center">
  #             <div class="text-2xl font-bold text-gray-900"><%= @integration_stats.participation_rate %>%</div>
  #             <div class="text-sm text-gray-600">Participation Rate</div>
  #           </div>
  #         </div>

  #         <!-- Poll-Specific Analytics -->
  #         <%= if length(@polls || []) > 0 do %>
  #           <div class="space-y-6">
  #             <%= for poll <- @polls do %>
  #               <div class="border border-gray-200 rounded-lg p-4">
  #                 <div class="flex items-center justify-between mb-4">
  #                   <h4 class="font-medium text-gray-900"><%= poll.title %></h4>
  #                   <button
  #                     type="button"
  #                     class="text-sm text-indigo-600 hover:text-indigo-500"
  #                     phx-click="view_poll_results"
  #                     phx-value-poll-id={poll.id}
  #                     phx-target={@myself}
  #                   >
  #                     View Full Results
  #                   </button>
  #                 </div>

  #                 <!-- Embedded Results Display -->
  #                 <.live_component
  #                   module={ResultsDisplayComponent}
  #                   id={"poll-results-#{poll.id}"}
  #                   poll={poll}
  #                   compact_view={true}
  #                   show_voter_details={false}
  #                 />
  #               </div>
  #             <% end %>
  #           </div>
  #         <% else %>
  #           <div class="text-center py-8 text-gray-500">
  #             <p>No polling data available yet.</p>
  #           </div>
  #         <% end %>
  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  # # Render Poll Details Section
  # defp render_poll_details_section(assigns) do
  #   ~H"""
  #   <div class="poll-details-section">
  #     <%= if @selected_poll do %>
  #       <div class="mb-4">
  #         <button
  #           type="button"
  #           class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700"
  #           phx-click="back_to_overview"
  #           phx-target={@myself}
  #         >
  #           <svg class="mr-1 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
  #             <path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L4.414 9H17a1 1 0 110 2H4.414l5.293 5.293a1 1 0 010 1.414z" clip-rule="evenodd" />
  #           </svg>
  #           Back to Polls
  #         </button>
  #       </div>

  #       <!-- Poll Details Component (metadata and stats) -->
  #       <.live_component
  #         module={PollDetailsComponent}
  #         id="selected-poll-details"
  #         poll={@selected_poll}
  #         current_user={@current_user}
  #         event={@event}
  #         compact_view={false}
  #         show_metadata={true}
  #       />

  #       <!-- Option Suggestion Component (for list_building phase) -->
  #       <%= if @selected_poll.phase == "list_building" do %>
  #         <div class="mt-6">
  #           <.live_component
  #             module={OptionSuggestionComponent}
  #             id="poll-option-suggestions"
  #             poll={@selected_poll}
  #             user={@current_user}
  #             event={@event}
  #             is_creator={@current_user.id == @selected_poll.created_by_id}
  #             max_options={@selected_poll.max_options_per_user || 3}
  #           />
  #         </div>
  #       <% end %>

  #       <!-- Voting Interface Component (for voting phase) -->
  #       <%= if @selected_poll.phase == "voting" do %>
  #         <div class="mt-6">
  #           <.live_component
  #             module={VotingInterfaceComponent}
  #             id="poll-voting-interface"
  #             poll={@selected_poll}
  #             user={@current_user}
  #             user_votes={[]}
  #             loading={false}
  #           />
  #         </div>
  #       <% end %>

  #       <!-- Results Display Component (for closed phase) -->
  #       <%= if @selected_poll.phase == "closed" do %>
  #         <div class="mt-6">
  #           <.live_component
  #             module={ResultsDisplayComponent}
  #             id="poll-results-display"
  #             poll={@selected_poll}
  #             show_voter_details={false}
  #             compact_view={false}
  #           />
  #         </div>
  #       <% end %>

  #     <% else %>
  #       <div class="text-center py-8 text-gray-500">
  #         <p>No poll selected.</p>
  #       </div>
  #     <% end %>
  #   </div>
  #   """
  # end

  # # Render Empty State
  # defp render_empty_state(assigns) do
  #   ~H"""
  #   <div class="text-center py-12">
  #     <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
  #       <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012-2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
  #     </svg>
  #     <h3 class="mt-2 text-sm font-medium text-gray-900">No polls yet</h3>
  #     <p class="mt-1 text-sm text-gray-500">Get started by creating a poll for your event.</p>

  #     <%= if @can_create_polls do %>
  #       <div class="mt-6">
  #         <button
  #           type="button"
  #           class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
  #           phx-click="show_creation_modal"
  #           phx-target={@myself}
  #         >
  #           <svg class="-ml-1 mr-2 h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
  #             <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
  #           </svg>
  #           Create Your First Poll
  #         </button>
  #       </div>
  #     <% end %>
  #   </div>
  #   """
  # end

  # # Render Creation Prompt
  # defp render_creation_prompt(assigns) do
  #   ~H"""
  #   <div class="bg-indigo-50 border border-indigo-200 rounded-lg p-6">
  #     <div class="flex items-center">
  #       <div class="flex-shrink-0">
  #         <svg class="h-8 w-8 text-indigo-600" fill="currentColor" viewBox="0 0 20 20">
  #           <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
  #         </svg>
  #       </div>
  #       <div class="ml-4 flex-1">
  #         <h4 class="text-lg font-medium text-indigo-900">Create Collaborative Polls</h4>
  #         <p class="text-sm text-indigo-700 mt-1">
  #           Engage your event participants with interactive polls. Choose from movies, places, activities,
  #           and more with different voting systems like approval voting, ranked choice, and star ratings.
  #         </p>
  #         <div class="mt-4">
  #           <button
  #             type="button"
  #             class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
  #             phx-click="show_creation_modal"
  #             phx-target={@myself}
  #           >
  #             Get Started
  #           </button>
  #         </div>
  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  # # Render Flash Messages
  # defp render_flash_messages(assigns) do
  #   ~H"""
  #   <%= if @error_message do %>
  #     <div class="fixed top-4 right-4 z-50 max-w-sm w-full bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded shadow-lg">
  #       <div class="flex items-center justify-between">
  #         <span><%= @error_message %></span>
  #         <button
  #           type="button"
  #           class="ml-2 -mr-1 flex p-2"
  #           phx-click="clear_error"
  #           phx-target={@myself}
  #         >
  #           <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
  #             <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
  #           </svg>
  #         </button>
  #       </div>
  #     </div>
  #   <% end %>

  #   <%= if @success_message do %>
  #     <div class="fixed top-4 right-4 z-50 max-w-sm w-full bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded shadow-lg">
  #       <div class="flex items-center justify-between">
  #         <span><%= @success_message %></span>
  #         <button
  #           type="button"
  #           class="ml-2 -mr-1 flex p-2"
  #           phx-click="clear_success"
  #           phx-target={@myself}
  #         >
  #           <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
  #             <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
  #           </svg>
  #         </button>
  #       </div>
  #     </div>
  #   <% end %>
  #   """
  # end

  # Event Handlers

  @impl true
  def handle_event("change_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, :active_view, view)}
  end

  @impl true
  def handle_event("toggle_poll_menu", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    current_open = socket.assigns[:open_poll_menu]

    new_open = if current_open == poll_id, do: nil, else: poll_id

    {:noreply, assign(socket, :open_poll_menu, new_open)}
  end

  @impl true
  def handle_event("close_poll_menu", _params, socket) do
    {:noreply, assign(socket, :open_poll_menu, nil)}
  end

  @impl true
  def handle_event("edit_poll", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

    {:noreply,
     socket
     |> assign(:showing_creation_modal, true)
     |> assign(:editing_poll, poll)
     |> assign(:open_poll_menu, nil)}
  end

  @impl true
  def handle_event("close_poll", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

    if poll && can_close_poll?(poll, socket.assigns.current_user, socket.assigns.event) do
      case Events.transition_poll_phase(poll, "closed") do
        {:ok, updated_poll} ->
          # Update the poll in the list
          updated_polls =
            Enum.map(socket.assigns.polls, fn p ->
              if p.id == updated_poll.id, do: updated_poll, else: p
            end)

          {:noreply,
           socket
           |> assign(:polls, updated_polls)
           |> assign(:open_poll_menu, nil)
           |> assign(:success_message, "Poll '#{updated_poll.title}' has been closed.")}

        {:error, _} ->
          {:noreply, assign(socket, :error_message, "Failed to close poll")}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :error_message, "You don't have permission to close this poll")}
    end
  end

  @impl true
  def handle_event("toggle_poll_selection", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    selected_polls = socket.assigns.selected_polls || []

    updated_selected =
      if poll_id in selected_polls do
        Enum.reject(selected_polls, &(&1 == poll_id))
      else
        [poll_id | selected_polls]
      end

    {:noreply, assign(socket, :selected_polls, updated_selected)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_polls, [])}
  end

  @impl true
  def handle_event("batch_close_polls", _params, socket) do
    selected_polls = socket.assigns.selected_polls || []

    polls_to_close =
      socket.assigns.polls
      |> Enum.filter(&(&1.id in selected_polls))
      |> Enum.filter(&can_close_poll?(&1, socket.assigns.current_user, socket.assigns.event))

    {success_count, updated_polls} =
      Enum.reduce(polls_to_close, {0, socket.assigns.polls}, fn poll, {count, polls} ->
        case Events.transition_poll_phase(poll, "closed") do
          {:ok, updated_poll} ->
            updated_list =
              Enum.map(polls, fn p ->
                if p.id == updated_poll.id, do: updated_poll, else: p
              end)

            {count + 1, updated_list}

          _ ->
            {count, polls}
        end
      end)

    message =
      if success_count > 0 do
        "Successfully closed #{success_count} poll(s)"
      else
        "Failed to close selected polls"
      end

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:selected_polls, [])
     |> assign(:success_message, message)}
  end

  @impl true
  def handle_event("batch_delete_polls", _params, socket) do
    selected_polls = socket.assigns.selected_polls || []

    polls_to_delete =
      socket.assigns.polls
      |> Enum.filter(&(&1.id in selected_polls))
      |> Enum.filter(&can_delete_poll?(&1, socket.assigns.current_user, socket.assigns.event))

    {success_count, failed_count} =
      Enum.reduce(polls_to_delete, {0, 0}, fn poll, {success, failed} ->
        case Events.delete_poll(poll) do
          {:ok, _} -> {success + 1, failed}
          _ -> {success, failed + 1}
        end
      end)

    # Remove deleted polls from the list
    remaining_polls = Enum.reject(socket.assigns.polls, &(&1.id in selected_polls))
    integration_stats = calculate_integration_stats_with_polls(remaining_polls)

    message =
      cond do
        failed_count == 0 -> "Successfully deleted #{success_count} poll(s)"
        success_count > 0 -> "Deleted #{success_count} poll(s), #{failed_count} failed"
        true -> "Failed to delete selected polls"
      end

    {:noreply,
     socket
     |> assign(:polls, remaining_polls)
     |> assign(:integration_stats, integration_stats)
     |> assign(:selected_polls, [])
     |> assign(:success_message, message)}
  end

  @impl true
  def handle_event("filter_polls", params, socket) do
    poll_filter = case Map.get(params, "poll_filter") do
      "" -> "all"
      filter -> filter
    end

    poll_sort = case Map.get(params, "poll_sort") do
      "" -> "newest"
      sort -> sort
    end

    {:noreply,
     socket
     |> assign(:poll_filter, poll_filter)
     |> assign(:poll_sort, poll_sort)}
  end

  @impl true
  def handle_event("clear_poll_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:poll_filter, "all")
     |> assign(:poll_sort, "newest")}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    filtered_polls = get_filtered_polls(socket.assigns.polls, socket.assigns.poll_filter)
    all_poll_ids = Enum.map(filtered_polls, & &1.id)

    updated_selected =
      if length(socket.assigns.selected_polls) == length(all_poll_ids) do
        []
      else
        all_poll_ids
      end

    {:noreply, assign(socket, :selected_polls, updated_selected)}
  end

  @impl true
  def handle_event("toggle_reorder_mode", _params, socket) do
    if socket.assigns.reorder_mode do
      # Save the new order
      case save_poll_order(socket) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:reorder_mode, false)
           |> assign(:reordered_polls, [])
           |> assign(:success_message, "Poll order saved successfully!")}
        
        {:error, _} ->
          {:noreply,
           socket
           |> assign(:error_message, "Failed to save poll order. Please try again.")}
      end
    else
      # Enter reorder mode
      {:noreply,
       socket
       |> assign(:reorder_mode, true)
       |> assign(:reordered_polls, socket.assigns.polls || [])}
    end
  end

  @impl true
  def handle_event("move_poll_up", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    polls = socket.assigns.reordered_polls || socket.assigns.polls || []
    
    index = Enum.find_index(polls, &(&1.id == poll_id))
    
    if index && index > 0 do
      updated_polls = 
        polls
        |> List.delete_at(index)
        |> List.insert_at(index - 1, Enum.at(polls, index))
      
      {:noreply, assign(socket, :reordered_polls, updated_polls)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move_poll_down", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    polls = socket.assigns.reordered_polls || socket.assigns.polls || []
    
    index = Enum.find_index(polls, &(&1.id == poll_id))
    
    if index && index < length(polls) - 1 do
      updated_polls = 
        polls
        |> List.delete_at(index)
        |> List.insert_at(index + 1, Enum.at(polls, index))
      
      {:noreply, assign(socket, :reordered_polls, updated_polls)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_poll", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

    if poll && can_delete_poll?(poll, socket.assigns.current_user, socket.assigns.event) do
      case Events.delete_poll(poll) do
        {:ok, _} ->
          # Remove the poll from the list and recalculate stats
          updated_polls = Enum.reject(socket.assigns.polls, &(&1.id == poll_id))
          integration_stats = calculate_integration_stats_with_polls(updated_polls)

          {:noreply,
           socket
           |> assign(:polls, updated_polls)
           |> assign(:integration_stats, integration_stats)
           |> assign(:open_poll_menu, nil)
           |> assign(:success_message, "Poll deleted successfully!")}

        {:error, _changeset} ->
          {:noreply, assign(socket, :error_message, "Failed to delete poll. Please try again.")}

        nil ->
          {:noreply, assign(socket, :error_message, "Poll not found.")}
      end
    else
      {:noreply, assign(socket, :error_message, "You don't have permission to delete this poll")}
    end
  end

  @impl true
  def handle_event("show_creation_modal", _params, socket) do
    {:noreply, assign(socket, :showing_creation_modal, true)}
  end

  @impl true
  def handle_event("close_creation_modal", _params, socket) do
    # Send message to parent to reset editing state
    send(self(), {:close_poll_editing})
    {:noreply, assign(socket, :showing_creation_modal, false)}
  end

  @impl true
  def handle_event("view_poll_details", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    polls = socket.assigns.polls

    selected_poll = Enum.find(polls, &(&1.id == poll_id))

    # Send message to parent LiveView to handle poll details view
    send(self(), {:view_poll_details, selected_poll})

    {:noreply, socket |> assign(:open_poll_menu, nil)}
  end

  @impl true
  def handle_event("back_to_overview", _params, socket) do
    # Notify parent to close poll details view
    send(self(), {:close_poll_details})

    {:noreply, socket}
  end

  @impl true
  def handle_event("moderate_poll", %{"poll-id" => poll_id}, socket) do
    # Send message to parent LiveView to open moderation interface
    send(self(), {:open_poll_moderation, String.to_integer(poll_id)})
    {:noreply, socket}
  end

  @impl true
  def handle_event("view_poll_results", %{"poll-id" => poll_id}, socket) do
    # Send message to parent LiveView to open full results view
    send(self(), {:view_poll_results, String.to_integer(poll_id)})
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
  end

  @impl true
  def handle_event("clear_success", _params, socket) do
    {:noreply, assign(socket, :success_message, nil)}
  end

  # PubSub Event Handlers
  def handle_info({:poll_created, poll}, socket) do
    # Update polls list with new poll and recalculate stats
    updated_polls = [poll | socket.assigns.polls]

    integration_stats =
      calculate_integration_stats_with_polls(updated_polls, socket.assigns.event)

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:integration_stats, integration_stats)
     |> assign(:success_message, "Poll created successfully!")
     |> assign(:showing_creation_modal, false)
     |> assign(:editing_poll, nil)}
  end

  def handle_info({:poll_updated, updated_poll}, socket) do
    # Update the specific poll in the polls list
    updated_polls =
      Enum.map(socket.assigns.polls, fn poll ->
        if poll.id == updated_poll.id, do: updated_poll, else: poll
      end)

    integration_stats =
      calculate_integration_stats_with_polls(updated_polls, socket.assigns.event)

    # Update selected poll if it's the one that changed
    selected_poll =
      if socket.assigns.selected_poll && socket.assigns.selected_poll.id == updated_poll.id do
        updated_poll
      else
        socket.assigns.selected_poll
      end

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:integration_stats, integration_stats)
     |> assign(:selected_poll, selected_poll)}
  end

  def handle_info({:vote_cast, _poll_id, _user_id}, socket) do
    # Recalculate integration statistics
    integration_stats =
      calculate_integration_stats_with_polls(socket.assigns.polls, socket.assigns.event)

    {:noreply, assign(socket, :integration_stats, integration_stats)}
  end

  # Enhanced PubSub handlers for the new polling system
  def handle_info(%{type: :option_suggested, poll_id: poll_id} = message, socket) do
    # Find the poll and update it with the new option
    updated_polls =
      Enum.map(socket.assigns.polls, fn poll ->
        if poll.id == poll_id do
          # Add the new option to the poll's options
          new_option = message.option
          updated_options = [new_option | (poll.poll_options || [])]
          %{poll | poll_options: updated_options}
        else
          poll
        end
      end)

    integration_stats =
      calculate_integration_stats_with_polls(updated_polls, socket.assigns.event)

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:integration_stats, integration_stats)}
  end

  def handle_info(%{type: :option_visibility_changed, poll_id: poll_id} = message, socket) do
    # Update the option visibility in the poll
    updated_polls =
      Enum.map(socket.assigns.polls, fn poll ->
        if poll.id == poll_id do
          updated_options =
            Enum.map(poll.poll_options || [], fn option ->
              if option.id == message.option.id do
                %{option | is_visible: message.option.is_visible}
              else
                option
              end
            end)

          %{poll | poll_options: updated_options}
        else
          poll
        end
      end)

    {:noreply, assign(socket, :polls, updated_polls)}
  end

  def handle_info(%{type: :options_reordered, poll_id: poll_id} = message, socket) do
    # Update the poll with reordered options
    updated_polls =
      Enum.map(socket.assigns.polls, fn poll ->
        if poll.id == poll_id do
          %{poll | poll_options: message.updated_options}
        else
          poll
        end
      end)

    {:noreply, assign(socket, :polls, updated_polls)}
  end

  def handle_info(%{type: :poll_phase_changed, poll_id: poll_id} = message, socket) do
    # Update the poll's phase
    updated_polls =
      Enum.map(socket.assigns.polls, fn poll ->
        if poll.id == poll_id do
          %{poll | phase: message.new_phase}
        else
          poll
        end
      end)

    integration_stats =
      calculate_integration_stats_with_polls(updated_polls, socket.assigns.event)

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:integration_stats, integration_stats)
     |> assign(:success_message, "Poll phase changed to #{format_phase_name(message.new_phase)}")}
  end

  def handle_info(%{type: :poll_counters_updated, poll_id: _poll_id} = _message, socket) do
    # Update counters - mainly affects statistics
    integration_stats =
      calculate_integration_stats_with_polls(socket.assigns.polls, socket.assigns.event)

    {:noreply, assign(socket, :integration_stats, integration_stats)}
  end

  def handle_info(%{type: :participant_joined, poll_id: _poll_id} = _message, socket) do
    # Update participant count
    integration_stats =
      calculate_integration_stats_with_polls(socket.assigns.polls, socket.assigns.event)

    {:noreply, assign(socket, :integration_stats, integration_stats)}
  end

  def handle_info(%{type: :duplicate_detected} = message, socket) do
    # Show a notification about duplicate detection
    {:noreply,
     assign(
       socket,
       :error_message,
       "Duplicate option detected: #{message.suggested_option.title}"
     )}
  end

  def handle_info({:poll_saved, poll, message}, socket) do
    # Reload polls from the database to get the updated list
    event = socket.assigns.event
    polls = Events.list_polls(event)
    
    # Smart redirect: After poll creation, redirect to poll details view
    # This makes option addition more discoverable
    # Only redirect for new polls (not edited polls)
    if message =~ ~r/created/i do
      {:noreply,
       socket
       |> assign(:polls, polls)
       |> assign(:showing_creation_modal, false)
       |> assign(:editing_poll, nil)
       |> assign(:selected_poll, poll)
       |> assign(:active_view, "poll_details")
       |> assign(:success_message, "Poll created successfully! Add options to get started.")}
    else
      # For edited polls, just close the modal without redirecting
      {:noreply,
       socket
       |> assign(:polls, polls)
       |> assign(:showing_creation_modal, false)
       |> assign(:editing_poll, nil)
       |> assign(:success_message, message)}
    end
  end

  # Handle messages from child components
  def handle_info({:close_poll_creation_modal}, socket) do
    # Close the modal and reset all editing states
    send(self(), {:close_poll_editing})

    {:noreply,
     socket
     |> assign(:showing_creation_modal, false)
     |> assign(:showing_poll_details, false)
     |> assign(:editing_poll, nil)
     |> assign(:selected_poll, nil)}
  end

  def handle_info(%{type: :polls_reordered, event_id: event_id} = _message, socket) do
    # Reload polls when they are reordered
    if socket.assigns.event.id == event_id do
      # Reload polls from database to get the new order
      polls = Events.list_polls(socket.assigns.event)
      
      # Recalculate stats with the new poll order - use the same pattern as other handlers
      integration_stats = calculate_integration_stats_with_polls(polls, socket.assigns.event)
      
      {:noreply,
       socket
       |> assign(:polls, polls)
       |> assign(:integration_stats, integration_stats)
       |> assign(:success_message, "Poll order saved successfully!")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helper functions

  # Render poll type specific icon
  defp render_poll_type_icon(poll_type) do
    case poll_type do
      "movie" ->
        Phoenix.HTML.raw("""
        <svg class="h-5 w-5 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"/>
        </svg>
        """)

      "places" ->
        Phoenix.HTML.raw("""
        <svg class="h-5 w-5 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/>
        </svg>
        """)

      "time" ->
        Phoenix.HTML.raw("""
        <svg class="h-5 w-5 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
        </svg>
        """)

      "date_selection" ->
        Phoenix.HTML.raw("""
        <svg class="h-5 w-5 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
        </svg>
        """)

      "music_track" ->
        Phoenix.HTML.raw("""
        <svg class="h-5 w-5 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"/>
        </svg>
        """)

      # Default for "custom" and any other type
      _ ->
        Phoenix.HTML.raw("""
        <svg class="h-5 w-5 text-indigo-600" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M3 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z" clip-rule="evenodd" />
        </svg>
        """)
    end
  end

  defp calculate_integration_stats_with_polls(polls, event \\ nil) do
    total_polls = length(polls)
    active_polls = Enum.count(polls, &(&1.phase in ["list_building", "voting"]))
    completed_polls = Enum.count(polls, &(&1.phase == "closed"))

    total_options = polls |> Enum.map(&length(&1.poll_options || [])) |> Enum.sum()

    # Safely get poll votes - handle case where association isn't loaded
    total_votes =
      polls
      |> Enum.map(fn poll ->
        case Map.get(poll, :poll_votes) do
          %Ecto.Association.NotLoaded{} -> 0
          votes when is_list(votes) -> length(votes)
          nil -> 0
        end
      end)
      |> Enum.sum()

    # Calculate participation rate (if event is provided)
    {participation_rate, unique_voters} =
      if event do
        total_participants = length(event.participants || [])

        # Safely get unique voters - handle case where association isn't loaded
        unique_voters =
          polls
          |> Enum.flat_map(fn poll ->
            case Map.get(poll, :poll_votes) do
              %Ecto.Association.NotLoaded{} -> []
              votes when is_list(votes) -> votes
              nil -> []
            end
          end)
          |> Enum.map(& &1.voter_id)
          |> Enum.uniq()
          |> length()

        participation_rate =
          if total_participants > 0 do
            round(unique_voters / total_participants * 100)
          else
            0
          end

        {participation_rate, unique_voters}
      else
        {0, 0}
      end

    %{
      total_polls: total_polls,
      active_polls: active_polls,
      completed_polls: completed_polls,
      total_options: total_options,
      total_votes: total_votes,
      participation_rate: participation_rate,
      unique_voters: unique_voters
    }
  end

  # defp get_navigation_items(stats) do
  #   [
  #     {"overview", "Overview", "M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2H5a2 2 0 00-2-2V5a2 2 0 012-2h14a2 2 0 012 2v2"},
  #     {"create", "Create", "M12 4v16m8-8H4"},
  #     {"manage", "Manage", "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"},
  #     {"analytics", "Analytics (#{stats.total_votes})", "M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"}
  #   ]
  # end

  # defp get_tab_classes(is_active) do
  #   base_classes = "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm flex items-center"

  #   if is_active do
  #     "#{base_classes} border-indigo-500 text-indigo-600"
  #   else
  #     "#{base_classes} border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
  #   end
  # end

  # defp get_status_classes(status) do
  #   case status do
  #     "list_building" -> "bg-blue-100 text-blue-800"
  #     "voting" -> "bg-green-100 text-green-800"
  #     "closed" -> "bg-gray-100 text-gray-800"
  #     _ -> "bg-red-100 text-red-800"
  #   end
  # end

  defp format_phase_name(phase) do
    case phase do
      "list_building" -> "suggestion collection"
      "voting" -> "voting"
      "closed" -> "results"
      _ -> phase
    end
  end

  # Helper functions for the new guests-style layout
  defp get_poll_status_badge_data(phase) do
    case phase do
      "list_building" ->
        {"🔨 Building", "bg-blue-100 text-blue-800 border border-blue-200"}

      "voting" ->
        {"🟢 Active", "bg-green-100 text-green-800 border border-green-200 animate-pulse"}

      "voting_with_suggestions" ->
        {"🟢 Active + Suggestions",
         "bg-green-100 text-green-800 border border-green-200 animate-pulse"}

      "voting_only" ->
        {"🟡 Voting Only", "bg-amber-100 text-amber-800 border border-amber-200"}

      "closed" ->
        {"🔴 Closed", "bg-gray-100 text-gray-800 border border-gray-200"}

      _ ->
        {"Unknown", "bg-gray-100 text-gray-800 border border-gray-200"}
    end
  end

  defp get_poll_vote_count(poll) do
    case poll do
      %{poll_options: options} when is_list(options) ->
        Enum.reduce(options, 0, fn option, acc ->
          case option do
            %{votes: votes} when is_list(votes) -> acc + length(votes)
            _ -> acc
          end
        end)

      _ ->
        0
    end
  end

  # Authorization helper functions
  defp can_manage_poll?(poll, user, event) do
    # User can manage poll if they are:
    # 1. The poll creator
    # 2. An event organizer
    # 3. The event creator
    cond do
      is_nil(user) -> false
      poll.created_by_id == user.id -> true
      event.user_id == user.id -> true
      Events.user_is_organizer?(event, user) -> true
      true -> false
    end
  end

  defp can_close_poll?(poll, user, event) do
    can_manage_poll?(poll, user, event) &&
      Map.get(poll, :phase, "list_building") in [
        "list_building",
        "voting",
        "voting_with_suggestions",
        "voting_only"
      ]
  end

  defp can_delete_poll?(poll, user, event) do
    # Only poll creator or event creator can delete
    cond do
      is_nil(user) -> false
      poll.created_by_id == user.id -> true
      event.user_id == user.id -> true
      true -> false
    end
  end

  defp save_poll_order(socket) do
    polls = socket.assigns.reordered_polls || []
    event_id = socket.assigns.event.id
    
    # Create the poll orders list with new indices
    poll_orders = 
      polls
      |> Enum.with_index()
      |> Enum.map(fn {poll, index} ->
        %{poll_id: poll.id, order_index: index}
      end)
    
    # Call the Events context function to save the new order
    Events.reorder_polls(event_id, poll_orders)
  end

  # Filtering helper functions
  defp get_filtered_polls(polls, filter) when is_list(polls) do
    case filter do
      "all" ->
        polls

      "active" ->
        Enum.filter(polls, fn poll ->
          Map.get(poll, :phase, "list_building") in [
            "list_building",
            "voting",
            "voting_with_suggestions",
            "voting_only"
          ]
        end)

      "closed" ->
        Enum.filter(polls, fn poll ->
          Map.get(poll, :phase, "list_building") == "closed"
        end)

      "date_selection" ->
        Enum.filter(polls, fn poll ->
          Map.get(poll, :poll_type, "general") == "date_selection"
        end)

      "general" ->
        Enum.filter(polls, fn poll ->
          Map.get(poll, :poll_type, "general") == "general"
        end)

      _ ->
        polls
    end
  end
  
  defp get_filtered_polls(_, _), do: []

  # Sorting helper functions
  defp get_sorted_polls(polls, sort) when is_list(polls) do
    case sort do
      "newest" ->
        # Keep the order_index ordering from the database (default ordering)
        # Don't sort by inserted_at as that overrides the manual ordering
        polls

      "oldest" ->
        # For oldest, reverse the default order
        Enum.reverse(polls)

      "most_votes" ->
        Enum.sort_by(polls, &get_poll_vote_count/1, :desc)

      "least_votes" ->
        Enum.sort_by(polls, &get_poll_vote_count/1, :asc)

      "name" ->
        Enum.sort_by(polls, & &1.title, :asc)

      _ ->
        polls
    end
  end
  
  defp get_sorted_polls(_, _), do: []

  # Helper function to format time for display
  defp format_relative_time(datetime) do
    case datetime do
      nil ->
        "recently"

      datetime ->
        now = DateTime.utc_now()

        datetime_utc =
          case datetime do
            %DateTime{} = dt ->
              dt

            %NaiveDateTime{} = ndt ->
              case DateTime.from_naive(ndt, "Etc/UTC") do
                {:ok, dt} -> dt
                {:error, _} -> now
              end

            _ ->
              # Log unexpected type for debugging
              require Logger

              Logger.warning(
                "Unexpected datetime type in format_relative_time: #{inspect(datetime)}"
              )

              now
          end

        diff = DateTime.diff(now, datetime_utc, :second)

        cond do
          diff < 60 -> "just now"
          diff < 3600 -> "#{div(diff, 60)}m ago"
          diff < 86400 -> "#{div(diff, 3600)}h ago"
          diff < 2_592_000 -> "#{div(diff, 86400)}d ago"
          true -> "#{div(diff, 2_592_000)}mo ago"
        end
    end
  end
end
