defmodule EventasaurusWeb.Components.PublicPlanWithFriendsModal do
  @moduledoc """
  Enhanced modal for creating private events from public events.
  Uses shared components and supports both user selection and email invitations.
  Does NOT include direct add functionality (invitation only).
  """
  use Phoenix.Component

  alias EventasaurusWeb.Components.Invitations.{
    HistoricalParticipantsComponent,
    SelectedParticipantsComponent,
    InvitationMessageComponent
  }

  import EventasaurusWeb.Components.IndividualEmailInput

  alias EventasaurusApp.Images.MovieImages
  alias EventasaurusWeb.Utils.TimeUtils

  # Configuration for adaptive date selection UI
  # Dates with availability <= this threshold use simple list UI
  # Dates > threshold use full grid UI
  @simple_list_max_days 5

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :public_event, :map, default: nil
  attr :selected_occurrence, :map, default: nil
  attr :selected_users, :list, default: []
  attr :selected_emails, :list, default: []
  attr :current_email_input, :string, default: ""
  attr :bulk_email_input, :string, default: ""
  attr :invitation_message, :string, default: ""
  attr :organizer, :map, required: true
  attr :on_close, :string, default: "close_plan_modal"
  attr :on_submit, :string, default: "submit_plan_with_friends"
  # Flexible planning attributes
  attr :planning_mode, :atom, default: :selection
  attr :filter_criteria, :map, default: %{}
  attr :matching_occurrences, :list, default: []
  attr :is_movie_event, :boolean, default: false
  attr :is_venue_event, :boolean, default: false
  # Phase 2: Context Detection attributes
  attr :entry_context, :atom, default: :standard_event
  attr :is_single_occurrence, :boolean, default: false
  attr :filter_preview_count, :integer, default: nil
  attr :movie_id, :integer, default: nil
  attr :city_id, :integer, default: nil
  attr :movie, :map, default: nil
  attr :city, :map, default: nil
  attr :date_availability, :map, default: %{}
  attr :time_period_availability, :map, default: %{}
  # Venue scope toggle (for movie events accessed from specific venue)
  attr :include_all_venues, :boolean, default: false

  def modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        id={@id}
        class="fixed inset-0 z-50 overflow-y-auto"
        phx-window-keydown={@on_close}
        phx-key="escape"
      >
        <!-- Backdrop -->
        <div class="fixed inset-0 bg-black bg-opacity-50" phx-click={@on_close}></div>

        <!-- Modal Content -->
        <div class="relative min-h-screen flex items-center justify-center p-4">
          <div class="relative bg-white rounded-lg max-w-3xl w-full max-h-[90vh] flex flex-col" phx-click-away={@on_close}>
            <!-- Context Banner (Event or Movie) -->
            <%= if @public_event do %>
              <!-- Event Context Banner -->
              <div class="flex-shrink-0 bg-gradient-to-r from-blue-600 to-purple-600 text-white px-6 py-3 rounded-t-lg">
                <div class="flex items-center gap-4">
                  <%= if get_event_image(@public_event) do %>
                    <img
                      src={get_event_image(@public_event)}
                      alt={@public_event.title}
                      class="w-12 h-12 rounded object-cover flex-shrink-0"
                    />
                  <% end %>
                  <div class="flex-1 min-w-0">
                    <h3 class="text-lg font-semibold truncate">
                      <%= @public_event.title %>
                    </h3>
                    <%= if @public_event.venue do %>
                      <p class="text-sm text-blue-100 truncate">
                        <%= @public_event.venue.name %>
                      </p>
                    <% end %>
                  </div>
                  <button
                    type="button"
                    phx-click={@on_close}
                    class="text-white hover:text-gray-200 flex-shrink-0"
                  >
                    <span class="sr-only">Close</span>
                    <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              </div>
            <% else %>
              <%= if @movie && @city do %>
                <!-- Movie Context Banner -->
                <div class="flex-shrink-0 bg-gradient-to-r from-indigo-600 to-purple-600 text-white px-6 py-3 rounded-t-lg">
                  <div class="flex items-center gap-4">
                    <%= if poster_url = MovieImages.get_poster_url(@movie.id, @movie.poster_url) do %>
                      <img
                        src={poster_url}
                        alt={"#{@movie.title} poster"}
                        class="w-12 h-12 rounded object-cover flex-shrink-0"
                      />
                    <% end %>
                    <div class="flex-1 min-w-0">
                      <h3 class="text-lg font-semibold truncate">
                        <%= @movie.title %>
                      </h3>
                      <p class="text-sm text-indigo-100 truncate">
                        Find showtimes in <%= @city.name %>
                      </p>
                    </div>
                    <button
                      type="button"
                      phx-click={@on_close}
                      class="text-white hover:text-gray-200 flex-shrink-0"
                    >
                      <span class="sr-only">Close</span>
                      <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                </div>
              <% end %>
            <% end %>

            <!-- Header -->
            <div class="flex-shrink-0 bg-white border-b border-gray-200 px-6 py-4">
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="text-2xl font-bold text-gray-900">
                    <%= case @planning_mode do %>
                      <% :selection -> %> Choose Planning Style
                      <% :quick -> %> Quick Plan
                      <% :flexible_filters -> %> Flexible Plan - Choose Options
                      <% :flexible_review -> %> Flexible Plan - Invite Friends
                    <% end %>
                  </h2>
                  <p class="mt-1 text-sm text-gray-600">
                    <%= case @planning_mode do %>
                      <% :selection -> %> Pick a date now or let friends vote on their preferred time
                      <% :quick -> %> Create a private event and invite your friends
                      <% :flexible_filters -> %> Find available showtimes<%= if @public_event, do: " for #{@public_event.title}" %> to create a poll
                      <% :flexible_review -> %> Invite friends to vote on their preferred showtime
                    <% end %>
                  </p>
                </div>
              </div>

              <!-- Progress Indicators - Phase 4 -->
              <%= render_progress_indicator(assigns) %>
            </div>

            <!-- Form Content (Scrollable) -->
            <div class="flex-1 overflow-y-auto px-6 py-4">
              <%= case @planning_mode do %>
                <% :selection -> %>
                  <%= render_mode_selection(assigns) %>
                <% :quick -> %>
                  <%= render_quick_plan_form(assigns) %>
                <% :flexible_filters -> %>
                  <%= render_filter_selection(assigns) %>
                <% :flexible_review -> %>
                  <%= render_flexible_review_form(assigns) %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Progress Indicator Component - Phase 4
  # Shows current step in the flow with visual indicators
  defp render_progress_indicator(assigns) do
    # Determine the flow type and current step
    # Quick Plan: 1. Choose Mode -> 2. Invite Friends -> Done
    # Flexible Plan: 1. Choose Mode -> 2. Select Options -> 3. Invite Friends -> Done
    # Single-occurrence: Skip step 1, go straight to step 2

    ~H"""
    <div class="mt-4">
      <%= case @planning_mode do %>
        <% :selection -> %>
          <!-- Step 1 of flow - mode selection -->
          <div class="flex items-center justify-center gap-2">
            <div class="flex items-center gap-1">
              <span class="flex items-center justify-center w-6 h-6 rounded-full bg-purple-600 text-white text-xs font-semibold">1</span>
              <span class="text-sm font-medium text-purple-600">Choose Plan</span>
            </div>
            <div class="w-8 h-0.5 bg-gray-200"></div>
            <div class="flex items-center gap-1">
              <span class="flex items-center justify-center w-6 h-6 rounded-full bg-gray-200 text-gray-500 text-xs font-semibold">2</span>
              <span class="text-sm text-gray-500">Invite Friends</span>
            </div>
          </div>

        <% :quick -> %>
          <!-- Quick Plan: Step 2 (final step for quick plan) -->
          <div class="flex items-center justify-center gap-2">
            <%= if @is_single_occurrence do %>
              <!-- Single occurrence skips step 1 -->
              <div class="flex items-center gap-1">
                <span class="flex items-center justify-center w-6 h-6 rounded-full bg-purple-600 text-white text-xs font-semibold">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                  </svg>
                </span>
                <span class="text-sm font-medium text-purple-600">Invite Friends</span>
              </div>
            <% else %>
              <div class="flex items-center gap-1">
                <span class="flex items-center justify-center w-6 h-6 rounded-full bg-green-500 text-white text-xs">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                  </svg>
                </span>
                <span class="text-sm text-green-600">Choose Plan</span>
              </div>
              <div class="w-8 h-0.5 bg-green-400"></div>
              <div class="flex items-center gap-1">
                <span class="flex items-center justify-center w-6 h-6 rounded-full bg-purple-600 text-white text-xs font-semibold">2</span>
                <span class="text-sm font-medium text-purple-600">Invite Friends</span>
              </div>
            <% end %>
          </div>

        <% :flexible_filters -> %>
          <!-- Flexible Plan: Step 2 of 3 (select options) -->
          <div class="flex items-center justify-center gap-2">
            <div class="flex items-center gap-1">
              <span class="flex items-center justify-center w-6 h-6 rounded-full bg-green-500 text-white text-xs">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
              </span>
              <span class="text-sm text-green-600">Choose Plan</span>
            </div>
            <div class="w-8 h-0.5 bg-green-400"></div>
            <div class="flex items-center gap-1">
              <span class="flex items-center justify-center w-6 h-6 rounded-full bg-purple-600 text-white text-xs font-semibold">2</span>
              <span class="text-sm font-medium text-purple-600">Select Options</span>
            </div>
            <div class="w-8 h-0.5 bg-gray-200"></div>
            <div class="flex items-center gap-1">
              <span class="flex items-center justify-center w-6 h-6 rounded-full bg-gray-200 text-gray-500 text-xs font-semibold">3</span>
              <span class="text-sm text-gray-500">Invite Friends</span>
            </div>
          </div>

        <% :flexible_review -> %>
          <!-- Flexible Plan: Step 3 of 3 (invite friends) -->
          <div class="flex items-center justify-center gap-2">
            <div class="flex items-center gap-1">
              <span class="flex items-center justify-center w-6 h-6 rounded-full bg-green-500 text-white text-xs">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
              </span>
              <span class="text-sm text-green-600">Choose Plan</span>
            </div>
            <div class="w-8 h-0.5 bg-green-400"></div>
            <div class="flex items-center gap-1">
              <span class="flex items-center justify-center w-6 h-6 rounded-full bg-green-500 text-white text-xs">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
              </span>
              <span class="text-sm text-green-600">Select Options</span>
            </div>
            <div class="w-8 h-0.5 bg-green-400"></div>
            <div class="flex items-center gap-1">
              <span class="flex items-center justify-center w-6 h-6 rounded-full bg-purple-600 text-white text-xs font-semibold">3</span>
              <span class="text-sm font-medium text-purple-600">Invite Friends</span>
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  # Mode Selection View
  # Phase 2: Adaptive behavior based on entry_context and is_single_occurrence
  defp render_mode_selection(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Quick Plan Option -->
      <button
        type="button"
        phx-click="select_planning_mode"
        phx-value-mode="quick"
        class="w-full p-6 border-2 border-gray-200 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition text-left"
      >
        <div class="flex items-start">
          <div class="flex-shrink-0">
            <svg class="w-12 h-12 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
          </div>
          <div class="ml-4 flex-1">
            <h3 class="text-lg font-bold text-gray-900">
              <%= if @is_single_occurrence, do: "Create Event", else: "Quick Plan" %>
            </h3>
            <p class="mt-1 text-sm text-gray-600">
              <%= cond do %>
                <% @is_single_occurrence && @selected_occurrence -> %>
                  Create an event for <span class="font-semibold"><%= format_occurrence_datetime_full(@selected_occurrence) %></span>
                  <%= if Map.get(@selected_occurrence, :venue_name) do %>
                    at <span class="font-semibold"><%= @selected_occurrence.venue_name %></span>
                  <% end %>
                <% @entry_context == :specific_showtime && @selected_occurrence -> %>
                  Create an event for <span class="font-semibold"><%= format_occurrence_datetime_full(@selected_occurrence) %></span>
                  <%= if Map.get(@selected_occurrence, :venue_name) do %>
                    at <span class="font-semibold"><%= @selected_occurrence.venue_name %></span>
                  <% end %>
                  <span class="block mt-1 text-xs text-green-600">✓ Showtime already selected</span>
                <% @selected_occurrence -> %>
                  Create an event for <span class="font-semibold"><%= format_occurrence_datetime_full(@selected_occurrence) %></span>
                  <%= if Map.get(@selected_occurrence, :venue_name) do %>
                    at <span class="font-semibold"><%= @selected_occurrence.venue_name %></span>
                  <% end %>
                <% true -> %>
                  Pick a specific showtime and create your event instantly
              <% end %>
            </p>
            <p class="mt-2 text-xs text-gray-500">
              <%= if @is_single_occurrence do %>
                This event has a single date/time
              <% else %>
                Best for: When you already know which <%= if @is_movie_event, do: "theater", else: "venue" %> and time works for your group
              <% end %>
            </p>
          </div>
        </div>
      </button>

      <!-- Flexible Plan Option - Hidden for single-occurrence events -->
      <!-- Recommended for generic movie pages (no specific showtime selected) -->
      <%= unless @is_single_occurrence do %>
        <% is_recommended = @entry_context == :generic_movie %>
        <button
          type="button"
          phx-click="select_planning_mode"
          phx-value-mode="flexible"
          class={[
            "w-full p-6 border-2 rounded-lg hover:border-purple-500 hover:bg-purple-50 transition text-left relative",
            if(is_recommended, do: "border-purple-400 bg-purple-50/50", else: "border-gray-200")
          ]}
        >
          <!-- Recommended badge for generic movie pages -->
          <%= if is_recommended do %>
            <div class="absolute -top-3 left-4 px-2 py-0.5 bg-purple-600 text-white text-xs font-semibold rounded-full">
              ✨ Recommended
            </div>
          <% end %>
          <div class="flex items-start">
            <div class="flex-shrink-0">
              <svg class="w-12 h-12 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
              </svg>
            </div>
            <div class="ml-4 flex-1">
              <h3 class="text-lg font-bold text-gray-900">
                Flexible Plan with Poll
                <%= if is_recommended do %>
                  <span class="text-sm font-normal text-purple-600 ml-1">— Best for groups</span>
                <% end %>
              </h3>
              <p class="mt-1 text-sm text-gray-600">
                Create a poll with multiple showtime options and let your friends vote on which time works best
              </p>
              <div class="mt-3 p-3 bg-purple-50 rounded-md border border-purple-100">
                <p class="text-xs text-gray-700">
                  <span class="font-semibold">How it works:</span>
                </p>
                <ol class="mt-1 text-xs text-gray-600 space-y-1 list-decimal list-inside">
                  <li>Choose date range and preferred times</li>
                  <li>Invite friends to vote on options</li>
                  <li>Everyone picks their availability</li>
                  <li>Book the time that works for most people</li>
                </ol>
              </div>
              <p class="mt-2 text-xs text-gray-500">
                Best for: When your group needs to coordinate schedules
              </p>
            </div>
          </div>
        </button>
      <% end %>

      <!-- Event Preview -->
      <%= if @public_event do %>
        <div class="mt-6 p-4 bg-gray-50 rounded-lg border border-gray-200">
          <h3 class="font-medium text-gray-900 mb-2">Event</h3>
          <p class="text-sm text-gray-700"><%= @public_event.title %></p>
          <%= if @public_event.venue do %>
            <p class="text-sm text-gray-600 mt-1"><%= @public_event.venue.name %></p>
          <% end %>
        </div>
      <% end %>

      <!-- Cancel button for consistency with other screens -->
      <div class="flex justify-end pt-4 border-t mt-6">
        <button
          type="button"
          phx-click={@on_close}
          class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end

  # Quick Plan Form (existing flow)
  defp render_quick_plan_form(assigns) do
    ~H"""
    <form phx-submit={@on_submit} phx-value-mode="quick" class="space-y-6">
      <!-- Historical Participants -->
      <.live_component
        module={HistoricalParticipantsComponent}
        id={@id <> "_historical"}
        organizer={@organizer}
        selected_users={@selected_users}
        exclude_event_ids={if @public_event, do: [@public_event.id], else: []}
        display_mode="list"
      />

      <!-- Unified Email Input -->
      <div class="border-t pt-6">
        <div class="mb-4">
          <h3 class="text-lg font-medium text-gray-900">Invite friends and contacts</h3>
          <p class="text-sm text-gray-500">Add email addresses to invite people to this event</p>
        </div>

        <.individual_email_input
          id="unified-email-input"
          emails={@selected_emails}
          current_input={@current_email_input}
          bulk_input={@bulk_email_input}
          on_add_email="add_email"
          on_remove_email="remove_email"
          on_input_change="email_input_change"
          placeholder="Enter email address"
        />
      </div>

      <!-- Selected Participants -->
      <div class="border-t pt-6">
        <.live_component
          module={SelectedParticipantsComponent}
          id={@id <> "_selected"}
          selected_users={@selected_users}
          selected_emails={@selected_emails}
        />
      </div>

      <!-- Invitation Message -->
      <div class="border-t pt-6">
        <.live_component
          module={InvitationMessageComponent}
          id={@id <> "_message"}
          invitation_message={@invitation_message}
        />
      </div>

      <!-- Time Selection (if occurrence selected) -->
      <%= if @selected_occurrence do %>
        <div class="border-t pt-6">
          <div class="p-4 bg-purple-50 border border-purple-200 rounded-lg">
            <div class="flex items-start justify-between gap-4">
              <div class="flex-1">
                <h3 class="font-medium text-gray-900 mb-2 flex items-center gap-2">
                  <svg
                    class="w-5 h-5 text-purple-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  Selected Showtime
                </h3>

                <!-- Theater/Venue -->
                <%= if Map.get(@selected_occurrence, :venue_name) do %>
                  <div class="mb-2">
                    <p class="text-xs text-gray-600 uppercase tracking-wide mb-0.5"><%= if @is_movie_event, do: "Theater", else: "Venue" %></p>
                    <p class="text-sm text-gray-900 font-semibold">
                      <%= @selected_occurrence.venue_name %>
                    </p>
                  </div>
                <% end %>

                <!-- Date & Time -->
                <div>
                  <p class="text-xs text-gray-600 uppercase tracking-wide mb-0.5">Date & Time</p>
                  <p class="text-sm text-gray-900 font-semibold">
                    <%= format_occurrence_datetime_full(@selected_occurrence) %>
                  </p>
                </div>

                <p class="text-xs text-gray-500 mt-2 italic">
                  Your friends will be invited to this specific showtime
                </p>
              </div>
              <button
                type="button"
                phx-click="select_planning_mode"
                phx-value-mode="flexible_filters"
                class="px-3 py-1.5 text-sm text-purple-700 bg-white border border-purple-300 rounded-md hover:bg-purple-50 flex-shrink-0"
              >
                Change
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Actions -->
      <div class="flex justify-end gap-4 pt-4 border-t">
        <!-- Back/Cancel button - Phase 4: Consistent back navigation -->
        <%= cond do %>
          <% @is_single_occurrence -> %>
            <!-- Single-occurrence: just show Cancel to close modal -->
            <button
              type="button"
              phx-click={@on_close}
              class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
            >
              Cancel
            </button>
          <% @public_event || @movie -> %>
            <!-- Multi-showtime: allow going back to mode selection -->
            <button
              type="button"
              phx-click="select_planning_mode"
              phx-value-mode="selection"
              class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
            >
              Back to Mode Selection
            </button>
          <% true -> %>
            <!-- Fallback: just Cancel -->
            <button
              type="button"
              phx-click={@on_close}
              class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
            >
              Cancel
            </button>
        <% end %>
        <button
          type="submit"
          disabled={!has_participants?(assigns)}
          class={[
            "px-4 py-2 rounded-md",
            if(has_participants?(assigns),
              do: "text-white bg-green-600 hover:bg-green-700",
              else: "text-gray-400 bg-gray-100 cursor-not-allowed"
            )
          ]}
        >
          <%= if has_participants?(assigns) do %>
            Create Private Event & Send Invites (<%= participant_count(assigns) %>)
          <% else %>
            Select participants to continue
          <% end %>
        </button>
      </div>
    </form>
    """
  end

  # Adaptive Date Selection rendering based on number of available dates
  # Mode :no_dates - No dates with availability
  defp render_date_selection(%{date_mode: :no_dates} = assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-900 mb-2">
        Select Dates
      </label>
      <div class="p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
        <div class="flex items-center gap-2 text-yellow-800">
          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          <span class="text-sm font-medium">No available dates found</span>
        </div>
        <p class="mt-2 text-xs text-yellow-700">
          <%= if @is_venue_event do %>
            There are no scheduled time slots in the upcoming days.
          <% else %>
            There are no showtimes available in the upcoming days.
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  # Mode :single_day - Exactly 1 date with availability (auto-select it)
  defp render_date_selection(
         %{date_mode: :single_day, available_dates: [{date, count}]} = assigns
       ) do
    assigns = assign(assigns, :single_date, date)
    assigns = assign(assigns, :single_count, count)

    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-900 mb-2">
        Available Date
      </label>
      <div class="p-4 bg-purple-50 border border-purple-200 rounded-lg">
        <!-- Hidden input to auto-select the single date -->
        <input type="hidden" name="selected_dates[]" value={Date.to_iso8601(@single_date)} />
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="flex-shrink-0 w-12 h-12 bg-purple-600 text-white rounded-lg flex flex-col items-center justify-center">
              <span class="text-xs font-medium uppercase"><%= Calendar.strftime(@single_date, "%b") %></span>
              <span class="text-lg font-bold"><%= Calendar.strftime(@single_date, "%d") %></span>
            </div>
            <div>
              <div class="font-medium text-gray-900">
                <%= Calendar.strftime(@single_date, "%A, %B %d") %>
              </div>
              <div class="text-sm text-gray-600">
                <%= @single_count %> <%= if @is_venue_event, do: "time slot", else: "showtime" %><%= if @single_count > 1, do: "s", else: "" %> available
              </div>
            </div>
          </div>
          <div class="flex items-center gap-1 text-purple-600">
            <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
            </svg>
            <span class="text-sm font-medium">Auto-selected</span>
          </div>
        </div>
      </div>
      <p class="mt-1 text-xs text-gray-500">
        Only one date is available, so it's been automatically selected for you.
      </p>
    </div>
    """
  end

  # Mode :simple_list - 2-5 dates with availability (simple buttons)
  defp render_date_selection(
         %{date_mode: :simple_list, available_dates: available_dates} = assigns
       ) do
    assigns = assign(assigns, :available_dates_list, available_dates)

    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-900 mb-2">
        Select Dates
      </label>
      <div class="space-y-2">
        <%= for {date, count} <- @available_dates_list do %>
          <label class="flex items-center p-3 border border-gray-300 rounded-lg cursor-pointer hover:bg-gray-50 hover:border-purple-300 transition-colors">
            <input
              type="checkbox"
              name="selected_dates[]"
              value={Date.to_iso8601(date)}
              checked={Date.to_iso8601(date) in Map.get(@filter_criteria, :selected_dates, [])}
              class="h-5 w-5 text-purple-600 focus:ring-purple-500 border-gray-300 rounded"
            />
            <div class="ml-3 flex-1 flex items-center justify-between">
              <div class="flex items-center gap-3">
                <div class="flex-shrink-0 w-10 h-10 bg-gray-100 rounded-lg flex flex-col items-center justify-center">
                  <span class="text-xs font-medium text-gray-500 uppercase"><%= Calendar.strftime(date, "%b") %></span>
                  <span class="text-sm font-bold text-gray-900"><%= Calendar.strftime(date, "%d") %></span>
                </div>
                <div>
                  <div class="font-medium text-gray-900">
                    <%= Calendar.strftime(date, "%A") %>
                  </div>
                  <div class="text-sm text-gray-500">
                    <%= Calendar.strftime(date, "%B %d, %Y") %>
                  </div>
                </div>
              </div>
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                <%= count %> <%= if @is_venue_event, do: "slot", else: "time" %><%= if count > 1, do: "s", else: "" %>
              </span>
            </div>
          </label>
        <% end %>
      </div>
      <p class="mt-2 text-xs text-gray-500">
        <%= if @is_venue_event do %>
          Select one or more dates to see available time slots
        <% else %>
          Select one or more dates to see available showtimes
        <% end %>
      </p>
    </div>
    """
  end

  # Mode :date_grid - 6+ dates (full grid view, original UI)
  defp render_date_selection(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-900 mb-2">
        Select Dates
      </label>
      <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2">
        <%= for date <- generate_date_options(@is_venue_event) do %>
          <%
            availability_count = Map.get(@date_availability, date, 0)
            has_availability = availability_count > 0
            label_class = if has_availability do
              "flex items-center p-3 border border-gray-300 rounded-md cursor-pointer hover:bg-gray-50"
            else
              "flex items-center p-3 border border-gray-200 rounded-md cursor-not-allowed bg-gray-50 opacity-60"
            end
          %>
          <label class={label_class}>
            <input
              type="checkbox"
              name="selected_dates[]"
              value={Date.to_iso8601(date)}
              checked={Date.to_iso8601(date) in Map.get(@filter_criteria, :selected_dates, [])}
              disabled={!has_availability}
              class="h-4 w-4 text-purple-600 focus:ring-purple-500 border-gray-300 rounded disabled:opacity-50 disabled:cursor-not-allowed"
            />
            <span class="ml-2 flex-1 text-sm text-gray-700">
              <div class="font-medium flex items-center justify-between">
                <span><%= Calendar.strftime(date, "%a") %></span>
                <%= if has_availability do %>
                  <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800">
                    <%= availability_count %>
                  </span>
                <% else %>
                  <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-500">
                    0
                  </span>
                <% end %>
              </div>
              <div class="text-xs text-gray-500"><%= Calendar.strftime(date, "%b %d") %></div>
            </span>
          </label>
        <% end %>
      </div>
      <p class="mt-1 text-xs text-gray-500">
        <%= if @is_venue_event do %>
          Select one or more dates to see available time slots
        <% else %>
          Select one or more dates to see available showtimes
        <% end %>
      </p>
    </div>
    """
  end

  # Filter Selection Form (for flexible planning)
  defp render_filter_selection(assigns) do
    # Determine adaptive date selection mode
    {date_mode, available_dates} = determine_date_selection_mode(assigns.date_availability)
    assigns = assign(assigns, :date_mode, date_mode)
    assigns = assign(assigns, :available_dates, available_dates)

    ~H"""
    <form phx-submit="apply_flexible_filters" phx-change="preview_filter_results" class="space-y-6">
      <!-- Venue Scope Selector (for movie events accessed from specific venue) -->
      <!-- Improved UX: Prominent button switcher instead of checkbox toggle -->
      <!-- See: https://github.com/razrfly/eventasaurus/issues/3258 -->
      <%= if @is_movie_event && @public_event && @public_event.venue && @movie do %>
        <div class="space-y-3">
          <!-- Breadcrumb showing current venue context -->
          <div class="flex items-center gap-2 text-sm text-gray-600">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            <span>
              Viewing from: <span class="font-medium text-gray-900"><%= @public_event.venue.name %></span>
            </span>
          </div>

          <!-- Prominent venue scope buttons -->
          <div class="grid grid-cols-2 gap-2">
            <button
              type="button"
              phx-click="toggle_venue_scope"
              phx-value-scope="single"
              class={[
                "flex flex-col items-center gap-1 p-3 rounded-lg border-2 transition-all",
                if(!@include_all_venues,
                  do: "border-purple-600 bg-purple-50 text-purple-700",
                  else: "border-gray-200 bg-white text-gray-600 hover:border-gray-300"
                )
              ]}
            >
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
              </svg>
              <span class="text-sm font-medium">This Venue</span>
              <span class="text-xs opacity-75"><%= @public_event.venue.name %></span>
            </button>
            <button
              type="button"
              phx-click="toggle_venue_scope"
              phx-value-scope="all"
              class={[
                "flex flex-col items-center gap-1 p-3 rounded-lg border-2 transition-all",
                if(@include_all_venues,
                  do: "border-purple-600 bg-purple-50 text-purple-700",
                  else: "border-gray-200 bg-white text-gray-600 hover:border-gray-300"
                )
              ]}
            >
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span class="text-sm font-medium">All Venues</span>
              <span class="text-xs opacity-75"><%= @city && @city.name || "This city" %></span>
            </button>
          </div>

          <!-- Hint about current selection -->
          <p class="text-xs text-gray-500 text-center">
            <%= if @include_all_venues do %>
              Showing all theaters in <%= @city && @city.name || "this city" %> showing <%= @movie.title %>
            <% else %>
              Showing only showtimes at <%= @public_event.venue.name %>
            <% end %>
          </p>
        </div>
      <% end %>

      <!-- Date Selection (Adaptive UI based on available dates) -->
      <%= render_date_selection(assigns) %>

      <!-- Time Preferences (data-driven based on available showtimes) -->
      <%
        # Compute available time periods from the availability data
        # Only show periods that have at least one showtime
        all_time_periods = [
          {"Morning", "morning"},
          {"Afternoon", "afternoon"},
          {"Evening", "evening"},
          {"Late Night", "late_night"}
        ]

        available_time_periods =
          Enum.filter(all_time_periods, fn {_label, value} ->
            count = Map.get(@time_period_availability, value, 0)
            count > 0
          end)

        # Only show the time filter if there are at least 2 different time periods available
        # If there's only 1 (or 0), the filter isn't useful
        show_time_filter = length(available_time_periods) >= 2
      %>
      <%= if show_time_filter do %>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-2">
            Preferred Times
          </label>
          <div class={[
            "grid gap-3",
            case length(available_time_periods) do
              2 -> "grid-cols-2"
              3 -> "grid-cols-3"
              _ -> "grid-cols-2 sm:grid-cols-4"
            end
          ]}>
            <%= for {time_label, time_value} <- available_time_periods do %>
              <% count = Map.get(@time_period_availability, time_value, 0) %>
              <label class="flex items-center p-3 border border-gray-300 rounded-md cursor-pointer hover:bg-gray-50">
                <input
                  type="checkbox"
                  name="time_preferences[]"
                  value={time_value}
                  checked={time_value in Map.get(@filter_criteria, :time_preferences, [])}
                  class="h-4 w-4 text-purple-600 focus:ring-purple-500 border-gray-300 rounded"
                />
                <span class="ml-2 text-sm text-gray-700">
                  <%= time_label %>
                  <span class="text-gray-400 text-xs">(<%= count %>)</span>
                </span>
              </label>
            <% end %>
          </div>
          <p class="mt-1 text-xs text-gray-500">
            Select one or more time slots (leave empty for all times)
          </p>
        </div>
      <% end %>

      <!-- Advanced Options (Collapsed) -->
      <details class="border border-gray-200 rounded-md">
        <summary class="px-4 py-2 cursor-pointer text-sm font-medium text-gray-700 hover:bg-gray-50">
          Advanced Options
        </summary>
        <div class="p-4 border-t">
          <label class="block text-sm font-medium text-gray-900 mb-2">
            Maximum Options
          </label>
          <input
            type="number"
            name="limit"
            value={Map.get(@filter_criteria, :limit, 10)}
            min="3"
            max="20"
            class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-purple-500 focus:border-purple-500"
          />
          <p class="mt-1 text-xs text-gray-500">
            Limit the number of options shown (3-20)
          </p>
        </div>
      </details>

      <!-- Filter Preview Count - only show when user has selected filters -->
      <%
        # Check for date selections and time preferences
        has_selected_filters = Enum.any?(Map.get(@filter_criteria, :selected_dates, [])) ||
                               Enum.any?(Map.get(@filter_criteria, :time_preferences, []))
        # Get limit for truncation warning
        current_limit = Map.get(@filter_criteria, :limit, 10)
        will_be_truncated = @filter_preview_count != nil and @filter_preview_count > current_limit
      %>
      <%= if @filter_preview_count != nil and has_selected_filters do %>
        <div class={[
          "p-4 rounded-lg border",
          if(@filter_preview_count > 0,
            do: "bg-green-50 border-green-200",
            else: "bg-yellow-50 border-yellow-200"
          )
        ]}>
          <%= if @filter_preview_count > 0 do %>
            <div class="flex items-center gap-2">
              <svg class="h-5 w-5 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <div>
                <p class="text-sm font-medium text-green-800">
                  <%= @filter_preview_count %> options available with your selected filters
                </p>
                <%= if will_be_truncated do %>
                  <p class="text-xs text-green-700 mt-1">
                    <span class="font-medium">Note:</span> Showing <%= current_limit %> of <%= @filter_preview_count %> options, distributed across your selected dates.
                    Adjust "Maximum Options" in Advanced Options to see more.
                  </p>
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="flex items-center gap-2">
              <svg class="h-5 w-5 text-yellow-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <div>
                <p class="text-sm font-medium text-yellow-800">
                  No options match your selected filters
                </p>
                <p class="text-xs text-yellow-700 mt-1">
                  Try selecting different dates or times to find availability
                </p>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Actions -->
      <div class="flex justify-end gap-4 pt-4 border-t">
        <!-- Back/Cancel button - Phase 4: Consistent back navigation -->
        <%= cond do %>
          <% @public_event || @movie -> %>
            <!-- Has context: allow going back to mode selection -->
            <button
              type="button"
              phx-click="select_planning_mode"
              phx-value-mode="selection"
              class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
            >
              Back to Mode Selection
            </button>
          <% true -> %>
            <!-- Fallback: just Cancel -->
            <button
              type="button"
              phx-click={@on_close}
              class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
            >
              Cancel
            </button>
        <% end %>
        <button
          type="submit"
          class="px-4 py-2 text-white bg-purple-600 rounded-md hover:bg-purple-700"
        >
          Find Available Times
        </button>
      </div>
    </form>
    """
  end

  # Flexible Review Form (occurrences + friend selector)
  defp render_flexible_review_form(assigns) do
    ~H"""
    <form phx-submit={@on_submit} phx-value-mode="flexible" class="space-y-6">
      <!-- Movie/Event Context -->
      <%= if @is_movie_event && @public_event do %>
        <div class="p-4 bg-gradient-to-r from-purple-50 to-blue-50 rounded-lg border border-purple-200">
          <div class="flex items-start gap-3">
            <div class="flex-shrink-0">
              <svg class="w-8 h-8 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 12h18M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
              </svg>
            </div>
            <div class="flex-1">
              <h3 class="font-semibold text-gray-900 mb-1">Creating Poll For</h3>
              <p class="text-sm text-gray-700 font-medium"><%= @public_event.title %></p>
              <p class="text-xs text-gray-600 mt-2">
                Your friends will vote on which showtime works best for their schedule
              </p>
            </div>
          </div>
        </div>
      <% end %>

      <!-- How Polling Works -->
      <div class="p-4 bg-blue-50 rounded-lg border border-blue-200">
        <div class="flex items-start gap-3">
          <div class="flex-shrink-0">
            <svg class="w-5 h-5 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <div class="flex-1">
            <p class="text-sm font-medium text-blue-900 mb-1">How This Works</p>
            <p class="text-xs text-blue-800">
              After sending invites, each friend will see all <%= length(@matching_occurrences) %> showtime options below and mark which times work for them. You'll then see everyone's availability to pick the best time.
            </p>
          </div>
        </div>
      </div>

      <!-- Matching Occurrences -->
      <div>
        <h3 class="text-lg font-medium text-gray-900 mb-3">
          Showtime Options for Poll (<%= length(@matching_occurrences) %>)
        </h3>
        <%= if length(@matching_occurrences) > 0 do %>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <%= for {occurrence, index} <- Enum.with_index(@matching_occurrences) do %>
              <div class="p-3 bg-gray-50 rounded-lg border border-gray-200 hover:border-purple-300 hover:bg-purple-50 transition">
                <div class="flex flex-col gap-2">
                  <div class="flex items-start justify-between">
                    <p class="font-medium text-gray-900 text-sm">
                      <%= format_occurrence_title(occurrence, @is_movie_event) %>
                    </p>
                    <span class="text-xs text-purple-600 font-semibold flex-shrink-0 ml-2">Option <%= index + 1 %></span>
                  </div>
                  <p class="text-sm text-gray-600">
                    <%= format_occurrence_datetime_full(occurrence) %>
                  </p>
                </div>
              </div>
            <% end %>
          </div>
          <p class="mt-3 text-xs text-gray-500 italic">
            These options will be shown to your friends who can then vote on their availability
          </p>
        <% else %>
          <div class="p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
            <p class="text-sm text-yellow-800">
              No showtimes found matching your filters. Try adjusting your date range or time preferences.
            </p>
          </div>
        <% end %>
      </div>

      <!-- Historical Participants -->
      <div class="border-t pt-6">
        <.live_component
          module={HistoricalParticipantsComponent}
          id={@id <> "_historical"}
          organizer={@organizer}
          selected_users={@selected_users}
          exclude_event_ids={if @public_event, do: [@public_event.id], else: []}
          display_mode="list"
        />
      </div>

      <!-- Unified Email Input -->
      <div class="border-t pt-6">
        <div class="mb-4">
          <h3 class="text-lg font-medium text-gray-900">Invite friends to vote</h3>
          <p class="text-sm text-gray-500">Add email addresses to invite people to vote on showtimes</p>
        </div>

        <.individual_email_input
          id="unified-email-input-flexible"
          emails={@selected_emails}
          current_input={@current_email_input}
          bulk_input={@bulk_email_input}
          on_add_email="add_email"
          on_remove_email="remove_email"
          on_input_change="email_input_change"
          placeholder="Enter email address"
        />
      </div>

      <!-- Selected Participants -->
      <div class="border-t pt-6">
        <.live_component
          module={SelectedParticipantsComponent}
          id={@id <> "_selected"}
          selected_users={@selected_users}
          selected_emails={@selected_emails}
        />
      </div>

      <!-- Invitation Message -->
      <div class="border-t pt-6">
        <.live_component
          module={InvitationMessageComponent}
          id={@id <> "_message"}
          invitation_message={@invitation_message}
        />
      </div>

      <!-- Actions -->
      <div class="flex justify-end gap-4 pt-4 border-t">
        <button
          type="button"
          phx-click="select_planning_mode"
          phx-value-mode="flexible_filters"
          class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
        >
          Back to Filters
        </button>
        <button
          type="submit"
          disabled={!has_participants?(assigns) or length(@matching_occurrences) == 0}
          class={[
            "px-4 py-2 rounded-md",
            if(has_participants?(assigns) and length(@matching_occurrences) > 0,
              do: "text-white bg-purple-600 hover:bg-purple-700",
              else: "text-gray-400 bg-gray-100 cursor-not-allowed"
            )
          ]}
        >
          <%= cond do %>
            <% length(@matching_occurrences) == 0 -> %> No Showtimes Available
            <% !has_participants?(assigns) -> %> Select participants to continue
            <% true -> %> Create Poll & Send Invites (<%= participant_count(assigns) %>)
          <% end %>
        </button>
      </div>
    </form>
    """
  end

  # Helper functions

  defp has_participants?(assigns) do
    user_count = length(assigns[:selected_users] || [])
    email_count = length(assigns[:selected_emails] || [])
    user_count + email_count > 0
  end

  defp participant_count(assigns) do
    length(assigns[:selected_users] || []) + length(assigns[:selected_emails] || [])
  end

  # When viewing a specific movie's page, show only venue names (movie title is redundant)
  defp format_occurrence_title(%{movie_title: _movie_title, venue_name: venue_name}, true)
       when not is_nil(venue_name) do
    venue_name
  end

  # When not viewing a specific movie (discovery mode), show full "Movie @ Venue" format
  defp format_occurrence_title(
         %{movie_title: movie_title, venue_name: venue_name},
         _is_movie_event
       )
       when not is_nil(movie_title) and not is_nil(venue_name) do
    "#{movie_title} @ #{venue_name}"
  end

  defp format_occurrence_title(%{movie_title: movie_title}, _is_movie_event)
       when not is_nil(movie_title) do
    movie_title
  end

  defp format_occurrence_title(%{venue_name: venue_name}, _is_movie_event)
       when not is_nil(venue_name) do
    venue_name
  end

  defp format_occurrence_title(_, _is_movie_event), do: "Showtime"

  defp format_occurrence_datetime_full(%{datetime: datetime}) when not is_nil(datetime) do
    format_datetime_value(datetime)
  end

  # Handle occurrences that use starts_at instead of datetime
  defp format_occurrence_datetime_full(%{starts_at: starts_at}) when not is_nil(starts_at) do
    format_datetime_value(starts_at)
  end

  defp format_occurrence_datetime_full(_), do: "Time TBD"

  # Helper to parse and format datetime values
  defp format_datetime_value(datetime) do
    parsed_datetime =
      case datetime do
        %DateTime{} = dt ->
          dt

        str when is_binary(str) ->
          case DateTime.from_iso8601(str) do
            {:ok, dt, _offset} -> dt
            _ -> DateTime.utc_now()
          end

        _ ->
          DateTime.utc_now()
      end

    date_part = Calendar.strftime(parsed_datetime, "%A, %B %d")
    time_part = TimeUtils.format_time(parsed_datetime)
    "#{date_part} at #{time_part}"
  end

  # Generate list of dates for selection (7 days for movies, 14 for venues)
  defp generate_date_options(is_venue_event) do
    days = if is_venue_event, do: 14, else: 7
    today = Date.utc_today()

    Enum.map(0..(days - 1), fn offset ->
      Date.add(today, offset)
    end)
  end

  # Determine the appropriate UI mode for date selection based on available dates
  # Returns:
  #   :no_dates - 0 days with availability (show message)
  #   :single_day - 1 day with availability (auto-select and skip to time)
  #   :simple_list - 2-5 days with availability (show simple buttons)
  #   :date_grid - 6+ days with availability (show full grid)
  defp determine_date_selection_mode(date_availability) when is_map(date_availability) do
    dates_with_availability =
      date_availability
      |> Enum.filter(fn {_date, count} -> count > 0 end)
      |> Enum.map(fn {date, count} -> {date, count} end)
      |> Enum.sort_by(fn {date, _count} -> Date.to_iso8601(date) end)

    case length(dates_with_availability) do
      0 -> {:no_dates, []}
      1 -> {:single_day, dates_with_availability}
      n when n in 2..@simple_list_max_days -> {:simple_list, dates_with_availability}
      _ -> {:date_grid, dates_with_availability}
    end
  end

  defp determine_date_selection_mode(_), do: {:date_grid, []}

  # Get event image URL (cover_image_url or thumbnail_url)
  defp get_event_image(event) do
    cond do
      Map.has_key?(event, :cover_image_url) and event.cover_image_url ->
        event.cover_image_url

      Map.has_key?(event, :thumbnail_url) and event.thumbnail_url ->
        event.thumbnail_url

      true ->
        nil
    end
  end
end
