defmodule EventasaurusDiscovery.Locations do
  @moduledoc """
  Context module for location-based queries and city management.

  Provides functions for city lookups, radius-based event queries,
  and geographic calculations using PostGIS.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.PublicEventsEnhanced

  @doc """
  Get a city by its slug.

  ## Examples

      iex> Locations.get_city_by_slug("krakow")
      %City{name: "Krakow", slug: "krakow", ...}

      iex> Locations.get_city_by_slug("invalid")
      nil
  """
  def get_city_by_slug(slug) when is_binary(slug) do
    Repo.one(
      from(c in City,
        where: c.slug == ^slug,
        preload: [:country]
      )
    )
  end

  @doc """
  Get a city by its slug, raising if not found.

  ## Examples

      iex> Locations.get_city_by_slug!("krakow")
      %City{name: "Krakow", slug: "krakow", ...}

      iex> Locations.get_city_by_slug!("invalid")
      ** (Ecto.NoResultsError)
  """
  def get_city_by_slug!(slug) do
    case get_city_by_slug(slug) do
      nil -> raise Ecto.NoResultsError, queryable: City
      city -> city
    end
  end

  @doc """
  Get the first discovery-enabled city to use as a fallback.

  ## Examples

      iex> Locations.get_first_discovery_enabled_city()
      %City{discovery_enabled: true, ...}

      iex> Locations.get_first_discovery_enabled_city()
      nil  # when no cities are discovery-enabled
  """
  def get_first_discovery_enabled_city do
    Repo.one(
      from(c in City,
        where: c.discovery_enabled == true,
        order_by: [asc: c.name],
        limit: 1,
        preload: [:country]
      )
    )
  end

  @doc """
  Get events for a city using radius-based queries.
  Uses the existing optimized by_location function from PublicEvents.

  ## Options
    * `:radius_km` - Search radius in kilometers (default: 25)
    * `:limit` - Maximum number of events to return (default: 50)
    * `:upcoming_only` - Only return upcoming events (default: true)

  ## Examples

      iex> city = Locations.get_city_by_slug!("krakow")
      iex> Locations.get_city_events(city, radius_km: 30)
      [%PublicEvent{...}, ...]
  """
  def get_city_events(%City{} = city, opts \\ []) do
    radius_km = Keyword.get(opts, :radius_km, 25)
    limit = Keyword.get(opts, :limit, 50)
    upcoming_only = Keyword.get(opts, :upcoming_only, true)
    language = Keyword.get(opts, :language, "en")

    # Convert Decimal to float for coordinates
    lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    if lat && lng do
      # Use PublicEventsEnhanced with geographic filtering at database level
      enhanced_opts = [
        show_past: not upcoming_only,
        page: 1,
        # Use page_size instead of limit
        page_size: limit,
        language: language,
        # Add geographic filtering parameters
        center_lat: lat,
        center_lng: lng,
        radius_km: radius_km
      ]

      PublicEventsEnhanced.list_events(enhanced_opts)
    else
      # Return empty list if city has no coordinates yet
      []
    end
  end

  @doc """
  Get nearby cities based on coordinates.

  ## Options
    * `:radius_km` - Search radius in kilometers (default: 100)
    * `:limit` - Maximum number of cities to return (default: 10)

  ## Examples

      iex> Locations.get_nearby_cities(50.0614, 19.9366, radius_km: 50)
      [%City{name: "Katowice", ...}, ...]
  """
  def get_nearby_cities(lat, lng, opts \\ []) when is_number(lat) and is_number(lng) do
    radius_km = Keyword.get(opts, :radius_km, 100)
    limit = Keyword.get(opts, :limit, 10)

    from(c in City,
      where: not is_nil(c.latitude) and not is_nil(c.longitude),
      where:
        fragment(
          "ST_DWithin(
          ST_MakePoint(?::float, ?::float)::geography,
          ST_MakePoint(?::float, ?::float)::geography,
          ?
        )",
          ^lng,
          ^lat,
          c.longitude,
          c.latitude,
          # Convert to meters
          ^(radius_km * 1000)
        ),
      order_by:
        fragment(
          "ST_Distance(
          ST_MakePoint(?::float, ?::float)::geography,
          ST_MakePoint(?::float, ?::float)::geography
        )",
          ^lng,
          ^lat,
          c.longitude,
          c.latitude
        ),
      limit: ^limit,
      preload: [:country]
    )
    |> Repo.all()
  end

  @doc """
  Search cities by name using ILIKE on name and alternate_names.

  ## Options
    * `:limit` - Maximum number of cities to return (default: 20)

  ## Examples

      iex> Locations.search_cities("krak")
      [%City{name: "Krakow", ...}]
  """
  def search_cities(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 20)
    pattern = "%#{query}%"

    from(c in City,
      where:
        ilike(c.name, ^pattern) or
          fragment("EXISTS (SELECT 1 FROM unnest(?) AS alt WHERE alt ILIKE ?)", c.alternate_names, ^pattern),
      where: not is_nil(c.latitude) and not is_nil(c.longitude),
      order_by: [asc: c.name],
      limit: ^limit,
      preload: [:country]
    )
    |> Repo.all()
  end

  @doc """
  List all cities with coordinates.

  ## Options
    * `:limit` - Maximum number of cities to return (default: 100)
    * `:country_id` - Filter by country ID

  ## Examples

      iex> Locations.list_cities_with_coordinates()
      [%City{name: "Krakow", latitude: #Decimal<50.0614>, ...}, ...]
  """
  def list_cities_with_coordinates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    query =
      from(c in City,
        where: not is_nil(c.latitude) and not is_nil(c.longitude),
        order_by: [asc: c.name],
        limit: ^limit,
        preload: [:country]
      )

    query =
      case Keyword.get(opts, :country_id) do
        nil -> query
        country_id -> where(query, [c], c.country_id == ^country_id)
      end

    Repo.all(query)
  end

  @doc """
  Calculate distance between two points in kilometers.

  ## Examples

      iex> Locations.calculate_distance(50.0614, 19.9366, 52.2297, 21.0122)
      251.8  # Krakow to Warsaw in km
  """
  def calculate_distance(lat1, lng1, lat2, lng2)
      when is_number(lat1) and is_number(lng1) and is_number(lat2) and is_number(lng2) do
    query = """
    SELECT ST_Distance(
      ST_MakePoint($1::float, $2::float)::geography,
      ST_MakePoint($3::float, $4::float)::geography
    ) / 1000.0 as distance_km
    """

    case Repo.query(query, [lng1, lat1, lng2, lat2]) do
      {:ok, %{rows: [[distance_km]]}} -> Float.round(distance_km, 1)
      _ -> nil
    end
  end
end
