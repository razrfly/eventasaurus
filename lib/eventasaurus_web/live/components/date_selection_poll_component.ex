defmodule EventasaurusWeb.DateSelectionPollComponent do
  @moduledoc """
  A comprehensive LiveView component for date selection polls that wraps the existing
  beautiful calendar UI and integrates it with the new generic polling system.

  This component provides:
  - Interactive calendar for date selection with the existing UI patterns
  - Integration with generic Poll system via DatePollAdapter
  - Real-time updates using Phoenix PubSub
  - Support for both authenticated and anonymous voting
  - Mobile responsive design with accessibility features

  ## Attributes:
  - poll: Poll struct with poll_type "date_selection" (required)
  - current_user: Current user struct (nil for anonymous users)
  - event: Event struct for context (required)
  - show_results: Whether to show voting results (default: false)
  - anonymous_mode: Enable anonymous voting flow (default: false)
  - temp_votes: Map of temporary votes for anonymous users
  - compact_view: Use compact layout (default: false)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.DateSelectionPollComponent}
        id="date-poll-123"
        poll={@poll}
        current_user={@current_user}
        event={@event}
        show_results={false}
        anonymous_mode={false}
        temp_votes={%{}}
      />
  """

  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Events
  alias EventasaurusWeb.Adapters.DatePollAdapter
  alias EventasaurusWeb.CalendarComponent
  alias EventasaurusWeb.Components.VotingInterfaceComponent
  alias Phoenix.PubSub

  require Logger

  # Import utilities for date handling and display
  import EventasaurusWeb.PollView, only: [poll_emoji: 1]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:error_message, nil)
     |> assign(:success_message, nil)
     |> assign(:showing_calendar, true)
     |> assign(:selected_dates, [])
     |> assign(:poll_options, [])
     |> assign(:user_votes, [])
     |> assign(:legacy_poll_data, nil)
     |> assign(:vote_summaries, %{})
     |> assign(:phase_display, "list_building")}
  end

  @impl true
  def update(assigns, socket) do
    poll = assigns.poll
    current_user = assigns.current_user

    # Validate this is a date_selection poll
    unless poll.poll_type == "date_selection" do
      {:ok, assign(socket, :error_message, "Invalid poll type - expected date_selection")}
    else
      # Subscribe to real-time updates for this poll
      if connected?(socket) do
        PubSub.subscribe(Eventasaurus.PubSub, "polls:#{poll.id}")
        PubSub.subscribe(Eventasaurus.PubSub, "votes:poll:#{poll.id}")
      end

      # Load poll options and votes
      poll_options = Events.list_poll_options(poll)
      user_votes = if current_user, do: Events.list_user_poll_votes(poll, current_user), else: []

      # Convert to legacy format for calendar UI using our adapter
      legacy_poll_data = case DatePollAdapter.get_legacy_poll_with_data(poll.id) do
        {:ok, legacy_data} -> legacy_data
        {:error, reason} ->
          Logger.warning("Failed to convert poll #{poll.id} to legacy format: #{inspect(reason)}")
          nil
      end

      # Extract selected dates from poll options for calendar display
      selected_dates = extract_dates_from_options(poll_options)

      # Calculate vote summaries for results display
      vote_summaries = calculate_vote_summaries(poll_options, user_votes)

      # Determine phase display string
      phase_display = DatePollAdapter.safe_status_display(poll)

      {:ok,
       socket
       |> assign(assigns)
       |> assign(:poll_options, poll_options)
       |> assign(:user_votes, user_votes)
       |> assign(:selected_dates, selected_dates)
       |> assign(:legacy_poll_data, legacy_poll_data)
       |> assign(:vote_summaries, vote_summaries)
       |> assign(:phase_display, phase_display)
       |> assign_new(:temp_votes, fn -> %{} end)
       |> assign_new(:show_results, fn -> false end)
       |> assign_new(:anonymous_mode, fn -> is_nil(current_user) end)
       |> assign_new(:compact_view, fn -> false end)}
    end
  end

  @impl true
  def handle_event("toggle_calendar", _params, socket) do
    {:noreply, assign(socket, :showing_calendar, !socket.assigns.showing_calendar)}
  end

  def handle_event("suggest_date", %{"date" => date_string}, socket) do
    %{poll: poll, current_user: user} = socket.assigns

    # Only allow date suggestions during list_building phase
    if poll.phase != "list_building" do
      {:noreply, put_flash(socket, :error, "Cannot add dates during #{socket.assigns.phase_display} phase")}
    else
      # Use adapter's date sanitization
      case DatePollAdapter.sanitize_date_input(date_string) do
        {:ok, sanitized_date_string} ->
          case Date.from_iso8601(sanitized_date_string) do
            {:ok, date} ->
              # Check if this date is already an option
              existing_option = Enum.find(socket.assigns.poll_options, fn option ->
                case DatePollAdapter.validate_date_option(option) do
                  {:ok, _} ->
                                         # Use adapter's date extraction function
                     case DatePollAdapter.extract_date_from_option(option) do
                      {:ok, existing_date} -> Date.compare(existing_date, date) == :eq
                      _ -> false
                    end
                  _ -> false
                end
              end)

              if existing_option do
                # Use adapter's safe display formatting
                formatted_date = DatePollAdapter.safe_format_date_for_display(date)
                {:noreply, put_flash(socket, :info, "Date #{formatted_date} is already an option")}
              else
                # Create new date option using our generic system
                case Events.create_date_poll_option(poll, user, date, %{}) do
                  {:ok, _option} ->
                    # Send real-time update
                    send(self(), {:poll_option_added, poll.id})

                    formatted_date = DatePollAdapter.safe_format_date_for_display(date)
                    {:noreply,
                     socket
                     |> put_flash(:success, "Added #{formatted_date} to the poll")
                     |> assign(:loading, false)}

                  {:error, reason} ->
                    Logger.error("Failed to create date option: #{inspect(reason)}")
                    {:noreply, put_flash(socket, :error, "Failed to add date option")}
                end
              end

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Invalid date format")}
          end

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Invalid date input: #{reason}")}
      end
    end
  end

  def handle_event("cast_vote", %{"option_id" => option_id, "vote_value" => vote_value}, socket) do
    %{poll: poll, current_user: user, anonymous_mode: anonymous_mode} = socket.assigns

    # Validate poll is in voting phase
    unless poll.phase in ["voting", "voting_with_suggestions", "voting_only"] do
      {:noreply, put_flash(socket, :error, "Voting is not currently open for this poll")}
    else
      if anonymous_mode do
        # Handle anonymous voting with temp storage
        handle_anonymous_vote(socket, option_id, vote_value)
      else
        # Handle authenticated user voting
        handle_authenticated_vote(socket, option_id, vote_value, user)
      end
    end
  end

  def handle_event("save_anonymous_votes", _params, socket) do
    # Send temp votes to parent for processing
    send(self(), {:save_anonymous_poll_votes, socket.assigns.poll.id, socket.assigns.temp_votes})
    {:noreply, assign(socket, :loading, true)}
  end

  def handle_event("clear_temp_votes", _params, socket) do
    {:noreply, assign(socket, :temp_votes, %{})}
  end

  # PubSub event handlers for real-time updates
  def handle_info({:poll_updated, updated_poll}, socket) do
    if updated_poll.id == socket.assigns.poll.id do
      # Refresh poll data
      handle_poll_refresh(socket, updated_poll)
    else
      {:noreply, socket}
    end
  end

  def handle_info({:poll_option_added, poll_id}, socket) do
    if poll_id == socket.assigns.poll.id do
      # Refresh options and calendar data
      handle_poll_refresh(socket, socket.assigns.poll)
    else
      {:noreply, socket}
    end
  end

  def handle_info({:vote_cast, poll_id, _user_id}, socket) do
    if poll_id == socket.assigns.poll.id do
      # Refresh vote data
      handle_poll_refresh(socket, socket.assigns.poll)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="date-selection-poll-component bg-white border border-gray-200 rounded-xl shadow-sm" data-testid="date-selection-poll">
      <%= if @error_message do %>
        <div class="p-4 bg-red-50 border-l-4 border-red-400">
          <p class="text-sm text-red-700"><%= @error_message %></p>
        </div>
      <% else %>
        <!-- Poll Header -->
        <div class="px-6 py-4 border-b border-gray-200">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-3">
              <div class="flex-shrink-0">
                <span class="text-2xl"><%= poll_emoji(@poll.poll_type) %></span>
              </div>
              <div>
                <h3 class="text-lg font-semibold text-gray-900"><%= @poll.title %></h3>
                <%= if @poll.description && @poll.description != "" do %>
                  <p class="text-sm text-gray-600 mt-1"><%= @poll.description %></p>
                <% end %>
              </div>
            </div>

            <!-- Phase Badge -->
            <div class="flex items-center space-x-2">
              <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{phase_badge_class(@poll.phase)}"}>
                <%= @phase_display %>
              </span>

              <!-- Calendar Toggle for mobile -->
              <button
                type="button"
                phx-click="toggle_calendar"
                phx-target={@myself}
                class="sm:hidden p-2 rounded-md hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                aria-label="Toggle calendar view"
              >
                <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                </svg>
              </button>
            </div>
          </div>
        </div>

        <!-- Main Content -->
        <div class={"#{if @compact_view, do: "p-4", else: "p-6"}"}>
          <%= cond do %>
            <% @poll.phase == "list_building" -> %>
              <!-- Date Suggestion Phase -->
              <div class="space-y-6">
                <%= if @showing_calendar or not Application.get_env(:eventasaurus, :mobile_optimized, false) do %>
                  <!-- Calendar for Date Selection -->
                  <div>
                    <h4 class="text-sm font-medium text-gray-900 mb-3">
                      Select dates to add to the poll
                    </h4>
                    <p class="text-sm text-gray-600 mb-4">
                      Click on calendar dates to suggest them for the event. Others can then vote on your suggestions.
                    </p>

                    <%= if @legacy_poll_data do %>
                      <.live_component
                        module={CalendarComponent}
                        id={"calendar-#{@poll.id}"}
                        selected_dates={@selected_dates}
                      />
                    <% else %>
                      <div class="p-4 bg-yellow-50 border border-yellow-200 rounded-md">
                        <p class="text-sm text-yellow-700">Calendar temporarily unavailable. Please try refreshing the page.</p>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <!-- Current Date Options -->
                <%= if length(@poll_options) > 0 do %>
                  <div>
                    <h4 class="text-sm font-medium text-gray-900 mb-3">
                      Suggested dates (<%= length(@poll_options) %>)
                    </h4>
                    <div class="space-y-2">
                      <%= for option <- @poll_options do %>
                        <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                          <div class="flex items-center space-x-3">
                            <span class="text-lg">📅</span>
                            <div>
                              <p class="font-medium text-gray-900"><%= option.title %></p>
                              <%= if option.suggested_by do %>
                                <p class="text-sm text-gray-500">
                                  Suggested by <%= option.suggested_by.name || option.suggested_by.email %>
                                </p>
                              <% end %>
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <div class="text-center py-8 text-gray-500">
                    <svg class="w-12 h-12 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                    </svg>
                    <p class="font-medium">No dates suggested yet</p>
                    <p class="text-sm">Use the calendar above to suggest dates for the event!</p>
                  </div>
                <% end %>
              </div>

            <% @poll.phase in ["voting", "voting_with_suggestions", "voting_only"] -> %>
              <!-- Voting Phase -->
              <div class="space-y-6">
                <!-- Date Options with Voting Interface -->
                <%= if length(@poll_options) > 0 do %>
                  <div>
                    <h4 class="text-sm font-medium text-gray-900 mb-3">
                      Vote on the possible dates
                    </h4>
                    <p class="text-sm text-gray-600 mb-4">
                      Select your availability for each date. You can choose Yes, Maybe, or No for each option.
                    </p>

                    <!-- Use the generic VotingInterfaceComponent -->
                    <.live_component
                      module={VotingInterfaceComponent}
                      id={"voting-#{@poll.id}"}
                      poll={@poll}
                      user={@current_user}
                      user_votes={@user_votes}
                      loading={@loading}
                      temp_votes={@temp_votes}
                      anonymous_mode={@anonymous_mode}
                    />
                  </div>
                <% else %>
                  <div class="text-center py-8 text-gray-500">
                    <p class="font-medium">No dates available for voting</p>
                    <p class="text-sm">The organizer needs to add some date options first.</p>
                  </div>
                <% end %>

                <!-- Anonymous Vote Summary -->
                <%= if @anonymous_mode and map_size(@temp_votes) > 0 do %>
                  <div class="p-4 bg-blue-50 border border-blue-200 rounded-md">
                    <h4 class="text-sm font-medium text-blue-900 mb-2">Your temporary votes</h4>
                    <p class="text-sm text-blue-700 mb-3">
                      Your votes are saved temporarily. To make them count, please provide your details.
                    </p>
                    <div class="flex space-x-2">
                      <button
                        type="button"
                        phx-click="save_anonymous_votes"
                        phx-target={@myself}
                        disabled={@loading}
                        class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
                      >
                        <%= if @loading do %>
                          <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                          </svg>
                        <% end %>
                        Save My Votes
                      </button>
                      <button
                        type="button"
                        phx-click="clear_temp_votes"
                        phx-target={@myself}
                        class="inline-flex items-center px-3 py-2 border border-gray-300 text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                      >
                        Clear All
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>

            <% @poll.phase == "closed" -> %>
              <!-- Results Phase -->
              <div class="space-y-6">
                <div>
                  <h4 class="text-sm font-medium text-gray-900 mb-3">Final Results</h4>
                  <%= if @poll.finalized_option_ids and length(@poll.finalized_option_ids) > 0 do %>
                    <div class="p-4 bg-green-50 border border-green-200 rounded-md mb-4">
                      <h5 class="text-sm font-medium text-green-900 mb-2">Selected Date(s)</h5>
                      <%= for option_id <- @poll.finalized_option_ids do %>
                        <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
                        <%= if option do %>
                          <p class="text-sm text-green-700">📅 <%= option.title %></p>
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>

                  <!-- Vote Summary -->
                  <%= if length(@poll_options) > 0 do %>
                    <div class="space-y-3">
                      <%= for option <- @poll_options do %>
                        <% summary = Map.get(@vote_summaries, option.id, %{vote_counts: %{yes: 0, maybe: 0, no: 0}, total_votes: 0}) %>
                        <div class="p-3 border border-gray-200 rounded-lg">
                          <div class="flex items-center justify-between mb-2">
                            <span class="font-medium text-gray-900"><%= option.title %></span>
                                                          <span class="text-sm text-gray-500"><%= summary.total_votes %> vote<%= if summary.total_votes != 1, do: "s" %></span>
                          </div>
                          <%= if summary.total_votes > 0 do %>
                            <div class="flex items-center space-x-4 text-sm">
                              <div class="flex items-center">
                                <span class="w-3 h-3 bg-green-500 rounded-full mr-1"></span>
                                <span class="text-gray-600">Yes: <%= summary.vote_counts.yes %></span>
                              </div>
                              <div class="flex items-center">
                                <span class="w-3 h-3 bg-yellow-500 rounded-full mr-1"></span>
                                <span class="text-gray-600">Maybe: <%= summary.vote_counts.maybe %></span>
                              </div>
                              <div class="flex items-center">
                                <span class="w-3 h-3 bg-red-500 rounded-full mr-1"></span>
                                <span class="text-gray-600">No: <%= summary.vote_counts.no %></span>
                              </div>
                            </div>
                          <% else %>
                            <p class="text-sm text-gray-500">No votes</p>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>

            <% true -> %>
              <!-- Unknown phase -->
              <div class="text-center py-8 text-gray-500">
                <p>Unknown poll phase: <%= @poll.phase %></p>
              </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Private helper functions

  defp handle_authenticated_vote(socket, option_id, vote_value, user) do
    %{poll: poll} = socket.assigns

    case Integer.parse(option_id) do
      {parsed_option_id, ""} ->
        case Events.get_poll_option(parsed_option_id) do
          nil ->
            {:noreply, put_flash(socket, :error, "Invalid option")}

          poll_option ->
            case Events.cast_binary_vote(poll, poll_option, user, vote_value) do
              {:ok, _vote} ->
                # Send real-time update
                send(self(), {:vote_cast, poll.id, user.id})

                {:noreply,
                 socket
                 |> put_flash(:success, "Vote recorded!")
                 |> assign(:loading, false)}

              {:error, reason} ->
                Logger.error("Failed to cast vote: #{inspect(reason)}")
                {:noreply, put_flash(socket, :error, "Failed to record vote")}
            end
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid option ID")}
    end
  end

  defp handle_anonymous_vote(socket, option_id, vote_value) do
    case Integer.parse(option_id) do
      {parsed_option_id, ""} ->
        temp_votes = socket.assigns.temp_votes
        updated_temp_votes = Map.put(temp_votes, parsed_option_id, vote_value)

        # Send update to parent
        send(self(), {:temp_votes_updated, socket.assigns.poll.id, updated_temp_votes})

        {:noreply, assign(socket, :temp_votes, updated_temp_votes)}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid option ID")}
    end
  end

  defp handle_poll_refresh(socket, updated_poll) do
    # Reload fresh data
    poll_options = Events.list_poll_options(updated_poll)
    user_votes = if socket.assigns.current_user do
      Events.list_user_poll_votes(updated_poll, socket.assigns.current_user)
    else
      []
    end

    # Update legacy data
    legacy_poll_data = case DatePollAdapter.get_legacy_poll_with_data(updated_poll.id) do
      {:ok, legacy_data} -> legacy_data
      {:error, _} -> nil
    end

    selected_dates = extract_dates_from_options(poll_options)
    vote_summaries = calculate_vote_summaries(poll_options, user_votes)
    phase_display = DatePollAdapter.safe_status_display(updated_poll)

    {:noreply,
     socket
     |> assign(:poll, updated_poll)
     |> assign(:poll_options, poll_options)
     |> assign(:user_votes, user_votes)
     |> assign(:selected_dates, selected_dates)
     |> assign(:legacy_poll_data, legacy_poll_data)
     |> assign(:vote_summaries, vote_summaries)
     |> assign(:phase_display, phase_display)
     |> assign(:loading, false)}
  end

  defp extract_dates_from_options(poll_options) do
    poll_options
    |> Enum.map(fn option ->
      case DatePollAdapter.extract_date_from_option(option) do
        {:ok, date} -> date
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
    |> Enum.sort()
  end

    defp calculate_vote_summaries(poll_options, _user_votes) do
    # Calculate vote summaries for each option
    poll_options
    |> Enum.into(%{}, fn option ->
      # Load votes for this option - use the existing votes from preloaded data
      votes = option.votes || []

      # Use adapter to safely display option title and validate option
      option_display = case DatePollAdapter.validate_date_option(option) do
        {:ok, _} -> DatePollAdapter.safe_option_title(option)
        {:error, _} -> option.title || "Invalid Option"
      end

      vote_counts = %{
        yes: Enum.count(votes, fn vote -> vote.vote_value == "yes" end),
        maybe: Enum.count(votes, fn vote -> vote.vote_value == "maybe" end),
        no: Enum.count(votes, fn vote -> vote.vote_value == "no" end)
      }

      total_votes = vote_counts.yes + vote_counts.maybe + vote_counts.no

      summary = %{
        option_id: option.id,
        option_title: option_display,
        vote_counts: vote_counts,
        total_votes: total_votes,
        winner_score: vote_counts.yes * 2 + vote_counts.maybe * 1 # Weighted scoring
      }

      {option.id, summary}
    end)
  end

  defp phase_badge_class(phase) do
    case phase do
      "list_building" -> "bg-blue-100 text-blue-800"
      "voting" -> "bg-green-100 text-green-800"
      "voting_with_suggestions" -> "bg-green-100 text-green-800"
      "voting_only" -> "bg-green-100 text-green-800"
      "closed" -> "bg-gray-100 text-gray-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
