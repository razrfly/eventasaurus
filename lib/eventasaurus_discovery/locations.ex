defmodule EventasaurusDiscovery.Locations do
  @moduledoc """
  Context module for location-based queries and city management.

  Provides functions for city lookups, radius-based event queries,
  and geographic calculations using PostGIS.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.PublicEvents
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
      from c in City,
      where: c.slug == ^slug,
      preload: [:country]
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
      # Use PublicEventsEnhanced to get properly formatted events with categories
      # but then filter by radius manually since it doesn't support radius filtering
      enhanced_opts = [
        show_past: not upcoming_only,
        limit: limit * 3, # Get more to account for radius filtering
        language: language
      ]

      all_enhanced_events = PublicEventsEnhanced.list_events(enhanced_opts)

      # Filter by radius using PostGIS distance calculation
      radius_meters = radius_km * 1000

      filtered_events = Enum.filter(all_enhanced_events, fn event ->
        case event.venue do
          %{latitude: venue_lat, longitude: venue_lng} when not is_nil(venue_lat) and not is_nil(venue_lng) ->
            # Convert Decimal to float if needed
            venue_lat = if is_struct(venue_lat, Decimal), do: Decimal.to_float(venue_lat), else: venue_lat
            venue_lng = if is_struct(venue_lng, Decimal), do: Decimal.to_float(venue_lng), else: venue_lng

            # Calculate distance using the same query we use elsewhere
            query = """
            SELECT ST_Distance(
              ST_MakePoint($1::float, $2::float)::geography,
              ST_MakePoint($3::float, $4::float)::geography
            ) as distance_meters
            """

            case Repo.query(query, [lng, lat, venue_lng, venue_lat]) do
              {:ok, %{rows: [[distance]]}} -> distance <= radius_meters
              _ -> false
            end
          _ ->
            false
        end
      end)

      # Take only the requested limit
      Enum.take(filtered_events, limit)
    else
      # Return empty list if city has no coordinates yet
      []
    end
  end

  defp get_cover_image_url(event) do
    # Check if sources are loaded
    case event do
      %{sources: %Ecto.Association.NotLoaded{}} ->
        # Need to preload sources if not loaded
        event = Repo.preload(event, :sources)
        extract_image_from_sources(event.sources)
      %{sources: sources} when is_list(sources) ->
        extract_image_from_sources(sources)
      _ ->
        nil
    end
  end

  defp extract_image_from_sources([]), do: nil
  defp extract_image_from_sources(sources) do
    # Sort by priority and get first image_url
    sources
    |> Enum.sort_by(fn source ->
      priority = case source.metadata do
        %{"priority" => p} when is_integer(p) -> p
        %{"priority" => p} when is_binary(p) ->
          case Integer.parse(p) do
            {num, _} -> num
            _ -> 10
          end
        _ -> 10
      end

      # Use negative timestamp to sort newest first
      timestamp = case source.last_seen_at do
        %DateTime{} = dt -> -DateTime.to_unix(dt)
        _ -> 0
      end

      {priority, timestamp}
    end)
    |> Enum.find_value(fn source ->
      case source.image_url do
        url when is_binary(url) and url != "" -> url
        _ -> nil
      end
    end)
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
      where: fragment(
        "ST_DWithin(
          ST_MakePoint(?::float, ?::float)::geography,
          ST_MakePoint(?::float, ?::float)::geography,
          ?
        )",
        ^lng, ^lat,
        c.longitude, c.latitude,
        ^(radius_km * 1000)  # Convert to meters
      ),
      order_by: fragment(
        "ST_Distance(
          ST_MakePoint(?::float, ?::float)::geography,
          ST_MakePoint(?::float, ?::float)::geography
        )",
        ^lng, ^lat,
        c.longitude, c.latitude
      ),
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

    query = from c in City,
      where: not is_nil(c.latitude) and not is_nil(c.longitude),
      order_by: [asc: c.name],
      limit: ^limit,
      preload: [:country]

    query = case Keyword.get(opts, :country_id) do
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