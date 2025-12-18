defmodule EventasaurusWeb.Live.Components.CityScreeningsSection do
  @moduledoc """
  Reusable component for displaying movie screenings grouped by city/venue.

  This component shows available screenings for a movie in a specific city,
  with venues listed as cards showing showtimes, dates, and format information.

  ## Props

  - `city` - City struct with name and slug (required)
  - `venues_with_info` - List of {venue, info} tuples (required)
  - `total_showtimes` - Total number of showtimes across all venues
  - `variant` - `:card` | `:dark` (default: `:card`)
  - `compact` - Boolean for compact display mode (default: false)
  - `show_empty_state` - Boolean to show empty state message (default: true)
  """

  use EventasaurusWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:variant, fn -> :card end)
     |> assign_new(:compact, fn -> false end)
     |> assign_new(:show_empty_state, fn -> true end)
     |> assign_new(:total_showtimes, fn -> 0 end)
     |> assign_new(:venues_with_info, fn -> [] end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={section_container_classes(@variant)}>
      <div class="flex items-center justify-between mb-6">
        <h2 class={section_title_classes(@variant)}>
          <%= gettext("Screenings in %{city}", city: @city.name) %>
          <span class={showtime_count_classes(@variant)}>
            (<%= ngettext("1 showtime", "%{count} showtimes", @total_showtimes) %>)
          </span>
        </h2>
      </div>

      <%= if @venues_with_info == [] do %>
        <%= if @show_empty_state do %>
          <.empty_state city={@city} variant={@variant} />
        <% end %>
      <% else %>
        <div class={venues_grid_classes(@compact)}>
          <%= for {venue, info} <- @venues_with_info do %>
            <.venue_card venue={venue} info={info} variant={@variant} compact={@compact} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
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
            <Heroicons.calendar_days class="w-4 h-4 mr-2 flex-shrink-0 text-gray-400" />
            <span class="font-medium text-sm">
              <%= @info.date_range %>
            </span>
            <span class="mx-2 text-gray-300">&bull;</span>
            <span class="text-sm text-gray-500">
              <%= ngettext("1 showtime", "%{count} showtimes", @info.count) %>
            </span>
          </div>

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

          <!-- Specific dates (if limited) -->
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

  defp venue_card_classes(:card) do
    "block h-full p-5 border border-gray-200 rounded-xl hover:border-blue-400 hover:shadow-md transition-all bg-white group"
  end

  defp venue_card_classes(:dark) do
    "block h-full p-5 bg-white/5 border border-white/10 rounded-xl hover:border-white/30 hover:bg-white/10 transition-all group"
  end

  defp venue_card_classes(_), do: venue_card_classes(:card)

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
end
