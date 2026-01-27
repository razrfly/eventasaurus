defmodule EventasaurusApp.Venues.VenueDeduplication do
  @moduledoc """
  Context module for venue deduplication operations.

  Provides:
  - Finding potential duplicates for a specific venue
  - Merging venue pairs with full audit trail
  - Managing exclusion pairs (venues marked as "not duplicates")
  - Searching venues for manual comparison
  """
  import Ecto.Query
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.{Venue, VenueMergeAudit, VenueDuplicateExclusion}
  alias EventasaurusDiscovery.Locations.VenueNameMatcher

  @default_distance_meters 2000
  @default_min_similarity 0.3

  # ===========================================================================
  # Finding Duplicates
  # ===========================================================================

  @doc """
  Finds potential duplicate venues for a given venue.

  Returns a list of maps with venue data and similarity metrics:
  - :venue - the potential duplicate venue
  - :similarity_score - name similarity (0.0 to 1.0)
  - :distance_meters - distance between venues in meters
  - :event_count - number of events at the venue

  Options:
  - :distance_meters - maximum distance to search (default: 2000)
  - :min_similarity - minimum name similarity score (default: 0.3)
  - :limit - maximum results (default: 20)
  """
  def find_duplicates_for_venue(venue_id, opts \\ []) do
    distance = Keyword.get(opts, :distance_meters, @default_distance_meters)
    min_similarity = Keyword.get(opts, :min_similarity, @default_min_similarity)
    limit = Keyword.get(opts, :limit, 20)

    with {:ok, venue} <- get_venue(venue_id) do
      candidates = find_candidates(venue, distance, limit * 3)
      excluded_ids = get_excluded_venue_ids(venue_id)

      duplicates =
        candidates
        |> Enum.reject(fn candidate -> candidate.id in excluded_ids end)
        |> Enum.map(fn candidate ->
          similarity = VenueNameMatcher.similarity_score(venue.name, candidate.name)
          distance_m = calculate_distance(venue, candidate)
          event_count = count_events(candidate.id)

          %{
            venue: candidate,
            similarity_score: similarity,
            distance_meters: distance_m,
            event_count: event_count
          }
        end)
        # Use distance-based thresholds (revised per Phase 1 audit - issue #3430)
        |> Enum.filter(fn %{similarity_score: score, distance_meters: dist} ->
          min_required =
            cond do
              dist && dist < 50 -> 0.30   # Close: require 30% similarity
              dist && dist < 100 -> 0.40  # Very close: require 40%
              dist && dist < 200 -> 0.45  # Nearby: require 45%
              true -> min_similarity      # Distant: use param (default 0.3)
            end

          score >= min_required
        end)
        |> Enum.sort_by(fn %{similarity_score: score} -> score end, :desc)
        |> Enum.take(limit)

      {:ok, duplicates}
    end
  end

  # ===========================================================================
  # City-Scoped Duplicates (for City Health Page)
  # ===========================================================================

  @doc """
  Finds potential duplicate venue groups within a city or metro area.

  Returns a list of duplicate groups, each containing:
  - :venues - list of venue structs in the group
  - :distances - map of {venue_id, venue_id} => distance_meters
  - :similarities - map of {venue_id, venue_id} => similarity_score
  - :confidence - aggregate confidence score (0.0 to 1.0)
  - :total_events - total events across all venues in group

  Options:
  - :distance_meters - maximum distance to search (default: 500)
  - :min_similarity - minimum name similarity score (default: 0.4)
  - :limit - maximum groups to return (default: 50)
  """
  @spec find_duplicates_for_city([integer()], keyword()) :: [map()]
  def find_duplicates_for_city(city_ids, opts \\ []) when is_list(city_ids) do
    max_distance = Keyword.get(opts, :distance_meters, 500)
    min_similarity = Keyword.get(opts, :min_similarity, 0.4)
    limit = Keyword.get(opts, :limit, 50)
    row_limit = Keyword.get(opts, :row_limit, 300)

    if Enum.empty?(city_ids) do
      []
    else
      groups =
        find_duplicate_pairs_for_city(city_ids, max_distance, min_similarity, row_limit)
        |> group_into_clusters()

      # Batch fetch event counts to avoid N+1 queries
      all_venue_ids =
        groups
        |> Enum.flat_map(fn group -> Enum.map(group.venues, & &1.id) end)
        |> Enum.uniq()

      event_counts_map = count_events_batch(all_venue_ids)

      groups
      |> Enum.map(&enrich_group_with_metrics(&1, event_counts_map))
      |> Enum.sort_by(& &1.confidence, :desc)
      |> Enum.take(limit)
    end
  end

  @doc """
  Finds potential duplicate venue PAIRS within a city (no transitive grouping).

  Unlike `find_duplicates_for_city/2`, this returns individual pairs with their
  own confidence scores. This avoids the "super-group" problem where A↔B and B↔C
  would incorrectly group A,B,C together even if A and C have nothing in common.

  Returns a list of pair maps:
  - :venue_a - first venue in the pair
  - :venue_b - second venue in the pair
  - :similarity - name similarity (0.0 to 1.0)
  - :distance - distance between venues in meters
  - :confidence - confidence score (0.0 to 1.0) based on similarity + distance
  - :event_count_a - events at venue_a
  - :event_count_b - events at venue_b

  Options:
  - :distance_meters - maximum distance to search (default: 500)
  - :min_similarity - minimum name similarity score (default: 0.4)
  - :limit - maximum pairs to return (default: 100)
  """
  @spec find_duplicate_pairs([integer()], keyword()) :: [map()]
  def find_duplicate_pairs(city_ids, opts \\ []) when is_list(city_ids) do
    max_distance = Keyword.get(opts, :distance_meters, 500)
    min_similarity = Keyword.get(opts, :min_similarity, 0.4)
    limit = Keyword.get(opts, :limit, 100)
    row_limit = Keyword.get(opts, :row_limit, 300)

    if Enum.empty?(city_ids) do
      []
    else
      pairs = find_duplicate_pairs_for_city(city_ids, max_distance, min_similarity, row_limit)

      # Batch fetch event counts to avoid N+1 queries
      all_venue_ids =
        pairs
        |> Enum.flat_map(fn pair -> [pair.venue1.id, pair.venue2.id] end)
        |> Enum.uniq()

      event_counts_map = count_events_batch(all_venue_ids)

      pairs
      |> Enum.map(&enrich_pair_with_metrics(&1, event_counts_map))
      |> Enum.sort_by(& &1.confidence, :desc)
      |> Enum.take(limit)
    end
  end

  # Enrich a pair with event counts and confidence score
  defp enrich_pair_with_metrics(pair, event_counts_map) do
    event_count_a = Map.get(event_counts_map, pair.venue1.id, 0)
    event_count_b = Map.get(event_counts_map, pair.venue2.id, 0)
    confidence = calculate_pair_confidence(pair.similarity, pair.distance)

    %{
      venue_a: Map.put(pair.venue1, :event_count, event_count_a),
      venue_b: Map.put(pair.venue2, :event_count, event_count_b),
      similarity: pair.similarity,
      distance: pair.distance,
      confidence: confidence,
      event_count_a: event_count_a,
      event_count_b: event_count_b
    }
  end

  # Calculate confidence score for a single pair based on similarity and distance
  defp calculate_pair_confidence(similarity, distance) do
    # Distance weight: closer venues get higher confidence boost
    distance_weight =
      cond do
        distance < 20 -> 1.0    # Same building
        distance < 50 -> 0.95   # Very close
        distance < 100 -> 0.85  # Close
        distance < 200 -> 0.70  # Nearby
        distance < 500 -> 0.50  # In area
        true -> 0.30            # Distant
      end

    # Base confidence from similarity, boosted by proximity
    # High similarity (>0.6) with close distance = high confidence
    # Low similarity (<0.4) with any distance = low confidence
    base = similarity * 0.7 + distance_weight * 0.3

    # Clamp to 0.0-1.0
    min(1.0, max(0.0, base))
  end

  @doc """
  Calculates duplicate venue metrics for a city or metro area using PAIR-based detection.

  Returns a map with:
  - :pair_count - number of distinct duplicate pairs
  - :unique_venue_count - number of unique venues involved in pairs
  - :affected_events - approximate count of events across duplicate venues
  - :high_confidence_count - pairs with confidence >= 0.8
  - :medium_confidence_count - pairs with confidence 0.5-0.8
  - :low_confidence_count - pairs with confidence < 0.5
  - :severity - :critical, :warning, or :healthy based on impact
  - :duplicate_pairs - list of enriched pair maps for display

  Options:
  - :distance_meters - maximum distance to search (default: 500)
  - :min_similarity - minimum name similarity score (default: 0.4)
  """
  @spec calculate_duplicate_metrics([integer()], keyword()) :: map()
  def calculate_duplicate_metrics(city_ids, opts \\ []) when is_list(city_ids) do
    # Get duplicate pairs (limit configurable via :limit opt, defaults to 100 per find_duplicate_pairs)
    pairs = find_duplicate_pairs(city_ids, opts)

    if Enum.empty?(pairs) do
      %{
        pair_count: 0,
        unique_venue_count: 0,
        affected_events: 0,
        high_confidence_count: 0,
        medium_confidence_count: 0,
        low_confidence_count: 0,
        severity: :healthy,
        duplicate_pairs: [],
        # Legacy fields for backwards compatibility
        duplicate_count: 0,
        duplicate_groups_count: 0,
        duplicate_groups: []
      }
    else
      # Count unique venues in pairs
      all_venue_ids =
        pairs
        |> Enum.flat_map(fn p -> [p.venue_a.id, p.venue_b.id] end)
        |> Enum.uniq()

      unique_venue_count = length(all_venue_ids)

      # Sum affected events
      affected_events = Enum.sum(Enum.map(pairs, fn p -> p.event_count_a + p.event_count_b end))

      # Categorize by confidence
      {high, medium, low} =
        Enum.reduce(pairs, {0, 0, 0}, fn pair, {h, m, l} ->
          cond do
            pair.confidence >= 0.8 -> {h + 1, m, l}
            pair.confidence >= 0.5 -> {h, m + 1, l}
            true -> {h, m, l + 1}
          end
        end)

      # Determine severity based on impact
      severity =
        cond do
          high >= 5 or affected_events >= 100 -> :critical
          high >= 2 or unique_venue_count >= 10 -> :warning
          true -> :healthy
        end

      %{
        pair_count: length(pairs),
        unique_venue_count: unique_venue_count,
        affected_events: affected_events,
        high_confidence_count: high,
        medium_confidence_count: medium,
        low_confidence_count: low,
        severity: severity,
        duplicate_pairs: pairs,
        # Legacy fields for backwards compatibility
        duplicate_count: unique_venue_count,
        duplicate_groups_count: length(pairs),
        duplicate_groups: []
      }
    end
  end

  # Find duplicate pairs within specified cities using PostGIS
  defp find_duplicate_pairs_for_city(city_ids, max_distance, min_similarity, row_limit) do
    # Pass city_ids list directly - Postgrex will encode it as int[]
    city_ids_array = city_ids

    # Query for venue pairs in the specified cities
    query = """
    WITH venue_pairs AS (
      SELECT
        v1.id as id1,
        v1.name as name1,
        v1.address as address1,
        v1.latitude as lat1,
        v1.longitude as lng1,
        v1.slug as slug1,
        v1.city_id as city_id1,
        v2.id as id2,
        v2.name as name2,
        v2.address as address2,
        v2.latitude as lat2,
        v2.longitude as lng2,
        v2.slug as slug2,
        v2.city_id as city_id2,
        ST_Distance(
          ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
          ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography
        ) as distance,
        similarity(v1.name, v2.name) as name_similarity
      FROM venues v1
      INNER JOIN venues v2 ON v1.id < v2.id
      WHERE v1.city_id = ANY($1::int[])
        AND v2.city_id = ANY($1::int[])
        AND v1.latitude IS NOT NULL
        AND v1.longitude IS NOT NULL
        AND v2.latitude IS NOT NULL
        AND v2.longitude IS NOT NULL
        AND NOT (v1.latitude = v2.latitude AND v1.longitude = v2.longitude)
        AND ST_DWithin(
          ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
          ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography,
          $2
        )
        -- Exclude pairs marked as "not duplicates" (issue #3431)
        AND NOT EXISTS (
          SELECT 1 FROM venue_duplicate_exclusions e
          WHERE (e.venue_id_1 = v1.id AND e.venue_id_2 = v2.id)
             OR (e.venue_id_1 = v2.id AND e.venue_id_2 = v1.id)
        )
    )
    SELECT * FROM venue_pairs
    WHERE
      -- Distance-based similarity thresholds (revised per Phase 1 audit - issue #3430)
      CASE
        WHEN distance < 50 THEN name_similarity >= 0.30  -- Close: require 30% similarity
        WHEN distance < 100 THEN name_similarity >= 0.40 -- Very close: require 40%
        WHEN distance < 200 THEN name_similarity >= 0.45 -- Nearby: require 45%
        ELSE name_similarity >= $3                       -- Distant: use min_similarity param
      END
    ORDER BY name_similarity DESC, distance ASC
    LIMIT $4
    """

    case Repo.query(query, [city_ids_array, max_distance, min_similarity, row_limit]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn row ->
          [
            id1,
            name1,
            addr1,
            lat1,
            lng1,
            slug1,
            city_id1,
            id2,
            name2,
            addr2,
            lat2,
            lng2,
            slug2,
            city_id2,
            distance,
            name_similarity
          ] = row

          %{
            venue1: %Venue{
              id: id1,
              name: name1,
              address: addr1,
              latitude: lat1,
              longitude: lng1,
              slug: slug1,
              city_id: city_id1
            },
            venue2: %Venue{
              id: id2,
              name: name2,
              address: addr2,
              latitude: lat2,
              longitude: lng2,
              slug: slug2,
              city_id: city_id2
            },
            distance: distance,
            similarity: name_similarity
          }
        end)

      {:error, error} ->
        Logger.error("Failed to find duplicate pairs for city: #{inspect(error)}")
        []
    end
  end

  # Group pairs into connected clusters using union-find algorithm
  defp group_into_clusters(pairs) do
    if Enum.empty?(pairs) do
      []
    else
      # Build adjacency map and collect metrics
      {adjacency, distances, similarities, venues_map} =
        Enum.reduce(pairs, {%{}, %{}, %{}, %{}}, fn pair, {adj, dist, sim, venues} ->
          v1 = pair.venue1
          v2 = pair.venue2

          adj =
            adj
            |> Map.update(v1.id, [v2.id], &[v2.id | &1])
            |> Map.update(v2.id, [v1.id], &[v1.id | &1])

          # Store with normalized key (smaller id first)
          key = if v1.id < v2.id, do: {v1.id, v2.id}, else: {v2.id, v1.id}
          dist = Map.put(dist, key, pair.distance)
          sim = Map.put(sim, key, pair.similarity)

          venues =
            venues
            |> Map.put(v1.id, v1)
            |> Map.put(v2.id, v2)

          {adj, dist, sim, venues}
        end)

      # Find connected components using DFS
      {groups, _visited} =
        Enum.reduce(Map.keys(adjacency), {[], MapSet.new()}, fn venue_id, {groups, visited} ->
          if MapSet.member?(visited, venue_id) do
            {groups, visited}
          else
            {component, visited} = dfs_collect(venue_id, adjacency, visited)

            group = %{
              venue_ids: component,
              venues: Enum.map(component, &Map.get(venues_map, &1)),
              distances: filter_map_by_keys(distances, component),
              similarities: filter_map_by_keys(similarities, component)
            }

            {[group | groups], visited}
          end
        end)

      groups
    end
  end

  # DFS to collect all connected venue IDs
  defp dfs_collect(start_id, adjacency, visited) do
    do_dfs([start_id], adjacency, visited, [])
  end

  defp do_dfs([], _adjacency, visited, collected) do
    {collected, visited}
  end

  defp do_dfs([current | rest], adjacency, visited, collected) do
    if MapSet.member?(visited, current) do
      do_dfs(rest, adjacency, visited, collected)
    else
      visited = MapSet.put(visited, current)
      neighbors = Map.get(adjacency, current, [])
      do_dfs(neighbors ++ rest, adjacency, visited, [current | collected])
    end
  end

  # Filter distance/similarity maps to only include keys for venues in the component
  defp filter_map_by_keys(map, venue_ids) do
    venue_set = MapSet.new(venue_ids)

    map
    |> Enum.filter(fn {{id1, id2}, _v} ->
      MapSet.member?(venue_set, id1) and MapSet.member?(venue_set, id2)
    end)
    |> Map.new()
  end

  # Enrich group with event counts and confidence score
  defp enrich_group_with_metrics(group, event_counts_map) do
    # Look up event counts from precomputed map
    venues_with_events =
      Enum.map(group.venues, fn venue ->
        event_count = Map.get(event_counts_map, venue.id, 0)
        Map.put(venue, :event_count, event_count)
      end)

    total_events = Enum.sum(Enum.map(venues_with_events, & &1.event_count))

    # Calculate confidence based on similarity and distance
    confidence = calculate_group_confidence(group)

    # Calculate average distance across all pairs
    avg_distance =
      if map_size(group.distances) > 0 do
        distances = Map.values(group.distances)
        Enum.sum(distances) / length(distances)
      else
        nil
      end

    %{
      venues: venues_with_events,
      distances: group.distances,
      similarities: group.similarities,
      confidence: confidence,
      total_events: total_events,
      avg_distance: avg_distance
    }
  end

  # Calculate confidence score for a duplicate group
  defp calculate_group_confidence(group) do
    if Enum.empty?(group.similarities) do
      0.0
    else
      # Average similarity weighted by closeness (closer = higher weight)
      weighted_scores =
        Enum.map(group.similarities, fn {key, similarity} ->
          distance = Map.get(group.distances, key, 500)

          # Weight: closer venues get higher weight
          distance_weight =
            cond do
              distance < 50 -> 1.0
              distance < 100 -> 0.9
              distance < 200 -> 0.7
              true -> 0.5
            end

          similarity * distance_weight
        end)

      avg_weighted = Enum.sum(weighted_scores) / length(weighted_scores)

      # Clamp to 0.0-1.0
      min(1.0, max(0.0, avg_weighted))
    end
  end

  defp find_candidates(venue, distance_meters, limit) do
    if venue.latitude && venue.longitude do
      # Use PostGIS for proximity search
      # Exclude venues with identical coordinates (geocoding fallback to city center)
      from(v in Venue,
        where: v.id != ^venue.id,
        where: v.city_id == ^venue.city_id,
        where:
          fragment(
            "ST_DWithin(ST_MakePoint(?, ?)::geography, ST_MakePoint(longitude, latitude)::geography, ?)",
            ^venue.longitude,
            ^venue.latitude,
            ^distance_meters
          ),
        where:
          fragment(
            "NOT (latitude = ? AND longitude = ?)",
            ^venue.latitude,
            ^venue.longitude
          ),
        limit: ^limit
      )
      |> Repo.all()
    else
      # Fallback to same city if no coordinates
      from(v in Venue,
        where: v.id != ^venue.id,
        where: v.city_id == ^venue.city_id,
        limit: ^limit
      )
      |> Repo.all()
    end
  end

  defp calculate_distance(%{latitude: lat1, longitude: lng1}, %{latitude: lat2, longitude: lng2})
       when not is_nil(lat1) and not is_nil(lng1) and not is_nil(lat2) and not is_nil(lng2) do
    # Haversine formula for distance in meters
    r = 6_371_000

    dlat = (lat2 - lat1) * :math.pi() / 180
    dlng = (lng2 - lng1) * :math.pi() / 180

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(lat1 * :math.pi() / 180) * :math.cos(lat2 * :math.pi() / 180) *
          :math.sin(dlng / 2) * :math.sin(dlng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    Float.round(r * c, 1)
  end

  defp calculate_distance(_, _), do: nil

  # ===========================================================================
  # Cities with Duplicates (for Admin Index Page)
  # ===========================================================================

  @doc """
  Gets all cities that have potential venue duplicates using strict criteria.

  Returns a list of flat maps, each containing:
  - :id - the city ID
  - :name - the city name
  - :slug - the city slug (used for navigation)
  - :duplicate_count - number of potential duplicate pairs

  Uses stricter criteria than city-level detection:
  - Distance: <100m (not 500m)
  - Similarity: >60% OR substring match (not 40%)

  Only returns cities with ≥1 duplicate pair, sorted by count descending.

  Options:
  - :distance_meters - max distance (default: 100)
  - :min_similarity - min name similarity (default: 0.6)
  """
  @spec get_cities_with_duplicates(keyword()) :: [map()]
  def get_cities_with_duplicates(opts \\ []) do
    max_distance = Keyword.get(opts, :distance_meters, 100)
    min_similarity = Keyword.get(opts, :min_similarity, 0.6)

    query = """
    WITH duplicate_pairs AS (
      SELECT
        LEAST(v1.city_id, v2.city_id) as city_id,
        v1.id as id1,
        v2.id as id2,
        ST_Distance(
          ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
          ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography
        ) as distance,
        similarity(v1.name, v2.name) as name_similarity,
        -- Check for substring match (either direction)
        (LOWER(v1.name) LIKE '%' || LOWER(v2.name) || '%' OR
         LOWER(v2.name) LIKE '%' || LOWER(v1.name) || '%') as is_substring_match
      FROM venues v1
      INNER JOIN venues v2 ON v1.id < v2.id AND v1.city_id = v2.city_id
      WHERE v1.latitude IS NOT NULL
        AND v1.longitude IS NOT NULL
        AND v2.latitude IS NOT NULL
        AND v2.longitude IS NOT NULL
        AND NOT (v1.latitude = v2.latitude AND v1.longitude = v2.longitude)
        AND ST_DWithin(
          ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
          ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography,
          $1
        )
        -- Exclude pairs marked as "not duplicates"
        AND NOT EXISTS (
          SELECT 1 FROM venue_duplicate_exclusions e
          WHERE (e.venue_id_1 = v1.id AND e.venue_id_2 = v2.id)
             OR (e.venue_id_1 = v2.id AND e.venue_id_2 = v1.id)
        )
    ),
    filtered_pairs AS (
      SELECT * FROM duplicate_pairs
      WHERE name_similarity >= $2 OR is_substring_match = true
    ),
    city_counts AS (
      SELECT city_id, COUNT(*) as pair_count
      FROM filtered_pairs
      GROUP BY city_id
      HAVING COUNT(*) > 0
    )
    SELECT c.id, c.name, c.slug, cc.pair_count
    FROM city_counts cc
    INNER JOIN cities c ON c.id = cc.city_id
    ORDER BY cc.pair_count DESC, c.name ASC
    """

    case Repo.query(query, [max_distance, min_similarity]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, name, slug, pair_count] ->
          %{
            id: id,
            name: name,
            slug: slug,
            duplicate_count: pair_count
          }
        end)

      {:error, error} ->
        Logger.error("Failed to get cities with duplicates: #{inspect(error)}")
        []
    end
  end

  @doc """
  Gets the total count of potential duplicate pairs across all cities.

  Uses the same strict criteria as get_cities_with_duplicates/1.
  """
  @spec get_total_duplicate_count(keyword()) :: integer()
  def get_total_duplicate_count(opts \\ []) do
    max_distance = Keyword.get(opts, :distance_meters, 100)
    min_similarity = Keyword.get(opts, :min_similarity, 0.6)

    query = """
    SELECT COUNT(*) FROM (
      SELECT v1.id
      FROM venues v1
      INNER JOIN venues v2 ON v1.id < v2.id AND v1.city_id = v2.city_id
      WHERE v1.latitude IS NOT NULL
        AND v1.longitude IS NOT NULL
        AND v2.latitude IS NOT NULL
        AND v2.longitude IS NOT NULL
        AND NOT (v1.latitude = v2.latitude AND v1.longitude = v2.longitude)
        AND ST_DWithin(
          ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
          ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography,
          $1
        )
        AND (similarity(v1.name, v2.name) >= $2
             OR LOWER(v1.name) LIKE '%' || LOWER(v2.name) || '%'
             OR LOWER(v2.name) LIKE '%' || LOWER(v1.name) || '%')
        AND NOT EXISTS (
          SELECT 1 FROM venue_duplicate_exclusions e
          WHERE (e.venue_id_1 = v1.id AND e.venue_id_2 = v2.id)
             OR (e.venue_id_1 = v2.id AND e.venue_id_2 = v1.id)
        )
    ) as pairs
    """

    case Repo.query(query, [max_distance, min_similarity]) do
      {:ok, %{rows: [[count]]}} -> count
      {:error, _} -> 0
    end
  end

  # ===========================================================================
  # Merging Venues
  # ===========================================================================

  @doc """
  Merges a source venue into a target venue with full audit trail.

  - Reassigns all events, public events, and groups from source to target
  - Merges provider_ids from source into target
  - Creates an audit record with source venue snapshot
  - Deletes the source venue

  Returns {:ok, %{target_venue: venue, audit: audit}} or {:error, reason}
  """
  def merge_venues(source_venue_id, target_venue_id, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    reason = Keyword.get(opts, :reason, "manual")
    similarity_score = Keyword.get(opts, :similarity_score)
    distance_meters = Keyword.get(opts, :distance_meters)

    Repo.transaction(fn ->
      with {:ok, source} <- get_venue(source_venue_id),
           {:ok, target} <- get_venue(target_venue_id),
           {:ok, counts} <- reassign_entities(source.id, target.id),
           {:ok, target} <- merge_provider_ids(source, target),
           {:ok, audit} <-
             create_audit_record(
               source,
               target,
               user_id,
               reason,
               similarity_score,
               distance_meters,
               counts
             ),
           {:ok, _} <- delete_venue(source) do
        Logger.info("""
        🔀 Merged venue #{source.id} (#{source.name}) into #{target.id} (#{target.name})
           Events: #{counts.events}, Public Events: #{counts.public_events}
           Audit ID: #{audit.id}
        """)

        %{target_venue: target, audit: audit}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp reassign_entities(source_id, target_id) do
    # Reassign events
    {events_count, _} =
      from(e in EventasaurusApp.Events.Event, where: e.venue_id == ^source_id)
      |> Repo.update_all(set: [venue_id: target_id])

    # Reassign public events
    {public_events_count, _} =
      from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent, where: pe.venue_id == ^source_id)
      |> Repo.update_all(set: [venue_id: target_id])

    # Reassign groups
    from(g in EventasaurusApp.Groups.Group, where: g.venue_id == ^source_id)
    |> Repo.update_all(set: [venue_id: target_id])

    # Reassign cached images
    from(ci in EventasaurusApp.Images.CachedImage,
      where: ci.entity_type == "venue" and ci.entity_id == ^source_id
    )
    |> Repo.update_all(set: [entity_id: target_id])

    {:ok, %{events: events_count, public_events: public_events_count}}
  end

  defp merge_provider_ids(source, target) do
    merged_ids = Map.merge(target.provider_ids || %{}, source.provider_ids || %{})

    target
    |> Venue.changeset(%{provider_ids: merged_ids})
    |> Repo.update()
  end

  defp create_audit_record(
         source,
         target,
         user_id,
         reason,
         similarity_score,
         distance_meters,
         counts
       ) do
    %VenueMergeAudit{}
    |> VenueMergeAudit.changeset(%{
      source_venue_id: source.id,
      target_venue_id: target.id,
      merged_by_user_id: user_id,
      merge_reason: reason,
      similarity_score: similarity_score,
      distance_meters: distance_meters,
      events_reassigned: counts.events,
      public_events_reassigned: counts.public_events,
      source_venue_snapshot: VenueMergeAudit.venue_snapshot(source)
    })
    |> Repo.insert()
  end

  defp delete_venue(venue) do
    Repo.delete(venue)
  end

  # ===========================================================================
  # Exclusions
  # ===========================================================================

  @doc """
  Marks two venues as "not duplicates".

  Creates an exclusion record that prevents them from showing up
  as potential duplicates in future searches.
  """
  def exclude_pair(venue_id_1, venue_id_2, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    reason = Keyword.get(opts, :reason)

    %VenueDuplicateExclusion{}
    |> VenueDuplicateExclusion.changeset(%{
      venue_id_1: venue_id_1,
      venue_id_2: venue_id_2,
      excluded_by_user_id: user_id,
      reason: reason
    })
    |> Repo.insert()
  end

  @doc """
  Checks if two venues have been excluded from duplicate matching.
  """
  def excluded?(venue_id_1, venue_id_2) do
    {id1, id2} = VenueDuplicateExclusion.normalize_pair(venue_id_1, venue_id_2)

    from(e in VenueDuplicateExclusion,
      where: e.venue_id_1 == ^id1 and e.venue_id_2 == ^id2
    )
    |> Repo.exists?()
  end

  @doc """
  Gets all venue IDs that have been excluded from matching with the given venue.
  """
  def get_excluded_venue_ids(venue_id) do
    from(e in VenueDuplicateExclusion,
      where: e.venue_id_1 == ^venue_id or e.venue_id_2 == ^venue_id,
      select:
        fragment(
          "CASE WHEN ? = ? THEN ? ELSE ? END",
          e.venue_id_1,
          ^venue_id,
          e.venue_id_2,
          e.venue_id_1
        )
    )
    |> Repo.all()
  end

  @doc """
  Removes an exclusion between two venues.
  """
  def remove_exclusion(venue_id_1, venue_id_2) do
    {id1, id2} = VenueDuplicateExclusion.normalize_pair(venue_id_1, venue_id_2)

    from(e in VenueDuplicateExclusion,
      where: e.venue_id_1 == ^id1 and e.venue_id_2 == ^id2
    )
    |> Repo.delete_all()
  end

  # ===========================================================================
  # Search
  # ===========================================================================

  @doc """
  Searches for venues by name with optional city filter.

  Returns venues with:
  - :event_count - number of events at the venue
  - :duplicate_count - number of potential duplicate pairs this venue appears in

  Options:
  - :city_id - filter to specific city
  - :limit - maximum results (default: 20)
  """
  def search_venues(query, opts \\ []) do
    city_id = Keyword.get(opts, :city_id)
    limit = Keyword.get(opts, :limit, 20)

    base_query =
      from(v in Venue,
        where: ilike(v.name, ^"%#{query}%"),
        order_by: [asc: v.name],
        limit: ^limit,
        preload: [:city_ref]
      )

    base_query =
      if city_id do
        from(v in base_query, where: v.city_id == ^city_id)
      else
        base_query
      end

    venues = Repo.all(base_query)
    venue_ids = Enum.map(venues, & &1.id)

    # Batch get duplicate counts for all venues
    duplicate_counts = get_duplicate_counts_batch(venue_ids)

    # Add event counts and duplicate counts
    Enum.map(venues, fn venue ->
      venue
      |> Map.put(:event_count, count_events(venue.id))
      |> Map.put(:duplicate_count, Map.get(duplicate_counts, venue.id, 0))
    end)
  end

  @doc """
  Gets the count of potential duplicate pairs for each venue in the list.

  Uses the same strict criteria as get_cities_with_duplicates:
  - Distance: <100m
  - Similarity: >60% OR substring match

  Returns a map of venue_id => duplicate_pair_count
  """
  @spec get_duplicate_counts_batch([integer()]) :: map()
  def get_duplicate_counts_batch([]), do: %{}

  def get_duplicate_counts_batch(venue_ids) do
    max_distance = 100
    min_similarity = 0.6

    query = """
    SELECT venue_id, COUNT(*) as pair_count FROM (
      SELECT v1.id as venue_id
      FROM venues v1
      INNER JOIN venues v2 ON v1.id < v2.id AND v1.city_id = v2.city_id
      WHERE v1.id = ANY($1::int[])
        AND v1.latitude IS NOT NULL
        AND v1.longitude IS NOT NULL
        AND v2.latitude IS NOT NULL
        AND v2.longitude IS NOT NULL
        AND NOT (v1.latitude = v2.latitude AND v1.longitude = v2.longitude)
        AND ST_DWithin(
          ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
          ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography,
          $2
        )
        AND (similarity(v1.name, v2.name) >= $3
             OR LOWER(v1.name) LIKE '%' || LOWER(v2.name) || '%'
             OR LOWER(v2.name) LIKE '%' || LOWER(v1.name) || '%')
        AND NOT EXISTS (
          SELECT 1 FROM venue_duplicate_exclusions e
          WHERE (e.venue_id_1 = v1.id AND e.venue_id_2 = v2.id)
             OR (e.venue_id_1 = v2.id AND e.venue_id_2 = v1.id)
        )

      UNION ALL

      SELECT v2.id as venue_id
      FROM venues v1
      INNER JOIN venues v2 ON v1.id < v2.id AND v1.city_id = v2.city_id
      WHERE v2.id = ANY($1::int[])
        AND v1.latitude IS NOT NULL
        AND v1.longitude IS NOT NULL
        AND v2.latitude IS NOT NULL
        AND v2.longitude IS NOT NULL
        AND NOT (v1.latitude = v2.latitude AND v1.longitude = v2.longitude)
        AND ST_DWithin(
          ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
          ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography,
          $2
        )
        AND (similarity(v1.name, v2.name) >= $3
             OR LOWER(v1.name) LIKE '%' || LOWER(v2.name) || '%'
             OR LOWER(v2.name) LIKE '%' || LOWER(v1.name) || '%')
        AND NOT EXISTS (
          SELECT 1 FROM venue_duplicate_exclusions e
          WHERE (e.venue_id_1 = v1.id AND e.venue_id_2 = v2.id)
             OR (e.venue_id_1 = v2.id AND e.venue_id_2 = v1.id)
        )
    ) as pairs
    GROUP BY venue_id
    """

    case Repo.query(query, [venue_ids, max_distance, min_similarity]) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [venue_id, count] -> {venue_id, count} end)

      {:error, error} ->
        Logger.error("Failed to get duplicate counts: #{inspect(error)}")
        %{}
    end
  end

  # ===========================================================================
  # Audit History
  # ===========================================================================

  @doc """
  Gets the merge history for a venue (as target).
  """
  def get_merge_history(venue_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(a in VenueMergeAudit,
      where: a.target_venue_id == ^venue_id,
      order_by: [desc: a.inserted_at],
      limit: ^limit,
      preload: [:merged_by_user]
    )
    |> Repo.all()
  end

  @doc """
  Gets recent merge audits across all venues.
  """
  def list_recent_merges(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(a in VenueMergeAudit,
      order_by: [desc: a.inserted_at],
      limit: ^limit,
      preload: [:target_venue, :merged_by_user]
    )
    |> Repo.all()
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp get_venue(id) do
    case Repo.get(Venue, id) do
      nil -> {:error, "Venue #{id} not found"}
      venue -> {:ok, venue}
    end
  end

  defp count_events(venue_id) do
    events =
      from(e in EventasaurusApp.Events.Event, where: e.venue_id == ^venue_id)
      |> Repo.aggregate(:count, :id)

    public_events =
      from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent, where: pe.venue_id == ^venue_id)
      |> Repo.aggregate(:count, :id)

    events + public_events
  end

  # Batch count events for multiple venues to avoid N+1 queries
  # Returns a map of venue_id => total_event_count
  defp count_events_batch([]), do: %{}

  defp count_events_batch(venue_ids) do
    # Count events from events table
    events_counts =
      from(e in EventasaurusApp.Events.Event,
        where: e.venue_id in ^venue_ids,
        group_by: e.venue_id,
        select: {e.venue_id, count(e.id)}
      )
      |> Repo.all()
      |> Map.new()

    # Count events from public_events table
    public_events_counts =
      from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
        where: pe.venue_id in ^venue_ids,
        group_by: pe.venue_id,
        select: {pe.venue_id, count(pe.id)}
      )
      |> Repo.all()
      |> Map.new()

    # Merge counts for each venue
    venue_ids
    |> Enum.map(fn venue_id ->
      events = Map.get(events_counts, venue_id, 0)
      public_events = Map.get(public_events_counts, venue_id, 0)
      {venue_id, events + public_events}
    end)
    |> Map.new()
  end
end
