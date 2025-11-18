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
  alias EventasaurusApp.Polls.PollSuggestions
  alias EventasaurusWeb.Endpoint
  alias EventasaurusWeb.Utils.PollPhaseUtils

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:show_creator_controls, false)
     |> assign(:suggestions, [])
     |> assign(:dismissed_suggestions, false)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:class, fn -> "" end)
     |> assign_new(:show_creator_controls, fn -> false end)
     |> assign_new(:dismissed_suggestions, fn -> false end)
     |> assign_computed_properties()
     |> maybe_generate_suggestions()
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
          <%= if !Enum.empty?(@suggestions) && !@dismissed_suggestions do %>
            <!-- Poll Suggestions Banner -->
            <div class="bg-gradient-to-br from-indigo-50 via-purple-50 to-pink-50 border border-indigo-200 rounded-xl p-6 mb-6 shadow-sm">
              <div class="flex items-start">
                <div class="flex-shrink-0">
                  <svg class="h-10 w-10 text-indigo-600 animate-pulse" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
                  </svg>
                </div>
                <div class="ml-4 flex-1">
                  <h3 class="text-xl font-bold text-gray-900">💡 We found polls you've created before!</h3>
                  <p class="mt-1.5 text-sm text-gray-600">
                    Would you like to use a template to get started faster?
                  </p>

                  <div class="mt-6 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
                    <%= for suggestion <- Enum.take(@suggestions, 3) do %>
                      <div class="relative bg-white border border-gray-200 rounded-xl p-5 shadow-sm hover:shadow-lg hover:-translate-y-0.5 transition-all duration-200 cursor-pointer group">
                        <!-- Match percentage badge - top right -->
                        <div class="absolute top-3 right-3 flex items-center gap-1 px-2 py-1 rounded-full bg-amber-50 border border-amber-200">
                          <svg class="w-3.5 h-3.5 text-amber-500" fill="currentColor" viewBox="0 0 20 20">
                            <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                          </svg>
                          <span class="text-xs font-semibold text-amber-700"><%= Float.round(suggestion.confidence * 100, 0) %>%</span>
                        </div>

                        <!-- Poll type and voting system badges -->
                        <div class="flex items-center gap-2 mb-3 pr-16">
                          <span class={"inline-flex items-center px-2.5 py-1 rounded-md text-xs font-semibold #{poll_type_badge_classes(suggestion.poll_type)}"}>
                            <%= format_poll_type_name(suggestion.poll_type) %>
                          </span>
                          <span class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium bg-gray-100 text-gray-700">
                            <%= format_voting_system(suggestion.voting_system) %>
                          </span>
                        </div>

                        <!-- Poll title -->
                        <h4 class="text-base font-bold text-gray-900 mb-3 group-hover:text-indigo-600 transition-colors">
                          <%= suggestion.suggested_title %>
                        </h4>

                        <!-- Common options preview -->
                        <%= if !Enum.empty?(suggestion.common_options) do %>
                          <ul class="text-sm text-gray-600 space-y-2 mb-4">
                            <%= for option <- Enum.take(suggestion.common_options, 3) do %>
                              <li class="flex items-start">
                                <svg class="h-4 w-4 text-indigo-400 mr-2 mt-0.5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                                </svg>
                                <span class="line-clamp-1"><%= Map.get(option, :title) || Map.get(option, "title") %></span>
                              </li>
                            <% end %>
                            <%= if length(suggestion.common_options) > 3 do %>
                              <li class="text-gray-400 text-xs ml-6">
                                +<%= length(suggestion.common_options) - 3 %> more options
                              </li>
                            <% end %>
                          </ul>
                        <% end %>

                        <!-- Usage count -->
                        <div class="text-xs text-gray-500 mb-4">
                          <span class="inline-flex items-center">
                            <svg class="h-3.5 w-3.5 text-gray-400 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                            </svg>
                            Used <%= suggestion.usage_count %> <%= if suggestion.usage_count == 1, do: "time", else: "times" %>
                          </span>
                        </div>

                        <!-- Use Template button -->
                        <button
                          phx-click="use_template"
                          phx-target={@myself}
                          phx-value-suggestion={Jason.encode!(suggestion)}
                          class="w-full inline-flex justify-center items-center px-4 py-2.5 border border-transparent text-sm font-semibold rounded-lg text-white bg-indigo-600 hover:bg-indigo-700 active:bg-indigo-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors duration-150 shadow-sm hover:shadow"
                        >
                          Use Template
                        </button>
                      </div>
                    <% end %>
                  </div>

                  <div class="mt-6 flex items-center justify-center">
                    <button
                      phx-click="dismiss_suggestions"
                      phx-target={@myself}
                      class="text-sm font-medium text-gray-600 hover:text-gray-900 hover:underline transition-colors"
                    >
                      No thanks, I'll create from scratch
                    </button>
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <!-- Default Empty State -->
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
          <% end %>
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
                          <%= PollPhaseUtils.format_poll_type(poll) %>
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
                          <button
                            phx-click="delete_poll"
                            phx-target={@myself}
                            phx-value-poll-id={poll.id}
                            class="text-red-400 hover:text-red-600"
                            title="Delete poll"
                            data-confirm="Are you sure you want to delete this poll? This action cannot be undone."
                          >
                            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
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
    case safe_string_to_integer(poll_id) do
      {:ok, poll_id} ->
        poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

        if poll do
          send(self(), {:view_poll, poll})
        end

      {:error, _} ->
        send(self(), {:show_error, "Invalid poll ID"})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_poll", %{"poll-id" => poll_id}, socket) do
    case safe_string_to_integer(poll_id) do
      {:ok, poll_id} ->
        poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

        if poll && poll.created_by_id == socket.assigns.user.id do
          send(self(), {:edit_poll, poll})
        end

      {:error, _} ->
        send(self(), {:show_error, "Invalid poll ID"})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_poll", %{"poll-id" => poll_id}, socket) do
    case safe_string_to_integer(poll_id) do
      {:ok, poll_id} ->
        poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

        if poll && poll.created_by_id == socket.assigns.user.id do
          send(self(), {:delete_poll, poll})
        end

      {:error, _} ->
        send(self(), {:show_error, "Invalid poll ID"})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("transition_poll_phase", %{"poll-id" => poll_id}, socket) do
    case safe_string_to_integer(poll_id) do
      {:ok, poll_id} ->
        poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

        if poll && poll.created_by_id == socket.assigns.user.id do
          case transition_poll_phase(poll) do
            {:ok, updated_poll} ->
              send(self(), {:poll_phase_transitioned, updated_poll})
              {:noreply, socket}

            {:error, changeset} ->
              errors =
                changeset.errors
                |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
                |> Enum.join(", ")

              send(self(), {:show_error, "Failed to transition poll: #{errors}"})
              {:noreply, socket}
          end
        else
          {:noreply, socket}
        end

      {:error, _} ->
        send(self(), {:show_error, "Invalid poll ID"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("use_template", %{"suggestion" => suggestion_json}, socket) do
    case Jason.decode(suggestion_json) do
      {:ok, suggestion} ->
        # Send message to parent to open the template editor
        send(self(), {:open_template_editor, suggestion})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:show_error, "Invalid suggestion data"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("dismiss_suggestions", _params, socket) do
    {:noreply, assign(socket, :dismissed_suggestions, true)}
  end

  # Private functions

  defp assign_computed_properties(socket) do
    user = socket.assigns[:user]
    event = socket.assigns[:event]

    can_create_polls =
      if user && event do
        Events.can_create_poll?(user, event)
      else
        false
      end

    socket
    |> assign(:can_create_polls, can_create_polls)
  end

  defp maybe_generate_suggestions(socket) do
    polls = socket.assigns[:polls] || []
    user = socket.assigns[:user]
    event = socket.assigns[:event]
    dismissed = socket.assigns[:dismissed_suggestions] || false

    # Only generate suggestions if:
    # 1. No polls exist yet
    # 2. User is authenticated
    # 3. Suggestions haven't been dismissed
    # 4. User can create polls
    if Enum.empty?(polls) && user && event && !dismissed && socket.assigns[:can_create_polls] do
      suggestions = PollSuggestions.generate_suggestions(user.id, event)
      assign(socket, :suggestions, suggestions)
    else
      socket
    end
  end

  defp maybe_subscribe_to_updates(socket) do
    if connected?(socket) do
      event_id = socket.assigns.event.id
      Endpoint.subscribe("polls:event:#{event_id}")
    end

    socket
  end

  defp format_poll_type_name("movie"), do: "Movie"
  defp format_poll_type_name("places"), do: "Places"
  defp format_poll_type_name("music_track"), do: "Music"
  defp format_poll_type_name("venue"), do: "Venue"
  defp format_poll_type_name("date_selection"), do: "Date"
  defp format_poll_type_name("time"), do: "Time"
  defp format_poll_type_name("general"), do: "General"
  defp format_poll_type_name("custom"), do: "Custom"
  defp format_poll_type_name(type), do: String.capitalize(type)

  defp poll_type_badge_classes("date_selection"), do: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-200"
  defp poll_type_badge_classes("movie"), do: "bg-purple-100 text-purple-700 dark:bg-purple-900 dark:text-purple-200"
  defp poll_type_badge_classes("places"), do: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-200"
  defp poll_type_badge_classes("venue"), do: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-200"
  defp poll_type_badge_classes("music_track"), do: "bg-pink-100 text-pink-700 dark:bg-pink-900 dark:text-pink-200"
  defp poll_type_badge_classes("time"), do: "bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-200"
  defp poll_type_badge_classes("general"), do: "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200"
  defp poll_type_badge_classes("custom"), do: "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200"
  defp poll_type_badge_classes(_), do: "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-200"

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

  defp safe_string_to_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp safe_string_to_integer(_), do: {:error, :invalid_input}
end
