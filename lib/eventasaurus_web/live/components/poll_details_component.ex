defmodule EventasaurusWeb.PollDetailsComponent do
  @moduledoc """
  A reusable LiveView component for displaying detailed poll information and status.

  Shows comprehensive poll metadata, phase progression, participant counts, and
  creator-specific actions. Provides a detailed view of poll state and progress.

  ## Attributes:
  - poll: Poll struct with preloaded options and votes (required)
  - current_user: Current user struct for permission checks (required)
  - event: Event struct for context (required)
  - compact_view: Whether to show a condensed version (default: false)
  - show_metadata: Whether to show detailed metadata (default: true)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.PollDetailsComponent}
        id="poll-details"
        poll={@poll}
        current_user={@current_user}
        event={@event}
        compact_view={false}
        show_metadata={true}
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
     |> assign(:poll_stats, %{})
     |> assign(:can_moderate, false)}
  end

  @impl true
  def update(assigns, socket) do
    # Subscribe to real-time poll updates
    if connected?(socket) do
      PubSub.subscribe(Eventasaurus.PubSub, "polls:#{assigns.poll.id}")
      PubSub.subscribe(Eventasaurus.PubSub, "votes:poll:#{assigns.poll.id}")
    end

    # Calculate poll statistics
    poll_stats = calculate_poll_statistics(assigns.poll)

    # Check moderation permissions
    can_moderate = can_user_moderate_poll?(assigns.current_user, assigns.poll, assigns.event)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:poll_stats, poll_stats)
     |> assign(:can_moderate, can_moderate)
     |> assign_new(:compact_view, fn -> false end)
     |> assign_new(:show_metadata, fn -> true end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg overflow-hidden">
      <!-- Header Section -->
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-start justify-between">
          <div class="flex-1 min-w-0">
            <div class="flex items-center space-x-3">
              <span class="text-2xl"><%= get_poll_type_emoji(@poll.poll_type) %></span>
              <div>
                <h2 class="text-xl font-semibold text-gray-900"><%= @poll.title %></h2>
                <%= if @poll.description do %>
                  <p class="text-sm text-gray-600 mt-1"><%= @poll.description %></p>
                <% end %>
              </div>
            </div>

            <!-- Phase Status -->
            <div class="mt-3 flex items-center space-x-4">
              <%= render_phase_badge(@poll.phase) %>
              <span class="text-sm text-gray-500">
                Created by <%= @poll.created_by.name || @poll.created_by.email %>
              </span>
              <span class="text-sm text-gray-500">
                <%= format_relative_time(@poll.inserted_at) %>
              </span>
            </div>
          </div>

          <!-- Action Buttons -->
          <%= if @can_moderate do %>
            <div class="ml-4 flex space-x-2">
              <%= render_phase_actions(assigns) %>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Progress Timeline -->
      <%= unless @compact_view do %>
        <div class="px-6 py-4 bg-gray-50 border-b border-gray-200">
          <%= render_phase_timeline(assigns) %>
        </div>
      <% end %>

      <!-- Statistics Grid -->
      <div class="px-6 py-4">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div class="text-center">
            <div class="text-2xl font-bold text-gray-900"><%= @poll_stats.total_options %></div>
            <div class="text-sm text-gray-500">Options</div>
          </div>
          <div class="text-center">
            <div class="text-2xl font-bold text-gray-900"><%= @poll_stats.total_participants %></div>
            <div class="text-sm text-gray-500">Participants</div>
          </div>
          <div class="text-center">
            <div class="text-2xl font-bold text-gray-900"><%= @poll_stats.total_votes %></div>
            <div class="text-sm text-gray-500">Total Votes</div>
          </div>
          <div class="text-center">
            <div class="text-2xl font-bold text-gray-900">
              <%= @poll_stats.participation_rate %>%
            </div>
            <div class="text-sm text-gray-500">Participation</div>
          </div>
        </div>
      </div>

      <!-- Configuration Details -->
      <%= if @show_metadata do %>
        <div class="px-6 py-4 border-t border-gray-200">
          <h3 class="text-sm font-medium text-gray-900 mb-3">Poll Configuration</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
            <div>
              <span class="text-gray-500">Voting System:</span>
              <span class="ml-2 font-medium"><%= format_voting_system(@poll.voting_system) %></span>
            </div>
            <div>
              <span class="text-gray-500">Poll Type:</span>
              <span class="ml-2 font-medium"><%= format_poll_type(@poll.poll_type) %></span>
            </div>
            <div>
              <span class="text-gray-500">Max Options per User:</span>
              <span class="ml-2 font-medium"><%= @poll.max_options_per_user %></span>
            </div>
            <div>
              <span class="text-gray-500">Auto-Finalize:</span>
              <span class="ml-2 font-medium">
                <%= if @poll.auto_finalize, do: "Enabled", else: "Disabled" %>
              </span>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Deadlines Section -->
      <%= if @poll.list_building_deadline || @poll.voting_deadline do %>
        <div class="px-6 py-4 border-t border-gray-200">
          <h3 class="text-sm font-medium text-gray-900 mb-3">Timeline</h3>
          <div class="space-y-2 text-sm">
            <%= if @poll.list_building_deadline do %>
              <div class="flex items-center justify-between">
                <span class="text-gray-500">List Building Deadline:</span>
                <span class={"font-medium #{get_deadline_status_class(@poll.list_building_deadline)}"}>
                  <%= format_deadline(@poll.list_building_deadline) %>
                </span>
              </div>
            <% end %>
            <%= if @poll.voting_deadline do %>
              <div class="flex items-center justify-between">
                <span class="text-gray-500">Voting Deadline:</span>
                <span class={"font-medium #{get_deadline_status_class(@poll.voting_deadline)}"}>
                  <%= format_deadline(@poll.voting_deadline) %>
                </span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Quick Actions -->
      <%= unless @compact_view do %>
        <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
          <div class="flex items-center justify-between">
            <div class="flex space-x-4">
              <%= unless @poll.phase == "closed" do %>
                <button
                  type="button"
                  class="text-sm text-indigo-600 hover:text-indigo-500"
                  phx-click="view_poll_details"
                  phx-target={@myself}
                >
                  View Full Details
                </button>
              <% end %>

              <%= if @poll.phase == "voting" do %>
                <button
                  type="button"
                  class="text-sm text-indigo-600 hover:text-indigo-500"
                  phx-click="view_results"
                  phx-target={@myself}
                >
                  View Results
                </button>
              <% end %>

              <%= if @can_moderate && @poll.phase != "closed" do %>
                <button
                  type="button"
                  class="text-sm text-indigo-600 hover:text-indigo-500"
                  phx-click="edit_poll"
                  phx-target={@myself}
                >
                  Edit Poll
                </button>
              <% end %>
            </div>

            <div class="text-xs text-gray-500">
              Last updated <%= format_relative_time(@poll.updated_at) %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Phase Badge Rendering
  defp render_phase_badge(phase) do
    {text, class} = case phase do
      "list_building" -> {"Building List", "bg-blue-100 text-blue-800"}
      "voting" -> {"Voting Open", "bg-green-100 text-green-800"}
      "closed" -> {"Closed", "bg-gray-100 text-gray-800"}
      _ -> {"Unknown", "bg-red-100 text-red-800"}
    end

    assigns = %{text: text, class: class}

    ~H"""
    <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{@class}"}>
      <%= @text %>
    </span>
    """
  end

  # Phase Action Buttons
  defp render_phase_actions(assigns) do
    ~H"""
    <%= case @poll.phase do %>
      <% "list_building" -> %>
        <%= if length(@poll.poll_options) > 0 do %>
          <button
            type="button"
            class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            phx-click="start_voting"
            phx-target={@myself}
          >
            Start Voting
          </button>
        <% end %>

      <% "voting" -> %>
        <button
          type="button"
          class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
          phx-click="finalize_poll"
          phx-target={@myself}
        >
          Finalize Poll
        </button>

      <% "closed" -> %>
        <span class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-gray-500">
          Poll Completed
        </span>
    <% end %>
    """
  end

  # Phase Timeline
  defp render_phase_timeline(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-8">
        <!-- List Building Phase -->
        <div class="flex items-center">
          <div class={"flex items-center justify-center w-8 h-8 rounded-full #{if @poll.phase in ["list_building", "voting", "closed"], do: "bg-blue-500 text-white", else: "bg-gray-300 text-gray-500"}"}>
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
          </div>
          <span class={"ml-2 text-sm #{if @poll.phase == "list_building", do: "font-medium text-blue-600", else: "text-gray-500"}"}>
            List Building
          </span>
        </div>

        <!-- Arrow -->
        <div class="flex items-center">
          <svg class="w-4 h-4 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z" clip-rule="evenodd"/>
          </svg>
        </div>

        <!-- Voting Phase -->
        <div class="flex items-center">
          <div class={"flex items-center justify-center w-8 h-8 rounded-full #{if @poll.phase in ["voting", "closed"], do: "bg-green-500 text-white", else: "bg-gray-300 text-gray-500"}"}>
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
          </div>
          <span class={"ml-2 text-sm #{if @poll.phase == "voting", do: "font-medium text-green-600", else: "text-gray-500"}"}>
            Voting
          </span>
        </div>

        <!-- Arrow -->
        <div class="flex items-center">
          <svg class="w-4 h-4 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z" clip-rule="evenodd"/>
          </svg>
        </div>

        <!-- Closed Phase -->
        <div class="flex items-center">
          <div class={"flex items-center justify-center w-8 h-8 rounded-full #{if @poll.phase == "closed", do: "bg-gray-500 text-white", else: "bg-gray-300 text-gray-500"}"}>
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
          </div>
          <span class={"ml-2 text-sm #{if @poll.phase == "closed", do: "font-medium text-gray-600", else: "text-gray-500"}"}>
            Closed
          </span>
        </div>
      </div>

      <!-- Phase Duration -->
      <div class="text-sm text-gray-500">
        <%= get_current_phase_duration(@poll) %>
      </div>
    </div>
    """
  end

  # Event Handlers
  @impl true
  def handle_event("start_voting", _params, socket) do
    case Events.transition_poll_to_voting(socket.assigns.poll) do
      {:ok, updated_poll} ->
        send(self(), {:poll_transitioned, updated_poll, "voting"})
        {:noreply, assign(socket, :poll, updated_poll)}

      {:error, _changeset} ->
        send(self(), {:show_error, "Failed to start voting phase"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("finalize_poll", _params, socket) do
    case Events.finalize_poll(socket.assigns.poll) do
      {:ok, updated_poll} ->
        send(self(), {:poll_finalized, updated_poll})
        {:noreply, assign(socket, :poll, updated_poll)}

      {:error, _changeset} ->
        send(self(), {:show_error, "Failed to finalize poll"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("view_poll_details", _params, socket) do
    send(self(), {:navigate_to_poll, socket.assigns.poll.id})
    {:noreply, socket}
  end

  @impl true
  def handle_event("view_results", _params, socket) do
    send(self(), {:view_poll_results, socket.assigns.poll.id})
    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_poll", _params, socket) do
    send(self(), {:edit_poll, socket.assigns.poll})
    {:noreply, socket}
  end

  # PubSub Event Handlers
  def handle_info({:poll_updated, updated_poll}, socket) do
    poll_stats = calculate_poll_statistics(updated_poll)

    {:noreply,
     socket
     |> assign(:poll, updated_poll)
     |> assign(:poll_stats, poll_stats)}
  end

  def handle_info({:vote_cast, _option_id, _vote}, socket) do
    # Recalculate statistics when votes are cast
    poll_stats = calculate_poll_statistics(socket.assigns.poll)
    {:noreply, assign(socket, :poll_stats, poll_stats)}
  end

  def handle_info({:votes_updated, updated_poll}, socket) do
    poll_stats = calculate_poll_statistics(updated_poll)

    {:noreply,
     socket
     |> assign(:poll, updated_poll)
     |> assign(:poll_stats, poll_stats)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helper functions

  defp calculate_poll_statistics(poll) do
    total_options = length(poll.poll_options || [])

    # Since poll_votes are associated with poll_options, we need to collect them
    # For now, we'll provide safe defaults if poll data isn't fully loaded
    poll_votes = case poll.poll_options do
      options when is_list(options) ->
        Enum.flat_map(options, fn option ->
          case option do
            %{poll_votes: votes} when is_list(votes) -> votes
            _ -> []
          end
        end)
      _ -> []
    end

    total_votes = length(poll_votes)

    # Count unique participants
    unique_participants = poll_votes
    |> Enum.map(fn vote ->
      case vote do
        %{voter_id: voter_id} -> voter_id
        %{user_id: user_id} -> user_id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()

    # Calculate participation rate based on event participants
    # Note: This assumes event has participants preloaded
    total_possible_participants = case poll.event do
      %{participants: participants} when is_list(participants) -> length(participants)
      _ -> 1  # Avoid division by zero
    end

    participation_rate = if total_possible_participants > 0 do
      round((unique_participants / total_possible_participants) * 100)
    else
      0
    end

    %{
      total_options: total_options,
      total_participants: unique_participants,
      total_votes: total_votes,
      participation_rate: participation_rate
    }
  end

  defp can_user_moderate_poll?(user, poll, event) do
    # User can moderate if they are the poll creator or event organizer
    user.id == poll.created_by_id || Events.user_is_organizer?(event, user)
  end

  # UI Helper Functions

  defp get_poll_type_emoji(poll_type) do
    case poll_type do
      "movie" -> "🎬"
      "restaurant" -> "🍽️"
      "activity" -> "🎯"
      "custom" -> "📝"
      _ -> "📝"
    end
  end

  defp format_voting_system(voting_system) do
    case voting_system do
      "binary" -> "Binary (Yes/No)"
      "approval" -> "Approval Voting"
      "ranked" -> "Ranked Choice"
      "star" -> "Star Rating"
      _ -> String.capitalize(voting_system)
    end
  end

  defp format_poll_type(poll_type) do
    case poll_type do
      "movie" -> "Movie"
      "restaurant" -> "Restaurant"
      "activity" -> "Activity"
      "custom" -> "Custom"
      _ -> String.capitalize(poll_type)
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
          diff < 10080 -> "#{div(diff, 1440)}d ago"
          true ->
            dt
            |> DateTime.to_date()
            |> Date.to_string()
        end
      _ -> "unknown"
    end
  end

  defp format_deadline(deadline) do
    case deadline do
      %DateTime{} = dt ->
        now = DateTime.utc_now()

        if DateTime.compare(dt, now) == :gt do
          # Future deadline
          diff = DateTime.diff(dt, now, :minute)

          cond do
            diff < 60 -> "in #{diff}m"
            diff < 1440 -> "in #{div(diff, 60)}h"
            diff < 10080 -> "in #{div(diff, 1440)}d"
            true -> Date.to_string(DateTime.to_date(dt))
          end
        else
          # Past deadline
          diff = DateTime.diff(now, dt, :minute)

          cond do
            diff < 60 -> "#{diff}m ago"
            diff < 1440 -> "#{div(diff, 60)}h ago"
            diff < 10080 -> "#{div(diff, 1440)}d ago"
            true -> Date.to_string(DateTime.to_date(dt))
          end
        end
      _ -> "Not set"
    end
  end

  defp get_deadline_status_class(deadline) do
    case deadline do
      %DateTime{} = dt ->
        now = DateTime.utc_now()

        if DateTime.compare(dt, now) == :gt do
          # Future deadline
          diff = DateTime.diff(dt, now, :hour)

          cond do
            diff < 1 -> "text-red-600"    # Less than 1 hour
            diff < 24 -> "text-yellow-600" # Less than 1 day
            true -> "text-green-600"       # More than 1 day
          end
        else
          "text-red-600"  # Past deadline
        end
      _ -> "text-gray-500"
    end
  end

  defp get_current_phase_duration(poll) do
    case poll.phase do
      "list_building" ->
        if poll.list_building_deadline do
          "Phase deadline: #{format_deadline(poll.list_building_deadline)}"
        else
          "No deadline set"
        end
      "voting" ->
        if poll.voting_deadline do
          "Phase deadline: #{format_deadline(poll.voting_deadline)}"
        else
          "No deadline set"
        end
      "closed" ->
        "Poll completed"
      _ ->
        ""
    end
  end
end
