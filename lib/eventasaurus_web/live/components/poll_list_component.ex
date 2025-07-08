defmodule EventasaurusWeb.PollListComponent do
  @moduledoc """
  A reusable LiveView component for displaying polls associated with an event.

  Shows all polls for an event with their current status, phase, vote counts, and
  creator controls. Supports real-time updates for poll status changes and new votes.

  ## Attributes:
  - event: Event struct (required)
  - user: User struct (nil for unauthenticated users)
  - polls: List of poll structs (required)
  - show_creator_controls: Whether to show moderation controls for poll creators
  - loading: Whether an API call is in progress
  - class: Additional CSS classes

  ## Usage:
      <.live_component
        module={EventasaurusWeb.PollListComponent}
        id="event-polls"
        event={@event}
        user={@user}
        polls={@polls}
        show_creator_controls={true}
        loading={@loading}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias EventasaurusWeb.Endpoint

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:show_creator_controls, false)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:class, fn -> "" end)
     |> assign_new(:show_creator_controls, fn -> false end)
     |> assign_computed_properties()
     |> maybe_subscribe_to_updates()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["poll-list-container", @class]}>
      <%= if @loading do %>
        <div class="flex items-center justify-center py-8">
          <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-gray-500" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          <span class="text-gray-500">Loading polls...</span>
        </div>
      <% else %>
        <%= if Enum.empty?(@polls) do %>
          <div class="text-center py-12">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No polls yet</h3>
            <p class="mt-1 text-sm text-gray-500">
              Create a poll to get feedback from event participants.
            </p>
            <%= if @can_create_polls do %>
              <div class="mt-6">
                <button
                  phx-click="show_create_poll_modal"
                  phx-target={@myself}
                  class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                >
                  <svg class="-ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                  </svg>
                  Create Poll
                </button>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="space-y-6">
            <%= for poll <- @polls do %>
              <div class="bg-white shadow rounded-lg border border-gray-200">
                <div class="px-6 py-4 border-b border-gray-200">
                  <div class="flex items-center justify-between">
                    <div class="flex-1">
                      <h3 class="text-lg font-medium text-gray-900"><%= poll.title %></h3>
                      <%= if poll.description && poll.description != "" do %>
                        <p class="mt-1 text-sm text-gray-500"><%= poll.description %></p>
                      <% end %>
                      <div class="mt-2 flex items-center space-x-4 text-sm text-gray-500">
                        <span class="inline-flex items-center">
                          <svg class="mr-1 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.997 1.997 0 013 12V7a2 2 0 012-2z" />
                          </svg>
                          <%= String.capitalize(poll.poll_type) %>
                        </span>
                        <span class="inline-flex items-center">
                          <svg class="mr-1 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                          </svg>
                          <%= format_voting_system(poll.voting_system) %>
                        </span>
                        <span class="inline-flex items-center">
                          <svg class="mr-1 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                          </svg>
                          <%= get_vote_count(poll) %> <%= ngettext("vote", "votes", get_vote_count(poll)) %>
                        </span>
                      </div>
                    </div>
                    <div class="flex items-center space-x-3">
                      <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", phase_badge_classes(poll.phase)]}>
                        <%= format_phase(poll.phase) %>
                      </span>
                      <%= if @show_creator_controls && poll.created_by_id == @user.id do %>
                        <div class="flex items-center space-x-1">
                          <button
                            phx-click="edit_poll"
                            phx-target={@myself}
                            phx-value-poll-id={poll.id}
                            class="text-gray-400 hover:text-gray-600"
                            title="Edit poll"
                          >
                            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                            </svg>
                          </button>
                          <%= if poll.phase != "closed" do %>
                            <button
                              phx-click="transition_poll_phase"
                              phx-target={@myself}
                              phx-value-poll-id={poll.id}
                              class="text-blue-400 hover:text-blue-600"
                              title={get_transition_title(poll.phase)}
                            >
                              <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                              </svg>
                            </button>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>

                <div class="px-6 py-4">
                  <button
                    phx-click="view_poll"
                    phx-target={@myself}
                    phx-value-poll-id={poll.id}
                    class="w-full text-left text-sm text-indigo-600 hover:text-indigo-900 font-medium"
                  >
                    <%= get_poll_action_text(poll) %>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("show_create_poll_modal", _params, socket) do
    send(self(), {:show_create_poll_modal, socket.assigns.event})
    {:noreply, socket}
  end

  @impl true
  def handle_event("view_poll", %{"poll-id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

    if poll do
      send(self(), {:view_poll, poll})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_poll", %{"poll-id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

    if poll && poll.created_by_id == socket.assigns.user.id do
      send(self(), {:edit_poll, poll})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("transition_poll_phase", %{"poll-id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

    if poll && poll.created_by_id == socket.assigns.user.id do
      case transition_poll_phase(poll) do
        {:ok, updated_poll} ->
          send(self(), {:poll_phase_transitioned, updated_poll})
          {:noreply, socket}

        {:error, changeset} ->
          errors = changeset.errors |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end) |> Enum.join(", ")
          send(self(), {:show_error, "Failed to transition poll: #{errors}"})
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Private functions

  defp assign_computed_properties(socket) do
    user = socket.assigns[:user]
    event = socket.assigns[:event]

    can_create_polls = if user && event do
      Events.can_create_poll?(user, event)
    else
      false
    end

    socket
    |> assign(:can_create_polls, can_create_polls)
  end

  defp maybe_subscribe_to_updates(socket) do
    if connected?(socket) do
      event_id = socket.assigns.event.id
      Endpoint.subscribe("polls:event:#{event_id}")
    end

    socket
  end

  defp format_voting_system("binary"), do: "Yes/No"
  defp format_voting_system("approval"), do: "Select Multiple"
  defp format_voting_system("ranked"), do: "Ranked Choice"
  defp format_voting_system("star"), do: "Star Rating"
  defp format_voting_system(system), do: String.capitalize(system)

  defp format_phase("list_building"), do: "Building List"
  defp format_phase("voting"), do: "Voting Open"
  defp format_phase("closed"), do: "Closed"
  defp format_phase(phase), do: String.capitalize(phase)

  defp phase_badge_classes("list_building") do
    "bg-yellow-100 text-yellow-800"
  end

  defp phase_badge_classes("voting") do
    "bg-green-100 text-green-800"
  end

  defp phase_badge_classes("closed") do
    "bg-gray-100 text-gray-800"
  end

  defp phase_badge_classes(_), do: "bg-gray-100 text-gray-800"

  defp get_transition_title("list_building"), do: "Start voting phase"
  defp get_transition_title("voting"), do: "Close poll and finalize results"
  defp get_transition_title(_), do: "Transition phase"

  defp get_poll_action_text(poll) do
    case poll.phase do
      "list_building" -> "Add options and suggestions →"
      "voting" -> "Cast your vote →"
      "closed" -> "View results →"
      _ -> "View poll →"
    end
  end

  defp transition_poll_phase(poll) do
    case poll.phase do
      "list_building" -> Events.transition_poll_to_voting(poll)
      "voting" -> Events.finalize_poll(poll)
      _ -> {:error, "Cannot transition from #{poll.phase}"}
    end
  end

  defp get_vote_count(poll) do
    cond do
      # If poll has a vote_count field (virtual or computed)
      Map.has_key?(poll, :vote_count) -> poll.vote_count || 0

      # If poll_votes association is loaded, count them
      is_list(Map.get(poll, :poll_votes)) -> length(poll.poll_votes)

      # Otherwise return 0 (association not loaded)
      true -> 0
    end
  end
end
