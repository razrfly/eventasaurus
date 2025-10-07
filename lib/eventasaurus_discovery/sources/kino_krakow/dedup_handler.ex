defmodule EventasaurusDiscovery.Sources.KinoKrakow.DedupHandler do
  @moduledoc """
  Deduplication handler for Kino Krakow movie showtimes.

  Kino Krakow is a regional source (priority 15) focused on movie showtimes
  at Kino Krakow theaters in Kraków, Poland. It should defer to higher-priority sources:
  - Ticketmaster (90) - International ticketing platform
  - Bandsintown (80) - Artist tour tracking platform
  - Resident Advisor (75) - Electronic music events
  - Karnet (60) - Kraków cultural events
  - PubQuiz (50) - Weekly trivia events

  ## Priority System

  Kino Krakow has priority 15, making it a lower-priority regional source.
  It should defer to all higher-priority sources for the same event.

  ## Deduplication Strategy

  1. **External ID Lookup**: Check if Kino Krakow event already imported
  2. **Title + Date + Venue Matching**: Fuzzy matching for duplicates
  3. **GPS Proximity**: Cinema location matching within 500m radius
  4. **Quality Assessment**: Ensure Kino Krakow event meets minimum standards

  ## Kino Krakow-Specific Features

  - Movie showtimes at Kino Krakow cinema locations
  - TMDB integration for movie metadata
  - HTML scraping (authoritative data)
  - Fixed cinema locations (rarely change)
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
        Logger.info("🔍 Found existing Kino Krakow event by external_id")
        {:duplicate, existing}

      nil ->
        # Check by title + date + venue (fuzzy match)
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
    title = normalize_title(event_data[:title])
    date = event_data[:starts_at]
    venue_name = get_in(event_data, [:venue_data, :name])
    city_name = get_in(event_data, [:venue_data, :city])
    venue_lat = get_in(event_data, [:venue_data, :latitude])
    venue_lng = get_in(event_data, [:venue_data, :longitude])

    # Try to find existing cinema by name+city to get coordinates
    # This handles the common case where cinema already exists in database
    {final_lat, final_lng} =
      if is_nil(venue_lat) or is_nil(venue_lng) do
        case find_existing_venue_coordinates(venue_name, city_name) do
          {lat, lng} when not is_nil(lat) and not is_nil(lng) ->
            Logger.debug("Using coordinates from existing cinema in database")
            {lat, lng}

          _ ->
            Logger.debug("Skipping fuzzy duplicate check - cinema not geocoded yet")
            {nil, nil}
        end
      else
        {venue_lat, venue_lng}
      end

    # Skip fuzzy matching if we still don't have coordinates
    if is_nil(final_lat) or is_nil(final_lng) do
      {:unique, event_data}
    else
      case find_matching_events(title, date, final_lat, final_lng) do
        [] ->
          {:unique, event_data}

        matches ->
          # Filter to higher priority sources only
          # Kino Krakow priority is 15, so check if existing source is higher
          higher_priority_match =
            Enum.find(matches, fn %{event: _event, source: source} ->
              source.priority > 15
            end)

          case higher_priority_match do
            nil ->
              # No higher priority matches, Kino Krakow event is unique
              {:unique, event_data}

            %{event: existing, source: source} ->
              # Found higher priority duplicate
              # Use fallback coordinates for confidence calculation
              event_data_for_confidence =
                event_data
                |> put_in([:venue_data, :latitude], final_lat)
                |> put_in([:venue_data, :longitude], final_lng)

              confidence = calculate_match_confidence(event_data_for_confidence, existing)

              if confidence > 0.8 do
                Logger.info("""
                🔍 Found likely duplicate from higher-priority source
                Kino Krakow Event: #{event_data[:title]}
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
    # Look up cinema by name and city to get GPS coordinates
    # This handles the common case where cinema already exists in database
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

  defp find_matching_events(title, date, venue_lat, venue_lng) do
    # Query events within:
    # - 1 day of target date (same showtime day)
    # - 500m of cinema coordinates
    # - Similar title (movie name)

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
    Enum.filter(candidates, fn %{event: event, source: _source} ->
      similar_title?(title, event.title)
    end)
  rescue
    e ->
      Logger.error("Error finding matching events: #{inspect(e)}")
      []
  end

  defp calculate_match_confidence(kino_krakow_event, existing_event) do
    scores = []

    # Title similarity (40% weight) - Movie name match
    scores =
      if similar_title?(kino_krakow_event[:title], existing_event.title) do
        [0.4 | scores]
      else
        scores
      end

    # Date match (30% weight) - Same showtime day
    scores =
      if same_date?(kino_krakow_event[:starts_at], existing_event.start_at) do
        [0.3 | scores]
      else
        scores
      end

    # Venue proximity (30% weight) - Same cinema location
    scores =
      if same_venue?(
           kino_krakow_event[:venue_data][:latitude],
           kino_krakow_event[:venue_data][:longitude],
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

  defp same_venue?(cinema_lat, cinema_lng, existing_venue) do
    cond do
      is_nil(cinema_lat) || is_nil(cinema_lng) || is_nil(existing_venue) ->
        false

      is_nil(existing_venue.latitude) || is_nil(existing_venue.longitude) ->
        false

      true ->
        # Convert Decimal to float if needed
        venue_lat = if is_struct(existing_venue.latitude, Decimal), do: Decimal.to_float(existing_venue.latitude), else: existing_venue.latitude
        venue_lng = if is_struct(existing_venue.longitude, Decimal), do: Decimal.to_float(existing_venue.longitude), else: existing_venue.longitude

        # Check if within 500m
        distance = calculate_distance(cinema_lat, cinema_lng, venue_lat, venue_lng)

        distance < 500
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
