defmodule EventasaurusDiscovery.Sources.Kupbilecik.DedupHandler do
  @moduledoc """
  Deduplication handler for Kupbilecik events.

  Kupbilecik is a Polish ticketing platform with performer data, making it
  suitable for performer-based deduplication similar to Bandsintown.

  ## Deduplication Strategy

  1. **External ID**: Primary deduplication via `external_id` (same-source)
  2. **Performer + Venue + Date**: Fuzzy matching for cross-source duplicates
  3. **GPS Coordinates**: Venue proximity matching (within 100m)

  ## Priority Handling

  Kupbilecik priority should be set in the sources table. When a higher-priority
  source (e.g., Ticketmaster, Bandsintown) has already imported the same event,
  Kupbilecik will defer to that source.

  ## Collision Data Tracking

  This handler returns collision data for MetricsTracker integration:

      case DedupHandler.check_duplicate(event_data, source) do
        {:duplicate, existing, collision_data} ->
          MetricsTracker.record_collision(job, external_id, collision_data)
          {:ok, :skipped}

        {:unique, event_data} ->
          # Process the event
          process_event(event_data)
      end

  ## Example Flow

      # Phase 1: Check if Kupbilecik already imported this
      {:duplicate, existing, collision_data} = check_duplicate(event_data, source)

      # Phase 2: Check if higher-priority source has this event
      # Uses performer + venue + date + GPS matching
  """

  require Logger

  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.Sources.BaseDedupHandler

  @doc """
  Check if an event already exists from any source.

  Two-phase deduplication strategy:
  - Phase 1: Check if THIS source already imported it (same-source dedup)
  - Phase 2: Check if higher-priority source imported it (cross-source fuzzy match)

  Uses fuzzy matching on performer name, date, and venue/GPS location.

  ## Parameters
  - `event_data` - Event data with external_id, title, starts_at, venue_data, performer_names
  - `source` - Source struct for Kupbilecik

  ## Returns
  - `{:duplicate, existing_event, collision_data}` - Event already exists with collision info
  - `{:unique, event_data}` - Event is unique
  """
  @spec check_duplicate(map(), struct()) ::
          {:duplicate, Event.t(), map()} | {:unique, map()}
  def check_duplicate(event_data, source) do
    # PHASE 1: Check if THIS source already imported this event (same-source dedup)
    case BaseDedupHandler.find_by_external_id(event_data[:external_id], source.id) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing Kupbilecik event by external_id (same source)")
        collision_data = BaseDedupHandler.build_same_source_collision(existing, "deferred")
        {:duplicate, existing, collision_data}

      nil ->
        # PHASE 2: Check by performer + date + venue (cross-source fuzzy match)
        check_fuzzy_duplicate(event_data, source)
    end
  end

  @doc """
  Validate event quality before processing.

  Ensures event meets minimum requirements:
  - Has valid external ID
  - Has valid start date/time
  - Has title
  - Has sane date (not past, not >2 years future)

  ## Returns
  - `{:ok, event_data}` - Event passes quality checks
  - `{:error, reason}` - Event fails validation
  """
  @spec validate_event_quality(map()) :: {:ok, map()} | {:error, String.t()}
  def validate_event_quality(event_data) do
    with :ok <- validate_required_fields(event_data),
         :ok <- validate_date_sanity(event_data) do
      {:ok, event_data}
    else
      {:error, reason} ->
        Logger.warning("⚠️ Event quality validation failed: #{reason}")
        {:error, reason}
    end
  end

  # PHASE 2: Cross-source fuzzy matching with performer-based deduplication
  defp check_fuzzy_duplicate(event_data, source) do
    # Extract performer name from title or performer_names
    performer_name = extract_performer_name(event_data)
    date = event_data[:starts_at]
    latitude = get_in(event_data, [:venue_data, :latitude])
    longitude = get_in(event_data, [:venue_data, :longitude])

    # Find potential matches using BaseDedupHandler
    matches =
      BaseDedupHandler.find_events_by_date_and_proximity(
        date,
        latitude,
        longitude,
        proximity_meters: 100
      )

    # Filter by performer/title similarity
    performer_matches =
      Enum.filter(matches, fn %{event: event} ->
        similar_performer?(performer_name, event.title)
      end)

    # Apply domain compatibility filtering (only higher-priority sources)
    higher_priority_matches =
      BaseDedupHandler.filter_higher_priority_matches(performer_matches, source)

    case higher_priority_matches do
      [] ->
        {:unique, event_data}

      [match | _] ->
        confidence = calculate_match_confidence(event_data, match.event)
        match_factors = build_match_factors(event_data, match.event)

        if BaseDedupHandler.should_defer_to_match?(match, source, confidence) do
          # Use enhanced logging that returns collision data
          collision_data =
            BaseDedupHandler.log_duplicate_with_collision(
              source,
              event_data,
              match.event,
              match.source,
              confidence,
              match_factors,
              "deferred"
            )

          {:duplicate, match.event, collision_data}
        else
          {:unique, event_data}
        end
    end
  end

  # Build list of match factors that contributed to the confidence score
  defp build_match_factors(event_data, existing_event) do
    factors = []

    # Check performer match
    performer_name = extract_performer_name(event_data)

    factors =
      if similar_performer?(performer_name, existing_event.title) do
        ["performer" | factors]
      else
        factors
      end

    # Check date match
    factors =
      if same_date?(event_data[:starts_at], existing_event.start_at) do
        ["date" | factors]
      else
        factors
      end

    # Check venue match
    venue_name = get_in(event_data, [:venue_data, :name])

    factors =
      if venue_name && existing_event.venue &&
           similar_venue?(venue_name, existing_event.venue.name) do
        ["venue" | factors]
      else
        factors
      end

    # Check GPS match
    latitude = get_in(event_data, [:venue_data, :latitude])
    longitude = get_in(event_data, [:venue_data, :longitude])

    factors =
      if latitude && longitude && existing_event.venue &&
           BaseDedupHandler.same_location?(
             latitude,
             longitude,
             existing_event.venue.latitude,
             existing_event.venue.longitude,
             threshold_meters: 100
           ) do
        ["gps" | factors]
      else
        factors
      end

    Enum.reverse(factors)
  end

  # Extract performer name from event data
  # Priority: performer_names list > title
  defp extract_performer_name(event_data) do
    case event_data[:performer_names] do
      [performer | _] when is_binary(performer) ->
        normalize_performer_name(performer)

      _ ->
        normalize_performer_name(event_data[:title])
    end
  end

  defp normalize_performer_name(nil), do: ""

  defp normalize_performer_name(name) do
    name
    |> String.downcase()
    # Remove common suffixes like "at Venue Name" or "w [venue]"
    |> String.replace(~r/\s+at\s+.+$/i, "")
    |> String.replace(~r/\s+w\s+.+$/i, "")
    |> String.replace(~r/\s+-\s+.+$/i, "")
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
  end

  defp similar_performer?(performer1, performer2) do
    normalized1 = normalize_performer_name(performer1 || "")
    normalized2 = normalize_performer_name(performer2 || "")

    # Check for exact match or containment
    normalized1 == normalized2 ||
      String.contains?(normalized1, normalized2) ||
      String.contains?(normalized2, normalized1)
  end

  defp calculate_match_confidence(kupbilecik_event, existing_event) do
    scores = []

    # Performer/Title similarity (40% weight)
    performer_name = extract_performer_name(kupbilecik_event)

    scores =
      if similar_performer?(performer_name, existing_event.title) do
        [0.4 | scores]
      else
        scores
      end

    # Date match (25% weight)
    scores =
      if same_date?(kupbilecik_event[:starts_at], existing_event.start_at) do
        [0.25 | scores]
      else
        scores
      end

    # Venue name match (20% weight)
    venue_name = get_in(kupbilecik_event, [:venue_data, :name])

    scores =
      if venue_name && existing_event.venue &&
           similar_venue?(venue_name, existing_event.venue.name) do
        [0.2 | scores]
      else
        scores
      end

    # GPS proximity match (15% weight)
    latitude = get_in(kupbilecik_event, [:venue_data, :latitude])
    longitude = get_in(kupbilecik_event, [:venue_data, :longitude])

    scores =
      if latitude && longitude && existing_event.venue &&
           BaseDedupHandler.same_location?(
             latitude,
             longitude,
             existing_event.venue.latitude,
             existing_event.venue.longitude,
             threshold_meters: 100
           ) do
        [0.15 | scores]
      else
        scores
      end

    Enum.sum(scores)
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
      is_nil(date1) || is_nil(date2) ->
        false

      true ->
        d1 =
          if is_struct(date1, DateTime),
            do: DateTime.to_date(date1),
            else: NaiveDateTime.to_date(date1)

        d2 =
          if is_struct(date2, DateTime),
            do: DateTime.to_date(date2),
            else: NaiveDateTime.to_date(date2)

        Date.compare(d1, d2) == :eq
    end
  end

  # Validation helpers

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

      DateTime.compare(
        starts_at,
        DateTime.add(DateTime.utc_now(), 365 * 2 * 24 * 60 * 60, :second)
      ) ==
          :gt ->
        # More than 2 years in future - likely parsing error
        {:error, "Event date seems incorrect (>2 years in future)"}

      true ->
        :ok
    end
  end
end
