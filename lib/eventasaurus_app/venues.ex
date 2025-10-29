defmodule EventasaurusApp.Venues do
  @moduledoc """
  The Venues context.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue

  @doc """
  Returns the list of venues.

  ## Options
  - `:type` - Filter venues by venue_type (e.g., "venue", "city", "region", "online", "tbd")
  - `:name` - Filter venues by name (case-insensitive partial match)

  ## Examples

      list_venues()
      list_venues(type: "venue")
      list_venues(type: "online", name: "zoom")
  """
  def list_venues(opts \\ []) do
    type = Keyword.get(opts, :type)
    name = Keyword.get(opts, :name)

    Venue
    |> venue_type_filter(type)
    |> venue_name_filter(name)
    |> Repo.all()
  end

  @doc """
  Gets a single venue.

  Raises `Ecto.NoResultsError` if the Venue does not exist.
  """
  def get_venue!(id), do: Repo.get!(Venue, id)

  @doc """
  Gets a single venue.

  Returns nil if the Venue does not exist.
  """
  def get_venue(id), do: Repo.get(Venue, id)

  @doc """
  Gets a single venue by slug.

  Raises `Ecto.NoResultsError` if the Venue does not exist.
  """
  def get_venue_by_slug!(slug) when is_binary(slug) do
    Repo.get_by!(Venue, slug: slug)
  end

  @doc """
  Lists related venues in the same city.

  Returns up to 6 venues from the same city, excluding the current venue.
  Prioritizes venues with images.

  ## Parameters
  - venue_id: The ID of the current venue
  - city_id: The city ID to find related venues in
  - limit: Maximum number of venues to return (default: 6)

  ## Examples

      iex> list_related_venues(123, 456)
      [%Venue{}, ...]
  """
  def list_related_venues(venue_id, city_id, limit \\ 6)
      when is_integer(venue_id) and is_integer(city_id) do
    from(v in Venue,
      where: v.city_id == ^city_id,
      where: v.id != ^venue_id,
      order_by: [
        desc: fragment("COALESCE(jsonb_array_length(?), 0)", v.venue_images),
        desc: v.id
      ],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Lists related venues in the same city with upcoming events count.

  Returns up to 6 venues from the same city with their upcoming events count,
  excluding the current venue. Prioritizes venues with images.

  Returns a list of maps with `:venue` and `:upcoming_events_count` keys,
  matching the format used by `list_city_venues/2`.

  ## Parameters
  - venue_id: The ID of the current venue
  - city_id: The city ID to find related venues in
  - limit: Maximum number of venues to return (default: 6)

  ## Examples

      iex> list_related_venues_with_events_count(123, 456)
      [
        %{venue: %Venue{}, upcoming_events_count: 5},
        %{venue: %Venue{}, upcoming_events_count: 3}
      ]
  """
  def list_related_venues_with_events_count(venue_id, city_id, limit \\ 6)
      when is_integer(venue_id) and is_integer(city_id) do
    from(v in Venue,
      left_join: pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
      on: pe.venue_id == v.id and pe.starts_at > ^DateTime.utc_now(),
      where: v.city_id == ^city_id,
      where: v.id != ^venue_id,
      group_by: v.id,
      order_by: [
        desc: fragment("COALESCE(jsonb_array_length(?), 0)", v.venue_images),
        desc: v.id
      ],
      limit: ^limit,
      select: %{
        venue: v,
        upcoming_events_count: count(pe.id)
      }
    )
    |> Repo.all()
  end

  @doc """
  Creates a venue.
  """
  def create_venue(attrs \\ %{}) do
    %Venue{}
    |> Venue.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a venue.
  """
  def update_venue(%Venue{} = venue, attrs) do
    venue
    |> Venue.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a venue.
  """
  def delete_venue(%Venue{} = venue) do
    Repo.delete(venue)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking venue changes.
  """
  def change_venue(%Venue{} = venue, attrs \\ %{}) do
    Venue.changeset(venue, attrs)
  end

  @doc """
  Returns the list of venues with name search.
  """
  def search_venues(name) do
    from(v in Venue, where: ilike(v.name, ^"%#{name}%"))
    |> Repo.all()
  end

  @doc """
  Lists venues filtered by venue type.
  """
  def list_venues_by_type(venue_type) when is_binary(venue_type) do
    list_venues(type: venue_type)
  end

  @doc """
  Lists all venues in a city with upcoming events count.

  Returns venues with a virtual field `:upcoming_events_count` for display.

  ## Options
  - `:search` - Search term for venue name or address
  - `:sort_by` - Sort order: `:name`, `:events_count`, `:id` (default: `:name`)
  - `:has_events` - Filter to only venues with upcoming events (default: false)
  - `:page` - Page number for pagination (default: 1)
  - `:page_size` - Number of venues per page (default: 30)

  ## Examples

      list_city_venues(123)
      list_city_venues(123, search: "theater", sort_by: :events_count)
  """
  def list_city_venues(city_id, opts \\ []) do
    search = Keyword.get(opts, :search)
    sort_by = Keyword.get(opts, :sort_by, :name)
    has_events = Keyword.get(opts, :has_events, false)

    page =
      opts
      |> Keyword.get(:page, 1)
      |> max(1)

    page_size =
      opts
      |> Keyword.get(:page_size, 30)
      |> max(1)

    offset = (page - 1) * page_size

    base_query =
      from(v in Venue,
        left_join: pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
        on: pe.venue_id == v.id and pe.starts_at > ^DateTime.utc_now(),
        where: v.city_id == ^city_id,
        group_by: v.id,
        select: %{
          venue: v,
          upcoming_events_count: count(pe.id)
        }
      )

    base_query
    |> maybe_search(search)
    |> maybe_filter_has_events(has_events)
    |> apply_sort(sort_by)
    |> limit(^page_size)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Counts total venues in a city.
  """
  def count_city_venues(city_id) do
    from(v in Venue, where: v.city_id == ^city_id, select: count(v.id))
    |> Repo.one()
  end

  @doc """
  Counts venues in a city with upcoming events.
  """
  def count_active_city_venues(city_id) do
    from(v in Venue,
      inner_join: pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
      on: pe.venue_id == v.id and pe.starts_at > ^DateTime.utc_now(),
      where: v.city_id == ^city_id,
      distinct: true,
      select: v.id
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets featured venue collections for a city.

  Returns a list of curated venue collections including:
  - Most Active: Venues with the most upcoming events
  - Best Documented: Venues with the most images
  - Recently Added: Newest venues

  Each collection includes up to 6 venues with their upcoming events count.

  ## Parameters
  - city_id: The city ID to get collections for
  - limit: Number of venues per collection (default: 6)

  ## Returns
  List of maps with:
  - `:name` - Collection name
  - `:description` - Collection description
  - `:slug` - URL-friendly collection identifier
  - `:venues` - List of venue data maps
  - `:icon` - Icon name for display

  ## Examples

      get_venue_collections(123)
      # Returns: [
      #   %{
      #     name: "Most Active Venues",
      #     description: "Venues hosting the most events",
      #     slug: "most-active",
      #     icon: "hero-fire",
      #     venues: [...]
      #   },
      #   ...
      # ]
  """
  def get_venue_collections(city_id, limit \\ 6) do
    [
      get_most_active_venues(city_id, limit),
      get_best_documented_venues(city_id, limit),
      get_recently_added_venues(city_id, limit)
    ]
    |> Enum.reject(fn collection -> Enum.empty?(collection.venues) end)
  end

  # Get venues with most upcoming events
  defp get_most_active_venues(city_id, limit) do
    venues =
      from(v in Venue,
        left_join: pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
        on: pe.venue_id == v.id and pe.starts_at > ^DateTime.utc_now(),
        where: v.city_id == ^city_id,
        group_by: v.id,
        having: count(pe.id) > 0,
        order_by: [desc: count(pe.id)],
        limit: ^limit,
        select: %{
          venue: v,
          upcoming_events_count: count(pe.id)
        }
      )
      |> Repo.all()

    %{
      name: "Most Active Venues",
      description: "Venues hosting the most upcoming events",
      slug: "most-active",
      icon: "hero-fire",
      venues: venues
    }
  end

  # Get venues with most images
  defp get_best_documented_venues(city_id, limit) do
    venues =
      from(v in Venue,
        left_join: pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
        on: pe.venue_id == v.id and pe.starts_at > ^DateTime.utc_now(),
        where: v.city_id == ^city_id,
        where: fragment("jsonb_array_length(?) > 0", v.venue_images),
        group_by: v.id,
        order_by: [desc: fragment("jsonb_array_length(?)", v.venue_images)],
        limit: ^limit,
        select: %{
          venue: v,
          upcoming_events_count: count(pe.id)
        }
      )
      |> Repo.all()

    %{
      name: "Best Documented Venues",
      description: "Venues with the best photo galleries",
      slug: "best-documented",
      icon: "hero-camera",
      venues: venues
    }
  end

  # Get most recently added venues
  defp get_recently_added_venues(city_id, limit) do
    venues =
      from(v in Venue,
        left_join: pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
        on: pe.venue_id == v.id and pe.starts_at > ^DateTime.utc_now(),
        where: v.city_id == ^city_id,
        group_by: v.id,
        order_by: [desc: v.inserted_at],
        limit: ^limit,
        select: %{
          venue: v,
          upcoming_events_count: count(pe.id)
        }
      )
      |> Repo.all()

    %{
      name: "Recently Added",
      description: "Newest venues added to our platform",
      slug: "recently-added",
      icon: "hero-sparkles",
      venues: venues
    }
  end

  # Private helpers for list_city_venues query building

  defp maybe_search(query, nil), do: query

  defp maybe_search(query, search_term) when is_binary(search_term) do
    search_pattern = "%#{search_term}%"

    from([v, pe] in query,
      where: ilike(v.name, ^search_pattern) or ilike(v.address, ^search_pattern)
    )
  end

  defp maybe_filter_has_events(query, false), do: query

  defp maybe_filter_has_events(query, true) do
    from([v, pe] in query,
      having: count(pe.id) > 0
    )
  end

  defp apply_sort(query, :name) do
    from([v, _pe] in query,
      order_by: [asc: v.name]
    )
  end

  defp apply_sort(query, :events_count) do
    from([v, pe] in query,
      order_by: [desc: count(pe.id), asc: v.name]
    )
  end

  defp apply_sort(query, :id) do
    from([v, _pe] in query,
      order_by: [desc: v.id]
    )
  end

  defp apply_sort(query, _), do: apply_sort(query, :name)

  # Private helper functions for query filtering

  defp venue_type_filter(query, nil), do: query

  defp venue_type_filter(query, type) when is_binary(type) do
    from(v in query, where: v.venue_type == ^type)
  end

  defp venue_name_filter(query, nil), do: query

  defp venue_name_filter(query, name) when is_binary(name) do
    from(v in query, where: ilike(v.name, ^"%#{name}%"))
  end

  @doc """
  Finds a venue by address.
  Returns nil if no venue with the given address exists.
  """
  def find_venue_by_address(address) when is_binary(address) do
    Repo.get_by(Venue, address: address)
  end

  def find_venue_by_address(_), do: nil

  # Duplicate Detection Functions (Phase 1)

  @doc """
  Finds venues within a specified distance of given coordinates.

  Uses PostGIS ST_DWithin with the existing GIST spatial index for efficient queries.

  ## Parameters
  - `latitude` - Latitude coordinate
  - `longitude` - Longitude coordinate
  - `distance_meters` - Search radius in meters (default: 100)

  ## Returns
  List of venues within the specified distance, ordered by proximity.

  ## Examples

      find_nearby_venues(51.5074, -0.1278, 100)
  """
  def find_nearby_venues(latitude, longitude, distance_meters \\ nil)
      when is_number(latitude) and is_number(longitude) do
    distance = distance_meters || get_distance_threshold()

    query = """
    SELECT id, name, address, latitude, longitude, slug,
           ST_Distance(
             ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography,
             ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
           ) as distance
    FROM venues
    WHERE ST_DWithin(
      ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography,
      ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
      $3
    )
    ORDER BY distance
    """

    case Repo.query(query, [latitude, longitude, distance]) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Map.new()
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Calculates name similarity between two venue names using PostgreSQL trigram similarity.

  Returns a value between 0.0 (completely different) and 1.0 (identical).

  ## Examples

      calculate_name_similarity("The Red Lion", "Red Lion Pub")
      # Returns: ~0.65
  """
  def calculate_name_similarity(name1, name2)
      when is_binary(name1) and is_binary(name2) do
    query = "SELECT similarity($1, $2) as score"

    case Repo.query(query, [name1, name2]) do
      {:ok, %{rows: [[score]]}} -> score
      {:error, _} -> 0.0
    end
  end

  @doc """
  Checks if a venue would be a duplicate based on coordinates and name similarity.

  Returns `{:ok, nil}` if no duplicate found, or `{:error, reason}` with duplicate details.

  ## Parameters
  - `attrs` - Map with `:latitude`, `:longitude`, and `:name` keys

  ## Examples

      check_duplicate(%{latitude: 51.5074, longitude: -0.1278, name: "The Red Lion"})
      # Returns: {:ok, nil} or {:error, "Duplicate venue found: ..."}
  """
  def check_duplicate(%{latitude: lat, longitude: lng, name: name} = _attrs)
      when is_number(lat) and is_number(lng) and is_binary(name) do
    nearby_venues = find_nearby_venues(lat, lng)
    similarity_threshold = get_similarity_threshold()

    duplicate =
      Enum.find(nearby_venues, fn venue ->
        similarity = calculate_name_similarity(name, venue["name"])
        similarity >= similarity_threshold
      end)

    case duplicate do
      nil ->
        {:ok, nil}

      venue ->
        # Return error with venue ID in opts for structured extraction
        {:error,
         "Duplicate venue found: '#{venue["name"]}' at #{venue["address"]} " <>
           "(#{Float.round(venue["distance"], 1)}m away, ID: #{venue["id"]})",
         existing_id: venue["id"]}
    end
  end

  def check_duplicate(_attrs), do: {:ok, nil}

  @doc """
  Gets the distance threshold for duplicate detection from environment or default.

  Default: 100 meters
  """
  def get_distance_threshold do
    case System.get_env("VENUE_DUPLICATE_DISTANCE_METERS") do
      nil ->
        100

      value ->
        # Extract numeric value (trim and handle inline comments)
        value
        |> String.split("#")
        |> List.first()
        |> String.trim()
        |> String.to_integer()
    end
  end

  @doc """
  Gets the name similarity threshold for duplicate detection from environment or default.

  Default: 0.80 (80% similar)
  """
  def get_similarity_threshold do
    case System.get_env("VENUE_DUPLICATE_NAME_SIMILARITY") do
      nil ->
        0.80

      value ->
        # Extract numeric value (trim and handle inline comments)
        value
        |> String.split("#")
        |> List.first()
        |> String.trim()
        |> String.to_float()
    end
  end

  # Duplicate Management Functions (Phase 2)

  @doc """
  Finds groups of duplicate venues based on proximity and name similarity.

  Returns a list of duplicate groups, where each group contains venues that are
  considered duplicates of each other.

  ## Parameters
  - `distance_threshold` - Maximum distance in meters (default: 100)
  - `similarity_threshold` - Minimum name similarity 0.0-1.0 (default: 0.80)

  ## Returns
  List of maps with:
  - `:venues` - List of duplicate venue structs in the group
  - `:distances` - Map of venue ID pairs to distances
  - `:similarities` - Map of venue ID pairs to name similarities

  ## Examples

      find_duplicate_groups()
      # Returns: [
      #   %{
      #     venues: [%Venue{id: 403, ...}, %Venue{id: 331, ...}, %Venue{id: 401, ...}],
      #     distances: %{{403, 331} => 4.2, {403, 401} => 11.0, {331, 401} => 12.5},
      #     similarities: %{{403, 331} => 1.0, {403, 401} => 1.0, {331, 401} => 1.0}
      #   }
      # ]
  """
  def find_duplicate_groups(distance_threshold \\ nil, similarity_threshold \\ nil) do
    distance = distance_threshold || get_distance_threshold()
    similarity = similarity_threshold || get_similarity_threshold()

    # Use a single optimized SQL query to find all duplicate pairs at once
    # This replaces the O(n²) nested loop with n²/2 database queries
    query = """
    SELECT
      v1.id as id1,
      v1.name as name1,
      v1.address as address1,
      v1.latitude as lat1,
      v1.longitude as lng1,
      v1.slug as slug1,
      v1.provider_ids as provider_ids1,
      v1.venue_images as venue_images1,
      v2.id as id2,
      v2.name as name2,
      v2.address as address2,
      v2.latitude as lat2,
      v2.longitude as lng2,
      v2.slug as slug2,
      v2.provider_ids as provider_ids2,
      v2.venue_images as venue_images2,
      ST_Distance(
        ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
        ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography
      ) as distance,
      similarity(v1.name, v2.name) as name_similarity
    FROM venues v1
    INNER JOIN venues v2 ON v1.id < v2.id
    WHERE v1.latitude IS NOT NULL
      AND v1.longitude IS NOT NULL
      AND v2.latitude IS NOT NULL
      AND v2.longitude IS NOT NULL
      AND ST_DWithin(
        ST_SetSRID(ST_MakePoint(v1.longitude, v1.latitude), 4326)::geography,
        ST_SetSRID(ST_MakePoint(v2.longitude, v2.latitude), 4326)::geography,
        $1
      )
      AND similarity(v1.name, v2.name) >= $2
    """

    case Repo.query(query, [distance, similarity]) do
      {:ok, %{rows: rows}} ->
        # Convert query results to venue structs and similarity data
        {duplicate_pairs, venues_map} =
          Enum.reduce(rows, {[], %{}}, fn row, {pairs, venues} ->
            [
              id1,
              name1,
              addr1,
              lat1,
              lng1,
              slug1,
              pids1,
              imgs1,
              id2,
              name2,
              addr2,
              lat2,
              lng2,
              slug2,
              pids2,
              imgs2,
              distance,
              name_similarity
            ] = row

            v1 = %Venue{
              id: id1,
              name: name1,
              address: addr1,
              latitude: lat1,
              longitude: lng1,
              slug: slug1,
              provider_ids: pids1,
              venue_images: imgs1
            }

            v2 = %Venue{
              id: id2,
              name: name2,
              address: addr2,
              latitude: lat2,
              longitude: lng2,
              slug: slug2,
              provider_ids: pids2,
              venue_images: imgs2
            }

            venues =
              venues
              |> Map.put(id1, v1)
              |> Map.put(id2, v2)

            pairs = [{v1, v2, name_similarity, distance} | pairs]

            {pairs, venues}
          end)

        # Group connected venues (transitive closure)
        group_connected_venues_optimized(duplicate_pairs, venues_map)

      {:error, _} ->
        []
    end
  end

  # Optimized version that uses pre-calculated distances and similarities
  defp group_connected_venues_optimized(duplicate_pairs, venues_map) do
    # Build adjacency map and store distances/similarities
    {adjacency, distances_map, similarities_map} =
      Enum.reduce(duplicate_pairs, {%{}, %{}, %{}}, fn {v1, v2, similarity, distance},
                                                       {adj, dist, sim} ->
        adj =
          adj
          |> Map.update(v1.id, [v2.id], &[v2.id | &1])
          |> Map.update(v2.id, [v1.id], &[v1.id | &1])

        dist = Map.put(dist, {v1.id, v2.id}, distance)
        sim = Map.put(sim, {v1.id, v2.id}, similarity)

        {adj, dist, sim}
      end)

    # Find connected components using DFS
    {groups, _visited} =
      Enum.reduce(Map.keys(adjacency), {[], MapSet.new()}, fn venue_id, {groups, visited} ->
        if MapSet.member?(visited, venue_id) do
          {groups, visited}
        else
          {group, new_visited} = dfs_component(venue_id, adjacency, visited)
          {[group | groups], new_visited}
        end
      end)

    # Convert venue IDs to venue structs with pre-calculated metrics
    Enum.map(groups, fn venue_ids ->
      group_venues = Enum.map(venue_ids, fn id -> Map.get(venues_map, id) end)

      # Extract distances and similarities for this group
      {distances, similarities} =
        for v1_id <- venue_ids,
            v2_id <- venue_ids,
            v1_id < v2_id,
            reduce: {%{}, %{}} do
          {dist_acc, sim_acc} ->
            dist = Map.get(distances_map, {v1_id, v2_id})
            sim = Map.get(similarities_map, {v1_id, v2_id})

            {
              if(dist, do: Map.put(dist_acc, {v1_id, v2_id}, dist), else: dist_acc),
              if(sim, do: Map.put(sim_acc, {v1_id, v2_id}, sim), else: sim_acc)
            }
        end

      %{
        venues: group_venues,
        distances: distances,
        similarities: similarities
      }
    end)
    |> Enum.sort_by(fn group -> length(group.venues) end, :desc)
  end

  # Depth-first search to find connected component
  defp dfs_component(venue_id, adjacency, visited) do
    if MapSet.member?(visited, venue_id) do
      {[], visited}
    else
      visited = MapSet.put(visited, venue_id)
      neighbors = Map.get(adjacency, venue_id, [])

      Enum.reduce(neighbors, {[venue_id], visited}, fn neighbor_id, {component, vis} ->
        {neighbor_component, new_vis} = dfs_component(neighbor_id, adjacency, vis)
        {component ++ neighbor_component, new_vis}
      end)
    end
  end

  @doc """
  Merges duplicate venues into a single primary venue.

  This operation:
  1. Reassigns all events, public_events, and groups to the primary venue
  2. Merges provider_ids from duplicate venues into primary
  3. Merges venue_images from duplicate venues into primary
  4. Deletes the duplicate venues
  5. All operations are atomic (transaction with rollback on failure)

  ## Parameters
  - `primary_venue_id` - The venue ID to keep (all data merges here)
  - `duplicate_venue_ids` - List of venue IDs to merge and delete

  ## Returns
  - `{:ok, primary_venue}` - Successfully merged
  - `{:error, reason}` - Merge failed (transaction rolled back)

  ## Examples

      merge_venues(403, [331, 401])
      # Merges venues 331 and 401 into venue 403
  """
  def merge_venues(primary_venue_id, duplicate_venue_ids) when is_list(duplicate_venue_ids) do
    Repo.transaction(fn ->
      # Get primary venue
      primary = Repo.get(Venue, primary_venue_id)

      if is_nil(primary) do
        Repo.rollback("Primary venue not found")
      end

      # Get duplicate venues
      duplicates =
        from(v in Venue, where: v.id in ^duplicate_venue_ids)
        |> Repo.all()

      if length(duplicates) != length(duplicate_venue_ids) do
        Repo.rollback("Some duplicate venues not found")
      else
        # 1. Reassign events
        from(e in EventasaurusApp.Events.Event, where: e.venue_id in ^duplicate_venue_ids)
        |> Repo.update_all(set: [venue_id: primary_venue_id])

        # 2. Reassign public_events
        from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
          where: pe.venue_id in ^duplicate_venue_ids
        )
        |> Repo.update_all(set: [venue_id: primary_venue_id])

        # 3. Reassign groups (if any)
        from(g in EventasaurusApp.Groups.Group, where: g.venue_id in ^duplicate_venue_ids)
        |> Repo.update_all(set: [venue_id: primary_venue_id])

        # 4. Merge provider_ids
        merged_provider_ids =
          Enum.reduce(duplicates, primary.provider_ids || %{}, fn dup, acc ->
            Map.merge(acc, dup.provider_ids || %{})
          end)

        # 5. Merge venue_images (deduplicate by URL)
        merged_images =
          ([primary.venue_images || []] ++
             Enum.flat_map(duplicates, fn dup -> dup.venue_images || [] end))
          |> Enum.uniq_by(fn img -> img["url"] end)

        # 6. Update primary venue with merged data
        primary
        |> Venue.changeset(%{
          provider_ids: merged_provider_ids,
          venue_images: merged_images
        })
        |> Repo.update!()

        # 7. Delete duplicate venues
        from(v in Venue, where: v.id in ^duplicate_venue_ids)
        |> Repo.delete_all()

        # Return updated primary venue
        Repo.get!(Venue, primary_venue_id)
      end
    end)
  end
end
