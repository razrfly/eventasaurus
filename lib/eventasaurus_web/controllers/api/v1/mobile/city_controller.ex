defmodule EventasaurusWeb.Api.V1.Mobile.CityController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.CityStats

  @doc """
  GET /api/v1/mobile/cities?q=krak

  Searches cities by name. If `q` param is >= 2 chars, searches by ILIKE;
  otherwise returns all cities with coordinates.
  """
  @spec search(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def search(conn, params) do
    cities =
      case params["q"] do
        q when is_binary(q) and byte_size(q) >= 2 ->
          Locations.search_cities(q, limit: 20)

        _ ->
          Locations.list_cities_with_coordinates(limit: 50)
      end

    json(conn, %{
      cities: Enum.map(cities, &serialize_city/1)
    })
  end

  @doc """
  GET /api/v1/mobile/cities/popular

  Returns cities ranked by number of upcoming events, for the default
  city picker view. Includes event_count for display.
  """
  @spec popular(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def popular(conn, _params) do
    cities = CityStats.list_popular_cities(limit: 10, min_events: 5)

    json(conn, %{
      cities: Enum.map(cities, &serialize_popular_city/1)
    })
  end

  @doc """
  GET /api/v1/mobile/cities/resolve?lat=50.06&lng=19.94

  Resolves GPS coordinates to the nearest city. Returns a single city
  so the app can display "Warsaw, Poland" instead of "Use My Location".
  """
  @spec resolve(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resolve(conn, %{"lat" => lat_str, "lng" => lng_str}) do
    with {lat, ""} <- Float.parse(lat_str),
         {lng, ""} <- Float.parse(lng_str),
         [nearest | _] <- Locations.get_nearby_cities(lat, lng, limit: 1, radius_km: 100) do
      json(conn, %{city: serialize_city(nearest)})
    else
      [] ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "No city found near those coordinates"})

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "bad_request", message: "Invalid lat/lng values"})
    end
  end

  def resolve(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "bad_request", message: "lat and lng parameters are required"})
  end

  defp serialize_city(city) do
    %{
      id: city.id,
      name: city.name,
      slug: city.slug,
      latitude: city.latitude && Decimal.to_float(city.latitude),
      longitude: city.longitude && Decimal.to_float(city.longitude),
      timezone: city.timezone,
      country: city.country && city.country.name,
      country_code: city.country && city.country.code
    }
  end

  defp serialize_popular_city(city) do
    serialize_city(city)
    |> Map.put(:event_count, city.event_count)
  end
end
