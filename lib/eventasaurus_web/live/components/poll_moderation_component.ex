defmodule EventasaurusWeb.PollModerationComponent do
  @moduledoc """
  A comprehensive LiveView component for poll moderation and management tools.

  Provides advanced moderation capabilities for poll creators including option
  management, phase transitions, user management, and poll settings. This is
  the central control panel for poll administration.

  ## Attributes:
  - poll: Poll struct with preloaded options, votes, and creator (required)
  - current_user: Current user struct for permission checks (required)
  - event: Event struct for context (required)
  - show_advanced_options: Whether to show advanced moderation features (default: false)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.PollModerationComponent}
        id="poll-moderation"
        poll={@poll}
        current_user={@current_user}
        event={@event}
        show_advanced_options={false}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias Phoenix.PubSub

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:selected_options, [])
     |> assign(:bulk_action, nil)
     |> assign(:showing_confirmation, false)
     |> assign(:confirmation_message, "")
     |> assign(:confirmation_action, nil)
     |> assign(:moderation_stats, %{})}
  end

  @impl true
  def update(assigns, socket) do
    # Subscribe to real-time updates
    if connected?(socket) do
      PubSub.subscribe(Eventasaurus.PubSub, "polls:#{assigns.poll.id}")
      PubSub.subscribe(Eventasaurus.PubSub, "votes:poll:#{assigns.poll.id}")
      PubSub.subscribe(Eventasaurus.PubSub, "poll_options:#{assigns.poll.id}")
    end

    # Check permissions
    can_moderate = can_user_moderate_poll?(assigns.current_user, assigns.poll, assigns.event)

    if not can_moderate do
      raise "User not authorized to moderate this poll"
    end

    # Calculate moderation statistics
    moderation_stats = calculate_moderation_stats(assigns.poll)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:can_moderate, can_moderate)
     |> assign(:moderation_stats, moderation_stats)
     |> assign_new(:show_advanced_options, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg">
      <!-- Header -->
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-lg font-medium text-gray-900">Poll Moderation</h3>
            <p class="text-sm text-gray-500">
              Manage options, phases, and settings for "<%= @poll.title %>"
            </p>
          </div>

          <div class="flex items-center space-x-2">
            <%= render_poll_status_indicator(@poll.status) %>
          </div>
        </div>
      </div>

      <!-- Quick Stats -->
      <div class="px-6 py-4 bg-gray-50 border-b border-gray-200">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div class="text-center">
            <div class="text-lg font-semibold text-gray-900"><%= @moderation_stats.total_options %></div>
            <div class="text-gray-500">Total Options</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-semibold text-gray-900"><%= @moderation_stats.hidden_options %></div>
            <div class="text-gray-500">Hidden</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-semibold text-gray-900"><%= @moderation_stats.user_suggestions %></div>
            <div class="text-gray-500">User Suggestions</div>
          </div>
          <div class="text-center">
            <div class="text-lg font-semibold text-gray-900"><%= @moderation_stats.total_votes %></div>
            <div class="text-gray-500">Total Votes</div>
          </div>
        </div>
      </div>

      <!-- Phase Management -->
      <div class="px-6 py-4 border-b border-gray-200">
        <h4 class="text-md font-medium text-gray-900 mb-3">Phase Management</h4>
        <div class="flex items-center space-x-4">
          <%= render_phase_controls(assigns) %>
        </div>
      </div>

      <!-- Option Management -->
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center justify-between mb-4">
          <h4 class="text-md font-medium text-gray-900">Option Management</h4>

          <!-- Bulk Actions -->
          <%= if length(@selected_options) > 0 do %>
            <div class="flex items-center space-x-2">
              <span class="text-sm text-gray-500">
                <%= length(@selected_options) %> selected
              </span>
              <select
                class="block text-sm border-gray-300 rounded-md focus:ring-indigo-500 focus:border-indigo-500"
                phx-change="set_bulk_action"
                phx-target={@myself}
              >
                <option value="">Bulk Actions</option>
                <option value="hide">Hide Selected</option>
                <option value="show">Show Selected</option>
                <option value="delete">Delete Selected</option>
              </select>
              <button
                type="button"
                class="text-sm text-indigo-600 hover:text-indigo-500"
                phx-click="clear_selection"
                phx-target={@myself}
              >
                Clear
              </button>
            </div>
          <% end %>
        </div>

        <!-- Options List -->
        <div class="space-y-3">
          <%= if length(@poll.poll_options) == 0 do %>
            <div class="text-center py-8 text-gray-500">
              <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012-2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
              </svg>
              <p class="mt-2">No options added yet</p>
              <p class="text-sm">Options will appear here once users start suggesting them</p>
            </div>
          <% else %>
            <%= for option <- @poll.poll_options do %>
              <%= render_option_management_row(assigns, option) %>
            <% end %>
          <% end %>
        </div>
      </div>

      <!-- Advanced Settings -->
      <%= if @show_advanced_options do %>
        <div class="px-6 py-4 border-b border-gray-200">
          <h4 class="text-md font-medium text-gray-900 mb-3">Advanced Settings</h4>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <!-- Deadline Management -->
            <div class="space-y-3">
              <h5 class="text-sm font-medium text-gray-700">Deadline Management</h5>

              <%= if @poll.list_building_deadline do %>
                <div class="flex items-center justify-between text-sm">
                  <span class="text-gray-600">List Building Deadline:</span>
                  <div class="flex items-center space-x-2">
                    <span class="font-medium"><%= format_deadline(@poll.list_building_deadline) %></span>
                    <button
                      type="button"
                      class="text-indigo-600 hover:text-indigo-500"
                      phx-click="extend_list_deadline"
                      phx-target={@myself}
                    >
                      Extend
                    </button>
                  </div>
                </div>
              <% end %>

              <%= if @poll.voting_deadline do %>
                <div class="flex items-center justify-between text-sm">
                  <span class="text-gray-600">Voting Deadline:</span>
                  <div class="flex items-center space-x-2">
                    <span class="font-medium"><%= format_deadline(@poll.voting_deadline) %></span>
                    <button
                      type="button"
                      class="text-indigo-600 hover:text-indigo-500"
                      phx-click="extend_voting_deadline"
                      phx-target={@myself}
                    >
                      Extend
                    </button>
                  </div>
                </div>
              <% end %>
            </div>

            <!-- User Management -->
            <div class="space-y-3">
              <h5 class="text-sm font-medium text-gray-700">User Management</h5>

              <div class="flex items-center justify-between text-sm">
                <span class="text-gray-600">Max Options per User:</span>
                <div class="flex items-center space-x-2">
                  <span class="font-medium"><%= @poll.max_options_per_user %></span>
                  <button
                    type="button"
                    class="text-indigo-600 hover:text-indigo-500"
                    phx-click="adjust_max_options"
                    phx-target={@myself}
                  >
                    Adjust
                  </button>
                </div>
              </div>

              <div class="flex items-center justify-between text-sm">
                <span class="text-gray-600">Auto-Finalize:</span>
                <button
                  type="button"
                  class={"text-sm font-medium #{if @poll.auto_finalize, do: "text-green-600", else: "text-gray-400"}"}
                  phx-click="toggle_auto_finalize"
                  phx-target={@myself}
                >
                  <%= if @poll.auto_finalize, do: "Enabled", else: "Disabled" %>
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Danger Zone -->
      <div class="px-6 py-4 bg-red-50 border-t border-gray-200">
        <h4 class="text-md font-medium text-red-900 mb-3">Danger Zone</h4>
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm text-red-700">Reset all votes and start over</p>
              <p class="text-xs text-red-600">This action cannot be undone</p>
            </div>
            <button
              type="button"
              class="inline-flex items-center px-3 py-2 border border-red-300 text-sm leading-4 font-medium rounded-md text-red-700 bg-white hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
              phx-click="reset_poll_votes"
              phx-target={@myself}
            >
              Reset All Votes
            </button>
          </div>
          <div class="flex items-center justify-between pt-3 border-t border-red-200">
            <div>
              <p class="text-sm text-red-700">Delete this poll permanently</p>
              <p class="text-xs text-red-600">This will remove the poll and all associated data</p>
            </div>
            <button
              type="button"
              class="inline-flex items-center px-3 py-2 border border-red-300 text-sm leading-4 font-medium rounded-md text-red-700 bg-white hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
              phx-click="delete_poll"
              phx-target={@myself}
            >
              Delete Poll
            </button>
          </div>
        </div>
      </div>

      <!-- Confirmation Modal -->
      <%= if @showing_confirmation do %>
        <div class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50" phx-click="cancel_confirmation" phx-target={@myself}>
          <div class="relative top-20 mx-auto p-5 border w-96 shadow-lg rounded-md bg-white" phx-click-away="cancel_confirmation" phx-target={@myself}>
            <div class="mt-3 text-center">
              <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-red-100">
                <svg class="h-6 w-6 text-red-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
                </svg>
              </div>
              <h3 class="text-lg leading-6 font-medium text-gray-900 mt-2">Confirm Action</h3>
              <div class="mt-2 px-7 py-3">
                <p class="text-sm text-gray-500"><%= @confirmation_message %></p>
              </div>
              <div class="items-center px-4 py-3">
                <button
                  type="button"
                  class="px-4 py-2 bg-red-500 text-white text-base font-medium rounded-md w-24 mr-2 hover:bg-red-600 focus:outline-none focus:ring-2 focus:ring-red-300"
                  phx-click="confirm_action"
                  phx-target={@myself}
                >
                  Confirm
                </button>
                <button
                  type="button"
                  class="px-4 py-2 bg-gray-500 text-white text-base font-medium rounded-md w-24 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-gray-300"
                  phx-click="cancel_confirmation"
                  phx-target={@myself}
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Render Poll Status Indicator
  defp render_poll_status_indicator(status) do
    {icon, text, classes} = case status do
      "list_building" ->
        {"M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4", "Building List", "bg-blue-100 text-blue-800"}
      "voting" ->
        {"M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z", "Voting Active", "bg-green-100 text-green-800"}
      "closed" ->
        {"M5 13l4 4L19 7", "Completed", "bg-gray-100 text-gray-800"}
      _ ->
        {"M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z", "Unknown", "bg-red-100 text-red-800"}
    end

    assigns = %{icon: icon, text: text, classes: classes}

    ~H"""
    <div class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{@classes}"}>
      <svg class="-ml-0.5 mr-1.5 h-2 w-2" fill="currentColor" viewBox="0 0 24 24">
        <path d={@icon}/>
      </svg>
      <%= @text %>
    </div>
    """
  end

  # Render Phase Controls
  defp render_phase_controls(assigns) do
    ~H"""
    <%= case @poll.status do %>
      <% "list_building" -> %>
        <%= if length(@poll.poll_options) > 0 do %>
          <button
            type="button"
            class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            phx-click="transition_to_voting"
            phx-target={@myself}
          >
            <svg class="-ml-1 mr-2 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10.293 15.707a1 1 0 010-1.414L14.586 10l-4.293-4.293a1 1 0 111.414-1.414l5 5a1 1 0 010 1.414l-5 5a1 1 0 01-1.414 0z" clip-rule="evenodd"/>
            </svg>
            Start Voting Phase
          </button>
        <% else %>
          <div class="text-sm text-gray-500">
            Add at least one option to start voting
          </div>
        <% end %>

      <% "voting" -> %>
        <div class="flex items-center space-x-3">
          <button
            type="button"
            class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
            phx-click="finalize_poll"
            phx-target={@myself}
          >
            <svg class="-ml-1 mr-2 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
            </svg>
            Finalize Poll
          </button>

          <button
            type="button"
            class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            phx-click="reopen_list_building"
            phx-target={@myself}
          >
            <svg class="-ml-1 mr-2 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M9.707 14.707a1 1 0 01-1.414 0l-5-5a1 1 0 010-1.414l5-5a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd"/>
            </svg>
            Reopen List Building
          </button>
        </div>

      <% "closed" -> %>
        <div class="flex items-center space-x-3">
          <span class="text-sm text-gray-500">Poll completed</span>

          <button
            type="button"
            class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            phx-click="reopen_voting"
            phx-target={@myself}
          >
            <svg class="-ml-1 mr-2 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clip-rule="evenodd"/>
            </svg>
            Reopen Voting
          </button>
        </div>
    <% end %>
    """
  end

  # Render Option Management Row
  defp render_option_management_row(assigns, option) do
    assigns = assign(assigns, :option, option)

    ~H"""
    <div class={"flex items-center justify-between p-3 border rounded-lg #{if @option.id in @selected_options, do: "border-indigo-300 bg-indigo-50", else: "border-gray-200"} #{unless @option.is_visible, do: "opacity-60"}"}>
      <div class="flex items-center space-x-3">
        <!-- Selection Checkbox -->
        <input
          type="checkbox"
          class="focus:ring-indigo-500 h-4 w-4 text-indigo-600 border-gray-300 rounded"
          checked={@option.id in @selected_options}
          phx-click="toggle_option_selection"
          phx-value-option-id={@option.id}
          phx-target={@myself}
        />

        <!-- Option Content -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center space-x-2">
            <h5 class="text-sm font-medium text-gray-900">
              <%= @option.title %>
            </h5>
            <%= unless @option.is_visible do %>
              <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800">
                Hidden
              </span>
            <% end %>
          </div>

          <%= if @option.description do %>
            <p class="text-sm text-gray-500 mt-1"><%= @option.description %></p>
          <% end %>

          <div class="flex items-center space-x-4 text-xs text-gray-400 mt-1">
            <span>Added by <%= @option.creator.name || @option.creator.email %></span>
            <span><%= get_vote_count_for_option(@option, @poll) %> votes</span>
            <span><%= format_relative_time(@option.inserted_at) %></span>
          </div>
        </div>
      </div>

      <!-- Action Buttons -->
      <div class="flex items-center space-x-2">
        <%= if @option.is_visible do %>
          <button
            type="button"
            class="text-sm text-yellow-600 hover:text-yellow-500"
            phx-click="hide_option"
            phx-value-option-id={@option.id}
            phx-target={@myself}
            title="Hide option"
          >
            <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M3.707 2.293a1 1 0 00-1.414 1.414l14 14a1 1 0 001.414-1.414l-1.473-1.473A10.014 10.014 0 0019.542 10C18.268 5.943 14.478 3 10 3a9.958 9.958 0 00-4.512 1.074l-1.78-1.781zm4.261 4.26l1.514 1.515a2.003 2.003 0 012.45 2.45l1.514 1.514a4 4 0 00-5.478-5.478z" clip-rule="evenodd"/>
              <path d="M12.454 16.697L9.75 13.992a4 4 0 01-3.742-3.741L2.335 6.578A9.98 9.98 0 00.458 10c1.274 4.057 5.065 7 9.542 7 .847 0 1.669-.105 2.454-.303z"/>
            </svg>
          </button>
        <% else %>
          <button
            type="button"
            class="text-sm text-green-600 hover:text-green-500"
            phx-click="show_option"
            phx-value-option-id={@option.id}
            phx-target={@myself}
            title="Show option"
          >
            <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10 12a2 2 0 100-4 2 2 0 000 4z"/>
              <path fill-rule="evenodd" d="M.458 10C1.732 5.943 5.522 3 10 3s8.268 2.943 9.542 7c-1.274 4.057-5.064 7-9.542 7S1.732 14.057.458 10zM14 10a4 4 0 11-8 0 4 4 0 018 0z" clip-rule="evenodd"/>
            </svg>
          </button>
        <% end %>

        <button
          type="button"
          class="text-sm text-red-600 hover:text-red-500"
          phx-click="delete_option"
          phx-value-option-id={@option.id}
          phx-target={@myself}
          title="Delete option"
        >
          <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M9 2a1 1 0 000 2h2a1 1 0 100-2H9z" clip-rule="evenodd"/>
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
          </svg>
        </button>
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("toggle_option_selection", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)

    selected_options = if option_id in socket.assigns.selected_options do
      List.delete(socket.assigns.selected_options, option_id)
    else
      [option_id | socket.assigns.selected_options]
    end

    {:noreply, assign(socket, :selected_options, selected_options)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_options, [])}
  end

  @impl true
  def handle_event("set_bulk_action", %{"value" => action}, socket) when action != "" do
    selected_count = length(socket.assigns.selected_options)

    if selected_count > 0 do
      message = case action do
        "hide" -> "Are you sure you want to hide #{selected_count} option(s)?"
        "show" -> "Are you sure you want to show #{selected_count} option(s)?"
        "delete" -> "Are you sure you want to delete #{selected_count} option(s)? This cannot be undone."
      end

      {:noreply,
       socket
       |> assign(:showing_confirmation, true)
       |> assign(:confirmation_message, message)
       |> assign(:confirmation_action, action)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_bulk_action", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_option", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)

    case Events.get_poll_option(option_id) do
      {:ok, poll_option} ->
        case Events.update_poll_option_status(poll_option, false) do
          {:ok, _option} ->
            send(self(), {:option_updated, option_id, "hidden"})
            {:noreply, socket}

          {:error, _} ->
            send(self(), {:show_error, "Failed to hide option"})
            {:noreply, socket}
        end

      {:error, _} ->
        send(self(), {:show_error, "Option not found"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_option", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)

    case Events.get_poll_option(option_id) do
      {:ok, poll_option} ->
        case Events.update_poll_option_status(poll_option, true) do
          {:ok, _option} ->
            send(self(), {:option_updated, option_id, "shown"})
            {:noreply, socket}

          {:error, _} ->
            send(self(), {:show_error, "Failed to show option"})
            {:noreply, socket}
        end

      {:error, _} ->
        send(self(), {:show_error, "Option not found"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_option", %{"option-id" => option_id}, socket) do
    {:noreply,
     socket
     |> assign(:showing_confirmation, true)
     |> assign(:confirmation_message, "Are you sure you want to delete this option? This action cannot be undone and will remove all associated votes.")
     |> assign(:confirmation_action, "delete_single_option")
     |> assign(:target_option_id, String.to_integer(option_id))}
  end

  @impl true
  def handle_event("transition_to_voting", _params, socket) do
    case Events.transition_poll_to_voting(socket.assigns.poll) do
      {:ok, updated_poll} ->
        send(self(), {:poll_transitioned, updated_poll, "voting"})
        {:noreply, assign(socket, :poll, updated_poll)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to transition to voting phase"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("finalize_poll", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_confirmation, true)
     |> assign(:confirmation_message, "Are you sure you want to finalize this poll? This will close voting and no further changes can be made.")
     |> assign(:confirmation_action, "finalize_poll_confirmed")}
  end

  @impl true
  def handle_event("reopen_list_building", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_confirmation, true)
     |> assign(:confirmation_message, "Are you sure you want to reopen list building? This will allow users to add more options.")
     |> assign(:confirmation_action, "reopen_list_building_confirmed")}
  end

  @impl true
  def handle_event("reopen_voting", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_confirmation, true)
     |> assign(:confirmation_message, "Are you sure you want to reopen voting? This will allow users to vote again.")
     |> assign(:confirmation_action, "reopen_voting_confirmed")}
  end

  @impl true
  def handle_event("reset_poll_votes", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_confirmation, true)
     |> assign(:confirmation_message, "Are you sure you want to reset all votes? This will permanently delete all voting data and cannot be undone.")
     |> assign(:confirmation_action, "reset_votes_confirmed")}
  end

  @impl true
  def handle_event("delete_poll", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_confirmation, true)
     |> assign(:confirmation_message, "Are you sure you want to delete this poll? This action cannot be undone and will remove all associated data.")
     |> assign(:confirmation_action, "delete_poll_confirmed")}
  end

  @impl true
  def handle_event("confirm_action", _params, socket) do
    case socket.assigns.confirmation_action do
      "hide" -> handle_bulk_hide(socket)
      "show" -> handle_bulk_show(socket)
      "delete" -> handle_bulk_delete(socket)
      "delete_single_option" -> handle_single_delete(socket)
      "finalize_poll_confirmed" -> handle_finalize_poll(socket)
      "reopen_list_building_confirmed" -> handle_reopen_list_building(socket)
      "reopen_voting_confirmed" -> handle_reopen_voting(socket)
      "reset_votes_confirmed" -> handle_reset_votes(socket)
      "delete_poll_confirmed" -> handle_delete_poll(socket)
      _ -> socket
    end
    |> clear_confirmation()
  end

  @impl true
  def handle_event("cancel_confirmation", _params, socket) do
    {:noreply, clear_confirmation(socket)}
  end

  # PubSub Event Handlers
  def handle_info({:poll_updated, updated_poll}, socket) do
    moderation_stats = calculate_moderation_stats(updated_poll)

    {:noreply,
     socket
     |> assign(:poll, updated_poll)
     |> assign(:moderation_stats, moderation_stats)}
  end

  def handle_info({:option_updated, _option_id, _action}, socket) do
    # The poll will be updated via PubSub, so we just need to recalculate stats
    moderation_stats = calculate_moderation_stats(socket.assigns.poll)
    {:noreply, assign(socket, :moderation_stats, moderation_stats)}
  end

  def handle_info({:votes_updated, updated_poll}, socket) do
    moderation_stats = calculate_moderation_stats(updated_poll)

    {:noreply,
     socket
     |> assign(:poll, updated_poll)
     |> assign(:moderation_stats, moderation_stats)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helper functions

  defp calculate_moderation_stats(poll) do
    total_options = length(poll.poll_options || [])
    hidden_options = poll.poll_options
    |> Enum.count(&(&1.status != "active"))

    user_suggestions = poll.poll_options
    |> Enum.count(&(&1.suggested_by_id != &1.created_by_id))

    # Calculate total votes by going through poll options
    total_votes = poll.poll_options
    |> Enum.reduce(0, fn option, acc ->
      votes = case option do
        %{votes: votes} when is_list(votes) -> length(votes)
        _ -> 0
      end
      acc + votes
    end)

    %{
      total_options: total_options,
      hidden_options: hidden_options,
      user_suggestions: user_suggestions,
      total_votes: total_votes
    }
  end

  defp can_user_moderate_poll?(user, poll, event) do
    user.id == poll.created_by_id || Events.user_is_organizer?(event, user)
  end

  defp get_vote_count_for_option(option, _poll) do
    case option do
      %{votes: votes} when is_list(votes) -> length(votes)
      _ -> 0
    end
  end

  defp format_relative_time(datetime) do
    case datetime do
      %DateTime{} = dt ->
        now = DateTime.utc_now()
        diff = DateTime.diff(now, dt, :minute)

        cond do
          diff < 1 -> "just now"
          diff < 60 -> "#{diff}m ago"
          diff < 1440 -> "#{div(diff, 60)}h ago"
          true -> "#{div(diff, 1440)}d ago"
        end
      _ -> "unknown"
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

  defp clear_confirmation(socket) do
    socket
    |> assign(:showing_confirmation, false)
    |> assign(:confirmation_message, "")
    |> assign(:confirmation_action, nil)
    |> assign(:target_option_id, nil)
  end

  # Bulk action handlers
  defp handle_bulk_hide(socket) do
    Enum.each(socket.assigns.selected_options, fn option_id ->
      case Events.get_poll_option(option_id) do
        {:ok, poll_option} -> Events.update_poll_option_status(poll_option, false)
        {:error, _} -> :ok  # Skip if option not found
      end
    end)

    send(self(), {:bulk_action_completed, "hide", length(socket.assigns.selected_options)})
    {:noreply, assign(socket, :selected_options, [])}
  end

  defp handle_bulk_show(socket) do
    Enum.each(socket.assigns.selected_options, fn option_id ->
      case Events.get_poll_option(option_id) do
        {:ok, poll_option} -> Events.update_poll_option_status(poll_option, true)
        {:error, _} -> :ok  # Skip if option not found
      end
    end)

    send(self(), {:bulk_action_completed, "show", length(socket.assigns.selected_options)})
    {:noreply, assign(socket, :selected_options, [])}
  end

  defp handle_bulk_delete(socket) do
    Enum.each(socket.assigns.selected_options, fn option_id ->
      Events.delete_poll_option(option_id)
    end)

    send(self(), {:bulk_action_completed, "delete", length(socket.assigns.selected_options)})
    {:noreply, assign(socket, :selected_options, [])}
  end

  defp handle_single_delete(socket) do
    case Events.delete_poll_option(socket.assigns.target_option_id) do
      {:ok, _} ->
        send(self(), {:option_deleted, socket.assigns.target_option_id})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:show_error, "Failed to delete option"})
        {:noreply, socket}
    end
  end

  defp handle_finalize_poll(socket) do
    case Events.finalize_poll(socket.assigns.poll) do
      {:ok, updated_poll} ->
        send(self(), {:poll_finalized, updated_poll})
        {:noreply, assign(socket, :poll, updated_poll)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to finalize poll"})
        {:noreply, socket}
    end
  end

  defp handle_reopen_list_building(socket) do
    case Events.update_poll_status(socket.assigns.poll, "list_building") do
      {:ok, updated_poll} ->
        send(self(), {:poll_reopened, updated_poll, "list_building"})
        {:noreply, assign(socket, :poll, updated_poll)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to reopen list building"})
        {:noreply, socket}
    end
  end

  defp handle_reopen_voting(socket) do
    case Events.update_poll_status(socket.assigns.poll, "voting") do
      {:ok, updated_poll} ->
        send(self(), {:poll_reopened, updated_poll, "voting"})
        {:noreply, assign(socket, :poll, updated_poll)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to reopen voting"})
        {:noreply, socket}
    end
  end

  defp handle_reset_votes(socket) do
    {:ok, _} = Events.clear_all_poll_votes(socket.assigns.poll.id)
    send(self(), {:votes_reset, socket.assigns.poll.id})
    {:noreply, socket}
  end

  defp handle_delete_poll(socket) do
    case Events.delete_poll(socket.assigns.poll) do
      {:ok, _} ->
        send(self(), {:poll_deleted, socket.assigns.poll})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:show_error, "Failed to delete poll"})
        {:noreply, socket}
    end
  end
end
