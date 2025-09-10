defmodule EventasaurusWeb.PollPhaseControlComponent do
  @moduledoc """
  Poll phase control component for managing poll lifecycle.
  
  Provides poll phase management functionality including:
  - Phase status display with current phase indicator
  - Phase transition controls for creators
  - Phase-specific messaging and restrictions
  - Phase validation and authorization
  - Broadcast integration for phase changes
  
  ## Attributes:
  - poll: Poll struct (required)
  - user: Current user struct (required) 
  - is_creator: Whether user is the poll creator (required)
  - show_phase_dropdown: Whether phase dropdown is visible
  - poll_options_count: Number of poll options (for validation)
  
  ## Events:
  - toggle_phase_dropdown: Show/hide phase control dropdown
  - close_phase_dropdown: Close phase control dropdown
  - change_poll_phase: Transition poll to new phase
  
  ## Supported Phase Transitions:
  - list_building → voting_with_suggestions, voting_only, closed
  - voting_with_suggestions → voting_only, list_building, closed
  - voting_only → voting_with_suggestions, list_building, closed
  - voting (legacy) → voting_with_suggestions, voting_only, list_building, closed
  - closed → (no transitions allowed)
  """

  use EventasaurusWeb, :live_component
  require Logger
  alias EventasaurusApp.Events
  alias EventasaurusWeb.Services.PollPubSubService
  alias EventasaurusWeb.OptionSuggestionHelpers

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:show_phase_dropdown, fn -> false end)
     |> assign_new(:poll_options_count, fn -> 0 end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @is_creator && @poll_options_count > 0 && @poll.phase != "closed" do %>
      <div class="relative inline-block text-left poll-phase-control" phx-click-away="close_phase_dropdown" phx-target={@myself}>
        <div>
          <button
            type="button"
            phx-click="toggle_phase_dropdown"
            phx-target={@myself}
            class="inline-flex items-center justify-center w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
            id="phase-menu-button"
            aria-expanded={to_string(@show_phase_dropdown)}
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
            <svg class={"-mr-1 ml-2 h-5 w-5 transition-transform #{if @show_phase_dropdown, do: "rotate-180", else: ""}"} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
            </svg>
          </button>
        </div>

        <div
          class={"origin-top-right absolute right-0 mt-2 w-56 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5 focus:outline-none z-10 #{if @show_phase_dropdown, do: "", else: "hidden"}"}
          role="menu"
          aria-orientation="vertical"
          aria-labelledby="phase-menu-button"
          tabindex="-1"
        >
          <div class="py-1" role="none">
            <!-- Phase transitions based on current phase -->
            <%= case @poll.phase do %>
              <% "list_building" -> %>
                <%= render_list_building_transitions(assigns) %>
              <% "voting_with_suggestions" -> %>
                <%= render_voting_with_suggestions_transitions(assigns) %>
              <% "voting_only" -> %>
                <%= render_voting_only_transitions(assigns) %>
              <% "voting" -> %>
                <%= render_legacy_voting_transitions(assigns) %>
              <% "closed" -> %>
                <%= render_closed_state(assigns) %>
              <% _ -> %>
                <%= render_unknown_phase_state(assigns) %>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Phase transition options for list_building phase
  defp render_list_building_transitions(assigns) do
    ~H"""
    <!-- From list_building, can go to either voting phase or close -->
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="voting_with_suggestions"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      Start Voting (with suggestions)
    </button>
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="voting_only"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      Start Voting (no more suggestions)
    </button>
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="closed"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      Close Poll
    </button>
    """
  end

  # Phase transition options for voting_with_suggestions phase
  defp render_voting_with_suggestions_transitions(assigns) do
    ~H"""
    <!-- From voting_with_suggestions, can switch to voting only, close, or back to building (if no votes) -->
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="voting_only"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728L5.636 5.636m12.728 12.728L18.364 5.636M5.636 18.364l12.728-12.728" />
      </svg>
      Disable New Suggestions
    </button>
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="list_building"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4" />
      </svg>
      Back to Building Phase
    </button>
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="closed"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      Close Poll
    </button>
    """
  end

  # Phase transition options for voting_only phase
  defp render_voting_only_transitions(assigns) do
    ~H"""
    <!-- From voting_only, can enable suggestions, go back to building (if no votes), or close -->
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="voting_with_suggestions"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
      </svg>
      Enable Suggestions
    </button>
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="list_building"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4" />
      </svg>
      Back to Building Phase
    </button>
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="closed"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      Close Poll
    </button>
    """
  end

  # Phase transition options for legacy voting phase
  defp render_legacy_voting_transitions(assigns) do
    ~H"""
    <!-- Legacy voting phase - can go back to building, upgrade to enhanced phases, or close -->
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="voting_with_suggestions"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
      </svg>
      Upgrade to Enhanced Voting (with suggestions)
    </button>
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="voting_only"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728L5.636 5.636m12.728 12.728L18.364 5.636M5.636 18.364l12.728-12.728" />
      </svg>
      Upgrade to Enhanced Voting (no suggestions)
    </button>
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="list_building"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 100 4m0-4v2m0-6V4" />
      </svg>
      Back to Building Phase
    </button>
    <button
      type="button"
      phx-click="change_poll_phase"
      phx-value-phase="closed"
      phx-target={@myself}
      class="group flex items-center px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 hover:text-gray-900 w-full text-left"
      role="menuitem"
    >
      <svg class="mr-3 h-4 w-4 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      Close Poll
    </button>
    """
  end

  # Closed state message
  defp render_closed_state(assigns) do
    ~H"""
    <!-- Closed phase - no transitions allowed -->
    <div class="px-3 py-2 text-sm text-gray-500 text-center">
      <div>Poll is closed</div>
      <div class="text-xs">No further changes allowed</div>
    </div>
    """
  end

  # Unknown phase state message
  defp render_unknown_phase_state(assigns) do
    ~H"""
    <!-- Unknown phases -->
    <div class="px-3 py-2 text-sm text-gray-500 text-center">
      <div>Unknown phase</div>
      <div class="text-xs">Contact support</div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_phase_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_phase_dropdown, !socket.assigns.show_phase_dropdown)}
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

  # Helper functions

  defp get_phase_display_name(phase) do
    OptionSuggestionHelpers.get_phase_display_name(phase)
  end
end