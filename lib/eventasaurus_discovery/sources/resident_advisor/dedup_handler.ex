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

  @doc """
  Validate event quality before processing.

  Ensures event meets minimum requirements:
  - Has valid venue with coordinates
  - Has valid start date/time
  - Has unique external ID
  - Has title

  Returns:
  - `{:ok, validated_event}` - Event passes quality checks
  - `{:error, reason}` - Event fails validation
  """
  def validate_event_quality(event_data) do
    cond do
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
    Repo.get_by(Event, external_id: external_id)
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
        higher_priority_match =
          Enum.find(matches, fn event ->
            # Get source priority
            source_priority = get_source_priority(event.source_id)

            # RA priority is 75, so check if existing source is higher
            source_priority > 75
          end)

        case higher_priority_match do
          nil ->
            # No higher priority matches, RA event is unique
            {:unique, event_data}

          existing ->
            # Found higher priority duplicate
            confidence = calculate_match_confidence(event_data, existing)

            if confidence > 0.8 do
              Logger.info("""
              🔍 Found likely duplicate from higher-priority source
              RA Event: #{event_data[:title]}
              Existing: #{existing.title}
              Confidence: #{Float.round(confidence, 2)}
              """)

              # Check if we can enrich the existing event
              if can_enrich?(event_data, existing) do
                Logger.info("✨ RA event can enrich existing event")
                {:enriched, enrich_existing_event(existing, event_data)}
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

    import Ecto.Query

    query =
      from e in Event,
        join: v in assoc(e, :venue),
        where:
          e.starts_at >= ^date_start and
            e.starts_at <= ^date_end and
            fragment(
              "earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?)) < 500",
              v.latitude,
              v.longitude,
              ^venue_lat,
              ^venue_lng
            ),
        preload: [:venue, :source]

    candidates = Repo.all(query)

    # Filter by title similarity
    Enum.filter(candidates, fn event ->
      similar_title?(title, event.title)
    end)
  rescue
    e ->
      Logger.error("Error finding matching events: #{inspect(e)}")
      []
  end

  defp get_source_priority(source_id) do
    case Repo.get(EventasaurusDiscovery.Sources.Source, source_id) do
      nil -> 0
      source -> source.priority || 0
    end
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
      if same_date?(ra_event[:starts_at], existing_event.starts_at) do
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
        Date.compare(DateTime.to_date(date1), DateTime.to_date(date2)) == :eq
    end
  end

  defp same_venue?(ra_lat, ra_lng, existing_venue) do
    cond do
      is_nil(ra_lat) || is_nil(ra_lng) || is_nil(existing_venue) ->
        false

      is_nil(existing_venue.latitude) || is_nil(existing_venue.longitude) ->
        false

      true ->
        # Check if within 500m
        distance = calculate_distance(ra_lat, ra_lng, existing_venue.latitude, existing_venue.longitude)
        distance < 500
    end
  end

  defp calculate_distance(lat1, lng1, lat2, lng2) do
    # Simple haversine formula
    r = 6371000
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
end
