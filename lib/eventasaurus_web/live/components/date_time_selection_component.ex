defmodule EventasaurusWeb.DateTimeSelectionComponent do
  @moduledoc """
  Date and time selection component for poll options.
  
  Handles date and time selection functionality including:
  - Calendar interface for date selection polls
  - Time selector dropdown for time polls  
  - Time slot configuration for date+time combinations
  - Date formatting and validation
  - Integration with calendar and time picker components
  
  ## Attributes:
  - poll: Poll struct (required)
  - selected_dates: List of selected dates
  - existing_dates: List of existing dates to show on calendar
  - time_enabled: Whether time selection is enabled
  - selected_date_for_time: Date currently being configured for time
  - date_time_slots: Map of date to time slots
  - changeset: Form changeset for validation
  
  ## Events:
  - calendar_date_selected: When a date is selected from calendar
  - toggle_time_selection: Toggle time selection on/off
  - configure_date_time: Configure time slots for a date
  - save_date_time_slots: Save time slot configuration
  - cancel_time_config: Cancel time configuration
  """

  use EventasaurusWeb, :live_component
  require Logger
  alias EventasaurusWeb.OptionSuggestionHelpers
  alias EventasaurusWeb.Utils.TimeUtils

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:selected_dates, fn -> [] end)
     |> assign_new(:existing_dates, fn -> [] end)
     |> assign_new(:time_enabled, fn -> false end)
     |> assign_new(:selected_date_for_time, fn -> nil end)
     |> assign_new(:date_time_slots, fn -> %{} end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="date-time-selection-component">
      <%= case @poll.poll_type do %>
        <% "time" -> %>
          <%= render_time_selector(assigns) %>
        <% "date_selection" -> %>
          <%= render_date_calendar(assigns) %>
        <% _ -> %>
          <!-- No date/time selection for this poll type -->
          <div></div>
      <% end %>
    </div>
    """
  end

  # Time selector for time polls
  defp render_time_selector(assigns) do
    ~H"""
    <div class="relative">
      <label for="option_title" class="block text-sm font-medium text-gray-700">
        Time <span class="text-red-500">*</span>
      </label>
      <select
        name="poll_option[title]"
        id="option_title"
        class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
        required
      >
        <option value="" disabled selected={Phoenix.HTML.Form.input_value(@changeset, :title) == ""}>Select a time...</option>
        <%= for time_option <- time_options() do %>
          <option value={time_option.value} selected={Phoenix.HTML.Form.input_value(@changeset, :title) == time_option.value}>
            <%= time_option.display %>
          </option>
        <% end %>
      </select>
      
      <!-- Time validation errors -->
      <%= if @changeset.errors[:title] do %>
        <div class="mt-1 text-sm text-red-600">
          <%= translate_error(@changeset.errors[:title]) %>
        </div>
      <% end %>
    </div>
    """
  end

  # Calendar interface for date selection polls  
  defp render_date_calendar(assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <label class="block text-sm font-medium text-gray-700">
          Select Date <span class="text-red-500">*</span>
        </label>
        <p class="text-sm text-gray-600 mb-4">
          Choose a date for people to vote on. You can add multiple dates by creating separate suggestions.
        </p>
      </div>

      <!-- Calendar Component -->
      <div>
        <.live_component
          module={EventasaurusWeb.CalendarComponent}
          id={"date-suggestion-calendar-#{@id}"}
          selected_dates={@selected_dates || []}
          existing_dates={@existing_dates || []}
          year={Date.utc_today().year}
          month={Date.utc_today().month}
          compact={false}
          allow_multiple={true}
          min_date={Date.utc_today()}
          on_date_select="calendar_date_selected"
          target={@myself}
        />
      </div>

      <!-- Time Selection Toggle -->
      <div class="bg-blue-50 rounded-lg p-4 border border-blue-200">
        <div class="flex items-center">
          <input
            id="time-enabled-toggle"
            type="checkbox"
            phx-click="toggle_time_selection"
            phx-target={@myself}
            checked={@time_enabled}
            class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
          />
          <label for="time-enabled-toggle" class="ml-2 flex items-center cursor-pointer">
            <span class="text-lg mr-2">⏰</span>
            <span class="text-sm font-medium text-gray-700">Specify times</span>
          </label>
        </div>

        <p class="text-sm text-gray-600">
          Optionally add specific time slots to your date suggestions
        </p>

        <!-- Time Configuration Interface -->
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

        <!-- Date Options with Time Display -->
        <%= if length(@selected_dates || []) > 0 do %>
          <div class="space-y-2">
            <%= for date <- (@selected_dates || []) do %>
              <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg transition-all duration-300 transform hover:scale-[1.02] hover:shadow-md">
                <div class="flex items-center space-x-3">
                  <div class="flex-shrink-0">
                    <div class="w-2 h-2 bg-indigo-600 rounded-full"></div>
                  </div>
                  <div>
                    <span class="text-sm font-medium text-gray-900">
                      <%= OptionSuggestionHelpers.format_date_for_display(date) %>
                    </span>
                    <%= if @time_enabled && Map.has_key?(@date_time_slots, Date.to_iso8601(date)) do %>
                      <div class="flex flex-wrap gap-1 mt-1">
                        <%= for time_slot <- Map.get(@date_time_slots, Date.to_iso8601(date), []) do %>
                          <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800">
                            <%= TimeUtils.format_time_12hour(time_slot["start_time"]) %> - <%= TimeUtils.format_time_12hour(time_slot["end_time"]) %>
                          </span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
                <%= if @time_enabled do %>
                  <button
                    type="button"
                    phx-click="configure_date_time"
                    phx-value-date={Date.to_iso8601(date)}
                    phx-target={@myself}
                    class="text-sm text-indigo-600 hover:text-indigo-800 font-medium"
                  >
                    <%= if Map.has_key?(@date_time_slots, Date.to_iso8601(date)) do %>
                      Edit times
                    <% else %>
                      Add times
                    <% end %>
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Hidden field to store the selected date as the option title -->
      <%= if length(@selected_dates || []) > 0 do %>
        <input
          type="hidden"
          name="poll_option[title]"
          value={OptionSuggestionHelpers.format_date_for_option_title(List.first(@selected_dates))}
        />
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("calendar_date_selected", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        # For suggestion form, we only allow one date at a time
        send(self(), {:date_selected, [date]})
        {:noreply, assign(socket, :selected_dates, [date])}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_time_selection", _params, socket) do
    enabled = !socket.assigns.time_enabled
    send(self(), {:time_selection_toggled, enabled})
    {:noreply, assign(socket, :time_enabled, enabled)}
  end

  @impl true
  def handle_event("configure_date_time", %{"date" => date_string}, socket) do
    send(self(), {:date_time_configure, date_string})
    {:noreply, assign(socket, :selected_date_for_time, date_string)}
  end

  @impl true
  def handle_event("save_date_time_slots", %{"date" => date_string, "time_slots" => time_slots}, socket) do
    updated_slots = Map.put(socket.assigns.date_time_slots, date_string, time_slots)
    send(self(), {:date_time_slots_saved, date_string, time_slots})
    {:noreply,
     socket
     |> assign(:date_time_slots, updated_slots)
     |> assign(:selected_date_for_time, nil)}
  end

  @impl true
  def handle_event("cancel_time_config", _params, socket) do
    send(self(), {:date_time_config_cancelled})
    {:noreply, assign(socket, :selected_date_for_time, nil)}
  end

  # Helper functions

  defp time_options() do
    # Start at 10:00 AM (10:00) and go through 11:30 PM (23:30)
    # 30-minute increments
    10..23
    |> Enum.flat_map(fn hour ->
      [
        %{display: format_time_12hour(hour, 0), value: format_time_24hour(hour, 0)},
        %{display: format_time_12hour(hour, 30), value: format_time_24hour(hour, 30)}
      ]
    end)
    |> Enum.filter(fn time ->
      # Filter out midnight (00:00) and very late times - stop at 11:30 PM
      !String.starts_with?(time.value, "00:") and time.value <= "23:30"
    end)
  end

  defp format_time_12hour(hour, minute) do
    suffix = if hour >= 12, do: "PM", else: "AM"
    display_hour = case hour do
      0 -> 12
      h when h > 12 -> h - 12
      h -> h
    end
    
    minute_str = if minute < 10, do: "0#{minute}", else: "#{minute}"
    "#{display_hour}:#{minute_str} #{suffix}"
  end

  defp format_time_24hour(hour, minute) do
    hour_str = if hour < 10, do: "0#{hour}", else: "#{hour}"
    minute_str = if minute < 10, do: "0#{minute}", else: "#{minute}"
    "#{hour_str}:#{minute_str}"
  end

end