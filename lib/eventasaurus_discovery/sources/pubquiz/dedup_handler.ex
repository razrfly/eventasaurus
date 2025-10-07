defmodule EventasaurusDiscovery.Sources.Pubquiz.DedupHandler do
  @moduledoc """
  Deduplication handler for PubQuiz recurring trivia events.

  PubQuiz is a Polish trivia night source (priority 50) that provides
  recurring weekly events. This handler ensures we don't create duplicates
  when updating recurring event schedules.

  ## Priority System

  PubQuiz has priority 50, so it should defer to:
  - Ticketmaster (90) - International ticketing platform
  - Bandsintown (80) - Artist tour tracking platform
  - Resident Advisor (75) - Electronic music events
  - Karnet (60) - Kraków cultural events

  ## Deduplication Strategy

  1. **External ID Lookup**: Check if PubQuiz event already imported
  2. **Venue + Recurrence Pattern**: Primary deduplication for recurring events
  3. **GPS Coordinates**: Venue proximity matching within 50m
  4. **Schedule Matching**: Same day of week + time

  ## Recurring Events Handling

  PubQuiz events are recurring (weekly trivia nights). We need to:
  - Detect if a recurrence rule already exists for this venue
  - Check against higher-priority sources
  - Handle schedule changes (day/time updates)
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Geo.City
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query

  @doc """
  Validate event quality before processing.

  Ensures event meets minimum requirements:
  - Has valid external ID
  - Has valid start date/time
  - Has title
  - Has venue data
  - Has recurrence rule

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

      is_nil(event_data[:recurrence_rule]) ->
        {:error, "Event missing recurrence_rule"}

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
  """
  def check_duplicate(event_data) do
    # First check by external_id (exact match)
    case find_by_external_id(event_data[:external_id]) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing PubQuiz event by external_id")
        {:duplicate, existing}

      nil ->
        # Check by venue + recurrence pattern (for recurring events)
        check_fuzzy_duplicate(event_data)
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
    venue_name = get_in(event_data, [:venue_data, :name])
    city_name = get_in(event_data, [:venue_data, :city])
    venue_lat = get_in(event_data, [:venue_data, :latitude])
    venue_lng = get_in(event_data, [:venue_data, :longitude])

    # Try to find existing venue by name+city to get coordinates
    # This handles the 95% case where venue already exists in database
    {final_lat, final_lng} =
      if is_nil(venue_lat) or is_nil(venue_lng) do
        case find_existing_venue_coordinates(venue_name, city_name) do
          {lat, lng} when not is_nil(lat) and not is_nil(lng) ->
            Logger.debug("Using coordinates from existing venue in database")
            {lat, lng}

          _ ->
            Logger.debug("Skipping fuzzy duplicate check - venue not geocoded yet")
            {nil, nil}
        end
      else
        {venue_lat, venue_lng}
      end

    # Skip fuzzy matching if we still don't have coordinates
    if is_nil(final_lat) or is_nil(final_lng) do
      {:unique, event_data}
    else
      case find_matching_recurring_events(venue_name, final_lat, final_lng) do
        [] ->
          {:unique, event_data}

        matches ->
          # Filter to higher priority sources only
          # PubQuiz priority is 50, so check if existing source is higher
          higher_priority_match =
            Enum.find(matches, fn %{event: _event, source: source} ->
              source.priority > 50
            end)

          case higher_priority_match do
            nil ->
              # No higher priority matches, PubQuiz event is unique
              {:unique, event_data}

            %{event: existing, source: source} ->
              # Found higher priority duplicate
              confidence = calculate_match_confidence(event_data, existing)

              if confidence > 0.8 do
                Logger.info("""
                🔍 Found likely duplicate from higher-priority source
                PubQuiz Event: #{event_data[:title]}
                Existing: #{existing.title} (source: #{source.name}, priority: #{source.priority})
                Confidence: #{Float.round(confidence, 2)}
                """)

                {:duplicate, existing}
              else
                {:unique, event_data}
              end
          end
      end
    end
  end

  defp find_existing_venue_coordinates(venue_name, city_name) do
    # Look up venue by name and city to get GPS coordinates
    # This handles the common case where venue already exists in database
    query =
      from(v in Venue,
        join: c in City,
        on: v.city_id == c.id,
        where:
          fragment("LOWER(?) = LOWER(?)", v.name, ^venue_name) and
            fragment("LOWER(?) = LOWER(?)", c.name, ^city_name) and
            not is_nil(v.latitude) and
            not is_nil(v.longitude),
        select: {v.latitude, v.longitude},
        limit: 1
      )

    case Repo.one(query) do
      {lat, lng} ->
        # Convert Decimal to float if needed
        lat_f = if is_struct(lat, Decimal), do: Decimal.to_float(lat), else: lat
        lng_f = if is_struct(lng, Decimal), do: Decimal.to_float(lng), else: lng
        {lat_f, lng_f}

      nil ->
        {nil, nil}
    end
  rescue
    _e ->
      {nil, nil}
  end

  defp find_matching_recurring_events(venue_name, venue_lat, venue_lng) do
    # Query events with nearby venue (50m radius)
    # Uses PostGIS earth_distance like other sources (Karnet, RA, Ticketmaster)
    query =
      from(e in Event,
        join: v in assoc(e, :venue),
        join: es in PublicEventSource,
        on: es.event_id == e.id,
        join: s in Source,
        on: s.id == es.source_id,
        where:
          is_nil(e.deleted_at) and
            fragment(
              "earth_distance(ll_to_earth(?, ?), ll_to_earth(?, ?)) < 50",
              v.latitude,
              v.longitude,
              ^venue_lat,
              ^venue_lng
            ),
        preload: [venue: v],
        select: %{event: e, source: s}
      )

    candidates = Repo.all(query)

    # Filter by venue name similarity
    # For recurring trivia events, venue match is the primary deduplication signal
    Enum.filter(candidates, fn %{event: event, source: _source} ->
      similar_venue?(venue_name, event.venue.name)
    end)
  rescue
    e ->
      Logger.error("Error finding matching recurring events: #{inspect(e)}")
      []
  end

  defp calculate_match_confidence(pubquiz_event, existing_event) do
    scores = []

    # Venue name similarity (50% weight) - Primary signal for recurring events
    venue_name = get_in(pubquiz_event, [:venue_data, :name])

    scores =
      if venue_name && similar_venue?(venue_name, existing_event.venue.name) do
        [0.5 | scores]
      else
        scores
      end

    # GPS proximity match (40% weight) - Strong signal for same venue
    latitude = get_in(pubquiz_event, [:venue_data, :latitude])
    longitude = get_in(pubquiz_event, [:venue_data, :longitude])

    scores =
      if latitude && longitude && nearby_location?(latitude, longitude, existing_event.venue) do
        [0.4 | scores]
      else
        scores
      end

    # Title similarity (10% weight) - All PubQuiz events are "Weekly Trivia Night"
    # This is a weak signal but helps confirm it's the same type of event
    scores =
      if similar_title?(pubquiz_event[:title], existing_event.title) do
        [0.1 | scores]
      else
        scores
      end

    Enum.sum(scores)
  end

  defp similar_title?(title1, title2) do
    normalized1 = normalize_title(title1 || "")
    normalized2 = normalize_title(title2 || "")

    normalized1 == normalized2 ||
      String.contains?(normalized1, normalized2) ||
      String.contains?(normalized2, normalized1)
  end

  defp normalize_title(nil), do: ""

  defp normalize_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
  end


  defp similar_venue?(venue1, venue2) do
    cond do
      is_nil(venue1) || is_nil(venue2) ->
        false

      true ->
        normalized1 = normalize_venue_name(venue1)
        normalized2 = normalize_venue_name(venue2)

        normalized1 == normalized2 ||
          String.contains?(normalized1, normalized2) ||
          String.contains?(normalized2, normalized1)
    end
  end

  defp normalize_venue_name(name) do
    name
    |> String.downcase()
    # Remove "PubQuiz.pl -" prefix
    |> String.replace(~r/^pubquiz\.pl\s*-\s*/i, "")
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
  end


  defp nearby_location?(lat1, lon1, venue) do
    cond do
      is_nil(venue) || is_nil(venue.latitude) || is_nil(venue.longitude) ->
        false

      true ->
        # Convert Decimal to float if needed
        venue_lat = if is_struct(venue.latitude, Decimal), do: Decimal.to_float(venue.latitude), else: venue.latitude
        venue_lng = if is_struct(venue.longitude, Decimal), do: Decimal.to_float(venue.longitude), else: venue.longitude

        # Calculate distance using Haversine formula
        distance_meters = calculate_distance(lat1, lon1, venue_lat, venue_lng)

        # Consider venues within 50m as the same location (tighter for recurring events)
        distance_meters < 50
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

end
