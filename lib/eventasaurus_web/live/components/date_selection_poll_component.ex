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
  alias EventasaurusWeb.Utils.TimeUtils
  alias Phoenix.PubSub

  require Logger

  # Import utilities for date handling and display
  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.VoterCountDisplay
  import EventasaurusWeb.ClearVotesButton

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
     |> assign(:poll_data, nil)
     |> assign(:vote_summaries, %{})
     |> assign(:phase_display, "list_building")
     # NEW: Time selection state
     |> assign(:time_enabled, false)
     |> assign(:selected_date_for_time, nil)
     |> assign(:date_time_slots, %{})}
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
        PubSub.subscribe(Eventasaurus.PubSub, "polls:#{poll.id}:stats")
      end

      # Load poll options and votes
      poll_options = Events.list_poll_options(poll)
      user_votes = if current_user, do: Events.list_user_poll_votes(poll, current_user), else: []

      # Get poll data using simplified adapter
      poll_data = case DatePollAdapter.get_poll_with_data(poll.id) do
        {:ok, data} -> data
        {:error, reason} ->
          Logger.warning("Failed to get poll #{poll.id} data: #{inspect(reason)}")
          nil
      end

      # Extract selected dates from poll options for calendar display
      selected_dates = extract_dates_from_options(poll_options)

      # Calculate vote summaries for results display
      vote_summaries = calculate_vote_summaries(poll_options, user_votes)

      # Determine phase display string
      phase_display = DatePollAdapter.safe_status_display(poll)

      # Load poll statistics for embedded display
      poll_stats = try do
        Events.get_poll_voting_stats(poll)
      rescue
        _ -> %{options: []}
      end

      {:ok,
       socket
       |> assign(assigns)
       |> assign(:poll_options, poll_options)
       |> assign(:user_votes, user_votes)
       |> assign(:selected_dates, selected_dates)
       |> assign(:poll_data, poll_data)
       |> assign(:vote_summaries, vote_summaries)
       |> assign(:phase_display, phase_display)
       |> assign(:poll_stats, poll_stats)
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

  # NEW: Time selection event handlers
  def handle_event("toggle_time_selection", _params, socket) do
    {:noreply, assign(socket, :time_enabled, !socket.assigns.time_enabled)}
  end

  def handle_event("configure_date_time", %{"date" => date_string}, socket) do
    {:noreply, assign(socket, :selected_date_for_time, date_string)}
  end

  def handle_event("save_date_time_slots", %{"date" => date_string, "time_slots" => time_slots}, socket) do
    updated_slots = Map.put(socket.assigns.date_time_slots, date_string, time_slots)
    {:noreply,
     socket
     |> assign(:date_time_slots, updated_slots)
     |> assign(:selected_date_for_time, nil)}
  end

  def handle_event("cancel_time_config", _params, socket) do
    {:noreply, assign(socket, :selected_date_for_time, nil)}
  end

  def handle_event("suggest_date", %{"date" => date_string}, socket) do
    %{poll: poll, current_user: user, time_enabled: time_enabled, date_time_slots: date_time_slots} = socket.assigns

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
                # Create enhanced metadata with time support
                # Use consistent ISO8601 format for time slot lookup
                date_iso = Date.to_iso8601(date)
                app_timezone = Application.get_env(:eventasaurus, :timezone, "UTC")
                metadata = create_date_metadata_with_time(date, time_enabled, date_time_slots[date_iso], app_timezone)

                # Create new date option using our generic system with enhanced metadata
                case Events.create_date_poll_option(poll, user, date, metadata) do
                  {:ok, _option} ->
                    # Send real-time update
                    send(self(), {:poll_option_added, poll.id})

                    formatted_date = DatePollAdapter.safe_format_date_for_display(date)
                    {:noreply,
                     socket
                     |> put_flash(:success, "Added #{formatted_date} to the poll")
                     |> assign(:loading, false)
                     # Clear time slots for this date after creating option
                     |> assign(:date_time_slots, Map.delete(date_time_slots, date_iso))}

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

  def handle_event("clear_all_votes", _params, socket) do
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

  def handle_info({:poll_stats_updated, stats}, socket) do
    {:noreply, assign(socket, :poll_stats, stats)}
  end

  def handle_info({:poll_stats_updated, poll_id, stats}, socket) do
    if poll_id == socket.assigns.poll.id do
      {:noreply, assign(socket, :poll_stats, stats)}
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
        <div class="px-4 sm:px-6 py-4 border-b border-gray-200">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between space-y-3 sm:space-y-0">
            <div class="flex items-center space-x-3">
              <div class="flex-shrink-0">
                <span class="text-2xl"><%= poll_emoji(@poll.poll_type) %></span>
              </div>
              <div class="min-w-0 flex-1">
                <h3 class="text-lg font-semibold text-gray-900 truncate"><%= @poll.title %></h3>
                <%= if @poll.description && @poll.description != "" do %>
                  <p class="text-sm text-gray-600 mt-1 line-clamp-2 sm:line-clamp-none"><%= @poll.description %></p>
                <% end %>
                <.voter_count poll_stats={@poll_stats} poll_phase={@poll.phase} class="mt-1" />
              </div>
            </div>

            <!-- Phase Badge -->
            <div class="flex flex-col sm:flex-row sm:items-center space-y-2 sm:space-y-0 sm:space-x-2">
              <div class="flex items-center justify-between sm:justify-start">
                <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{phase_badge_class(@poll.phase)}"}>
                  <%= @phase_display %>
                </span>

                <!-- Calendar Toggle for mobile -->
                <button
                  type="button"
                  phx-click="toggle_calendar"
                  phx-target={@myself}
                  class="sm:hidden ml-2 p-2 rounded-md hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  aria-label="Toggle calendar view"
                >
                  <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 002 2z"/>
                  </svg>
                </button>
              </div>

              <%= if @poll.deadline do %>
                <span class="text-xs text-gray-500 sm:text-left">
                  Deadline: <%= format_deadline(@poll.deadline) %>
                </span>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Main Content -->
        <div class={"#{if @compact_view, do: "p-3 sm:p-4", else: "p-4 sm:p-6"}"}>
          <%= cond do %>
            <% @poll.phase == "list_building" -> %>
              <!-- Date Suggestion Phase -->
              <div class="space-y-4 sm:space-y-6">
                <%= if @showing_calendar or not Application.get_env(:eventasaurus, :mobile_optimized, false) do %>
                  <!-- Calendar for Date Selection -->
                  <div class="overflow-hidden">
                    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-3">
                      <h4 class="text-sm font-medium text-gray-900">
                        Select dates to add to the poll
                      </h4>
                      <button
                        type="button"
                        phx-click="toggle_calendar"
                        phx-target={@myself}
                        class="sm:hidden text-sm text-blue-600 hover:text-blue-700 font-medium mt-1"
                      >
                        Hide Calendar
                      </button>
                    </div>
                    <p class="text-sm text-gray-600 mb-4">
                      Click on calendar dates to suggest them for the event. Others can then vote on your suggestions.
                    </p>

                    <div class="calendar-container bg-white rounded-lg border border-gray-200 overflow-hidden">
                      <%= if @poll_data do %>
                        <.live_component
                          module={CalendarComponent}
                          id={"calendar-#{@poll.id}"}
                          selected_dates={@selected_dates}
                        />
                      <% else %>
                        <div class="p-3 sm:p-4 bg-yellow-50 border border-yellow-200 rounded-md">
                          <p class="text-sm text-yellow-700">Calendar temporarily unavailable. Please try refreshing the page.</p>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <!-- NEW: Time Selection Toggle -->
                <div class="bg-gray-50 p-4 rounded-lg border border-gray-200">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center space-x-3">
                      <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                      </svg>
                      <div>
                        <h4 class="text-sm font-medium text-gray-900">Specify times</h4>
                        <p class="text-xs text-gray-600">Include start and end times for each option</p>
                      </div>
                    </div>
                    <label class="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        phx-click="toggle_time_selection"
                        phx-target={@myself}
                        checked={@time_enabled}
                        class="sr-only peer"
                      />
                      <div class="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
                    </label>
                  </div>

                  <!-- Time Configuration Interface (when enabled) -->
                  <%= if @time_enabled and @selected_date_for_time do %>
                    <div class="mt-4 p-4 bg-white rounded-lg border border-gray-200">
                      <div class="flex items-center justify-between mb-3">
                        <h5 class="text-sm font-medium text-gray-900">
                          Configure times for <%= @selected_date_for_time %>
                        </h5>
                        <button
                          type="button"
                          phx-click="cancel_time_config"
                          phx-target={@myself}
                          class="text-gray-400 hover:text-gray-600"
                        >
                          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                          </svg>
                        </button>
                      </div>

                      <!-- Time Slot Picker Component -->
                      <.live_component
                        module={EventasaurusWeb.TimeSlotPickerComponent}
                        id={"time-picker-#{@selected_date_for_time}"}
                        date={@selected_date_for_time}
                        existing_slots={@date_time_slots[@selected_date_for_time] || []}
                        on_save="save_date_time_slots"
                        target={@myself}
                      />
                    </div>
                  <% end %>
                </div>

                <!-- Current Date Options -->
                <%= if length(@poll_options) > 0 do %>
                  <div>
                    <h4 class="text-sm font-medium text-gray-900 mb-3">
                      Suggested dates (<%= length(@poll_options) %>)
                    </h4>
                    <div class="space-y-2">
                      <%= for option <- @poll_options do %>
                        <div class="p-3 bg-gray-50 rounded-lg">
                          <div class="flex items-center justify-between">
                            <div class="flex items-center space-x-3 flex-1">
                              <span class="text-lg">📅</span>
                              <div class="flex-1">
                                <div class="flex items-center space-x-2 mb-1">
                                  <p class="font-medium text-gray-900"><%= option.title %></p>
                                  <%= if @time_enabled and has_time_slots?(option) do %>
                                    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800">
                                      <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                      </svg>
                                      Times
                                    </span>
                                  <% end %>
                                </div>

                                <!-- Time Slots Display -->
                                <%= if @time_enabled and has_time_slots?(option) do %>
                                  <div class="mt-2 flex flex-wrap gap-2">
                                    <%= for time_slot <- get_time_slots_from_option(option) do %>
                                      <span class="inline-flex items-center px-2.5 py-1 rounded-md text-sm bg-white border border-gray-200 text-gray-700">
                                        <%= format_time_slot_display(time_slot) %>
                                      </span>
                                    <% end %>
                                  </div>
                                <% end %>

                                <%= if option.suggested_by do %>
                                  <p class="text-sm text-gray-500 mt-1">
                                    Suggested by <%= option.suggested_by.name || option.suggested_by.email %>
                                  </p>
                                <% end %>

                                <!-- Embedded Progress Bar for list building phase -->
                                <%= if @poll_stats && @poll.phase == "list_building" do %>
                                  <div class="mt-2">
                                    <.live_component
                                      module={EventasaurusWeb.EmbeddedProgressBarComponent}
                                      id={"progress-list-#{option.id}"}
                                      poll_stats={@poll_stats}
                                      option_id={option.id}
                                      voting_system={@poll.voting_system || "binary"}
                                      compact={true}
                                      show_labels={false}
                                      show_counts={true}
                                      anonymous_mode={false}
                                    />
                                  </div>
                                <% end %>
                              </div>
                            </div>

                          <!-- Time Configuration Button -->
                          <%= if @time_enabled do %>
                            <div class="flex items-center space-x-2">
                              <button
                                type="button"
                                phx-click="configure_date_time"
                                phx-value-date={extract_date_string_from_option(option)}
                                phx-target={@myself}
                                class="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                              >
                                <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                <%= if has_time_slots?(option), do: "Edit", else: "Add" %> Times
                              </button>
                            </div>
                          <% end %>
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
              <div class="space-y-4 sm:space-y-6">
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
                  <div class="p-3 sm:p-4 bg-blue-50 border border-blue-200 rounded-md">
                    <h4 class="text-sm font-medium text-blue-900 mb-2">Your temporary votes</h4>
                    <p class="text-sm text-blue-700 mb-3">
                      Your votes are saved temporarily. To make them count, please provide your details.
                    </p>
                    <div class="flex flex-col sm:flex-row space-y-2 sm:space-y-0 sm:space-x-2">
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
                      <.clear_votes_button
                        id={"clear-temp-votes-date-#{@poll.id}"}
                        target={@myself}
                        has_votes={map_size(@temp_votes) > 0}
                        loading={@loading}
                        anonymous_mode={true}
                        variant="button"
                      />
                    </div>
                  </div>
                <% end %>
              </div>

            <% @poll.phase == "closed" -> %>
              <!-- Results Phase -->
              <div class="space-y-4 sm:space-y-6">
                <div>
                  <h4 class="text-sm font-medium text-gray-900 mb-3">Final Results</h4>
                  <%= if @poll.finalized_option_ids and length(@poll.finalized_option_ids) > 0 do %>
                    <div class="p-3 sm:p-4 bg-green-50 border border-green-200 rounded-md mb-4">
                      <h5 class="text-sm font-medium text-green-900 mb-2">Selected Date(s)</h5>
                      <%= for option_id <- @poll.finalized_option_ids do %>
                        <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
                        <%= if option do %>
                          <p class="text-sm text-green-700">📅 <%= option.title %></p>
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>

                  <!-- Vote Summary with Embedded Results -->
                  <%= if length(@poll_options) > 0 do %>
                    <div class="space-y-3">
                      <%= for option <- @poll_options do %>
                        <% is_finalized = option.id in (@poll.finalized_option_ids || []) %>
                        <div class={"p-4 border border-gray-200 rounded-lg #{if is_finalized, do: "bg-green-50 border-green-300", else: "bg-white"}"}>
                          <div class="flex items-start space-x-3">
                            <span class="text-lg mt-0.5">📅</span>
                            <div class="flex-1">
                              <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-2">
                                <div>
                                  <h4 class="font-medium text-gray-900"><%= option.title %></h4>
                                  <%= if option.id in (@poll.finalized_option_ids || []) do %>
                                    <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 mt-1">
                                      ✓ Selected
                                    </span>
                                  <% end %>
                                </div>
                              </div>

                              <!-- Time Slots Display -->
                              <%= if has_time_slots?(option) do %>
                                <div class="mb-2 flex flex-wrap gap-2">
                                  <%= for time_slot <- get_time_slots_from_option(option) do %>
                                    <span class="inline-flex items-center px-2.5 py-1 rounded-md text-sm bg-white border border-gray-200 text-gray-700">
                                      <%= format_time_slot_display(time_slot) %>
                                    </span>
                                  <% end %>
                                </div>
                              <% end %>

                              <!-- Embedded Progress Bar for Results -->
                              <.live_component
                                module={EventasaurusWeb.EmbeddedProgressBarComponent}
                                id={"progress-result-#{option.id}"}
                                poll_stats={@poll_stats}
                                option_id={option.id}
                                voting_system={@poll.voting_system || "binary"}
                                compact={false}
                                show_labels={true}
                                show_counts={true}
                                anonymous_mode={false}
                              />
                            </div>
                          </div>
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

    # Update poll data
    poll_data = case DatePollAdapter.get_poll_with_data(updated_poll.id) do
      {:ok, data} -> data
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
     |> assign(:poll_data, poll_data)
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

  defp format_deadline(deadline) when is_nil(deadline), do: "None"

  defp format_deadline(%DateTime{} = datetime) do
    case DateTime.compare(datetime, DateTime.utc_now()) do
      :lt -> "Expired"
      _ ->
        # Format for mobile: shorter format
        timezone = Application.get_env(:eventasaurus, :timezone, "UTC")
        case DateTime.shift_zone(datetime, timezone) do
          {:ok, shifted_datetime} ->
            Calendar.strftime(shifted_datetime, "%-m/%-d %I:%M %p")
          {:error, _} ->
            # Fallback to UTC if timezone shift fails
            Calendar.strftime(datetime, "%-m/%-d %I:%M %p")
        end
    end
  end

  defp format_deadline(deadline) when is_binary(deadline) do
    case DateTime.from_iso8601(deadline) do
      {:ok, datetime, _} -> format_deadline(datetime)
      _ -> "Invalid"
    end
  end

  defp format_deadline(_), do: "Invalid"

  defp create_date_metadata_with_time(date, time_enabled, time_slots, timezone) do
    base_metadata = %{
      "date" => Date.to_iso8601(date),
      "display_date" => DatePollAdapter.safe_format_date_for_display(date),
      "date_type" => "single_date",
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    if time_enabled and time_slots && length(time_slots) > 0 do
      base_metadata
      |> Map.put("time_enabled", true)
      |> Map.put("all_day", false)
      |> Map.put("time_slots", time_slots)
      |> Map.put("timezone", timezone)
    else
      base_metadata
      |> Map.put("time_enabled", false)
      |> Map.put("all_day", true)
      |> Map.put("timezone", timezone)
    end
  end

  defp has_time_slots?(option) do
    case option.metadata do
      %{"time_enabled" => true, "time_slots" => time_slots} when is_list(time_slots) and length(time_slots) > 0 ->
        true
      _ ->
        false
    end
  end

  defp get_time_slots_from_option(option) do
    case option.metadata do
      %{"time_enabled" => true, "time_slots" => time_slots} when is_list(time_slots) ->
        time_slots
      _ ->
        []
    end
  end

  defp format_time_slot_display(slot) when is_map(slot) do
    case {slot["start_time"], slot["end_time"]} do
      {start_time, end_time} when is_binary(start_time) and is_binary(end_time) ->
        # Convert 24-hour format to 12-hour format for display
        start_display = TimeUtils.format_time_12hour(start_time)
        end_display = TimeUtils.format_time_12hour(end_time)
        "#{start_display} - #{end_display}"
      _ ->
        "Invalid time slot"
    end
  end

  defp format_time_slot_display(_), do: "Invalid time slot"

  defp extract_date_string_from_option(option) do
    case DatePollAdapter.extract_date_from_option(option) do
      {:ok, date} -> Date.to_iso8601(date)
      _ -> nil
    end
  end
end
