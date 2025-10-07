defmodule EventasaurusDiscovery.Sources.Ticketmaster.DedupHandler do
  @moduledoc """
  Deduplication handler for Ticketmaster events.

  Ticketmaster is the highest priority source (priority 90), so it should:
  - Check for duplicates within Ticketmaster itself (same external_id)
  - NOT defer to any other sources (it's the highest priority)
  - Allow lower priority sources to be replaced/enriched

  ## Priority System

  Ticketmaster (90) > Bandsintown (80) > Resident Advisor (75) > Karnet (60)

  ## Deduplication Strategy

  1. **External ID**: Primary deduplication via `external_id`
  2. **Title + Venue + Date**: Fuzzy matching for duplicate detection
  3. **GPS Coordinates**: Venue proximity matching (within 100m)

  ## Ticketmaster-Specific Features

  - Official ticketing data (ticket prices, availability)
  - Venue seating charts and layouts
  - Artist tour information
  - High-quality promotional images
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query

  @doc """
  Check if a Ticketmaster event already exists.

  Since Ticketmaster is the highest priority source, we only check for
  duplicates within Ticketmaster itself, not from other sources.

  Returns {:duplicate, existing_event} or {:unique, nil}
  """
  def check_duplicate(event_data) do
    # First check by external_id (exact match within Ticketmaster)
    case find_by_external_id(event_data[:external_id]) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing Ticketmaster event by external_id")
        {:duplicate, existing}

      nil ->
        # Check by title + date + venue (fuzzy match)
        check_fuzzy_duplicate(event_data)
    end
  end

  @doc """
  Validate event quality before processing.

  Ensures event meets minimum requirements:
  - Has valid external ID
  - Has valid start date/time
  - Has title
  - Has venue data

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

      not is_date_sane?(event_data[:starts_at]) ->
        {:error, "Event date is not sane (past or >2 years future)"}

      true ->
        {:ok, event_data}
    end
  end

  # Private functions

  defp is_date_sane?(datetime) do
    now = DateTime.utc_now()
    two_years_in_seconds = 2 * 365 * 24 * 60 * 60
    two_years_future = DateTime.add(now, two_years_in_seconds, :second)

    # Event should be in future but not more than 2 years out
    DateTime.compare(datetime, now) in [:gt, :eq] &&
      DateTime.compare(datetime, two_years_future) == :lt
  end

  defp find_by_external_id(external_id) when is_binary(external_id) do
    # Query through public_event_sources join table
    # Only look for Ticketmaster events
    query =
      from(e in Event,
        join: es in PublicEventSource,
        on: es.event_id == e.id,
        join: s in Source,
        on: s.id == es.source_id,
        where: es.external_id == ^external_id and s.slug == "ticketmaster" and is_nil(e.deleted_at),
        limit: 1
      )

    Repo.one(query)
  end

  defp find_by_external_id(_), do: nil

  defp check_fuzzy_duplicate(event_data) do
    title = normalize_title(event_data[:title])
    date = event_data[:starts_at]
    venue_lat = get_in(event_data, [:venue_data, :latitude])
    venue_lng = get_in(event_data, [:venue_data, :longitude])

    case find_matching_events(title, date, venue_lat, venue_lng) do
      [] ->
        {:unique, event_data}

      matches ->
        # Ticketmaster is highest priority (90), so only dedup against itself
        # Don't let lower-priority sources suppress Ticketmaster events
        tm_matches =
          Enum.filter(matches, fn %{source: source} ->
            source.slug == "ticketmaster"
          end)

        case tm_matches do
          [] ->
            # No Ticketmaster matches found - only lower-priority sources
            # Ticketmaster should import and supersede them
            {:unique, event_data}

          tm_candidates ->
            # Find best Ticketmaster match
            best_match = Enum.max_by(tm_candidates, fn %{event: event, source: _source} ->
              calculate_match_confidence(event_data, event)
            end)

            %{event: existing, source: source} = best_match
            confidence = calculate_match_confidence(event_data, existing)

            if confidence > 0.8 do
              Logger.info("""
              🔍 Found likely duplicate Ticketmaster event
              New: #{event_data[:title]}
              Existing: #{existing.title} (source: #{source.name})
              Confidence: #{Float.round(confidence, 2)}
              """)

              {:duplicate, existing}
            else
              {:unique, event_data}
            end
        end
    end
  end

  defp find_matching_events(title, date, venue_lat, venue_lng) do
    # Query events within:
    # - 1 day of target date
    # - 100m of venue coordinates
    # - Similar title

    date_start = DateTime.add(date, -86400, :second)
    date_end = DateTime.add(date, 86400, :second)

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
            is_nil(e.deleted_at),
        preload: [venue: v],
        select: %{event: e, source: s}
      )

    # Add GPS proximity filter if coordinates available
    query =
      if venue_lat && venue_lng do
        from([e, v, es, s] in query,
          where:
            fragment(
              "earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?)) < 100",
              v.latitude,
              v.longitude,
              ^venue_lat,
              ^venue_lng
            )
        )
      else
        query
      end

    candidates = Repo.all(query)

    # Filter by title similarity
    Enum.filter(candidates, fn %{event: event, source: _source} ->
      similar_title?(title, event.title)
    end)
  rescue
    e ->
      Logger.error("Error finding matching events: #{inspect(e)}")
      []
  end

  defp calculate_match_confidence(ticketmaster_event, existing_event) do
    scores = []

    # Title similarity (40% weight)
    scores =
      if similar_title?(ticketmaster_event[:title], existing_event.title) do
        [0.4 | scores]
      else
        scores
      end

    # Date match (30% weight)
    scores =
      if same_date?(ticketmaster_event[:starts_at], existing_event.start_at) do
        [0.3 | scores]
      else
        scores
      end

    # Venue proximity (30% weight)
    venue_lat = get_in(ticketmaster_event, [:venue_data, :latitude])
    venue_lng = get_in(ticketmaster_event, [:venue_data, :longitude])

    scores =
      if venue_lat && venue_lng && existing_event.venue &&
           same_venue?(venue_lat, venue_lng, existing_event.venue) do
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

  defp same_venue?(tm_lat, tm_lng, existing_venue) do
    cond do
      is_nil(tm_lat) || is_nil(tm_lng) || is_nil(existing_venue) ->
        false

      is_nil(existing_venue.latitude) || is_nil(existing_venue.longitude) ->
        false

      true ->
        # Convert Decimal to float if needed
        venue_lat = if is_struct(existing_venue.latitude, Decimal), do: Decimal.to_float(existing_venue.latitude), else: existing_venue.latitude
        venue_lng = if is_struct(existing_venue.longitude, Decimal), do: Decimal.to_float(existing_venue.longitude), else: existing_venue.longitude

        # Check if within 100m
        distance = calculate_distance(tm_lat, tm_lng, venue_lat, venue_lng)

        distance < 100
    end
  end

  defp calculate_distance(lat1, lng1, lat2, lng2) do
    # Haversine formula
    r = 6_371_000  # Earth radius in meters

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
end
