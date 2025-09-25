defmodule EventasaurusWeb.Plugs.ValidateCity do
  @moduledoc """
  Plug to validate city slugs in URLs and load the city into the connection.

  This plug is used in the `/c/:city_slug` routes to ensure the city exists
  and has coordinates before proceeding with the request.
  """

  import Plug.Conn
  import Phoenix.Controller
  alias EventasaurusDiscovery.Locations

  def init(opts), do: opts

  def call(conn, _opts) do
    city_slug = conn.params["city_slug"] || conn.path_params["city_slug"]

    case Locations.get_city_by_slug(city_slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(html: EventasaurusWeb.ErrorHTML)
        |> render(:"404")
        |> halt()

      city ->
        # Check if city has coordinates
        if city.latitude && city.longitude do
          assign(conn, :current_city, city)
        else
          # City exists but has no coordinates yet
          conn
          |> put_status(:service_unavailable)
          |> put_view(html: EventasaurusWeb.ErrorHTML)
          |> render(:"503", message: "City location data is being processed. Please try again later.")
          |> halt()
        end
    end
  end
end