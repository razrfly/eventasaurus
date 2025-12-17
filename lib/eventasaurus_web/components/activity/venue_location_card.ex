defmodule EventasaurusWeb.Components.Activity.VenueLocationCard do
  @moduledoc """
  Sidebar component displaying venue information with integrated map.

  Combines venue name, address, and static map into a single card
  for the activity page sidebar.
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext
  use Phoenix.VerifiedRoutes, endpoint: EventasaurusWeb.Endpoint, router: EventasaurusWeb.Router

  alias EventasaurusWeb.StaticMapComponent

  @doc """
  Renders a venue location card with venue info and integrated map.

  ## Attributes

    * `:venue` - Required. The venue struct with name, slug, address, coordinates.
    * `:map_id` - Required. Unique ID for the map component.
    * `:class` - Optional. Additional CSS classes for the container.
    * `:show_directions` - Optional. Whether to show the directions link. Defaults to `true`.

  ## Examples

      <VenueLocationCard.venue_location_card
        venue={@event.venue}
        map_id="event-venue-map"
      />
  """
  attr :venue, :map, required: true
  attr :map_id, :string, required: true
  attr :class, :string, default: ""
  attr :show_directions, :boolean, default: true

  def venue_location_card(assigns) do
    ~H"""
    <div class={["bg-white rounded-xl border border-gray-200 overflow-hidden", @class]}>
      <!-- Map Section -->
      <%= if has_coordinates?(@venue) do %>
        <div class="relative">
          <.live_component
            module={StaticMapComponent}
            id={@map_id}
            venue={@venue}
            theme={:minimal}
            size={:small}
          />
          <!-- Map overlay gradient for visual polish -->
          <div class="absolute inset-x-0 bottom-0 h-8 bg-gradient-to-t from-white/80 to-transparent pointer-events-none">
          </div>
        </div>
      <% end %>

      <!-- Venue Info Section -->
      <div class="p-4">
        <div class="flex items-start gap-3">
          <div class="flex-shrink-0 w-10 h-10 bg-gray-100 rounded-lg flex items-center justify-center">
            <Heroicons.map_pin class="w-5 h-5 text-gray-600" />
          </div>
          <div class="flex-1 min-w-0">
            <%= if @venue.slug do %>
              <.link
                navigate={~p"/venues/#{@venue.slug}"}
                class="font-semibold text-gray-900 hover:text-indigo-600 transition-colors block truncate"
              >
                <%= @venue.name %>
              </.link>
            <% else %>
              <span class="font-semibold text-gray-900 block truncate">
                <%= @venue.name %>
              </span>
            <% end %>
            <p class="text-sm text-gray-500 mt-0.5">
              <%= format_venue_address(@venue) %>
            </p>
          </div>
        </div>

        <!-- Action Buttons -->
        <%= if @show_directions && has_coordinates?(@venue) do %>
          <div class="mt-4 flex gap-2">
            <a
              href={google_maps_directions_url(@venue)}
              target="_blank"
              rel="noopener noreferrer"
              class="flex-1 inline-flex items-center justify-center px-3 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
            >
              <Heroicons.arrow_top_right_on_square class="w-4 h-4 mr-1.5" />
              <%= gettext("Directions") %>
            </a>
            <%= if @venue.slug do %>
              <.link
                navigate={~p"/venues/#{@venue.slug}"}
                class="flex-1 inline-flex items-center justify-center px-3 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
              >
                <Heroicons.building_storefront class="w-4 h-4 mr-1.5" />
                <%= gettext("Venue Info") %>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Private helpers

  defp has_coordinates?(%{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon),
       do: true

  defp has_coordinates?(_), do: false

  defp format_venue_address(venue) do
    parts =
      [
        venue.address,
        get_city_name(venue),
        get_country_name(venue)
      ]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.join(", ")

    if parts == "", do: nil, else: parts
  end

  defp get_city_name(%{city_ref: %{name: name}}) when is_binary(name), do: name
  defp get_city_name(_), do: nil

  defp get_country_name(%{city_ref: %{country: %{name: name}}}) when is_binary(name), do: name
  defp get_country_name(_), do: nil

  defp google_maps_directions_url(%{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon) do
    "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lon}"
  end

  defp google_maps_directions_url(%{address: address, name: name}) when is_binary(address) do
    query = URI.encode("#{name}, #{address}")
    "https://www.google.com/maps/dir/?api=1&destination=#{query}"
  end

  defp google_maps_directions_url(_), do: "#"
end
