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
    # Load all cities with their coordinates from city_stats (cities with events)
    city_ids = Enum.map(city_stats, & &1.city_id)
    cities_with_events = load_cities_with_coords(city_ids)

    # PHASE 1: Find and include discovery-enabled parent cities
    # For each city with events, check if there's a nearby discovery-enabled city
    # (This is what breadcrumbs do, and it works correctly)
    discovery_cities =
      cities_with_events
      |> Enum.map(&find_nearby_discovery_city(&1, 50.0))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.id)

    # Combine cities with events and discovery-enabled parent cities
    all_cities = Enum.uniq_by(cities_with_events ++ discovery_cities, & &1.id)

    # Build clusters based on geographic proximity (now includes parent cities)
    clusters = cluster_nearby_cities(all_cities, distance_threshold)

    # For each cluster, aggregate stats
    clusters
    |> Enum.map(fn cluster ->
      aggregate_cluster_stats(cluster, city_stats, all_cities)
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  @doc """
  Returns all city IDs in the same geographic cluster as the given city.

  Uses the same clustering algorithm as the main stats page to identify
  metropolitan areas. Cities within the distance threshold are grouped together.

  ## Parameters

    - `city_id` - The ID of the city to find cluster members for
    - `distance_threshold` - Maximum distance in km to group cities (default: 20.0)

  ## Returns

  List of city IDs in the cluster, including the given city_id:

      [2, 460, 461, 490]  # Melbourne + South Melbourne + West Melbourne + Collingwood

  ## Example

      iex> CityHierarchy.get_cluster_city_ids(2)  # Melbourne
      [2, 460, 461, 490, ...]  # All Melbourne metro area cities
  """
  def get_cluster_city_ids(city_id, distance_threshold \\ @default_distance_threshold_km) do
    # Load the target city
    city = Repo.get!(City, city_id)

    # Get all cities in the same country (clustering respects country boundaries)
    cities =
      from(c in City,
        where: c.country_id == ^city.country_id,
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

    # Build clusters using the same algorithm as the main stats page
    clusters = cluster_nearby_cities(cities, distance_threshold)

    # Find which cluster contains our city_id
    cluster = Enum.find(clusters, fn cluster -> city_id in cluster end)

    # Return the cluster (or singleton list if no cluster found)
    cluster || [city_id]
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
    clusters = find_connected_components(adjacency, MapSet.new(Enum.map(cities, & &1.id)))

    # Validate clusters: Remove outliers from clusters that are too spread out
    # This prevents villages from being grouped with major cities through transitive chains
    # (e.g., Meaux → Chessy → Paris should NOT group Meaux with Paris)
    validate_and_fix_clusters(clusters, cities, distance_threshold)
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
        country_id: c.country_id,
        discovery_enabled: c.discovery_enabled
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

  defp aggregate_cluster_stats(city_ids_in_cluster, city_stats, _cities) do
    # Get stats for all cities in this cluster
    city_stats_in_cluster =
      Enum.filter(city_stats, fn stat ->
        stat.city_id in city_ids_in_cluster
      end)

    # Load FULL city records for all cities in cluster (not just those with events)
    # We need discovery_enabled field and other metadata for base city detection
    all_cities_in_cluster = load_full_cities_for_cluster(city_ids_in_cluster)

    # PHASE 1: Detect potential base cities that might be missing from city_stats
    # (cities with 0 events are filtered out by the query but should be parent cities)
    potential_base_city = detect_base_city_in_cluster(all_cities_in_cluster)

    # PHASE 2: Inject base city into candidates if it's missing from stats
    city_stats_in_cluster_with_base =
      if potential_base_city && !Enum.any?(city_stats_in_cluster, &(&1.city_id == potential_base_city.id)) do
        # Base city not in stats (has 0 events), inject it
        [%{city_id: potential_base_city.id, count: 0} | city_stats_in_cluster]
      else
        city_stats_in_cluster
      end

    # Find primary city using hierarchy-aware scoring
    # Priority 0: Active discovery cities (discovery_enabled: true) - 100,000 points
    # Priority 1: Parent city (name is prefix of 2+ other cities) - 10,000 points
    # Priority 2: Base city (no numeric suffix in slug) - 1,000 points
    # Priority 3: Shorter name - up to 100 points
    # Priority 4: Most events - 1 point per event (fallback)

    primary_city =
      city_stats_in_cluster_with_base
      |> Enum.map(fn stat ->
        city = Enum.find(all_cities_in_cluster, &(&1.id == stat.city_id))

        # Calculate priority score with hierarchy-aware bonuses
        # Active discovery bonus: 100,000 points if city is actively monitored
        # This ensures cities we're actively discovering ALWAYS become parent cities
        discovery_bonus = if city.discovery_enabled, do: 100_000, else: 0

        # Parent city bonus: 10,000 points if this city's name is a substring of other cities
        # (e.g., "Paris" is substring of "Paris 1", "Paris 8" -> it's the parent)
        parent_city_bonus =
          if is_parent_city_of_cluster?(city, all_cities_in_cluster), do: 10_000, else: 0

        # Base city bonus: 1,000 points if slug has no numeric suffix
        base_city_bonus = if is_base_city?(city.slug), do: 1_000, else: 0

        # Name length bonus: prefer shorter names (max 100 points)
        name_length_bonus = max(0, 100 - String.length(city.name))

        # Event count: 1 point per event (lowest priority, just a tiebreaker)
        event_bonus = stat.count

        score = discovery_bonus + parent_city_bonus + base_city_bonus + name_length_bonus + event_bonus

        {city, score}
      end)
      |> Enum.max_by(fn {_city, score} -> score end)
      |> elem(0)

    # Get all other cities in cluster as subcities
    subcities =
      city_stats_in_cluster_with_base
      |> Enum.reject(&(&1.city_id == primary_city.id))
      |> Enum.map(fn stat ->
        city = Enum.find(all_cities_in_cluster, &(&1.id == stat.city_id))

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
    has_geographic = Enum.any?(city_stats_in_cluster_with_base, &Map.get(&1, :is_geographic, false))

    total_count =
      if has_geographic do
        # Use MAX count when cluster contains geographic city
        # (the geographic city's count already includes nearby cities)
        Enum.max(Enum.map(city_stats_in_cluster_with_base, & &1.count))
      else
        # Use SUM for traditional city_id-based clusters
        Enum.sum(Enum.map(city_stats_in_cluster_with_base, & &1.count))
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

  # Load full City records for all cities in a cluster
  # This includes cities with 0 events that might have been filtered out
  defp load_full_cities_for_cluster(city_ids) do
    from(c in City,
      where: c.id in ^city_ids,
      select: %{
        id: c.id,
        name: c.name,
        slug: c.slug,
        latitude: c.latitude,
        longitude: c.longitude,
        discovery_enabled: c.discovery_enabled,
        country_id: c.country_id
      }
    )
    |> Repo.all()
  end

  # Detect the base/parent city in a cluster that should be the primary city
  # Prioritizes: 1) discovery_enabled cities, 2) parent cities, 3) base cities
  defp detect_base_city_in_cluster(cities) do
    cities
    |> Enum.map(fn city ->
      # Score each city as a potential base city
      discovery_score = if city.discovery_enabled, do: 100_000, else: 0
      parent_score = if is_parent_city_of_cluster?(city, cities), do: 10_000, else: 0
      base_score = if is_base_city?(city.slug), do: 1_000, else: 0
      name_score = max(0, 100 - String.length(city.name))

      total_score = discovery_score + parent_score + base_score + name_score

      {city, total_score}
    end)
    |> Enum.max_by(fn {_city, score} -> score end, fn -> {nil, 0} end)
    |> elem(0)
  end

  # Check if a city is the "parent" city of a cluster
  # A parent city's name appears as a prefix/substring in other city names
  # Examples:
  #   is_parent_city_of_cluster?("Paris", ["Paris 1", "Paris 8", "Meaux"]) -> true
  #   is_parent_city_of_cluster?("Meaux", ["Paris 1", "Paris 8", "Meaux"]) -> false
  defp is_parent_city_of_cluster?(city, all_cities_in_cluster) do
    # Count how many OTHER cities in the cluster have this city's name as a prefix
    matching_count =
      all_cities_in_cluster
      |> Enum.reject(&(&1.id == city.id))
      |> Enum.count(fn other_city ->
        # Check if other city's name starts with this city's name
        # (case-insensitive, and handle spaces/dashes)
        base_name = String.downcase(city.name)
        other_name = String.downcase(other_city.name)

        String.starts_with?(other_name, base_name <> " ") or
          String.starts_with?(other_name, base_name <> "-")
      end)

    # If at least 2 other cities match, this is likely the parent
    matching_count >= 2
  end

  # Check if a city is a "base" city without district/suburb suffixes
  # Examples:
  #   is_base_city?("paris") -> true
  #   is_base_city?("paris-8") -> false
  #   is_base_city?("london") -> true
  #   is_base_city?("south-london") -> false
  defp is_base_city?(slug) do
    # A base city slug should not end with a dash followed by digits
    # and should not have directional prefixes (north-, south-, east-, west-)
    not String.match?(slug, ~r/-\d+$/) and
      not String.match?(slug, ~r/^(north|south|east|west|central)-/)
  end

  # Find a nearby discovery-enabled city (the parent city for metro areas)
  # This mimics the breadcrumb logic which correctly identifies parent cities
  # Returns the nearest discovery-enabled city (excluding itself) or nil if none found
  defp find_nearby_discovery_city(city, radius_km) do
    # Look for nearby discovery-enabled cities within radius
    # Exclude the current city to find a different parent even if this city is discovery-enabled
    if city.latitude && city.longitude do
      # Calculate bounding box for search radius
      lat = to_float(city.latitude)
      lng = to_float(city.longitude)

      lat_delta = radius_km / 111.0
      lng_delta = radius_km / (111.0 * :math.cos(lat * :math.pi() / 180.0))

      min_lat = lat - lat_delta
      max_lat = lat + lat_delta
      min_lng = lng - lng_delta
      max_lng = lng + lng_delta

      # Find the nearest discovery-enabled city (excluding current city)
      Repo.one(
        from(c in City,
          where: c.country_id == ^city.country_id,
          where: c.discovery_enabled == true,
          where: c.id != ^city.id,
          where: not is_nil(c.latitude) and not is_nil(c.longitude),
          where: c.latitude >= ^min_lat and c.latitude <= ^max_lat,
          where: c.longitude >= ^min_lng and c.longitude <= ^max_lng,
          # Order by distance (approximation using lat/lng delta)
          order_by: [
            asc:
              fragment(
                "ABS(? - ?) + ABS(? - ?)",
                c.latitude,
                ^city.latitude,
                c.longitude,
                ^city.longitude
              )
          ],
          limit: 1,
          select: %{
            id: c.id,
            name: c.name,
            slug: c.slug,
            latitude: c.latitude,
            longitude: c.longitude,
            discovery_enabled: c.discovery_enabled,
            country_id: c.country_id
          }
        )
      )
    else
      nil
    end
  end

  # Validate clusters and remove outliers from oversized clusters
  # Prevents villages from being grouped with major cities through transitive chains
  defp validate_and_fix_clusters(clusters, cities, distance_threshold) do
    # Maximum allowed cluster diameter (1.5x the distance threshold)
    max_diameter = distance_threshold * 1.5

    # Create a map of city_id -> city for quick lookup
    cities_by_id = Map.new(cities, fn city -> {city.id, city} end)

    clusters
    |> Enum.flat_map(fn cluster_ids ->
      # Get cities in this cluster
      cluster_cities = Enum.map(cluster_ids, &Map.get(cities_by_id, &1)) |> Enum.reject(&is_nil/1)

      # Calculate cluster diameter (max distance between any two cities)
      diameter = calculate_cluster_diameter(cluster_cities)

      if diameter <= max_diameter do
        # Cluster is valid, keep it as-is
        [cluster_ids]
      else
        # Cluster is too spread out, split it by removing outliers
        split_oversized_cluster(cluster_cities, cities_by_id, distance_threshold)
      end
    end)
  end

  # Calculate the maximum distance between any two cities in a cluster
  defp calculate_cluster_diameter(cities) do
    cities
    |> Enum.flat_map(fn city1 ->
      Enum.map(cities, fn city2 ->
        if city1.id != city2.id and not is_nil(city1.latitude) and not is_nil(city2.latitude) do
          haversine_distance(city1.latitude, city1.longitude, city2.latitude, city2.longitude)
        else
          0.0
        end
      end)
    end)
    |> Enum.max(fn -> 0.0 end)
  end

  # Split an oversized cluster by grouping cities around their geographic centroid
  # Cities far from the centroid are excluded (outliers)
  defp split_oversized_cluster(cluster_cities, _cities_by_id, distance_threshold) do
    # Calculate geographic centroid of the cluster
    {sum_lat, sum_lon, count} =
      cluster_cities
      |> Enum.filter(fn city -> not is_nil(city.latitude) and not is_nil(city.longitude) end)
      |> Enum.reduce({0.0, 0.0, 0}, fn city, {lat_sum, lon_sum, cnt} ->
        {lat_sum + to_float(city.latitude), lon_sum + to_float(city.longitude), cnt + 1}
      end)

    if count == 0 do
      # No valid coordinates, return as single cluster
      [Enum.map(cluster_cities, & &1.id)]
    else
      centroid_lat = sum_lat / count
      centroid_lon = sum_lon / count

      # Group cities into "core" (within threshold of centroid) and "outliers"
      {core_cities, outlier_cities} =
        cluster_cities
        |> Enum.split_with(fn city ->
          if not is_nil(city.latitude) and not is_nil(city.longitude) do
            distance = haversine_distance(centroid_lat, centroid_lon, city.latitude, city.longitude)
            distance <= distance_threshold
          else
            false
          end
        end)

      # Return core as one cluster, each outlier as its own cluster
      core_cluster = Enum.map(core_cities, & &1.id)
      outlier_clusters = Enum.map(outlier_cities, fn city -> [city.id] end)

      [core_cluster | outlier_clusters] |> Enum.reject(&Enum.empty?/1)
    end
  end
end
