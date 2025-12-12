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
      <div class="flex justify-between items-start">
        <div class="flex-1 min-w-0">
          <!-- Venue Name -->
          <h3 class={venue_name_classes(@variant)}>
            <%= @venue.name %>
          </h3>

          <!-- Address -->
          <%= if @venue.address do %>
            <p class={venue_address_classes(@variant)}>
              <Heroicons.map_pin class="w-4 h-4 inline mr-1 flex-shrink-0" />
              <%= @venue.address %>
            </p>
          <% end %>

          <!-- Date range and showtime count -->
          <div class={date_info_classes(@variant)}>
            <Heroicons.calendar_days class="w-5 h-5 mr-2 flex-shrink-0" />
            <span class="font-medium">
              <%= @info.date_range %> &bull; <%= ngettext("1 showtime", "%{count} showtimes", @info.count) %>
            </span>
          </div>

          <!-- Format badges -->
          <%= if length(@info.formats) > 0 do %>
            <div class="flex flex-wrap gap-2 mt-2">
              <%= for format <- @info.formats do %>
                <span class={format_badge_classes(@variant)}>
                  <%= format %>
                </span>
              <% end %>
            </div>
          <% end %>

          <!-- Specific dates (if limited) -->
          <%= if @info.dates && length(@info.dates) <= 7 do %>
            <div class={dates_list_classes(@variant)}>
              <%= @info.dates
                  |> Enum.take(4)
                  |> Enum.map(&format_date_label/1)
                  |> Enum.join(", ") %>
              <%= if length(@info.dates) > 4 do %>
                <span class={more_dates_classes(@variant)}>
                  +<%= length(@info.dates) - 4 %> more
                </span>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- CTA Button -->
        <div class="ml-4 flex-shrink-0">
          <span class={cta_button_classes(@variant)}>
            <%= gettext("View Showtimes") %>
            <Heroicons.arrow_right class="w-4 h-4 ml-2" />
          </span>
        </div>
      </div>
    </.link>
    """
  end

  # CSS class helpers for variants

  defp section_container_classes(:card), do: "bg-white rounded-lg shadow-lg p-8"
  defp section_container_classes(:dark), do: "bg-gray-900/50 backdrop-blur-sm rounded-lg p-8"

  defp section_title_classes(:card), do: "text-2xl font-bold text-gray-900"
  defp section_title_classes(:dark), do: "text-2xl font-bold text-white"

  defp showtime_count_classes(:card), do: "text-lg font-normal text-gray-600"
  defp showtime_count_classes(:dark), do: "text-lg font-normal text-gray-400"

  defp venues_grid_classes(true), do: "space-y-3"
  defp venues_grid_classes(false), do: "space-y-4"

  defp venue_card_classes(:card) do
    "block p-6 border border-gray-200 rounded-lg hover:border-blue-400 hover:shadow-md transition-all"
  end

  defp venue_card_classes(:dark) do
    "block p-6 bg-white/5 border border-white/10 rounded-lg hover:border-white/30 hover:bg-white/10 transition-all"
  end

  defp venue_name_classes(:card), do: "text-lg font-semibold text-gray-900 mb-2"
  defp venue_name_classes(:dark), do: "text-lg font-semibold text-white mb-2"

  defp venue_address_classes(:card), do: "text-sm text-gray-600 mb-3"
  defp venue_address_classes(:dark), do: "text-sm text-gray-400 mb-3"

  defp date_info_classes(:card), do: "flex items-center text-gray-700 mb-2"
  defp date_info_classes(:dark), do: "flex items-center text-gray-300 mb-2"

  defp format_badge_classes(:card) do
    "px-2 py-1 bg-purple-100 text-purple-800 rounded text-xs font-semibold"
  end

  defp format_badge_classes(:dark) do
    "px-2 py-1 bg-purple-500/20 text-purple-300 rounded text-xs font-semibold"
  end

  defp dates_list_classes(:card), do: "mt-2 text-sm text-gray-600"
  defp dates_list_classes(:dark), do: "mt-2 text-sm text-gray-400"

  defp more_dates_classes(:card), do: "text-gray-500"
  defp more_dates_classes(:dark), do: "text-gray-500"

  defp cta_button_classes(:card) do
    "inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition font-medium"
  end

  defp cta_button_classes(:dark) do
    "inline-flex items-center px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-400 transition font-medium"
  end

  defp empty_state_classes(:card), do: "text-center py-12"
  defp empty_state_classes(:dark), do: "text-center py-12"

  defp empty_icon_classes(:card), do: "w-16 h-16 text-gray-400 mx-auto mb-4"
  defp empty_icon_classes(:dark), do: "w-16 h-16 text-gray-600 mx-auto mb-4"

  defp empty_text_classes(:card), do: "text-gray-600 text-lg"
  defp empty_text_classes(:dark), do: "text-gray-400 text-lg"

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
