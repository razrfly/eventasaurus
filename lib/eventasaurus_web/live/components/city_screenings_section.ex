defmodule EventasaurusWeb.Live.Components.CityScreeningsSection do
  @moduledoc """
  Reusable component for displaying movie screenings grouped by city/venue.

  This component shows available screenings for a movie in a specific city,
  with venues listed as cards showing showtimes, dates, and format information.

  Supports two view modes:
  - **By Venue** (default): Showtimes grouped by cinema
  - **By Day**: Showtimes organized chronologically with horizontal day picker

  ## Props

  - `city` - City struct with name and slug (required)
  - `venues_with_info` - List of {venue, info} tuples (required)
  - `total_showtimes` - Total number of showtimes across all venues
  - `variant` - `:card` | `:dark` (default: `:card`)
  - `compact` - Boolean for compact display mode (default: false)
  - `show_empty_state` - Boolean to show empty state message (default: true)

  ## View Mode Props (optional, enables toggle)

  - `view_mode` - Current mode: `:by_venue` or `:by_day` (default: nil, hides toggle)
  - `selected_day` - Currently selected Date for By Day view
  - `showtimes_by_day` - Map of Date => list of showtime maps
  - `available_days` - Sorted list of dates with showtimes
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusWeb.Components.Movies.{ViewModeToggle, ShowtimesByDay}

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:variant, fn -> :card end)
      |> assign_new(:compact, fn -> false end)
      |> assign_new(:show_empty_state, fn -> true end)
      |> assign_new(:total_showtimes, fn -> 0 end)
      |> assign_new(:venues_with_info, fn -> [] end)
      |> assign_new(:recently_missed_expanded, fn -> false end)
      # View mode toggle props (optional)
      |> assign_new(:view_mode, fn -> nil end)
      |> assign_new(:selected_day, fn -> nil end)
      |> assign_new(:showtimes_by_day, fn -> %{} end)
      |> assign_new(:available_days, fn -> [] end)

    # Separate venues into upcoming and recent-past-only groups
    venues_with_info = socket.assigns.venues_with_info

    {upcoming_venues, recent_past_only_venues} =
      Enum.split_with(venues_with_info, fn {_venue, info} ->
        Map.get(info, :upcoming_count, info.count) > 0
      end)

    # Count total upcoming showtimes (for header display)
    total_upcoming =
      upcoming_venues
      |> Enum.map(fn {_venue, info} -> Map.get(info, :upcoming_count, info.count) end)
      |> Enum.sum()

    # Check if all venues are recent-past-only (expand by default in this case)
    all_past_only = upcoming_venues == [] and recent_past_only_venues != []

    {:ok,
     socket
     |> assign(:upcoming_venues, upcoming_venues)
     |> assign(:recent_past_only_venues, recent_past_only_venues)
     |> assign(:total_upcoming, total_upcoming)
     |> assign(:recently_missed_expanded, all_past_only)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={section_container_classes(@variant)}>
      <%= if @venues_with_info == [] do %>
        <!-- Empty state when no venues at all -->
        <%= if @show_empty_state do %>
          <.empty_state city={@city} variant={@variant} />
        <% end %>
      <% else %>
        <!-- View Mode Toggle (only shown when view_mode is set) -->
        <%= if @view_mode do %>
          <div class="flex items-center justify-between mb-6">
            <h2 class={section_title_classes(@variant)}>
              <Heroicons.calendar class="w-6 h-6 inline mr-2 text-green-600" />
              <%= gettext("Showtimes") %>
              <span class={showtime_count_classes(@variant)}>
                (<%= ngettext("1 showtime", "%{count} showtimes", @total_upcoming) %>)
              </span>
            </h2>
            <ViewModeToggle.view_mode_toggle view_mode={@view_mode} />
          </div>
        <% end %>

        <!-- By Day View -->
        <%= if @view_mode == :by_day do %>
          <ShowtimesByDay.showtimes_by_day
            showtimes_by_day={@showtimes_by_day}
            available_days={@available_days}
            selected_day={@selected_day}
            variant={@variant}
          />
        <% else %>
          <!-- By Venue View (default) -->
          <!-- Upcoming Showtimes Section -->
          <%= if @upcoming_venues != [] do %>
            <div class="mb-8">
              <!-- Header only shown when no view toggle (legacy mode) -->
              <%= if is_nil(@view_mode) do %>
                <div class="flex items-center justify-between mb-6">
                  <h2 class={section_title_classes(@variant)}>
                    <Heroicons.calendar class="w-6 h-6 inline mr-2 text-green-600" />
                    <%= gettext("Upcoming Showtimes") %>
                    <span class={showtime_count_classes(@variant)}>
                      (<%= ngettext("1 showtime", "%{count} showtimes", @total_upcoming) %>)
                    </span>
                  </h2>
                </div>
              <% end %>

              <div class={venues_grid_classes(@compact)}>
                <%= for {venue, info} <- @upcoming_venues do %>
                  <.venue_card
                    venue={venue}
                    info={info}
                    variant={@variant}
                    compact={@compact}
                    show_recent_past_note={Map.get(info, :recent_past_count, 0) > 0}
                  />
                <% end %>
              </div>
            </div>
          <% end %>

        <!-- Recently Missed Section -->
        <%= if @recent_past_only_venues != [] do %>
          <div class="mt-8 pt-6 border-t border-gray-200">
            <!-- Collapsible Header -->
            <button
              type="button"
              phx-click="toggle_recently_missed"
              phx-target={@myself}
              class="w-full flex items-center justify-between text-left group"
              aria-expanded={@recently_missed_expanded}
            >
              <h3 class="text-lg font-semibold text-gray-500 group-hover:text-gray-700 transition-colors">
                <Heroicons.clock class="w-5 h-5 inline mr-2 text-gray-400" />
                <%= gettext("Recently Missed") %>
                <span class="text-sm font-normal text-gray-400 ml-2">
                  (<%= ngettext("1 venue", "%{count} venues", length(@recent_past_only_venues)) %>)
                </span>
              </h3>
              <span class={chevron_classes(@recently_missed_expanded)}>
                <Heroicons.chevron_down class="w-5 h-5" />
              </span>
            </button>

            <!-- Collapsible Content with smooth animation -->
            <div class={collapsible_content_classes(@recently_missed_expanded)}>
              <div class="overflow-hidden min-h-0">
                <div class="mt-4">
                  <p class="text-sm text-gray-500 mb-4 italic">
                    <%= gettext("These venues showed this film recently. Check back for future screenings!") %>
                  </p>
                  <div class={venues_grid_classes(@compact)}>
                    <%= for {venue, info} <- @recent_past_only_venues do %>
                      <.venue_card_past venue={venue} info={info} variant={@variant} />
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <!-- All Past - Expanded by Default Message -->
        <%= if @upcoming_venues == [] and @recent_past_only_venues != [] do %>
          <div class="mb-6 p-4 bg-amber-50 border border-amber-200 rounded-lg">
            <div class="flex items-start">
              <Heroicons.information_circle class="w-5 h-5 text-amber-600 mt-0.5 mr-3 flex-shrink-0" />
              <div>
                <p class="text-sm font-medium text-amber-800">
                  <%= gettext("No upcoming showtimes") %>
                </p>
                <p class="text-sm text-amber-700 mt-1">
                  <%= gettext("This film played recently at the venues below. We'll update this page when new showtimes are announced.") %>
                </p>
              </div>
            </div>
          </div>
        <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("toggle_recently_missed", _params, socket) do
    {:noreply, assign(socket, :recently_missed_expanded, !socket.assigns.recently_missed_expanded)}
  end

  # Private function components

  defp empty_state(assigns) do
    ~H"""
    <div class={empty_state_classes(@variant)}>
      <Heroicons.film class={empty_icon_classes(@variant)} />
      <p class={empty_text_classes(@variant)}>
        <%= gettext("No screenings found for this movie in %{city}", city: @city.name) %>
      </p>
    </div>
    """
  end

  defp venue_card(assigns) do
    assigns = assign_new(assigns, :show_recent_past_note, fn -> false end)

    ~H"""
    <.link
      navigate={~p"/activities/#{@info.slug}"}
      class={venue_card_classes(@variant)}
    >
      <div class="flex flex-col h-full justify-between">
        <div class="flex-1 min-w-0">
          <!-- Venue Name -->
          <h3 class={venue_name_classes(@variant)}>
            <%= @venue.name %>
          </h3>

          <!-- Address -->
          <%= if @venue.address do %>
            <p class={venue_address_classes(@variant)}>
              <Heroicons.map_pin class="w-3.5 h-3.5 inline mr-1 flex-shrink-0 -mt-0.5" />
              <%= @venue.address %>
            </p>
          <% end %>

          <!-- Divider -->
          <div class={divider_classes(@variant)}></div>

          <!-- Date range and showtime count -->
          <div class={date_info_classes(@variant)}>
            <Heroicons.calendar_days class="w-4 h-4 mr-2 flex-shrink-0 text-green-500" />
            <span class="font-medium text-sm">
              <%= @info.date_range %>
            </span>
            <span class="mx-2 text-gray-300">&bull;</span>
            <span class="text-sm text-gray-500">
              <%= ngettext("1 showtime", "%{count} showtimes", Map.get(@info, :upcoming_count, @info.count)) %>
            </span>
          </div>

          <!-- "Also played recently" note for venues with both upcoming and past -->
          <%= if @show_recent_past_note do %>
            <div class="mt-2 text-xs text-gray-400 italic">
              <Heroicons.clock class="w-3 h-3 inline mr-1" />
              <%= gettext("Also played recently") %>
            </div>
          <% end %>

          <!-- Format badges -->
          <%= if length(@info.formats) > 0 do %>
            <div class="flex flex-wrap gap-2 mt-3 mb-4">
              <%= for format <- @info.formats do %>
                <span class={format_badge_classes(@variant)}>
                  <%= format %>
                </span>
              <% end %>
            </div>
          <% else %>
             <div class="mb-4"></div>
          <% end %>

          <!-- Specific dates (if limited) - show upcoming dates only -->
          <%= if @info.dates && length(@info.dates) <= 7 do %>
            <div class={dates_list_classes(@variant)}>
              <%= @info.dates
                  |> Enum.take(3)
                  |> Enum.map(&format_date_label/1)
                  |> Enum.join(", ") %>
              <%= if length(@info.dates) > 3 do %>
                <span class={more_dates_classes(@variant)}>
                  <%= ngettext("+1 more", "+%{count} more", length(@info.dates) - 3) %>
                </span>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- CTA Button -->
        <div class={cta_container_classes(@variant)}>
          <span class={cta_button_classes(@variant)}>
            <%= gettext("View Showtimes") %>
            <Heroicons.arrow_right class="w-4 h-4 ml-1.5" />
          </span>
        </div>
      </div>
    </.link>
    """
  end

  # Venue card for recently missed (past-only) - dimmed styling
  defp venue_card_past(assigns) do
    ~H"""
    <.link
      navigate={~p"/activities/#{@info.slug}"}
      class={venue_card_past_classes(@variant)}
    >
      <div class="flex flex-col h-full justify-between">
        <div class="flex-1 min-w-0">
          <!-- Venue Name -->
          <h3 class="text-base font-semibold text-gray-500 mb-1 line-clamp-1 group-hover:text-gray-700 transition-colors">
            <%= @venue.name %>
          </h3>

          <!-- Address -->
          <%= if @venue.address do %>
            <p class="text-xs text-gray-400 mb-0 truncate">
              <Heroicons.map_pin class="w-3.5 h-3.5 inline mr-1 flex-shrink-0 -mt-0.5" />
              <%= @venue.address %>
            </p>
          <% end %>

          <!-- Divider -->
          <div class="w-full h-px bg-gray-100 my-3"></div>

          <!-- Past date info -->
          <div class="flex items-center text-gray-400">
            <Heroicons.clock class="w-4 h-4 mr-2 flex-shrink-0" />
            <span class="text-sm">
              <%= gettext("Played") %>
              <%= format_past_date_range(@info) %>
            </span>
          </div>

          <!-- Past showtime count -->
          <div class="mt-1 text-xs text-gray-400">
            <%= ngettext("1 showing", "%{count} showings", Map.get(@info, :recent_past_count, @info.count)) %>
          </div>
        </div>

        <!-- CTA Button - muted style -->
        <div class="mt-4 pt-3 border-t border-gray-100">
          <span class="w-full flex items-center justify-center px-4 py-2 bg-gray-50 text-gray-500 rounded-lg group-hover:bg-gray-100 group-hover:text-gray-700 transition-all font-medium text-sm">
            <%= gettext("View Details") %>
            <Heroicons.arrow_right class="w-4 h-4 ml-1.5" />
          </span>
        </div>
      </div>
    </.link>
    """
  end

  # CSS class helpers for variants

  defp section_container_classes(:card), do: "bg-white rounded-lg shadow-lg p-8"
  defp section_container_classes(:dark), do: "bg-gray-900/50 backdrop-blur-sm rounded-lg p-8"
  defp section_container_classes(_), do: section_container_classes(:card)

  defp section_title_classes(:card), do: "text-2xl font-bold text-gray-900"
  defp section_title_classes(:dark), do: "text-2xl font-bold text-white"
  defp section_title_classes(_), do: section_title_classes(:card)

  defp showtime_count_classes(:card), do: "text-lg font-normal text-gray-600"
  defp showtime_count_classes(:dark), do: "text-lg font-normal text-gray-400"
  defp showtime_count_classes(_), do: showtime_count_classes(:card)

  defp venues_grid_classes(true), do: "space-y-3"
  defp venues_grid_classes(false), do: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"

  # Collapsible animation classes using CSS grid technique for smooth height transitions
  defp collapsible_content_classes(true) do
    "grid grid-rows-[1fr] transition-all duration-300 ease-in-out opacity-100"
  end

  defp collapsible_content_classes(false) do
    "grid grid-rows-[0fr] transition-all duration-300 ease-in-out opacity-0 overflow-hidden"
  end

  # Chevron rotation animation classes
  defp chevron_classes(true) do
    "text-gray-400 group-hover:text-gray-600 transition-all duration-300 rotate-180"
  end

  defp chevron_classes(false) do
    "text-gray-400 group-hover:text-gray-600 transition-all duration-300 rotate-0"
  end

  defp venue_card_classes(:card) do
    "block h-full p-5 border border-gray-200 rounded-xl hover:border-blue-400 hover:shadow-md transition-all bg-white group"
  end

  defp venue_card_classes(:dark) do
    "block h-full p-5 bg-white/5 border border-white/10 rounded-xl hover:border-white/30 hover:bg-white/10 transition-all group"
  end

  defp venue_card_classes(_), do: venue_card_classes(:card)

  # Past venue card - dimmed, less prominent styling
  defp venue_card_past_classes(:card) do
    "block h-full p-5 border border-gray-200 rounded-xl hover:border-gray-300 hover:shadow-sm transition-all bg-gray-50/50 group opacity-75 hover:opacity-100"
  end

  defp venue_card_past_classes(:dark) do
    "block h-full p-5 bg-white/3 border border-white/5 rounded-xl hover:border-white/15 hover:bg-white/5 transition-all group opacity-60 hover:opacity-90"
  end

  defp venue_card_past_classes(_), do: venue_card_past_classes(:card)

  defp venue_name_classes(:card),
    do:
      "text-lg font-bold text-gray-900 mb-1 line-clamp-1 group-hover:text-blue-600 transition-colors"

  defp venue_name_classes(:dark),
    do:
      "text-lg font-bold text-white mb-1 line-clamp-1 group-hover:text-blue-400 transition-colors"

  defp venue_name_classes(_), do: venue_name_classes(:card)

  defp venue_address_classes(:card), do: "text-xs text-gray-500 mb-0 truncate"
  defp venue_address_classes(:dark), do: "text-xs text-gray-400 mb-0 truncate"
  defp venue_address_classes(_), do: venue_address_classes(:card)

  defp date_info_classes(:card), do: "flex items-center text-gray-700"
  defp date_info_classes(:dark), do: "flex items-center text-gray-300"
  defp date_info_classes(_), do: date_info_classes(:card)

  defp format_badge_classes(:card) do
    "px-2.5 py-1 bg-gray-100 text-gray-700 rounded-md text-xs font-semibold border border-gray-200"
  end

  defp format_badge_classes(:dark) do
    "px-2.5 py-1 bg-white/10 text-gray-300 rounded-md text-xs font-semibold border border-white/10"
  end

  defp format_badge_classes(_), do: format_badge_classes(:card)

  defp dates_list_classes(:card), do: "mt-2 text-xs text-gray-500"
  defp dates_list_classes(:dark), do: "mt-2 text-xs text-gray-400"
  defp dates_list_classes(_), do: dates_list_classes(:card)

  defp more_dates_classes(:card), do: "text-gray-400"
  defp more_dates_classes(:dark), do: "text-gray-500"
  defp more_dates_classes(_), do: more_dates_classes(:card)

  defp cta_button_classes(:card) do
    "w-full flex items-center justify-center px-4 py-2 bg-blue-50 text-blue-700 rounded-lg group-hover:bg-blue-600 group-hover:text-white transition-all font-semibold text-sm"
  end

  defp cta_button_classes(:dark) do
    "w-full flex items-center justify-center px-4 py-2 bg-white/10 text-white rounded-lg group-hover:bg-blue-500 transition-all font-semibold text-sm"
  end

  defp cta_button_classes(_), do: cta_button_classes(:card)

  defp cta_container_classes(:card), do: "mt-6 pt-4 border-t border-gray-100"
  defp cta_container_classes(:dark), do: "mt-6 pt-4 border-t border-white/10"
  defp cta_container_classes(_), do: cta_container_classes(:card)

  defp divider_classes(:card), do: "w-full h-px bg-gray-100 my-4"
  defp divider_classes(:dark), do: "w-full h-px bg-white/10 my-4"
  defp divider_classes(_), do: divider_classes(:card)

  defp empty_state_classes(:card), do: "text-center py-12"
  defp empty_state_classes(:dark), do: "text-center py-12"
  defp empty_state_classes(_), do: empty_state_classes(:card)

  defp empty_icon_classes(:card), do: "w-16 h-16 text-gray-400 mx-auto mb-4"
  defp empty_icon_classes(:dark), do: "w-16 h-16 text-gray-600 mx-auto mb-4"
  defp empty_icon_classes(_), do: empty_icon_classes(:card)

  defp empty_text_classes(:card), do: "text-gray-600 text-lg"
  defp empty_text_classes(:dark), do: "text-gray-400 text-lg"
  defp empty_text_classes(_), do: empty_text_classes(:card)

  # Helper functions

  defp format_date_label(date) do
    today = Date.utc_today()
    tomorrow = Date.add(today, 1)

    case date do
      ^today -> gettext("Today")
      ^tomorrow -> gettext("Tomorrow")
      _ -> format_date_short(date)
    end
  end

  defp format_date_short(date) do
    month_abbr = Calendar.strftime(date, "%b") |> String.capitalize()
    "#{month_abbr} #{date.day}"
  end

  # Format past date range for recently missed venues
  defp format_past_date_range(info) do
    # Use past_date_range if available, otherwise fallback to date_range
    case Map.get(info, :past_date_range) do
      nil ->
        # Fallback: use regular date_range if past_date_range not set
        Map.get(info, :date_range, "recently")

      range ->
        range
    end
  end
end
