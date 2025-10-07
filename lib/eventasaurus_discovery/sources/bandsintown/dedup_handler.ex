defmodule EventasaurusDiscovery.Sources.Bandsintown.DedupHandler do
  @moduledoc """
  Deduplication handler for Bandsintown concert events.

  Bandsintown is an international concert source (priority 80) that provides
  comprehensive artist/performer data. This handler ensures we don't create
  duplicates when the same concert is found in multiple sources.

  ## Deduplication Strategy

  1. **External ID**: Primary deduplication via `external_id`
  2. **Artist + Venue + Date**: Fuzzy matching for cross-source duplicates
  3. **GPS Coordinates**: Venue proximity matching (within 100m)

  ## Priority Handling

  - Bandsintown (80) > Karnet (60) for music events
  - Ticketmaster (90) > Bandsintown (80) for major concerts
  - Preserves higher priority source data, enriches with Bandsintown metadata
  """

  require Logger

  @doc """
  Check if a concert already exists from other sources.
  Uses fuzzy matching on artist name, date, and venue/GPS location.

  Returns {:duplicate, existing_event} or {:unique, nil}
  """
  def check_duplicate(event_data) do
    # Extract key fields for matching
    artist_name = normalize_artist_name(event_data[:title])
    date = event_data[:starts_at]
    venue_name = get_in(event_data, [:venue_data, :name])
    latitude = get_in(event_data, [:venue_data, :latitude])
    longitude = get_in(event_data, [:venue_data, :longitude])

    # Look for potential duplicates
    case find_similar_concert(artist_name, date, venue_name, latitude, longitude) do
      nil ->
        {:unique, nil}

      existing ->
        confidence = calculate_match_confidence(event_data, existing)

        if confidence > 0.8 do
          Logger.info("🔍 Found likely duplicate concert from other source: #{existing.title}")
          {:duplicate, existing}
        else
          {:unique, nil}
        end
    end
  end

  @doc """
  Enrich Bandsintown concert data with information from existing events.
  Since Bandsintown provides good artist/performer data, we can enhance
  events from lower-priority sources.
  """
  def enrich_event_data(event_data) do
    case check_duplicate(event_data) do
      {:duplicate, existing} ->
        # If higher priority source exists, skip
        # If lower priority source exists, update with Bandsintown data
        handle_duplicate(event_data, existing)

      {:unique, _} ->
        # Enrich with any additional artist/venue data
        enrich_with_partial_matches(event_data)
    end
  end

  defp find_similar_concert(artist_name, date, venue_name, latitude, longitude) do
    # TODO: Implement actual event lookup when Events module has the proper function
    # For now, external_id uniqueness is handled by database constraint

    # events = Events.list_events_by_date_range(
    #   DateTime.add(date, -86400, :second),  # 1 day before
    #   DateTime.add(date, 86400, :second)    # 1 day after
    # )

    # Temporary - no cross-source deduplication until we have proper event lookup
    events = []

    Enum.find(events, fn event ->
      artist_match = similar_artist?(artist_name, event.title)
      venue_match = venue_name && similar_venue?(venue_name, event.venue_name)
      location_match = latitude && longitude && nearby_location?(latitude, longitude, event)

      artist_match && (venue_match || location_match || same_date?(date, event.starts_at))
    end)
  rescue
    _ -> nil
  end

  defp calculate_match_confidence(bandsintown_event, existing_event) do
    scores = []

    # Artist name similarity (40% weight)
    scores =
      if similar_artist?(bandsintown_event[:title], existing_event.title) do
        [0.4 | scores]
      else
        scores
      end

    # Date match (25% weight)
    scores =
      if same_date?(bandsintown_event[:starts_at], existing_event.starts_at) do
        [0.25 | scores]
      else
        scores
      end

    # Venue name match (20% weight)
    venue_name = get_in(bandsintown_event, [:venue_data, :name])

    scores =
      if venue_name && similar_venue?(venue_name, existing_event.venue_name) do
        [0.2 | scores]
      else
        scores
      end

    # GPS proximity match (15% weight)
    latitude = get_in(bandsintown_event, [:venue_data, :latitude])
    longitude = get_in(bandsintown_event, [:venue_data, :longitude])

    scores =
      if latitude && longitude && nearby_location?(latitude, longitude, existing_event) do
        [0.15 | scores]
      else
        scores
      end

    Enum.sum(scores)
  end

  defp handle_duplicate(bandsintown_data, existing) do
    # Compare priority scores
    # Ticketmaster (90) > Bandsintown (80) > Karnet (60)

    # For now, skip if duplicate exists
    # Future: enrich lower-priority events with Bandsintown performer data
    %{
      id: existing.id,
      action: :skip,
      reason: "Event already exists from another source",
      bandsintown_metadata: %{
        "bandsintown_url" => bandsintown_data[:source_url],
        "artist_name" => bandsintown_data[:title],
        "performer_data" => bandsintown_data[:performer]
      }
    }
  end

  defp normalize_artist_name(title) do
    title
    |> String.downcase()
    # Remove common suffixes like "at Venue Name"
    |> String.replace(~r/\s+at\s+.+$/i, "")
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
  end

  defp similar_artist?(artist1, artist2) do
    normalized1 = normalize_artist_name(artist1 || "")
    normalized2 = normalize_artist_name(artist2 || "")

    # Simple similarity check
    # In production, use Jaro-Winkler or similar algorithm
    normalized1 == normalized2 ||
      String.contains?(normalized1, normalized2) ||
      String.contains?(normalized2, normalized1)
  end

  defp similar_venue?(venue1, venue2) do
    cond do
      is_nil(venue1) || is_nil(venue2) ->
        false

      true ->
        normalized1 = String.downcase(String.trim(venue1))
        normalized2 = String.downcase(String.trim(venue2))

        normalized1 == normalized2 ||
          String.contains?(normalized1, normalized2) ||
          String.contains?(normalized2, normalized1)
    end
  end

  defp nearby_location?(lat1, lon1, event) do
    cond do
      is_nil(event.latitude) || is_nil(event.longitude) ->
        false

      true ->
        # Calculate distance using Haversine formula
        distance_meters = calculate_distance(lat1, lon1, event.latitude, event.longitude)

        # Consider venues within 100m as the same location
        distance_meters < 100
    end
  end

  defp calculate_distance(lat1, lon1, lat2, lon2) do
    # Haversine formula for great-circle distance
    r = 6371000  # Earth radius in meters

    lat1_rad = lat1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    delta_lat = (lat2 - lat1) * :math.pi() / 180
    delta_lon = (lon2 - lon1) * :math.pi() / 180

    a =
      :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(delta_lon / 2) * :math.sin(delta_lon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    r * c
  end

  defp same_date?(date1, date2) do
    cond do
      is_nil(date1) || is_nil(date2) ->
        false

      true ->
        # Check if same day (ignore time for concert matching)
        Date.compare(DateTime.to_date(date1), DateTime.to_date(date2)) == :eq
    end
  end

  defp enrich_with_partial_matches(event_data) do
    # For unique events, try to enrich with performer or venue data

    enriched = event_data

    # Bandsintown already provides good performer data
    enriched =
      if performer = event_data[:performer] do
        Map.put(enriched, :performer_enriched, true)
      else
        enriched
      end

    # Ensure GPS coordinates are present (Bandsintown usually has them)
    enriched =
      if venue_data = event_data[:venue_data] do
        enrich_venue_data(enriched, venue_data)
      else
        enriched
      end

    enriched
  end

  defp enrich_venue_data(event_data, venue_data) do
    # Bandsintown provides international venue data
    # Ensure all standard fields are present
    venue_data =
      Map.merge(
        %{
          timezone: "UTC",
          # Will be geocoded if coordinates missing
          needs_geocoding: is_nil(venue_data[:latitude]) || is_nil(venue_data[:longitude])
        },
        venue_data
      )

    Map.put(event_data, :venue_data, venue_data)
  end

  @doc """
  Validate event data quality before processing.
  Returns {:ok, event_data} or {:error, reason}
  """
  def validate_event_quality(event_data) do
    with :ok <- validate_required_fields(event_data),
         :ok <- validate_date_sanity(event_data),
         :ok <- validate_artist_data(event_data) do
      {:ok, event_data}
    else
      {:error, reason} ->
        Logger.warning("⚠️ Event quality validation failed: #{reason}")
        {:error, reason}
    end
  end

  defp validate_required_fields(event_data) do
    required = [:title, :external_id, :starts_at]

    missing =
      Enum.filter(required, fn field ->
        is_nil(event_data[field]) || event_data[field] == ""
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required fields: #{inspect(missing)}"}
    end
  end

  defp validate_date_sanity(event_data) do
    starts_at = event_data[:starts_at]

    cond do
      is_nil(starts_at) ->
        {:error, "No parsed date for event"}

      DateTime.compare(starts_at, DateTime.utc_now()) == :lt ->
        # Past event - skip
        {:error, "Event is in the past"}

      DateTime.compare(starts_at, DateTime.add(DateTime.utc_now(), 365 * 2, :day)) == :gt ->
        # More than 2 years in future - likely parsing error
        {:error, "Event date seems incorrect (>2 years in future)"}

      true ->
        :ok
    end
  end

  defp validate_artist_data(event_data) do
    # Bandsintown should always have artist/title data
    if event_data[:title] && String.length(event_data[:title]) > 0 do
      :ok
    else
      {:error, "Missing artist/title information"}
    end
  end
end
