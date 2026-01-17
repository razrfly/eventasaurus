defmodule EventasaurusWeb.Components.Movies.ShowtimesByDay do
  @moduledoc """
  Component for displaying movie showtimes organized by day.

  Shows a horizontal day picker at the top with showtime counts per day,
  followed by chronologically sorted showtime cards for the selected day.

  ## Props

  - `showtimes_by_day` - Map of Date => list of showtime maps (required)
  - `available_days` - Sorted list of dates with showtimes (required)
  - `selected_day` - Currently selected Date (required)
  - `on_select_day` - Event name for day selection (default: "select_day")
  - `target` - Target for phx-click (optional, for LiveComponents)
  - `variant` - `:card` | `:dark` (default: `:card`)
  """

  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext
  use Phoenix.VerifiedRoutes, endpoint: EventasaurusWeb.Endpoint, router: EventasaurusWeb.Router

  attr :showtimes_by_day, :map, required: true
  attr :available_days, :list, required: true
  attr :selected_day, Date, required: true
  attr :on_select_day, :string, default: "select_day"
  attr :target, :any, default: nil
  attr :variant, :atom, default: :card

  def showtimes_by_day(assigns) do
    # Get showtimes for selected day
    selected_showtimes =
      Map.get(assigns.showtimes_by_day, assigns.selected_day, [])

    assigns = assign(assigns, :selected_showtimes, selected_showtimes)

    ~H"""
    <div class="space-y-6">
      <!-- Day Picker -->
      <.day_picker
        available_days={@available_days}
        selected_day={@selected_day}
        showtimes_by_day={@showtimes_by_day}
        on_select_day={@on_select_day}
        target={@target}
      />

      <!-- Showtimes for Selected Day -->
      <div>
        <%= if @selected_showtimes == [] do %>
          <.empty_day_state />
        <% else %>
          <div class="mb-4">
            <h3 class={day_header_classes(@variant)}>
              <Heroicons.clock class="w-5 h-5 inline mr-2 text-blue-500" />
              <%= format_day_header(@selected_day) %>
              <span class="text-sm font-normal text-gray-500 ml-2">
                (<%= ngettext("1 showtime", "%{count} showtimes", length(@selected_showtimes)) %>)
              </span>
            </h3>
          </div>

          <div class="space-y-3">
            <%= for showtime <- @selected_showtimes do %>
              <.showtime_card showtime={showtime} variant={@variant} />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Day Picker Component - horizontal scrolling day tabs
  defp day_picker(assigns) do
    ~H"""
    <div class="overflow-x-auto scrollbar-thin scrollbar-thumb-gray-300 scrollbar-track-gray-100">
      <div
        role="tablist"
        aria-label={gettext("Select day to view showtimes")}
        class="flex space-x-2 min-w-max pb-2"
      >
        <%= for day <- @available_days do %>
          <.day_tab
            date={day}
            selected={day == @selected_day}
            count={length(Map.get(@showtimes_by_day, day, []))}
            on_select_day={@on_select_day}
            target={@target}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # Individual day tab
  defp day_tab(assigns) do
    ~H"""
    <button
      type="button"
      role="tab"
      phx-click={@on_select_day}
      phx-value-date={Date.to_iso8601(@date)}
      phx-target={@target}
      class={[
        "flex flex-col items-center px-4 py-3 rounded-xl transition-all duration-200 min-w-[72px]",
        if(@selected,
          do: "bg-blue-600 text-white shadow-md",
          else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
        )
      ]}
      aria-selected={@selected}
      aria-label={format_day_label(@date, @count)}
    >
      <span class={[
        "text-xs font-medium uppercase",
        if(@selected, do: "text-blue-100", else: "text-gray-500")
      ]}>
        <%= format_day_abbr(@date) %>
      </span>
      <span class="text-lg font-bold">
        <%= @date.day %>
      </span>
      <span class={[
        "text-xs mt-1",
        if(@selected, do: "text-blue-200", else: "text-gray-400")
      ]}>
        <%= @count %> <%= if(@count == 1, do: gettext("show"), else: gettext("shows")) %>
      </span>
    </button>
    """
  end

  # Individual showtime card
  defp showtime_card(assigns) do
    # Defensive access for venue data - Map.get works on both maps and structs
    venue = assigns.showtime[:venue]

    assigns =
      assigns
      |> assign(:venue_name, (venue && Map.get(venue, :name)) || gettext("Unknown venue"))
      |> assign(:venue_address, venue && Map.get(venue, :address))

    ~H"""
    <.link
      navigate={~p"/activities/#{@showtime.slug}"}
      class={showtime_card_classes(@variant)}
    >
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-4">
          <!-- Time -->
          <div class="flex-shrink-0">
            <span class={time_display_classes(@variant)}>
              <%= format_time(@showtime.datetime) %>
            </span>
          </div>

          <!-- Venue Info -->
          <div class="min-w-0">
            <h4 class={venue_name_classes(@variant)}>
              <%= @venue_name %>
            </h4>
            <%= if @venue_address do %>
              <p class={venue_address_classes(@variant)}>
                <Heroicons.map_pin class="w-3 h-3 inline mr-1 flex-shrink-0" />
                <%= truncate_address(@venue_address, 40) %>
              </p>
            <% end %>
          </div>
        </div>

        <div class="flex items-center space-x-3">
          <!-- Format Badge -->
          <%= if @showtime.label do %>
            <span class={format_badge_classes(@variant)}>
              <%= extract_format(@showtime.label) %>
            </span>
          <% end %>

          <!-- Arrow -->
          <Heroicons.chevron_right class={arrow_classes(@variant)} />
        </div>
      </div>
    </.link>
    """
  end

  # Empty state when no showtimes for selected day
  defp empty_day_state(assigns) do
    ~H"""
    <div class="text-center py-8">
      <Heroicons.calendar_days class="w-12 h-12 text-gray-300 mx-auto mb-3" />
      <p class="text-gray-500">
        <%= gettext("No showtimes available for this day") %>
      </p>
    </div>
    """
  end

  # CSS Classes

  defp day_header_classes(:card), do: "text-lg font-semibold text-gray-900"
  defp day_header_classes(:dark), do: "text-lg font-semibold text-white"
  defp day_header_classes(_), do: day_header_classes(:card)

  defp showtime_card_classes(:card) do
    "block p-4 bg-white border border-gray-200 rounded-xl hover:border-blue-400 hover:shadow-md transition-all group"
  end

  defp showtime_card_classes(:dark) do
    "block p-4 bg-white/5 border border-white/10 rounded-xl hover:border-white/30 hover:bg-white/10 transition-all group"
  end

  defp showtime_card_classes(_), do: showtime_card_classes(:card)

  defp time_display_classes(:card) do
    "text-xl font-bold text-blue-600 group-hover:text-blue-700"
  end

  defp time_display_classes(:dark) do
    "text-xl font-bold text-blue-400 group-hover:text-blue-300"
  end

  defp time_display_classes(_), do: time_display_classes(:card)

  defp venue_name_classes(:card) do
    "font-semibold text-gray-900 group-hover:text-blue-600 transition-colors truncate"
  end

  defp venue_name_classes(:dark) do
    "font-semibold text-white group-hover:text-blue-400 transition-colors truncate"
  end

  defp venue_name_classes(_), do: venue_name_classes(:card)

  defp venue_address_classes(:card), do: "text-xs text-gray-500 truncate mt-0.5"
  defp venue_address_classes(:dark), do: "text-xs text-gray-400 truncate mt-0.5"
  defp venue_address_classes(_), do: venue_address_classes(:card)

  defp format_badge_classes(:card) do
    "px-2.5 py-1 bg-gray-100 text-gray-700 rounded-md text-xs font-semibold border border-gray-200"
  end

  defp format_badge_classes(:dark) do
    "px-2.5 py-1 bg-white/10 text-gray-300 rounded-md text-xs font-semibold border border-white/10"
  end

  defp format_badge_classes(_), do: format_badge_classes(:card)

  defp arrow_classes(:card), do: "w-5 h-5 text-gray-400 group-hover:text-blue-500 transition-colors"
  defp arrow_classes(:dark), do: "w-5 h-5 text-gray-500 group-hover:text-white transition-colors"
  defp arrow_classes(_), do: arrow_classes(:card)

  # Helper functions

  defp format_day_abbr(date) do
    Calendar.strftime(date, "%a")
  end

  # Accessible label for day tabs (e.g., "Saturday, January 18, 3 showtimes")
  defp format_day_label(date, count) do
    day_name = Calendar.strftime(date, "%A, %B %d")
    showtime_text = ngettext("1 showtime", "%{count} showtimes", count)
    "#{day_name}, #{showtime_text}"
  end

  defp format_day_header(date) do
    today = Date.utc_today()
    tomorrow = Date.add(today, 1)

    cond do
      date == today ->
        gettext("Today") <> ", " <> Calendar.strftime(date, "%B %d")

      date == tomorrow ->
        gettext("Tomorrow") <> ", " <> Calendar.strftime(date, "%B %d")

      true ->
        Calendar.strftime(date, "%A, %B %d")
    end
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  defp truncate_address(address, max_length) do
    if String.length(address) > max_length do
      String.slice(address, 0, max_length) <> "..."
    else
      address
    end
  end

  # Extract the primary format from a label like "IMAX 2D Napisy PL"
  defp extract_format(label) when is_binary(label) do
    label_lower = String.downcase(label)

    cond do
      String.contains?(label_lower, "imax") -> "IMAX"
      String.contains?(label_lower, "4dx") -> "4DX"
      String.contains?(label_lower, "3d") -> "3D"
      String.contains?(label_lower, "2d") -> "2D"
      true -> label
    end
  end

  defp extract_format(_), do: nil
end
