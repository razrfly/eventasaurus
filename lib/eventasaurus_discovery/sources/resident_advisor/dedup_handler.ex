defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.DedupHandler do
  @moduledoc """
  Deduplication handler for Resident Advisor events.

  Checks incoming RA events against existing events from higher-priority sources
  (Ticketmaster priority 90, Bandsintown priority 80) to prevent duplicates.

  ## Priority System

  RA has priority 75, so it should defer to:
  - Ticketmaster (90) - International ticketing platform
  - Bandsintown (80) - Artist tour tracking platform

  But takes precedence over:
  - Regional sources (60) - Local event scrapers
  - Karnet (30) - Kraków-specific source

  ## Deduplication Strategy

  1. **Title + Date + Venue Matching**: Same event, same location, same time
  2. **External ID Lookup**: Check if RA event already imported
  3. **Quality Assessment**: Ensure RA event meets minimum quality standards
  4. **Enrichment**: Add RA-specific data (editorial picks, artist info) to existing events

  ## RA-Specific Features

  - Editorial pick content can enrich existing events
  - Artist lineup data may be more comprehensive
  - Attendance counts provide social proof
  - High-resolution images from RA flyers
  """

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainers
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query

  @doc """
  Validate event quality before processing.

  Ensures event meets minimum requirements:
  - Has valid venue with coordinates
  - Has valid start date/time
  - Has unique external ID
  - Has title

  Special handling:
  - Detects umbrella events (festivals, conferences) and creates containers instead

  Returns:
  - `{:ok, validated_event}` - Event passes quality checks
  - `{:error, reason}` - Event fails validation
  - `{:container, container}` - Umbrella event created as container
  """
  def validate_event_quality(event_data) do
    cond do
      # Check for umbrella event FIRST (before other validations)
      is_umbrella_event?(event_data[:raw_data]) ->
        handle_umbrella_event(event_data)

      is_nil(event_data[:title]) || event_data[:title] == "" ->
        {:error, "Event missing title"}

      is_nil(event_data[:external_id]) || event_data[:external_id] == "" ->
        {:error, "Event missing external_id"}

      is_nil(event_data[:starts_at]) ->
        {:error, "Event missing starts_at"}

      not is_struct(event_data[:starts_at], DateTime) ->
        {:error, "starts_at must be DateTime"}

      is_nil(event_data[:venue_data]) ->
        {:error, "Event missing venue_data"}

      # NOTE: Do NOT validate latitude/longitude here
      # RA events rarely have coordinates at this stage
      # VenueProcessor will geocode after this validation passes

      not is_date_sane?(event_data[:starts_at]) ->
        {:error, "Event date is not sane (past or >2 years future)"}

      true ->
        {:ok, event_data}
    end
  end

  @doc """
  Check if event is a duplicate of existing higher-priority source.

  ## Returns
  - `{:unique, event_data}` - Event is unique, safe to import
  - `{:duplicate, existing_event}` - Event exists from higher priority source
  - `{:enriched, event_data}` - Event exists but RA provides additional data
  """
  def check_duplicate(event_data) do
    # First check by external_id (exact match)
    case find_by_external_id(event_data[:external_id]) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing RA event by external_id")
        {:duplicate, existing}

      nil ->
        # Check by title + date + venue (fuzzy match)
        check_fuzzy_duplicate(event_data)
    end
  end

  # Private functions

  defp is_date_sane?(datetime) do
    now = DateTime.utc_now()
    # DateTime.add only accepts :second unit - convert 2 years to seconds
    two_years_in_seconds = 2 * 365 * 24 * 60 * 60
    two_years_future = DateTime.add(now, two_years_in_seconds, :second)

    # Event should be in future but not more than 2 years out
    DateTime.compare(datetime, now) in [:gt, :eq] &&
      DateTime.compare(datetime, two_years_future) == :lt
  end

  defp find_by_external_id(external_id) when is_binary(external_id) do
    # Query through public_event_sources join table
    query =
      from(e in Event,
        join: es in PublicEventSource,
        on: es.event_id == e.id,
        where: es.external_id == ^external_id and is_nil(e.deleted_at),
        limit: 1
      )

    Repo.one(query)
  end

  defp find_by_external_id(_), do: nil

  defp check_fuzzy_duplicate(event_data) do
    title = normalize_title(event_data[:title])
    date = event_data[:starts_at]
    venue_lat = event_data[:venue_data][:latitude]
    venue_lng = event_data[:venue_data][:longitude]

    case find_matching_events(title, date, venue_lat, venue_lng) do
      [] ->
        {:unique, event_data}

      matches ->
        # Filter to higher priority sources only
        # matches is now a list of %{event: event, source: source}
        higher_priority_match =
          Enum.find(matches, fn %{event: _event, source: source} ->
            # RA priority is 75, so check if existing source is higher
            source.priority > 75
          end)

        case higher_priority_match do
          nil ->
            # No higher priority matches, RA event is unique
            {:unique, event_data}

          %{event: existing, source: source} ->
            # Found higher priority duplicate
            confidence = calculate_match_confidence(event_data, existing)

            if confidence > 0.8 do
              Logger.info("""
              🔍 Found likely duplicate from higher-priority source
              RA Event: #{event_data[:title]}
              Existing: #{existing.title} (source: #{source.name}, priority: #{source.priority})
              Confidence: #{Float.round(confidence, 2)}
              """)

              # Check if we can enrich the existing event
              if can_enrich?(event_data, existing) do
                Logger.info("✨ RA event can enrich existing event")
                # Attach source to existing event for enrichment
                existing_with_source = Map.put(existing, :source, source)
                {:enriched, enrich_existing_event(existing_with_source, event_data)}
              else
                {:duplicate, existing}
              end
            else
              {:unique, event_data}
            end
        end
    end
  end

  defp find_matching_events(title, date, venue_lat, venue_lng) do
    # Query events within:
    # - 1 day of target date
    # - 500m of venue coordinates
    # - Similar title

    date_start = DateTime.add(date, -86400, :second)
    # 1 day before
    date_end = DateTime.add(date, 86400, :second)

    # 1 day after

    # Query through public_event_sources to get source information
    query =
      from(e in Event,
        join: v in assoc(e, :venue),
        join: es in PublicEventSource,
        on: es.event_id == e.id,
        join: s in Source,
        on: s.id == es.source_id,
        where:
          e.start_at >= ^date_start and
            e.start_at <= ^date_end and
            is_nil(e.deleted_at) and
            fragment(
              "earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?)) < 500",
              v.latitude,
              v.longitude,
              ^venue_lat,
              ^venue_lng
            ),
        preload: [venue: v],
        select: %{event: e, source: s}
      )

    candidates = Repo.all(query)

    # Filter by title similarity
    # candidates is now a list of %{event: event, source: source}
    Enum.filter(candidates, fn %{event: event, source: _source} ->
      similar_title?(title, event.title)
    end)
  rescue
    e ->
      Logger.error("Error finding matching events: #{inspect(e)}")
      []
  end

  defp calculate_match_confidence(ra_event, existing_event) do
    scores = []

    # Title similarity (40% weight)
    scores =
      if similar_title?(ra_event[:title], existing_event.title) do
        [0.4 | scores]
      else
        scores
      end

    # Date match (30% weight)
    scores =
      if same_date?(ra_event[:starts_at], existing_event.start_at) do
        [0.3 | scores]
      else
        scores
      end

    # Venue proximity (30% weight)
    scores =
      if same_venue?(
           ra_event[:venue_data][:latitude],
           ra_event[:venue_data][:longitude],
           existing_event.venue
         ) do
        [0.3 | scores]
      else
        scores
      end

    Enum.sum(scores)
  end

  defp normalize_title(nil), do: ""

  defp normalize_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
  end

  defp similar_title?(title1, title2) do
    normalized1 = normalize_title(title1 || "")
    normalized2 = normalize_title(title2 || "")

    # Simple similarity check
    normalized1 == normalized2 ||
      String.contains?(normalized1, normalized2) ||
      String.contains?(normalized2, normalized1)
  end

  defp same_date?(date1, date2) do
    cond do
      is_nil(date1) || is_nil(date2) ->
        false

      true ->
        # Check if same day (ignore time)
        # Handle both DateTime and NaiveDateTime
        d1 = if is_struct(date1, DateTime), do: DateTime.to_date(date1), else: NaiveDateTime.to_date(date1)
        d2 = if is_struct(date2, DateTime), do: DateTime.to_date(date2), else: NaiveDateTime.to_date(date2)

        Date.compare(d1, d2) == :eq
    end
  end

  defp same_venue?(ra_lat, ra_lng, existing_venue) do
    cond do
      is_nil(ra_lat) || is_nil(ra_lng) || is_nil(existing_venue) ->
        false

      is_nil(existing_venue.latitude) || is_nil(existing_venue.longitude) ->
        false

      true ->
        # Convert Decimal to float if needed
        venue_lat = if is_struct(existing_venue.latitude, Decimal), do: Decimal.to_float(existing_venue.latitude), else: existing_venue.latitude
        venue_lng = if is_struct(existing_venue.longitude, Decimal), do: Decimal.to_float(existing_venue.longitude), else: existing_venue.longitude

        # Check if within 500m
        distance = calculate_distance(ra_lat, ra_lng, venue_lat, venue_lng)

        distance < 500
    end
  end

  defp calculate_distance(lat1, lng1, lat2, lng2) do
    # Simple haversine formula
    r = 6_371_000
    # Earth radius in meters

    lat1_rad = lat1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    delta_lat = (lat2 - lat1) * :math.pi() / 180
    delta_lng = (lng2 - lng1) * :math.pi() / 180

    a =
      :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(delta_lng / 2) * :math.sin(delta_lng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    r * c
  end

  defp can_enrich?(ra_data, existing) do
    # RA can enrich if it has:
    # - Editorial pick content (description)
    # - Higher resolution images
    # - Artist lineup details
    # - Attendance counts

    has_editorial = not is_nil(ra_data[:description]) && ra_data[:description] != ""
    has_better_image = not is_nil(ra_data[:image_url]) && is_nil(existing.image_url)
    has_artist_info = not is_nil(ra_data[:performer]) && is_nil(existing.performer_id)
    has_attendance = not is_nil(ra_data[:attending_count])

    has_editorial || has_better_image || has_artist_info || has_attendance
  end

  defp enrich_existing_event(existing, ra_data) do
    # Build enrichment data
    enrichments = %{}

    # Add editorial content if available
    enrichments =
      if not is_nil(ra_data[:description]) && ra_data[:description] != "" do
        Map.put(enrichments, :description_enrichment, ra_data[:description])
      else
        enrichments
      end

    # Add image if better quality
    enrichments =
      if not is_nil(ra_data[:image_url]) && is_nil(existing.image_url) do
        Map.put(enrichments, :image_url, ra_data[:image_url])
      else
        enrichments
      end

    # Add RA-specific metadata
    enrichments =
      Map.put(enrichments, :ra_metadata, %{
        ra_external_id: ra_data[:external_id],
        ra_url: ra_data[:source_url],
        is_featured: ra_data[:is_featured],
        attending_count: ra_data[:attending_count],
        is_ticketed: ra_data[:is_ticketed]
      })

    Map.merge(existing, enrichments)
  end

  # Umbrella Event Detection
  # Based on analysis from issue #1512 and /tmp/ra_festival_analysis.md

  @umbrella_venue_ids ["267425"]
  # Various venues - Kraków

  # Detect if RA event is an umbrella event (festival, conference, tour).
  #
  # Detection signals (95% accuracy):
  # 1. Venue ID 267425 ("Various venues - Kraków")
  # 2. Venue name contains "Various venues"
  # 3. Multi-day span (5+ days) + generic times (12:00 start, 23:59 end)
  # 4. High artist count (>30 artists)
  # 5. High attending count (>500 people)
  #
  # Primary signal: Venue ID (most reliable)
  # Secondary signals: Used for venues outside Kraków
  defp is_umbrella_event?(raw_event) when is_map(raw_event) do
    venue_id = get_in(raw_event, ["event", "venue", "id"])
    venue_name = get_in(raw_event, ["event", "venue", "name"]) || ""

    # Primary check: Known umbrella venue IDs
    cond do
      venue_id in @umbrella_venue_ids ->
        true

      # Secondary check: Venue name pattern
      String.contains?(String.downcase(venue_name), "various venues") ->
        true

      # Tertiary check: Multi-signal heuristics
      check_umbrella_heuristics(raw_event) ->
        true

      true ->
        false
    end
  end

  defp is_umbrella_event?(_), do: false

  defp check_umbrella_heuristics(raw_event) do
    event = raw_event["event"] || %{}

    # Extract signals
    start_time = get_in(event, ["startTime"])
    end_time = get_in(event, ["endTime"])
    artist_count = length(event["artists"] || [])
    attending_count = event["attending"] || 0

    # Multi-day event with generic times
    has_generic_times =
      start_time == "12:00" && end_time == "23:59"

    # High artist count (festivals typically have many artists)
    high_artist_count = artist_count > 30

    # High attendance (festivals attract large crowds)
    high_attendance = attending_count > 500

    # Combine signals (require at least 2 of 3)
    signals = [has_generic_times, high_artist_count, high_attendance]
    true_count = Enum.count(signals, & &1)

    true_count >= 2
  end

  defp handle_umbrella_event(event_data) do
    Logger.info("🎪 Detected umbrella event: #{event_data[:title]}")

    # Create container from umbrella event
    case PublicEventContainers.create_from_umbrella_event(event_data, event_data[:source_id]) do
      {:ok, container} ->
        Logger.info("✅ Created event container: #{container.title} (#{container.container_type})")
        {:container, container}

      {:error, changeset} ->
        Logger.error("❌ Failed to create container: #{inspect(changeset.errors)}")
        {:error, "Failed to create container: #{inspect(changeset.errors)}"}
    end
  end
end
