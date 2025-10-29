defmodule EventasaurusDiscovery.Locations.CityHierarchy do
  @moduledoc """
  Runtime detection of metropolitan areas using pure geographic clustering.

  This module groups nearby cities into metropolitan areas and identifies
  primary cities based on event counts. No database changes required.

  ## Algorithm

  1. Calculate distances between all city pairs (Haversine formula)
  2. Group cities within threshold distance (default 20km)
  3. Select city with most events as primary for each cluster
  4. Aggregate statistics by metropolitan area

  ## Example

      # Paris (302 events), Paris 8 (21 events), Paris 16 (21 events)
      # All within 10km of each other -> cluster together
      # Paris becomes primary (most events)
      # Result: "Paris - 344 events (3 areas)"
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query

  @default_distance_threshold_km 20.0
  @earth_radius_km 6371.0

  @doc """
  Aggregates city statistics by metropolitan area clusters.

  Cities within the distance threshold (default 20km) are grouped together.
  The city with the most events becomes the primary city for display.

  ## Parameters

    - `city_stats` - List of maps with `:city_id` and `:count` keys
    - `distance_threshold` - Maximum distance in km to group cities (default: 20.0)

  ## Returns

  List of aggregated statistics with structure:

      %{
        city_id: primary_city_id,
        city_name: "Paris",
        city_slug: "paris",
        count: 344,  # Sum of all cities in cluster
        subcities: [
          %{city_id: 2, city_name: "Paris 8", count: 21},
          %{city_id: 3, city_name: "Paris 16", count: 21}
        ]
      }
  """
  def aggregate_stats_by_cluster(city_stats, distance_threshold \\ @default_distance_threshold_km) do
    # Load all cities with their coordinates
    city_ids = Enum.map(city_stats, & &1.city_id)
    cities = load_cities_with_coords(city_ids)

    # Build clusters based on geographic proximity
    clusters = cluster_nearby_cities(cities, distance_threshold)

    # For each cluster, aggregate stats
    clusters
    |> Enum.map(fn cluster ->
      aggregate_cluster_stats(cluster, city_stats, cities)
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  @doc """
  Clusters cities by geographic proximity.

  Uses connected components algorithm to group cities that are within
  the distance threshold of each other.

  ## Parameters

    - `cities` - List of City structs with latitude/longitude
    - `distance_threshold` - Maximum distance in km to consider cities as part of same cluster

  ## Returns

  List of clusters, where each cluster is a list of city IDs:

      [[1, 2, 3], [4], [5, 6]]  # 3 clusters: one with 3 cities, two singles
  """
  def cluster_nearby_cities(cities, distance_threshold \\ @default_distance_threshold_km) do
    # Build adjacency map: city_id -> [nearby_city_ids]
    adjacency = build_adjacency_map(cities, distance_threshold)

    # Find connected components (each component is a metropolitan area)
    find_connected_components(adjacency, MapSet.new(Enum.map(cities, & &1.id)))
  end

  @doc """
  Calculates distance between two geographic coordinates using Haversine formula.

  ## Parameters

    - `lat1`, `lon1` - First coordinate (Decimal or Float)
    - `lat2`, `lon2` - Second coordinate (Decimal or Float)

  ## Returns

  Distance in kilometers as float.

  ## Example

      iex> CityHierarchy.haversine_distance(48.8566, 2.3522, 48.8738, 2.2950)
      4.87  # ~5km between Paris center and La Défense
  """
  def haversine_distance(lat1, lon1, lat2, lon2) do
    # Convert Decimal to float if needed
    lat1_f = to_float(lat1)
    lon1_f = to_float(lon1)
    lat2_f = to_float(lat2)
    lon2_f = to_float(lon2)

    # Convert to radians
    lat1_rad = degrees_to_radians(lat1_f)
    lat2_rad = degrees_to_radians(lat2_f)
    delta_lat = degrees_to_radians(lat2_f - lat1_f)
    delta_lon = degrees_to_radians(lon2_f - lon1_f)

    # Haversine formula
    a =
      :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(delta_lon / 2) * :math.sin(delta_lon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    @earth_radius_km * c
  end

  # Private functions

  defp load_cities_with_coords(city_ids) do
    from(c in City,
      where: c.id in ^city_ids,
      select: %{
        id: c.id,
        name: c.name,
        slug: c.slug,
        latitude: c.latitude,
        longitude: c.longitude,
        country_id: c.country_id
      }
    )
    |> Repo.all()
  end

  defp build_adjacency_map(cities, threshold) do
    has_coords? = fn c -> not is_nil(c.latitude) and not is_nil(c.longitude) end

    cities
    |> Enum.reduce(%{}, fn city, acc ->
      # Find all cities within threshold distance
      nearby =
        cities
        |> Enum.filter(fn other ->
          city.id != other.id and
            city.country_id == other.country_id and
            has_coords?.(city) and has_coords?.(other) and
            haversine_distance(city.latitude, city.longitude, other.latitude, other.longitude) <
              threshold
        end)
        |> Enum.map(& &1.id)

      Map.put(acc, city.id, nearby)
    end)
  end

  defp find_connected_components(adjacency, all_city_ids) do
    # Use depth-first search to find all connected components
    {components, _visited} =
      all_city_ids
      |> Enum.reduce({[], MapSet.new()}, fn city_id, {components, visited} ->
        if MapSet.member?(visited, city_id) do
          {components, visited}
        else
          # Start a new component with DFS from this city
          component = dfs(city_id, adjacency, MapSet.new())
          new_visited = MapSet.union(visited, component)
          {[MapSet.to_list(component) | components], new_visited}
        end
      end)

    components
  end

  defp dfs(city_id, adjacency, visited) do
    if MapSet.member?(visited, city_id) do
      visited
    else
      new_visited = MapSet.put(visited, city_id)

      # Visit all neighbors
      neighbors = Map.get(adjacency, city_id, [])

      Enum.reduce(neighbors, new_visited, fn neighbor_id, acc ->
        dfs(neighbor_id, adjacency, acc)
      end)
    end
  end

  defp aggregate_cluster_stats(city_ids_in_cluster, city_stats, cities) do
    # Get stats for all cities in this cluster
    city_stats_in_cluster =
      Enum.filter(city_stats, fn stat ->
        stat.city_id in city_ids_in_cluster
      end)

    # Find primary city (most events)
    primary_stat = Enum.max_by(city_stats_in_cluster, & &1.count)
    primary_city = Enum.find(cities, &(&1.id == primary_stat.city_id))

    # Get all other cities in cluster as subcities
    subcities =
      city_stats_in_cluster
      |> Enum.reject(&(&1.city_id == primary_city.id))
      |> Enum.map(fn stat ->
        city = Enum.find(cities, &(&1.id == stat.city_id))

        %{
          city_id: city.id,
          city_name: city.name,
          city_slug: city.slug,
          count: stat.count
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)

    # Check if any city in this cluster uses geographic matching (is_geographic: true)
    # If so, use MAX count instead of SUM to avoid double-counting events
    # (Geographic cities already include events from nearby inactive cities)
    has_geographic = Enum.any?(city_stats_in_cluster, &Map.get(&1, :is_geographic, false))

    total_count =
      if has_geographic do
        # Use MAX count when cluster contains geographic city
        # (the geographic city's count already includes nearby cities)
        Enum.max(Enum.map(city_stats_in_cluster, & &1.count))
      else
        # Use SUM for traditional city_id-based clusters
        Enum.sum(Enum.map(city_stats_in_cluster, & &1.count))
      end

    %{
      city_id: primary_city.id,
      city_name: primary_city.name,
      city_slug: primary_city.slug,
      count: total_count,
      subcities: subcities
    }
  end

  defp degrees_to_radians(degrees), do: degrees * :math.pi() / 180.0

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(float) when is_float(float), do: float
  defp to_float(int) when is_integer(int), do: int * 1.0
end
