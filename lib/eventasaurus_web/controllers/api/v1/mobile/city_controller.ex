defmodule EventasaurusWeb.Api.V1.Mobile.CityController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.Locations

  @doc """
  GET /api/v1/mobile/cities?q=krak

  Searches cities by name. If `q` param is >= 2 chars, searches by ILIKE;
  otherwise returns all cities with coordinates.
  """
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

  defp serialize_city(city) do
    %{
      id: city.id,
      name: city.name,
      slug: city.slug,
      latitude: city.latitude && Decimal.to_float(city.latitude),
      longitude: city.longitude && Decimal.to_float(city.longitude),
      timezone: city.timezone,
      country: city.country && city.country.name
    }
  end
end
