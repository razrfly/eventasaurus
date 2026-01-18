defmodule EventasaurusWeb.Components.Movies.ShowtimesByDay do
  @moduledoc """
  Component for displaying movie showtimes organized by day with venue grouping.

  Shows a horizontal day picker at the top with showtime counts per day,
  followed by venue cards containing time chips for the selected day.

  ## Props

  - `showtimes_by_day` - Map of Date => list of {venue, showtimes} tuples (required)
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
    # Get venues with showtimes for selected day
    # Data structure: [{venue, [showtimes]}, ...]
    venues_for_day =
      Map.get(assigns.showtimes_by_day, assigns.selected_day, [])

    # Count total showtimes for the day
    total_showtimes =
      venues_for_day
      |> Enum.reduce(0, fn {_venue, showtimes}, acc -> acc + length(showtimes) end)

    assigns =
      assigns
      |> assign(:venues_for_day, venues_for_day)
      |> assign(:total_showtimes, total_showtimes)

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

      <!-- Venues with Showtimes for Selected Day -->
      <div>
        <%= if @venues_for_day == [] do %>
          <.empty_day_state />
        <% else %>
          <div class="mb-4">
            <h3 class={day_header_classes(@variant)}>
              <Heroicons.clock class="w-5 h-5 inline mr-2 text-blue-500" />
              <%= format_day_header(@selected_day) %>
              <span class="text-sm font-normal text-gray-500 ml-2">
                (<%= ngettext("1 showtime", "%{count} showtimes", @total_showtimes) %>)
              </span>
            </h3>
          </div>

          <div class="space-y-4">
            <%= for {venue, showtimes} <- @venues_for_day do %>
              <.venue_card venue={venue} showtimes={showtimes} variant={@variant} selected_day={@selected_day} />
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
            count={count_showtimes_for_day(@showtimes_by_day, day)}
            on_select_day={@on_select_day}
            target={@target}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # Count total showtimes for a day (across all venues)
  defp count_showtimes_for_day(showtimes_by_day, day) do
    venues_for_day = Map.get(showtimes_by_day, day, [])

    Enum.reduce(venues_for_day, 0, fn {_venue, showtimes}, acc ->
      acc + length(showtimes)
    end)
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

  # Venue card with time chips
  defp venue_card(assigns) do
    venue = assigns.venue
    venue_name = (venue && Map.get(venue, :name)) || gettext("Unknown venue")
    venue_address = venue && Map.get(venue, :address)

    assigns =
      assigns
      |> assign(:venue_name, venue_name)
      |> assign(:venue_address, venue_address)

    ~H"""
    <div class={venue_card_classes(@variant)}>
      <!-- Venue Header -->
      <div class="mb-3">
        <h4 class={venue_name_classes(@variant)}>
          <Heroicons.building_storefront class="w-4 h-4 inline mr-2 text-blue-500" />
          <%= @venue_name %>
        </h4>
        <%= if @venue_address do %>
          <p class={venue_address_classes(@variant)}>
            <Heroicons.map_pin class="w-3 h-3 inline mr-1 flex-shrink-0" />
            <%= truncate_address(@venue_address, 50) %>
          </p>
        <% end %>
      </div>

      <!-- Time Chips -->
      <div class="flex flex-wrap gap-2">
        <%= for showtime <- @showtimes do %>
          <.time_chip showtime={showtime} variant={@variant} selected_day={@selected_day} />
        <% end %>
      </div>
    </div>
    """
  end

  # Individual time chip linking to the showtime
  # Includes the selected day in the URL path so the activity page shows the correct date
  # Also includes time as query param so activity page can pre-select the showtime
  defp time_chip(assigns) do
    # Build URL with date slug to preserve navigation context
    # Format: /activities/slug/jan-22?time=14:10 (using the activity page's date format)
    date_slug = date_to_url_slug(assigns.selected_day)
    time_param = format_time(assigns.showtime.datetime)
    url = ~p"/activities/#{assigns.showtime.slug}/#{date_slug}?time=#{time_param}"

    assigns = assign(assigns, :url, url)

    ~H"""
    <.link
      navigate={@url}
      class={time_chip_classes(@variant)}
    >
      <span class="font-bold"><%= format_time(@showtime.datetime) %></span>
      <%= if format = extract_format(@showtime.label) do %>
        <span class={time_chip_label_classes(@variant)}>
          <%= format %>
        </span>
      <% end %>
    </.link>
    """
  end

  # Convert date to URL slug format matching PublicEventShowLive
  defp date_to_url_slug(%Date{} = date) do
    month_abbr = Calendar.strftime(date, "%b") |> String.downcase()
    "#{month_abbr}-#{date.day}"
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

  defp venue_card_classes(:card) do
    "p-4 bg-white border border-gray-200 rounded-xl"
  end

  defp venue_card_classes(:dark) do
    "p-4 bg-white/5 border border-white/10 rounded-xl"
  end

  defp venue_card_classes(_), do: venue_card_classes(:card)

  defp venue_name_classes(:card) do
    "font-semibold text-gray-900"
  end

  defp venue_name_classes(:dark) do
    "font-semibold text-white"
  end

  defp venue_name_classes(_), do: venue_name_classes(:card)

  defp venue_address_classes(:card), do: "text-xs text-gray-500 mt-1"
  defp venue_address_classes(:dark), do: "text-xs text-gray-400 mt-1"
  defp venue_address_classes(_), do: venue_address_classes(:card)

  defp time_chip_classes(:card) do
    "inline-flex items-center gap-1.5 px-3 py-2 bg-blue-50 text-blue-700 rounded-lg hover:bg-blue-100 hover:text-blue-800 transition-colors text-sm border border-blue-200"
  end

  defp time_chip_classes(:dark) do
    "inline-flex items-center gap-1.5 px-3 py-2 bg-blue-900/30 text-blue-300 rounded-lg hover:bg-blue-900/50 hover:text-blue-200 transition-colors text-sm border border-blue-700/50"
  end

  defp time_chip_classes(_), do: time_chip_classes(:card)

  defp time_chip_label_classes(:card), do: "text-xs text-blue-500 font-medium"
  defp time_chip_label_classes(:dark), do: "text-xs text-blue-400 font-medium"
  defp time_chip_label_classes(_), do: time_chip_label_classes(:card)

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
  # Returns nil if no recognized format is found (we don't want to show
  # redundant venue/title info that's already visible in the context)
  defp extract_format(label) when is_binary(label) do
    label_lower = String.downcase(label)

    cond do
      String.contains?(label_lower, "imax") -> "IMAX"
      String.contains?(label_lower, "4dx") -> "4DX"
      String.contains?(label_lower, "3d") -> "3D"
      String.contains?(label_lower, "2d") -> "2D"
      true -> nil
    end
  end

  defp extract_format(_), do: nil
end
