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
  alias Phoenix.PubSub

  # Import the other polling components
  alias EventasaurusWeb.PollListComponent
  alias EventasaurusWeb.PollCreationComponent
  alias EventasaurusWeb.PollDetailsComponent
  alias EventasaurusWeb.OptionSuggestionComponent
  alias EventasaurusWeb.VotingInterfaceComponent
  alias EventasaurusWeb.ResultsDisplayComponent
  alias EventasaurusWeb.PollModerationComponent

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
     |> assign(:integration_stats, %{})}
  end

  @impl true
  def update(assigns, socket) do
    # Subscribe to real-time updates for all polls in this event
    if connected?(socket) do
      PubSub.subscribe(EventasaurusApp.PubSub, "polls:event:#{assigns.event.id}")
      PubSub.subscribe(EventasaurusApp.PubSub, "votes:event:#{assigns.event.id}")
      PubSub.subscribe(EventasaurusApp.PubSub, "event:#{assigns.event.id}")
    end

    # Calculate integration statistics
    integration_stats = calculate_integration_stats(assigns.event)

    # Determine user permissions
    can_create_polls = Events.can_create_poll?(assigns.event, assigns.current_user)
    is_organizer = Events.user_is_organizer?(assigns.event, assigns.current_user)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:integration_mode, fn -> "embedded" end)
     |> assign_new(:show_creation_prompt, fn -> true end)
     |> assign_new(:compact_mode, fn -> false end)
     |> assign(:integration_stats, integration_stats)
     |> assign(:can_create_polls, can_create_polls)
     |> assign(:is_organizer, is_organizer)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={"polling-integration #{@integration_mode}-mode"}>
      <!-- Integration Header -->
      <%= render_integration_header(assigns) %>

      <!-- Navigation for Different Views -->
      <%= if @integration_mode in ["tab", "sidebar"] do %>
        <%= render_navigation_tabs(assigns) %>
      <% end %>

      <!-- Main Content Area -->
      <div class="integration-content">
        <%= case @active_view do %>
          <% "overview" -> %>
            <%= render_overview_section(assigns) %>

          <% "create" -> %>
            <%= render_creation_section(assigns) %>

          <% "manage" -> %>
            <%= render_management_section(assigns) %>

          <% "analytics" -> %>
            <%= render_analytics_section(assigns) %>

          <% "poll_details" -> %>
            <%= render_poll_details_section(assigns) %>
        <% end %>
      </div>

      <!-- Floating Action Button (for embedded mode) -->
      <%= if @integration_mode == "embedded" and @can_create_polls and length(@event.polls || []) > 0 do %>
        <div class="fixed bottom-6 right-6 z-50">
          <button
            type="button"
            class="inline-flex items-center justify-center p-3 bg-indigo-600 text-white rounded-full shadow-lg hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-all duration-200"
            phx-click="show_creation_modal"
            phx-target={@myself}
            title="Create New Poll"
          >
            <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
          </button>
        </div>
      <% end %>

      <!-- Poll Creation Modal -->
      <%= if @showing_creation_modal do %>
        <.live_component
          module={PollCreationComponent}
          id="poll-creation-modal"
          event={@event}
          current_user={@current_user}
          poll={nil}
        />
      <% end %>

      <!-- Messages -->
      <%= render_flash_messages(assigns) %>
    </div>
    """
  end

  # Render Integration Header
  defp render_integration_header(assigns) do
    ~H"""
    <div class={"header-section #{if @integration_mode == "sidebar", do: "sidebar-header", else: "main-header"}"}>
      <div class="flex items-center justify-between">
        <div>
          <h2 class={"font-semibold #{if @integration_mode == "sidebar", do: "text-lg text-gray-900", else: "text-2xl text-gray-900"}"}>
            <span class="inline-flex items-center">
              <svg class="mr-2 h-5 w-5 text-indigo-600" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 2a4 4 0 00-4 4v1H5a1 1 0 00-.994.89l-1 9A1 1 0 004 18h12a1 1 0 00.994-1.11l-1-9A1 1 0 0015 7h-1V6a4 4 0 00-4-4zM8 6V5a2 2 0 114 0v1H8zm2 6a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1z" clip-rule="evenodd" />
              </svg>
              Event Polls
            </span>
          </h2>

          <%= unless @integration_mode == "sidebar" do %>
            <p class="text-sm text-gray-600 mt-1">
              Collaborative polling for <%= @event.title %>
            </p>
          <% end %>
        </div>

        <!-- Quick Stats -->
        <div class="flex items-center space-x-4 text-sm">
          <%= if length(@event.polls || []) > 0 do %>
            <div class="flex items-center space-x-4">
              <div class="text-center">
                <div class="text-lg font-semibold text-gray-900"><%= @integration_stats.total_polls %></div>
                <div class="text-gray-500">Polls</div>
              </div>
              <div class="text-center">
                <div class="text-lg font-semibold text-gray-900"><%= @integration_stats.active_polls %></div>
                <div class="text-gray-500">Active</div>
              </div>
              <div class="text-center">
                <div class="text-lg font-semibold text-gray-900"><%= @integration_stats.total_votes %></div>
                <div class="text-gray-500">Votes</div>
              </div>
            </div>
          <% end %>

          <!-- Create Poll Button -->
          <%= if @can_create_polls and @integration_mode != "embedded" do %>
            <button
              type="button"
              class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              phx-click="show_creation_modal"
              phx-target={@myself}
            >
              <svg class="-ml-0.5 mr-2 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
              </svg>
              New Poll
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Render Navigation Tabs (for tab and sidebar modes)
  defp render_navigation_tabs(assigns) do
    ~H"""
    <nav class="border-b border-gray-200 mt-4">
      <div class="-mb-px flex space-x-8">
        <%= for {view, label, icon} <- get_navigation_items(@integration_stats) do %>
          <button
            type="button"
            class={get_tab_classes(@active_view == view)}
            phx-click="change_view"
            phx-value-view={view}
            phx-target={@myself}
          >
            <svg class="-ml-0.5 mr-2 h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
              <path d={icon}/>
            </svg>
            <%= label %>
          </button>
        <% end %>
      </div>
    </nav>
    """
  end

  # Render Overview Section
  defp render_overview_section(assigns) do
    ~H"""
    <div class="overview-section space-y-6">
      <!-- Polls List -->
      <%= if length(@event.polls || []) > 0 do %>
        <.live_component
          module={PollListComponent}
          id="event-polls-list"
          event={@event}
          current_user={@current_user}
          compact_view={@compact_mode}
        />
      <% else %>
        <%= render_empty_state(assigns) %>
      <% end %>

      <!-- Quick Creation Prompt -->
      <%= if @show_creation_prompt and @can_create_polls and length(@event.polls || []) == 0 do %>
        <%= render_creation_prompt(assigns) %>
      <% end %>
    </div>
    """
  end

  # Render Creation Section
  defp render_creation_section(assigns) do
    ~H"""
    <div class="creation-section">
      <div class="max-w-4xl mx-auto">
        <div class="bg-white shadow sm:rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
              Create a New Poll
            </h3>
            <p class="text-sm text-gray-600 mb-6">
              Set up a collaborative poll for your event participants. Choose from different poll types
              and voting systems to gather input from your community.
            </p>

            <!-- Creation Form/Component Would Go Here -->
            <div class="text-center py-8 text-gray-500">
              <button
                type="button"
                class="inline-flex items-center px-4 py-2 border border-transparent text-base font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                phx-click="show_creation_modal"
                phx-target={@myself}
              >
                <svg class="-ml-1 mr-3 h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
                </svg>
                Create Poll
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Render Management Section (for organizers)
  defp render_management_section(assigns) do
    ~H"""
    <div class="management-section space-y-6">
      <%= if @is_organizer do %>
        <!-- Poll Management Dashboard -->
        <div class="bg-white shadow sm:rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
              Poll Management Dashboard
            </h3>

            <!-- Management Actions -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
              <div class="bg-blue-50 rounded-lg p-4">
                <h4 class="font-medium text-blue-900">Active Polls</h4>
                <p class="text-2xl font-bold text-blue-600"><%= @integration_stats.active_polls %></p>
                <p class="text-sm text-blue-700">Currently accepting votes</p>
              </div>

              <div class="bg-green-50 rounded-lg p-4">
                <h4 class="font-medium text-green-900">Completed Polls</h4>
                <p class="text-2xl font-bold text-green-600"><%= @integration_stats.completed_polls %></p>
                <p class="text-sm text-green-700">Results available</p>
              </div>

              <div class="bg-purple-50 rounded-lg p-4">
                <h4 class="font-medium text-purple-900">Total Participation</h4>
                <p class="text-2xl font-bold text-purple-600"><%= @integration_stats.total_votes %></p>
                <p class="text-sm text-purple-700">Votes across all polls</p>
              </div>
            </div>

            <!-- Poll List with Management Actions -->
            <%= if length(@event.polls || []) > 0 do %>
              <div class="space-y-4">
                <%= for poll <- @event.polls do %>
                  <div class="border border-gray-200 rounded-lg p-4">
                    <div class="flex items-center justify-between">
                      <div>
                        <h5 class="font-medium text-gray-900"><%= poll.title %></h5>
                        <p class="text-sm text-gray-600"><%= poll.description %></p>
                        <div class="flex items-center space-x-4 text-xs text-gray-500 mt-2">
                          <span class={"inline-flex items-center px-2 py-1 rounded-full text-xs font-medium #{get_status_classes(poll.status)}"}>
                            <%= String.replace(poll.status, "_", " ") |> String.capitalize() %>
                          </span>
                          <span><%= length(poll.poll_options || []) %> options</span>
                          <span><%= length(poll.poll_votes || []) %> votes</span>
                        </div>
                      </div>

                      <div class="flex items-center space-x-2">
                        <button
                          type="button"
                          class="text-sm text-indigo-600 hover:text-indigo-500"
                          phx-click="view_poll_details"
                          phx-value-poll-id={poll.id}
                          phx-target={@myself}
                        >
                          View Details
                        </button>

                        <button
                          type="button"
                          class="text-sm text-gray-600 hover:text-gray-500"
                          phx-click="moderate_poll"
                          phx-value-poll-id={poll.id}
                          phx-target={@myself}
                        >
                          Moderate
                        </button>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-center py-8 text-gray-500">
                <p>No polls created yet for this event.</p>
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="text-center py-8 text-gray-500">
          <p>You need organizer permissions to access poll management.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Render Analytics Section
  defp render_analytics_section(assigns) do
    ~H"""
    <div class="analytics-section space-y-6">
      <div class="bg-white shadow sm:rounded-lg">
        <div class="px-4 py-5 sm:p-6">
          <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
            Event Polling Analytics
          </h3>

          <!-- Overall Statistics -->
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
            <div class="bg-gray-50 rounded-lg p-4 text-center">
              <div class="text-2xl font-bold text-gray-900"><%= @integration_stats.total_polls %></div>
              <div class="text-sm text-gray-600">Total Polls</div>
            </div>
            <div class="bg-gray-50 rounded-lg p-4 text-center">
              <div class="text-2xl font-bold text-gray-900"><%= @integration_stats.total_options %></div>
              <div class="text-sm text-gray-600">Total Options</div>
            </div>
            <div class="bg-gray-50 rounded-lg p-4 text-center">
              <div class="text-2xl font-bold text-gray-900"><%= @integration_stats.total_votes %></div>
              <div class="text-sm text-gray-600">Total Votes</div>
            </div>
            <div class="bg-gray-50 rounded-lg p-4 text-center">
              <div class="text-2xl font-bold text-gray-900"><%= @integration_stats.participation_rate %>%</div>
              <div class="text-sm text-gray-600">Participation Rate</div>
            </div>
          </div>

          <!-- Poll-Specific Analytics -->
          <%= if length(@event.polls || []) > 0 do %>
            <div class="space-y-6">
              <%= for poll <- @event.polls do %>
                <div class="border border-gray-200 rounded-lg p-4">
                  <div class="flex items-center justify-between mb-4">
                    <h4 class="font-medium text-gray-900"><%= poll.title %></h4>
                    <button
                      type="button"
                      class="text-sm text-indigo-600 hover:text-indigo-500"
                      phx-click="view_poll_results"
                      phx-value-poll-id={poll.id}
                      phx-target={@myself}
                    >
                      View Full Results
                    </button>
                  </div>

                  <!-- Embedded Results Display -->
                  <.live_component
                    module={ResultsDisplayComponent}
                    id={"poll-results-#{poll.id}"}
                    poll={poll}
                    compact_view={true}
                    show_voter_details={false}
                  />
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="text-center py-8 text-gray-500">
              <p>No polling data available yet.</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Render Poll Details Section
  defp render_poll_details_section(assigns) do
    ~H"""
    <div class="poll-details-section">
      <%= if @selected_poll do %>
        <div class="mb-4">
          <button
            type="button"
            class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700"
            phx-click="back_to_overview"
            phx-target={@myself}
          >
            <svg class="mr-1 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L4.414 9H17a1 1 0 110 2H4.414l5.293 5.293a1 1 0 010 1.414z" clip-rule="evenodd" />
            </svg>
            Back to Polls
          </button>
        </div>

        <.live_component
          module={PollDetailsComponent}
          id="selected-poll-details"
          poll={@selected_poll}
          current_user={@current_user}
          event={@event}
          compact_view={false}
          show_metadata={true}
        />
      <% else %>
        <div class="text-center py-8 text-gray-500">
          <p>No poll selected.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Render Empty State
  defp render_empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012-2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
      </svg>
      <h3 class="mt-2 text-sm font-medium text-gray-900">No polls yet</h3>
      <p class="mt-1 text-sm text-gray-500">Get started by creating a poll for your event.</p>

      <%= if @can_create_polls do %>
        <div class="mt-6">
          <button
            type="button"
            class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            phx-click="show_creation_modal"
            phx-target={@myself}
          >
            <svg class="-ml-1 mr-2 h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
            </svg>
            Create Your First Poll
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  # Render Creation Prompt
  defp render_creation_prompt(assigns) do
    ~H"""
    <div class="bg-indigo-50 border border-indigo-200 rounded-lg p-6">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <svg class="h-8 w-8 text-indigo-600" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
          </svg>
        </div>
        <div class="ml-4 flex-1">
          <h4 class="text-lg font-medium text-indigo-900">Create Collaborative Polls</h4>
          <p class="text-sm text-indigo-700 mt-1">
            Engage your event participants with interactive polls. Choose from movies, restaurants, activities,
            and more with different voting systems like approval voting, ranked choice, and star ratings.
          </p>
          <div class="mt-4">
            <button
              type="button"
              class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              phx-click="show_creation_modal"
              phx-target={@myself}
            >
              Get Started
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Render Flash Messages
  defp render_flash_messages(assigns) do
    ~H"""
    <%= if @error_message do %>
      <div class="fixed top-4 right-4 z-50 max-w-sm w-full bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded shadow-lg">
        <div class="flex items-center justify-between">
          <span><%= @error_message %></span>
          <button
            type="button"
            class="ml-2 -mr-1 flex p-2"
            phx-click="clear_error"
            phx-target={@myself}
          >
            <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
            </svg>
          </button>
        </div>
      </div>
    <% end %>

    <%= if @success_message do %>
      <div class="fixed top-4 right-4 z-50 max-w-sm w-full bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded shadow-lg">
        <div class="flex items-center justify-between">
          <span><%= @success_message %></span>
          <button
            type="button"
            class="ml-2 -mr-1 flex p-2"
            phx-click="clear_success"
            phx-target={@myself}
          >
            <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
            </svg>
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("change_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, :active_view, view)}
  end

  @impl true
  def handle_event("show_creation_modal", _params, socket) do
    {:noreply, assign(socket, :showing_creation_modal, true)}
  end

  @impl true
  def handle_event("close_creation_modal", _params, socket) do
    {:noreply, assign(socket, :showing_creation_modal, false)}
  end

  @impl true
  def handle_event("view_poll_details", %{"poll-id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    selected_poll = Enum.find(socket.assigns.event.polls, &(&1.id == poll_id))

    {:noreply,
     socket
     |> assign(:selected_poll, selected_poll)
     |> assign(:active_view, "poll_details")}
  end

  @impl true
  def handle_event("back_to_overview", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_poll, nil)
     |> assign(:active_view, "overview")}
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
  @impl true
  def handle_info({:poll_created, poll}, socket) do
    # Update event with new poll and recalculate stats
    updated_event = %{socket.assigns.event | polls: [poll | socket.assigns.event.polls]}
    integration_stats = calculate_integration_stats(updated_event)

    {:noreply,
     socket
     |> assign(:event, updated_event)
     |> assign(:integration_stats, integration_stats)
     |> assign(:success_message, "Poll created successfully!")
     |> assign(:showing_creation_modal, false)}
  end

  @impl true
  def handle_info({:poll_updated, updated_poll}, socket) do
    # Update the specific poll in the event
    updated_polls = Enum.map(socket.assigns.event.polls, fn poll ->
      if poll.id == updated_poll.id, do: updated_poll, else: poll
    end)

    updated_event = %{socket.assigns.event | polls: updated_polls}
    integration_stats = calculate_integration_stats(updated_event)

    # Update selected poll if it's the one that changed
    selected_poll = if socket.assigns.selected_poll && socket.assigns.selected_poll.id == updated_poll.id do
      updated_poll
    else
      socket.assigns.selected_poll
    end

    {:noreply,
     socket
     |> assign(:event, updated_event)
     |> assign(:integration_stats, integration_stats)
     |> assign(:selected_poll, selected_poll)}
  end

  @impl true
  def handle_info({:vote_cast, poll_id, _user_id}, socket) do
    # Recalculate integration statistics
    integration_stats = calculate_integration_stats(socket.assigns.event)
    {:noreply, assign(socket, :integration_stats, integration_stats)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helper functions

  defp calculate_integration_stats(event) do
    polls = event.polls || []

    total_polls = length(polls)
    active_polls = Enum.count(polls, &(&1.status in ["list_building", "voting"]))
    completed_polls = Enum.count(polls, &(&1.status == "closed"))

    total_options = polls |> Enum.map(&length(&1.poll_options || [])) |> Enum.sum()
    total_votes = polls |> Enum.map(&length(&1.poll_votes || [])) |> Enum.sum()

    # Calculate participation rate (assuming event has participants)
    total_participants = length(event.participants || [])
    unique_voters = polls
    |> Enum.flat_map(&(&1.poll_votes || []))
    |> Enum.map(&(&1.user_id))
    |> Enum.uniq()
    |> length()

    participation_rate = if total_participants > 0 do
      round((unique_voters / total_participants) * 100)
    else
      0
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

  defp get_navigation_items(stats) do
    [
      {"overview", "Overview", "M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2H5a2 2 0 00-2-2V5a2 2 0 012-2h14a2 2 0 012 2v2"},
      {"create", "Create", "M12 4v16m8-8H4"},
      {"manage", "Manage", "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"},
      {"analytics", "Analytics (#{stats.total_votes})", "M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"}
    ]
  end

  defp get_tab_classes(is_active) do
    base_classes = "whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm flex items-center"

    if is_active do
      "#{base_classes} border-indigo-500 text-indigo-600"
    else
      "#{base_classes} border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
    end
  end

  defp get_status_classes(status) do
    case status do
      "list_building" -> "bg-blue-100 text-blue-800"
      "voting" -> "bg-green-100 text-green-800"
      "closed" -> "bg-gray-100 text-gray-800"
      _ -> "bg-red-100 text-red-800"
    end
  end
end
