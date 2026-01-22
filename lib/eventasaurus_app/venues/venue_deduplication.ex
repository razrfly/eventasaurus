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
        |> Enum.filter(fn %{similarity_score: score} -> score >= min_similarity end)
        |> Enum.sort_by(fn %{similarity_score: score} -> score end, :desc)
        |> Enum.take(limit)

      {:ok, duplicates}
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
        preload: [:city]
      )

    base_query =
      if city_id do
        from(v in base_query, where: v.city_id == ^city_id)
      else
        base_query
      end

    venues = Repo.all(base_query)

    # Add event counts
    Enum.map(venues, fn venue ->
      Map.put(venue, :event_count, count_events(venue.id))
    end)
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
end
