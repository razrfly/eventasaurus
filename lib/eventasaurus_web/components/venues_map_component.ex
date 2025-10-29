defmodule EventasaurusWeb.VenuesMapComponent do
  @moduledoc """
  Interactive map component for displaying multiple venues with markers.
  Uses Google Maps JS API for interactive features like clustering and info windows.
  """
  use EventasaurusWeb, :live_component

  @doc """
  Renders an interactive map showing all venues in a city.

  ## Props

  * `:venues` - List of venue data with coordinates
  * `:city` - The city struct
  * `:id` - Unique component ID

  ## Examples

      <.live_component
        module={EventasaurusWeb.VenuesMapComponent}
        id="venues-map"
        venues={@venues}
        city={@city}
      />
  """
  def render(assigns) do
    ~H"""
    <div class="relative w-full h-[600px] rounded-lg overflow-hidden shadow-lg border border-gray-200 dark:border-gray-700">
      <div
        id={"venues-map-#{@id}"}
        phx-hook="VenuesMap"
        phx-update="ignore"
        data-venues={Jason.encode!(prepare_venues_data(@venues))}
        data-center={Jason.encode!(get_city_center(@city))}
        class="w-full h-full"
      >
        <!-- Map loading state -->
        <div class="flex items-center justify-center h-full bg-gray-100 dark:bg-gray-800">
          <div class="text-center">
            <svg
              class="animate-spin h-8 w-8 text-blue-600 mx-auto mb-2"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4"
              >
              </circle>
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              >
              </path>
            </svg>
            <p class="text-gray-600 dark:text-gray-400 text-sm">Loading map...</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  # Private functions

  defp prepare_venues_data(venues) do
    venues
    |> Enum.filter(fn venue_data -> has_coordinates?(venue_data.venue) end)
    |> Enum.map(fn venue_data ->
      venue = venue_data.venue

      %{
        id: venue.id,
        name: venue.name,
        slug: venue.slug,
        address: venue.address,
        latitude: venue.latitude,
        longitude: venue.longitude,
        events_count: venue_data.upcoming_events_count,
        url: "/venues/#{venue.slug}"
      }
    end)
  end

  defp has_coordinates?(%{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon),
       do: true

  defp has_coordinates?(_), do: false

  defp get_city_center(city) do
    %{
      lat: city.latitude || 52.2297,
      lng: city.longitude || 21.0122
    }
  end
end
