defmodule EventasaurusApp.Venues.DuplicateDetection do
  @moduledoc """
  Unified duplicate detection logic for venues.

  This module provides a single source of truth for determining whether a venue
  is a duplicate based on GPS coordinates and name similarity.

  ## Strategy

  Uses distance-based similarity thresholds with token-based name matching:
  - < 50m: 0.0 similarity required (same location = same venue, coordinates authoritative)
  - 50-100m: 0.4 similarity required (very close = low bar)
  - 100-200m: 0.5 similarity required (nearby = moderate bar)
  - > 200m: 0.6 similarity required (distant = high bar)

  ## Search Radius

  Searches for potential duplicates within 3000m (3km) radius to handle geocoding
  variations between different providers. For example, Cinema City venues can be
  geocoded 2945m apart by different providers (Photon, HERE, Mapbox) but are
  actually the same physical location.

  ## Name Matching Algorithm

  Uses `VenueNameMatcher` with token-based Jaccard similarity:
  1. Extracts significant tokens (removes stop words like "kraków", "cinema", "galeria")
  2. Calculates Jaccard similarity: |A ∩ B| / |A ∪ B|
  3. Adds +20% bonus for any shared significant location token
  4. Returns score between 0.0 (no match) and 1.0 (perfect match)

  This algorithm correctly handles venue naming variations like:
  - "Cinema City Kazimierz" vs "Kraków - Galeria Kazimierz" → 100% match
  - "Cinema City Bonarka" vs "Kraków - Bonarka" → 100% match

  While correctly rejecting false positives:
  - "Cinema City Kazimierz" vs "Nalej Se" (bar nearby) → 0% match

  ## Rationale

  Physical proximity is stronger evidence than name matching. If two venues are at
  the exact same coordinates, they're the same venue regardless of name differences
  (which could be due to UI text, translations, rebranding, typos, etc.).

  ## Configuration

  Thresholds can be overridden via environment variables:
  - VENUE_DUPLICATE_DISTANCE_TIGHT (default: 50)
  - VENUE_DUPLICATE_DISTANCE_CLOSE (default: 100)
  - VENUE_DUPLICATE_DISTANCE_NEARBY (default: 200)
  - VENUE_DUPLICATE_SIMILARITY_TIGHT (default: 0.0)
  - VENUE_DUPLICATE_SIMILARITY_CLOSE (default: 0.4)
  - VENUE_DUPLICATE_SIMILARITY_NEARBY (default: 0.5)
  - VENUE_DUPLICATE_SIMILARITY_DISTANT (default: 0.6)
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.VenueNameMatcher
  require Logger

  # Distance thresholds in meters
  @distance_tight 50
  @distance_close 100
  @distance_nearby 200

  # Name similarity thresholds (0.0 = completely different, 1.0 = identical)
  # Updated to match VenueNameMatcher's token-based algorithm expectations
  @similarity_tight 0.0
  @similarity_close 0.4
  @similarity_nearby 0.5
  @similarity_distant 0.6

  @doc """
  Finds an existing venue that would be considered a duplicate of the given attributes.

  Returns the closest matching venue or nil if no duplicate found.

  ## Parameters
  - attrs: Map with :latitude, :longitude, :name, and :city_id keys

  ## Examples

      find_duplicate(%{
        latitude: 52.2363,
        longitude: 21.00642,
        name: "Piętro Niżej",
        city_id: 1
      })
      # Returns: %Venue{} or nil
  """
  def find_duplicate(%{latitude: lat, longitude: lng, name: name, city_id: city_id} = _attrs)
      when is_number(lat) and is_number(lng) and is_binary(name) and not is_nil(city_id) do
    # Find all venues within maximum search distance using PostGIS
    # Using 3000m (3km) radius to handle geocoding variations between different providers
    # (e.g., Cinema City venues geocoded 2945m apart but are the same physical location)
    nearby_venues = find_nearby_venues_postgis(lat, lng, city_id, 3000)

    # Filter by distance-based similarity threshold and return closest match
    nearby_venues
    |> Enum.filter(fn venue ->
      distance = venue.distance
      similarity = calculate_name_similarity(venue.name, name)
      required_similarity = get_similarity_threshold_for_distance(distance)

      similarity >= required_similarity
    end)
    |> Enum.min_by(& &1.distance, fn -> nil end)
  end

  def find_duplicate(_attrs), do: nil

  @doc """
  Checks if a venue would be a duplicate based on coordinates and name similarity.

  Returns {:ok, nil} if no duplicate found, or {:error, reason, opts} with duplicate details.

  ## Parameters
  - attrs: Map with :latitude, :longitude, and :name keys

  ## Examples

      check_duplicate(%{latitude: 51.5074, longitude: -0.1278, name: "The Red Lion"})
      # Returns: {:ok, nil} or {:error, "Duplicate venue found: ...", existing_id: 123}
  """
  def check_duplicate(%{latitude: lat, longitude: lng, name: name, city_id: city_id} = _attrs)
      when is_number(lat) and is_number(lng) and is_binary(name) do
    case find_duplicate(%{latitude: lat, longitude: lng, name: name, city_id: city_id}) do
      nil ->
        {:ok, nil}

      venue ->
        similarity = calculate_name_similarity(venue.name, name)

        {:error,
         "Duplicate venue found: '#{venue.name}' " <>
           "(#{Float.round(venue.distance, 1)}m away, #{Float.round(similarity * 100, 1)}% similar, ID: #{venue.id})",
         existing_id: venue.id, distance: venue.distance, similarity: similarity}
    end
  end

  def check_duplicate(_attrs), do: {:ok, nil}

  @doc """
  Finds venues within maximum search distance of given coordinates using PostGIS.

  Returns venues with a virtual :distance field containing distance in meters.
  Uses ST_DWithin for efficient spatial queries with the GIST index.

  ## Parameters
  - latitude: Latitude coordinate
  - longitude: Longitude coordinate
  - city_id: City ID to search within
  - max_distance_meters: Maximum search radius (default: @distance_nearby)

  ## Returns
  List of venues with :distance field, ordered by proximity.
  """
  def find_nearby_venues_postgis(
        latitude,
        longitude,
        _city_id,
        max_distance_meters \\ @distance_nearby
      )
      when is_number(latitude) and is_number(longitude) do
    query = """
    SELECT
      id, name, address, latitude, longitude, slug,
      ST_Distance(
        ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography,
        ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
      ) as distance
    FROM venues
    WHERE latitude IS NOT NULL
      AND longitude IS NOT NULL
      AND ST_DWithin(
        ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography,
        ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
        $3
      )
    ORDER BY distance
    """

    # Note: city_id parameter kept for backwards compatibility but not used in query
    # GPS coordinates are absolute - duplicates should be detected regardless of city assignment
    case Repo.query(query, [latitude, longitude, max_distance_meters]) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Map.new()
          |> convert_keys_to_atoms()
        end)

      {:error, reason} ->
        Logger.error("PostGIS query failed: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Gets the similarity threshold required based on GPS distance.

  ## Distance Tiers
  - < 50m: 0.0 (same location = same venue, coordinates authoritative)
  - 50-100m: 0.4 (very close = low similarity OK)
  - 100-200m: 0.5 (nearby = moderate similarity required)
  - > 200m: 0.6 (distant = high similarity required)

  ## Examples

      get_similarity_threshold_for_distance(0)     # => 0.0
      get_similarity_threshold_for_distance(75)    # => 0.4
      get_similarity_threshold_for_distance(150)   # => 0.5
      get_similarity_threshold_for_distance(300)   # => 0.6
  """
  def get_similarity_threshold_for_distance(distance_meters) do
    distance_tight = get_config(:distance_tight, @distance_tight)
    distance_close = get_config(:distance_close, @distance_close)
    distance_nearby = get_config(:distance_nearby, @distance_nearby)

    similarity_tight = get_config(:similarity_tight, @similarity_tight)
    similarity_close = get_config(:similarity_close, @similarity_close)
    similarity_nearby = get_config(:similarity_nearby, @similarity_nearby)
    similarity_distant = get_config(:similarity_distant, @similarity_distant)

    cond do
      distance_meters < distance_tight -> similarity_tight
      distance_meters < distance_close -> similarity_close
      distance_meters < distance_nearby -> similarity_nearby
      true -> similarity_distant
    end
  end

  @doc """
  Calculates name similarity between two venue names using token-based matching.

  Uses `VenueNameMatcher` with Jaccard similarity:
  1. Extracts significant tokens (removes stop words)
  2. Calculates token overlap ratio
  3. Adds +20% bonus for shared location tokens
  4. Returns value between 0.0 (completely different) and 1.0 (identical)

  ## Examples

      calculate_name_similarity("Cinema City Kazimierz", "Kraków - Galeria Kazimierz")
      # Returns: 1.0 (100% match - shared "kazimierz" token)

      calculate_name_similarity("Cinema City Bonarka", "Kraków - Bonarka")
      # Returns: 1.0 (100% match - shared "bonarka" token)

      calculate_name_similarity("Cinema City Kazimierz", "Nalej Se")
      # Returns: 0.0 (0% match - no shared tokens)
  """
  def calculate_name_similarity(name1, name2)
      when is_binary(name1) and is_binary(name2) do
    VenueNameMatcher.similarity_score(name1, name2)
  end

  # Get configuration value from environment or use default
  defp get_config(:distance_tight, default),
    do: get_env_int("VENUE_DUPLICATE_DISTANCE_TIGHT", default)

  defp get_config(:distance_close, default),
    do: get_env_int("VENUE_DUPLICATE_DISTANCE_CLOSE", default)

  defp get_config(:distance_nearby, default),
    do: get_env_int("VENUE_DUPLICATE_DISTANCE_NEARBY", default)

  defp get_config(:similarity_tight, default),
    do: get_env_float("VENUE_DUPLICATE_SIMILARITY_TIGHT", default)

  defp get_config(:similarity_close, default),
    do: get_env_float("VENUE_DUPLICATE_SIMILARITY_CLOSE", default)

  defp get_config(:similarity_nearby, default),
    do: get_env_float("VENUE_DUPLICATE_SIMILARITY_NEARBY", default)

  defp get_config(:similarity_distant, default),
    do: get_env_float("VENUE_DUPLICATE_SIMILARITY_DISTANT", default)

  defp get_env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> String.to_integer(String.trim(value))
    end
  end

  defp get_env_float(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> String.to_float(String.trim(value))
    end
  end

  defp convert_keys_to_atoms(map) do
    map
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Map.new()
  end
end
