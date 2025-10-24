defmodule EventasaurusWeb.VenueLive.Components.VenueMap do
  @moduledoc """
  Interactive map component for venue location display using Leaflet.js.

  Displays:
  - Interactive map centered on venue location
  - Marker with venue name
  - Zoom controls
  - Default zoom level: 15 (street level)
  """
  use Phoenix.Component

  attr :venue, :map, required: true, doc: "Venue with latitude and longitude"
  attr :height, :string, default: "h-96", doc: "Tailwind height class"

  def venue_map(assigns) do
    ~H"""
    <div class="venue-map-container">
      <%= if has_coordinates?(@venue) do %>
        <div
          id="venue-map"
          phx-hook="VenueMap"
          data-latitude={@venue.latitude}
          data-longitude={@venue.longitude}
          data-venue-name={@venue.name}
          class={["w-full rounded-lg overflow-hidden", @height]}
        >
        </div>
      <% else %>
        <div class={["w-full rounded-lg bg-gray-100 flex items-center justify-center", @height]}>
          <div class="text-center text-gray-500">
            <svg
              class="mx-auto h-12 w-12 text-gray-400"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"
              />
            </svg>
            <p class="mt-2">Location coordinates not available</p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions

  defp has_coordinates?(%{latitude: lat, longitude: lng})
       when is_float(lat) and is_float(lng) and lat != 0.0 and lng != 0.0,
       do: true

  defp has_coordinates?(_), do: false
end
