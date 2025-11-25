defmodule EventasaurusWeb.Components.PublicPlanWithFriendsModal do
  @moduledoc """
  Enhanced modal for creating private events from public events.
  Uses shared components and supports both user selection and email invitations.
  Does NOT include direct add functionality (invitation only).
  """
  use Phoenix.Component
  import EventasaurusWeb.Helpers.PublicEventDisplayHelpers

  alias EventasaurusWeb.Components.Invitations.{
    HistoricalParticipantsComponent,
    SelectedParticipantsComponent,
    InvitationMessageComponent
  }

  import EventasaurusWeb.Components.IndividualEmailInput

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :public_event, :map, required: true
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
          <div class="relative bg-white rounded-lg max-w-3xl w-full max-h-[90vh] overflow-hidden" phx-click-away={@on_close}>
            <!-- Header -->
            <div class="sticky top-0 bg-white border-b border-gray-200 px-6 py-4 z-10">
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
                      <% :quick -> %> Create a private event for '<%= @public_event.title %>' and invite your friends
                      <% :flexible_filters -> %> Select date range, times, and venues to find available options
                      <% :flexible_review -> %> Invite friends to vote on their preferred showtime
                    <% end %>
                  </p>
                </div>
                <button
                  type="button"
                  phx-click={@on_close}
                  class="text-gray-400 hover:text-gray-500"
                >
                  <span class="sr-only">Close</span>
                  <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>

            <!-- Form Content (Scrollable) -->
            <div class="overflow-y-auto max-h-[calc(90vh-140px)] px-6 py-4">
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

  # Mode Selection View
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
            <h3 class="text-lg font-bold text-gray-900">Quick Plan</h3>
            <p class="mt-1 text-sm text-gray-600">
              Pick the <%= if @selected_occurrence, do: "selected", else: "default" %> time and create your event right away
            </p>
            <p class="mt-2 text-xs text-gray-500">
              Best for: When you know which showtime works for everyone
            </p>
          </div>
        </div>
      </button>

      <!-- Flexible Plan Option -->
      <button
        type="button"
        phx-click="select_planning_mode"
        phx-value-mode="flexible"
        class="w-full p-6 border-2 border-gray-200 rounded-lg hover:border-purple-500 hover:bg-purple-50 transition text-left"
      >
        <div class="flex items-start">
          <div class="flex-shrink-0">
            <svg class="w-12 h-12 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
            </svg>
          </div>
          <div class="ml-4 flex-1">
            <h3 class="text-lg font-bold text-gray-900">Flexible Plan with Poll</h3>
            <p class="mt-1 text-sm text-gray-600">
              Let your friends vote on their preferred showtime from multiple options
            </p>
            <p class="mt-2 text-xs text-gray-500">
              Best for: When your group needs to coordinate schedules
            </p>
          </div>
        </div>
      </button>

      <!-- Event Preview -->
      <div class="mt-6 p-4 bg-gray-50 rounded-lg border border-gray-200">
        <h3 class="font-medium text-gray-900 mb-2">Event</h3>
        <p class="text-sm text-gray-700"><%= @public_event.title %></p>
        <%= if @public_event.venue do %>
          <p class="text-sm text-gray-600 mt-1"><%= @public_event.venue.name %></p>
        <% end %>
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
        exclude_event_ids={[@public_event.id]}
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
                <h3 class="font-medium text-gray-900 mb-1 flex items-center gap-2">
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
                  Selected Time
                </h3>
                <p class="text-sm text-gray-700 font-medium">
                  <%= format_occurrence_datetime(@selected_occurrence) %>
                </p>
                <p class="text-xs text-gray-500 mt-1">
                  You selected this time for the event
                </p>
              </div>
              <button
                type="button"
                phx-click="select_planning_mode"
                phx-value-mode="filter_selection"
                class="px-3 py-1.5 text-sm text-purple-700 bg-white border border-purple-300 rounded-md hover:bg-purple-50"
              >
                Change Time
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Event Details Preview -->
      <div class="border-t pt-6">
        <div class="p-4 bg-gray-50 rounded-lg">
          <h3 class="font-medium text-gray-900 mb-2">
            Event Details
          </h3>
          <p class="text-sm text-gray-600">
            <strong>Event:</strong> <%= @public_event.title %>
          </p>
          <p class="text-sm text-gray-600">
            <strong>Date:</strong>
            <%= if @selected_occurrence do %>
              <%= format_occurrence_datetime(@selected_occurrence) %>
            <% else %>
              <%= format_local_datetime(@public_event.starts_at, @public_event.venue, :full) %>
            <% end %>
          </p>
          <%= if @public_event.venue do %>
            <p class="text-sm text-gray-600">
              <strong>Location:</strong> <%= @public_event.venue.name %>
            </p>
          <% end %>
        </div>
      </div>

      <!-- Actions -->
      <div class="flex justify-end gap-4 pt-4 border-t">
        <button
          type="button"
          phx-click="select_planning_mode"
          phx-value-mode="selection"
          class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
        >
          Back
        </button>
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

  # Filter Selection Form (for flexible planning)
  defp render_filter_selection(assigns) do
    ~H"""
    <form phx-submit="apply_flexible_filters" class="space-y-6">
      <!-- Date Selection -->
      <div>
        <label class="block text-sm font-medium text-gray-900 mb-2">
          Select Dates
        </label>
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2">
          <%= for date <- generate_date_options(@is_venue_event) do %>
            <label class="flex items-center p-3 border border-gray-300 rounded-md cursor-pointer hover:bg-gray-50">
              <input
                type="checkbox"
                name="selected_dates[]"
                value={Date.to_iso8601(date)}
                checked={Date.to_iso8601(date) in Map.get(@filter_criteria, :selected_dates, [])}
                class="h-4 w-4 text-purple-600 focus:ring-purple-500 border-gray-300 rounded"
              />
              <span class="ml-2 text-sm text-gray-700">
                <div class="font-medium"><%= Calendar.strftime(date, "%a") %></div>
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

      <!-- Time Preferences (for movies) or Meal Periods (for venues) -->
      <%= if @is_movie_event do %>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-2">
            Preferred Times
          </label>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <%= for {time_label, time_value} <- [{"Morning", "morning"}, {"Afternoon", "afternoon"}, {"Evening", "evening"}, {"Late Night", "late_night"}] do %>
              <label class="flex items-center p-3 border border-gray-300 rounded-md cursor-pointer hover:bg-gray-50">
                <input
                  type="checkbox"
                  name="time_preferences[]"
                  value={time_value}
                  checked={time_value in Map.get(@filter_criteria, :time_preferences, [])}
                  class="h-4 w-4 text-purple-600 focus:ring-purple-500 border-gray-300 rounded"
                />
                <span class="ml-2 text-sm text-gray-700"><%= time_label %></span>
              </label>
            <% end %>
          </div>
          <p class="mt-1 text-xs text-gray-500">
            Select one or more time slots (leave empty for all times)
          </p>
        </div>
      <% end %>

      <%= if @is_venue_event do %>
        <div>
          <label class="block text-sm font-medium text-gray-900 mb-2">
            Meal Periods
          </label>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <%= for {period_label, period_value} <- [{"Breakfast", "breakfast"}, {"Lunch", "lunch"}, {"Dinner", "dinner"}, {"Brunch", "brunch"}, {"Late Night", "late_night"}] do %>
              <label class="flex items-center p-3 border border-gray-300 rounded-md cursor-pointer hover:bg-gray-50">
                <input
                  type="checkbox"
                  name="meal_periods[]"
                  value={period_value}
                  checked={period_value in Map.get(@filter_criteria, :meal_periods, [])}
                  class="h-4 w-4 text-purple-600 focus:ring-purple-500 border-gray-300 rounded"
                />
                <span class="ml-2 text-sm text-gray-700"><%= period_label %></span>
              </label>
            <% end %>
          </div>
          <p class="mt-1 text-xs text-gray-500">
            Select preferred dining times (leave empty for all periods)
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

      <!-- Actions -->
      <div class="flex justify-end gap-4 pt-4 border-t">
        <button
          type="button"
          phx-click="select_planning_mode"
          phx-value-mode="selection"
          class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
        >
          Back
        </button>
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
      <!-- Matching Occurrences -->
      <div>
        <h3 class="text-lg font-medium text-gray-900 mb-3">
          Available Showtimes (<%= length(@matching_occurrences) %>)
        </h3>
        <%= if length(@matching_occurrences) > 0 do %>
          <div class="space-y-2 max-h-64 overflow-y-auto">
            <%= for {occurrence, index} <- Enum.with_index(@matching_occurrences) do %>
              <div class="p-3 bg-gray-50 rounded-lg border border-gray-200">
                <div class="flex items-start justify-between">
                  <div>
                    <p class="font-medium text-gray-900">
                      <%= format_occurrence_title(occurrence, @is_movie_event) %>
                    </p>
                    <p class="text-sm text-gray-600 mt-1">
                      <%= format_occurrence_datetime_full(occurrence) %>
                    </p>
                  </div>
                  <span class="text-xs text-gray-500">Option <%= index + 1 %></span>
                </div>
              </div>
            <% end %>
          </div>
          <p class="mt-2 text-xs text-gray-500">
            Your friends will vote on which showtime works best for them
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
          exclude_event_ids={[@public_event.id]}
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

  defp format_occurrence_datetime(%{datetime: datetime}) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end

  defp format_occurrence_datetime(_), do: "TBD"

  # When viewing a specific movie's page, show only venue names (movie title is redundant)
  defp format_occurrence_title(%{movie_title: _movie_title, venue_name: venue_name}, true)
       when not is_nil(venue_name) do
    venue_name
  end

  # When not viewing a specific movie (discovery mode), show full "Movie @ Venue" format
  defp format_occurrence_title(%{movie_title: movie_title, venue_name: venue_name}, _is_movie_event)
       when not is_nil(movie_title) and not is_nil(venue_name) do
    "#{movie_title} @ #{venue_name}"
  end

  defp format_occurrence_title(%{movie_title: movie_title}, _is_movie_event) when not is_nil(movie_title) do
    movie_title
  end

  defp format_occurrence_title(%{venue_name: venue_name}, _is_movie_event) when not is_nil(venue_name) do
    venue_name
  end

  defp format_occurrence_title(_, _is_movie_event), do: "Showtime"

  defp format_occurrence_datetime_full(%{starts_at: starts_at}) when not is_nil(starts_at) do
    # Parse ISO8601 datetime if it's a string
    datetime =
      case starts_at do
        %DateTime{} -> starts_at
        str when is_binary(str) -> DateTime.from_iso8601(str) |> elem(1)
        _ -> DateTime.utc_now()
      end

    Calendar.strftime(datetime, "%A, %B %d at %I:%M %p")
  end

  defp format_occurrence_datetime_full(_), do: "Time TBD"

  # Generate list of dates for selection (7 days for movies, 14 for venues)
  defp generate_date_options(is_venue_event) do
    days = if is_venue_event, do: 14, else: 7
    today = Date.utc_today()

    Enum.map(0..(days - 1), fn offset ->
      Date.add(today, offset)
    end)
  end
end
