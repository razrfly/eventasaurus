defmodule EventasaurusWeb.CalendarComponent do
  @moduledoc """
  A reusable calendar component for selecting multiple non-continuous dates.

  Inspired by Rallly.co's calendar interface design (reference:
  https://private-user-images.githubusercontent.com/48241/453440100-5cd62673-2b7a-4d0e-908b-3b1e81e14cd6.png)

  This component allows users to click on calendar dates to select/deselect them
  for event date polling, replacing the traditional date range picker.
  """

  use Phoenix.LiveComponent

  @impl true
  def mount(socket) do
    today = Date.utc_today()

    socket =
      socket
      |> assign(:current_month, today)
      |> assign(:selected_dates, [])
      |> assign(:hover_date, nil)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Always use selected_dates from parent if provided, otherwise keep internal state
    selected_dates = case Map.get(assigns, :selected_dates) do
      nil -> Map.get(socket.assigns, :selected_dates, [])
      dates -> dates
    end

    socket =
      socket
      |> assign(assigns)
      |> assign(:selected_dates, selected_dates)

    {:ok, socket}
  end

    @impl true
  def handle_event("toggle_date", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        toggle_date_in_socket(socket, date)

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prev_month", _params, socket) do
    current_month = socket.assigns.current_month
    prev_month = Date.add(current_month, -Date.days_in_month(current_month))

    {:noreply, assign(socket, :current_month, prev_month)}
  end

  @impl true
  def handle_event("next_month", _params, socket) do
    current_month = socket.assigns.current_month
    next_month = Date.add(current_month, Date.days_in_month(current_month))

    {:noreply, assign(socket, :current_month, next_month)}
  end

  @impl true
  def handle_event("hover_date", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        {:noreply, assign(socket, :hover_date, date)}
      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("unhover_date", _params, socket) do
    {:noreply, assign(socket, :hover_date, nil)}
  end

  @impl true
  def handle_event("key_navigation", %{"key" => key, "date" => current_date_string}, socket) do
    case Date.from_iso8601(current_date_string) do
      {:ok, current_date} ->
        case key do
          "ArrowLeft" ->
            next_date = Date.add(current_date, -1)
            socket = push_event(socket, "focus_date", %{date: Date.to_iso8601(next_date)})
            {:noreply, socket}

          "ArrowRight" ->
            next_date = Date.add(current_date, 1)
            socket = push_event(socket, "focus_date", %{date: Date.to_iso8601(next_date)})
            {:noreply, socket}

          "ArrowUp" ->
            next_date = Date.add(current_date, -7)
            socket = push_event(socket, "focus_date", %{date: Date.to_iso8601(next_date)})
            {:noreply, socket}

          "ArrowDown" ->
            next_date = Date.add(current_date, 7)
            socket = push_event(socket, "focus_date", %{date: Date.to_iso8601(next_date)})
            {:noreply, socket}

          "Enter" ->
            # Toggle the current date directly
            toggle_date_in_socket(socket, current_date)

          "Space" ->
            # Toggle the current date directly
            toggle_date_in_socket(socket, current_date)

          _ ->
            {:noreply, socket}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="calendar-component bg-white border border-gray-200 rounded-lg shadow-sm" role="application" aria-label="Date picker calendar" phx-hook="CalendarKeyboardNav" id={"calendar-#{@id || "default"}"}>
      <!-- Calendar Header -->
      <div class="flex items-center justify-between px-3 py-3 sm:px-4 border-b border-gray-200">
        <button
          type="button"
          phx-click="prev_month"
          phx-target={@myself}
          class="p-2 rounded-md hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-blue-500 touch-manipulation"
          aria-label="Previous month"
          title="Previous month"
        >
          <svg class="w-4 h-4 sm:w-5 sm:h-5 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
        </button>

        <h3 class="text-base sm:text-lg font-semibold text-gray-900" id="calendar-month-year">
          <%= Calendar.strftime(@current_month, "%B %Y") %>
        </h3>

        <button
          type="button"
          phx-click="next_month"
          phx-target={@myself}
          class="p-2 rounded-md hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-blue-500 touch-manipulation"
          aria-label="Next month"
          title="Next month"
        >
          <svg class="w-4 h-4 sm:w-5 sm:h-5 text-gray-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
          </svg>
        </button>
      </div>

      <!-- Calendar Grid -->
      <div class="p-3 sm:p-4">
        <!-- Day headers -->
        <div class="grid grid-cols-7 gap-1 mb-2" role="row">
          <div class="text-center text-xs font-medium text-gray-500 py-2" role="columnheader" aria-label="Sunday">
            <span class="hidden sm:inline">Sun</span>
            <span class="sm:hidden">S</span>
          </div>
          <div class="text-center text-xs font-medium text-gray-500 py-2" role="columnheader" aria-label="Monday">
            <span class="hidden sm:inline">Mon</span>
            <span class="sm:hidden">M</span>
          </div>
          <div class="text-center text-xs font-medium text-gray-500 py-2" role="columnheader" aria-label="Tuesday">
            <span class="hidden sm:inline">Tue</span>
            <span class="sm:hidden">T</span>
          </div>
          <div class="text-center text-xs font-medium text-gray-500 py-2" role="columnheader" aria-label="Wednesday">
            <span class="hidden sm:inline">Wed</span>
            <span class="sm:hidden">W</span>
          </div>
          <div class="text-center text-xs font-medium text-gray-500 py-2" role="columnheader" aria-label="Thursday">
            <span class="hidden sm:inline">Thu</span>
            <span class="sm:hidden">T</span>
          </div>
          <div class="text-center text-xs font-medium text-gray-500 py-2" role="columnheader" aria-label="Friday">
            <span class="hidden sm:inline">Fri</span>
            <span class="sm:hidden">F</span>
          </div>
          <div class="text-center text-xs font-medium text-gray-500 py-2" role="columnheader" aria-label="Saturday">
            <span class="hidden sm:inline">Sat</span>
            <span class="sm:hidden">S</span>
          </div>
        </div>

        <!-- Calendar dates -->
        <div class="grid grid-cols-7 gap-1" role="grid" aria-labelledby="calendar-month-year">
          <%= for date <- calendar_dates(@current_month) do %>
            <.calendar_day
              date={date}
              current_month={@current_month}
              selected_dates={@selected_dates}
              hover_date={@hover_date}
              myself={@myself}
            />
          <% end %>
        </div>
      </div>

      <!-- Selected dates summary -->
      <%= if length(@selected_dates) > 0 do %>
        <div class="px-3 py-3 sm:px-4 border-t border-gray-200 bg-gray-50">
          <h4 class="text-sm font-medium text-gray-700 mb-2" role="status" aria-live="polite">
            Selected dates (<%= length(@selected_dates) %>):
          </h4>
          <div class="flex flex-wrap gap-1">
            <%= for date <- Enum.sort(@selected_dates, Date) do %>
              <span class="inline-flex items-center px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 rounded-md">
                <span class="hidden sm:inline"><%= Calendar.strftime(date, "%b %d") %></span>
                <span class="sm:hidden"><%= Calendar.strftime(date, "%m/%d") %></span>
                <button
                  type="button"
                  phx-click="toggle_date"
                  phx-target={@myself}
                  phx-value-date={Date.to_iso8601(date)}
                  class="ml-1 text-blue-600 hover:text-blue-800 focus:outline-none focus:ring-1 focus:ring-blue-500 focus:ring-offset-1 touch-manipulation"
                  aria-label={"Remove #{Calendar.strftime(date, "%B %d, %Y")} from selection"}
                  title={"Remove #{Calendar.strftime(date, "%B %d")}"}
                >
                  <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </span>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private component for individual calendar days
  defp calendar_day(assigns) do
    today = Date.utc_today()
    is_current_month = assigns.date.month == assigns.current_month.month
    is_selected = assigns.date in assigns.selected_dates
    is_today = assigns.date == today
    is_past = Date.compare(assigns.date, today) == :lt
    is_hovered = assigns.date == assigns.hover_date

    # Determine styling classes
    base_classes = "relative w-full h-8 sm:h-10 flex items-center justify-center text-xs sm:text-sm rounded-md transition-all duration-150 cursor-pointer touch-manipulation focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1"

    day_classes = cond do
      is_past and is_current_month ->
        "#{base_classes} text-gray-300 cursor-not-allowed"

      !is_current_month ->
        "#{base_classes} text-gray-300 cursor-not-allowed"

      is_selected ->
        "#{base_classes} bg-blue-600 text-white font-semibold shadow-sm hover:bg-blue-700 focus:bg-blue-700"

      is_today and is_current_month ->
        "#{base_classes} bg-blue-50 text-blue-600 font-semibold border border-blue-200 hover:bg-blue-100 focus:bg-blue-100"

      is_hovered and is_current_month and !is_past ->
        "#{base_classes} bg-gray-100 text-gray-900 font-medium"

      is_current_month ->
        "#{base_classes} text-gray-700 hover:bg-gray-100 hover:text-gray-900 focus:bg-gray-100"

      true ->
        "#{base_classes} text-gray-300 cursor-not-allowed"
    end

    assigns =
      assigns
      |> assign(:day_classes, day_classes)
      |> assign(:is_current_month, is_current_month)
      |> assign(:is_past, is_past)
      |> assign(:is_selected, is_selected)
      |> assign(:is_today, is_today)

    ~H"""
    <button
      type="button"
      class={@day_classes}
      disabled={!@is_current_month or @is_past}
      phx-click={if @is_current_month and !@is_past, do: "toggle_date"}
      phx-target={@myself}
      phx-value-date={Date.to_iso8601(@date)}
      phx-mouseenter={if @is_current_month and !@is_past, do: "hover_date"}
      phx-mouseleave={if @is_current_month and !@is_past, do: "unhover_date"}
      aria-label={"#{if @is_selected, do: "Deselect", else: "Select"} #{Calendar.strftime(@date, "%B %d, %Y")}"}
      aria-pressed={if @is_selected, do: "true", else: "false"}
      role="gridcell"
      tabindex={if @is_current_month and !@is_past, do: "0", else: "-1"}
      title={"#{Calendar.strftime(@date, "%B %d, %Y")}#{if @is_today, do: " (Today)", else: ""}#{if @is_selected, do: " - Selected", else: ""}"}
    >
      <span class="sr-only">
        <%= Calendar.strftime(@date, "%B %d, %Y") %>
        <%= if @is_today, do: " (Today)" %>
        <%= if @is_selected, do: " - Selected" %>
      </span>
      <span aria-hidden="true"><%= @date.day %></span>
      <%= if @is_today do %>
        <span class="absolute bottom-0.5 sm:bottom-1 left-1/2 transform -translate-x-1/2 w-1 h-1 bg-current rounded-full" aria-hidden="true"></span>
      <% end %>
    </button>
    """
  end

  # Helper function to generate calendar dates for the month view
  defp calendar_dates(date) do
    first_day = Date.beginning_of_month(date)
    last_day = Date.end_of_month(date)

    # Find the first Sunday of the calendar view
    start_date =
      case Date.day_of_week(first_day, :sunday) do
        1 -> first_day  # Already Sunday
        day_of_week -> Date.add(first_day, -(day_of_week - 1))
      end

    # Find the last Saturday of the calendar view
    end_date =
      case Date.day_of_week(last_day, :sunday) do
        7 -> last_day  # Already Saturday
        day_of_week -> Date.add(last_day, 7 - day_of_week)
      end

    # Generate the range of dates
    Date.range(start_date, end_date)
    |> Enum.to_list()
  end

  # Private helper function to toggle a date in the socket
  defp toggle_date_in_socket(socket, date) do
    selected_dates = socket.assigns.selected_dates

    updated_dates =
      if date in selected_dates do
        List.delete(selected_dates, date)
      else
        [date | selected_dates] |> Enum.sort()
      end

    socket =
      socket
      |> assign(:selected_dates, updated_dates)
      |> push_event("calendar_dates_changed", %{
        dates: Enum.map(updated_dates, &Date.to_iso8601/1),
        component_id: socket.assigns.id || "calendar"
      })

    # Send the updated dates to the parent LiveView
    send(self(), {:selected_dates_changed, updated_dates})

    {:noreply, socket}
  end
end
