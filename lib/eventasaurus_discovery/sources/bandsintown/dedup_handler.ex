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

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.Sources.BaseDedupHandler

  @doc """
  Check if a concert already exists from other sources.

  Two-phase deduplication strategy:
  - Phase 1: Check if THIS source already imported it (same-source dedup)
  - Phase 2: Check if higher-priority source imported it (cross-source fuzzy match)

  Uses fuzzy matching on artist name, date, and venue/GPS location.

  Returns {:duplicate, existing_event} or {:unique, nil}
  """
  def check_duplicate(event_data, source) do
    # PHASE 1: Check if THIS source already imported this event (same-source dedup)
    case BaseDedupHandler.find_by_external_id(event_data[:external_id], source.id) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing BandsInTown event by external_id (same source)")
        {:duplicate, existing}

      nil ->
        # PHASE 2: Check by artist + date + venue (cross-source fuzzy match)
        check_fuzzy_duplicate(event_data, source)
    end
  end

  # PHASE 2: Cross-source fuzzy matching with domain compatibility
  defp check_fuzzy_duplicate(event_data, source) do
    artist_name = normalize_artist_name(event_data[:title])
    date = event_data[:starts_at]
    latitude = get_in(event_data, [:venue_data, :latitude])
    longitude = get_in(event_data, [:venue_data, :longitude])

    # Find potential matches using BaseDedupHandler
    matches = BaseDedupHandler.find_events_by_date_and_proximity(
      date, latitude, longitude, proximity_meters: 100
    )

    # Filter by artist/title similarity
    title_matches = Enum.filter(matches, fn %{event: event} ->
      similar_artist?(artist_name, event.title)
    end)

    # Apply domain compatibility filtering
    higher_priority_matches = BaseDedupHandler.filter_higher_priority_matches(title_matches, source)

    case higher_priority_matches do
      [] ->
        {:unique, nil}

      [match | _] ->
        confidence = calculate_match_confidence(event_data, match.event)

        if BaseDedupHandler.should_defer_to_match?(match, source, confidence) do
          BaseDedupHandler.log_duplicate(source, event_data, match.event, match.source, confidence)
          {:duplicate, match.event}
        else
          {:unique, nil}
        end
    end
  end

  @doc """
  DEPRECATED: This function is deprecated and should not be used.
  Use check_duplicate/2 instead with source struct parameter.
  """
  def enrich_event_data(event_data) do
    # Deprecated - return event data unchanged
    event_data
  end

  defp calculate_match_confidence(bandsintown_event, existing_event) do
    scores = []

    # Artist name similarity (40%)
    scores = if similar_artist?(bandsintown_event[:title], existing_event.title), do: [0.4 | scores], else: scores

    # Date match (25%)
    scores = if same_date?(bandsintown_event[:starts_at], existing_event.start_at), do: [0.25 | scores], else: scores

    # Venue name match (20%)
    venue_name = get_in(bandsintown_event, [:venue_data, :name])
    scores = if venue_name && existing_event.venue && similar_venue?(venue_name, existing_event.venue.name), do: [0.2 | scores], else: scores

    # GPS proximity match (15%)
    latitude = get_in(bandsintown_event, [:venue_data, :latitude])
    longitude = get_in(bandsintown_event, [:venue_data, :longitude])
    scores = if latitude && longitude && BaseDedupHandler.same_location?(
           latitude, longitude,
           existing_event.venue.latitude, existing_event.venue.longitude,
           threshold_meters: 100
         ), do: [0.15 | scores], else: scores

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

  defp same_date?(date1, date2) do
    cond do
      is_nil(date1) || is_nil(date2) -> false
      true ->
        d1 = if is_struct(date1, DateTime), do: DateTime.to_date(date1), else: NaiveDateTime.to_date(date1)
        d2 = if is_struct(date2, DateTime), do: DateTime.to_date(date2), else: NaiveDateTime.to_date(date2)
        Date.compare(d1, d2) == :eq
    end
  end

  defp enrich_with_partial_matches(event_data) do
    # For unique events, try to enrich with performer or venue data

    enriched = event_data

    # Bandsintown already provides good performer data
    enriched =
      if event_data[:performer] do
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
