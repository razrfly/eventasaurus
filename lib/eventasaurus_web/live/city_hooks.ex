defmodule EventasaurusWeb.Live.CityHooks do
  @moduledoc """
  LiveView hooks for city-based pages.

  Assigns the current city from the URL parameters to the socket.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [redirect: 2, put_flash: 3]
  alias EventasaurusDiscovery.Locations

  def on_mount(:assign_city, params, _session, socket) do
    city_slug = params["city_slug"]

    case Locations.get_city_by_slug(city_slug) do
      nil ->
        # City not found - redirect to home with error message
        socket =
          socket
          |> put_flash(:error, "City not found")
          |> redirect(to: "/")

        {:halt, socket}

      city ->
        if city.latitude && city.longitude do
          {:cont, assign(socket, current_city: city)}
        else
          # City exists but has no coordinates - redirect with error
          socket =
            socket
            |> put_flash(:error, "City location data is incomplete")
            |> redirect(to: "/")

          {:halt, socket}
        end
    end
  end
end
