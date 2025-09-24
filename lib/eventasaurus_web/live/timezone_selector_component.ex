defmodule EventasaurusWeb.TimezoneSelectorComponent do
  use EventasaurusWeb, :live_component

  @impl true
  def update(assigns, socket) do
    # Get the current timezone value from the form field or selected_timezone
    current_timezone = assigns[:selected_timezone] || ""

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:search_query, current_timezone)
     |> assign(:show_dropdown, false)
     |> assign(:filtered_timezones, get_grouped_timezones())}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    filtered = filter_timezones(query)

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:filtered_timezones, filtered)
     |> assign(:show_dropdown, true)}
  end

  @impl true
  def handle_event("select_timezone", %{"timezone" => timezone}, socket) do
    # Send the selected timezone back to the parent form
    send(self(), {:timezone_selected, timezone})

    {:noreply,
     socket
     |> assign(:show_dropdown, false)
     |> assign(:search_query, timezone)}
  end

  @impl true
  def handle_event("toggle_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_dropdown, !socket.assigns.show_dropdown)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative" phx-target={@myself}>

      <!-- Search input -->
      <div class="relative">
        <input
          type="text"
          id={@id <> "_search"}
          value={@search_query}
          phx-keyup="search"
          phx-click="toggle_dropdown"
          phx-target={@myself}
          phx-debounce="300"
          placeholder="Search or select timezone..."
          class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm pr-10"
          autocomplete="off"
        />
        <div class="absolute inset-y-0 right-0 flex items-center pr-3">
          <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>
      </div>

      <!-- Dropdown -->
      <%= if @show_dropdown do %>
        <div class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm">
          <!-- Common shortcuts -->
          <div class="px-3 py-2 bg-gray-50 border-b">
            <div class="text-xs font-medium text-gray-500 mb-2">COMMON TIMEZONES</div>
            <div class="grid grid-cols-2 gap-1">
              <%= for {label, tz} <- common_timezones() do %>
                <button
                  type="button"
                  phx-click="select_timezone"
                  phx-value-timezone={tz}
                  phx-target={@myself}
                  class="text-left px-2 py-1 text-xs hover:bg-indigo-50 hover:text-indigo-600 rounded transition-colors"
                >
                  <%= label %>
                </button>
              <% end %>
            </div>
          </div>

          <!-- Grouped timezones -->
          <%= for {region, timezones} <- @filtered_timezones do %>
            <%= if length(timezones) > 0 do %>
              <div class="px-3 py-1 bg-gray-50 border-b">
                <div class="text-xs font-medium text-gray-500"><%= region %></div>
              </div>
              <%= for tz <- timezones do %>
                <button
                  type="button"
                  phx-click="select_timezone"
                  phx-value-timezone={tz}
                  phx-target={@myself}
                  class="block w-full text-left px-3 py-2 text-sm hover:bg-indigo-50 hover:text-indigo-600 transition-colors flex justify-between items-center"
                >
                  <span><%= format_timezone_display(tz) %></span>
                  <span class="text-xs text-gray-400"><%= get_timezone_offset(tz) %></span>
                </button>
              <% end %>
            <% end %>
          <% end %>
        </div>
      <% end %>

      <!-- Current time display -->
      <%= if @search_query != "" do %>
        <div class="mt-2 text-xs text-gray-500 flex items-center">
          <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          Current time: <span id={@id <> "_current_time"} class="font-medium ml-1">--:--</span>
        </div>
      <% end %>
    </div>
    """
  end

  # Private functions

  defp common_timezones do
    [
      {"UTC", "UTC"},
      {"EST", "America/New_York"},
      {"PST", "America/Los_Angeles"},
      {"GMT", "Europe/London"},
      {"CET", "Europe/Paris"},
      {"JST", "Asia/Tokyo"}
    ]
  end

  defp get_grouped_timezones do
    [
      {"Americas",
       [
         "America/New_York",
         "America/Chicago",
         "America/Denver",
         "America/Los_Angeles",
         "America/Toronto",
         "America/Vancouver",
         "America/Mexico_City",
         "America/Sao_Paulo",
         "America/Argentina/Buenos_Aires"
       ]},
      {"Europe",
       [
         "Europe/London",
         "Europe/Paris",
         "Europe/Berlin",
         "Europe/Rome",
         "Europe/Madrid",
         "Europe/Amsterdam",
         "Europe/Stockholm",
         "Europe/Moscow"
       ]},
      {"Asia",
       [
         "Asia/Tokyo",
         "Asia/Seoul",
         "Asia/Shanghai",
         "Asia/Hong_Kong",
         "Asia/Singapore",
         "Asia/Mumbai",
         "Asia/Dubai",
         "Asia/Bangkok"
       ]},
      {"Pacific",
       [
         "Pacific/Auckland",
         "Australia/Sydney",
         "Australia/Melbourne",
         "Pacific/Honolulu",
         "Pacific/Fiji"
       ]},
      {"Other",
       [
         "UTC",
         "Africa/Cairo",
         "Africa/Johannesburg"
       ]}
    ]
  end

  defp filter_timezones(query) when query == "", do: get_grouped_timezones()

  defp filter_timezones(query) do
    query_lower = String.downcase(query)

    get_grouped_timezones()
    |> Enum.map(fn {region, timezones} ->
      filtered =
        Enum.filter(timezones, fn tz ->
          String.contains?(String.downcase(tz), query_lower) or
            String.contains?(String.downcase(format_timezone_display(tz)), query_lower)
        end)

      {region, filtered}
    end)
  end

  defp format_timezone_display(timezone) do
    timezone
    |> String.replace("_", " ")
    |> String.split("/")
    |> Enum.map(&String.replace(&1, "_", " "))
    |> Enum.join(" - ")
  end

  defp get_timezone_offset(timezone) do
    # This is a simplified offset calculation
    # In a real app, you might want to use a proper timezone library
    case timezone do
      "UTC" -> "UTC+0"
      "America/New_York" -> "UTC-5"
      "America/Chicago" -> "UTC-6"
      "America/Denver" -> "UTC-7"
      "America/Los_Angeles" -> "UTC-8"
      "Europe/London" -> "UTC+0"
      "Europe/Paris" -> "UTC+1"
      "Asia/Tokyo" -> "UTC+9"
      _ -> ""
    end
  end
end
