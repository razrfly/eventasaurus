defmodule EventasaurusDiscovery.Sources.Pubquiz.DedupHandler do
  @moduledoc """
  Deduplication handler for PubQuiz recurring trivia events.

  PubQuiz is a Polish trivia night source (priority 50) that provides recurring weekly events.

  ## Deduplication Strategy

  1. **External ID Lookup**: Check if PubQuiz event already imported
  2. **Venue + Recurrence Pattern**: Primary deduplication for recurring events
  3. **GPS Coordinates**: Venue proximity matching within 50m
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Geo.City
  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.Sources.BaseDedupHandler

  import Ecto.Query

  @doc """
  Validate event quality before processing.
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

      not BaseDedupHandler.is_date_sane?(event_data[:starts_at]) ->
        {:error, "Event date is not sane (past or >2 years future)"}

      true ->
        {:ok, event_data}
    end
  end

  @doc """
  Check if event is a duplicate.

  Uses BaseDedupHandler for shared logic, implements PubQuiz-specific fuzzy matching.
  """
  def check_duplicate(event_data, source) do
    # PHASE 1: Same-source dedup
    case BaseDedupHandler.find_by_external_id(event_data[:external_id], source.id) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing PubQuiz event by external_id (same source)")
        {:duplicate, existing}

      nil ->
        check_fuzzy_duplicate(event_data, source)
    end
  end

  # PubQuiz-specific fuzzy matching (venue-based for recurring events)
  defp check_fuzzy_duplicate(event_data, source) do
    venue_name = get_in(event_data, [:venue_data, :name])
    city_name = get_in(event_data, [:venue_data, :city])
    venue_lat = get_in(event_data, [:venue_data, :latitude])
    venue_lng = get_in(event_data, [:venue_data, :longitude])

    # Get coordinates from existing venue if needed
    {final_lat, final_lng} =
      if is_nil(venue_lat) or is_nil(venue_lng) do
        case find_existing_venue_coordinates(venue_name, city_name) do
          {lat, lng} when not is_nil(lat) and not is_nil(lng) -> {lat, lng}
          _ -> {nil, nil}
        end
      else
        {venue_lat, venue_lng}
      end

    if is_nil(final_lat) or is_nil(final_lng) do
      {:unique, event_data}
    else
      # Find recurring events at same venue
      matches =
        BaseDedupHandler.find_events_by_date_and_proximity(
          event_data[:starts_at],
          final_lat,
          final_lng,
          proximity_meters: 50
        )

      # Filter by venue name similarity
      venue_matches =
        Enum.filter(matches, fn %{event: event} ->
          similar_venue?(venue_name, event.venue.name)
        end)

      # Apply domain compatibility filtering
      higher_priority_matches =
        BaseDedupHandler.filter_higher_priority_matches(venue_matches, source)

      event_data_with_coords =
        event_data
        |> put_in([:venue_data, :latitude], final_lat)
        |> put_in([:venue_data, :longitude], final_lng)

      case Enum.find_value(higher_priority_matches, fn match ->
             confidence = calculate_match_confidence(event_data_with_coords, match.event)

             if BaseDedupHandler.should_defer_to_match?(match, source, confidence) do
               {match, confidence}
             end
           end) do
        nil ->
          {:unique, event_data_with_coords}

        {match, confidence} ->
          BaseDedupHandler.log_duplicate(
            source,
            event_data,
            match.event,
            match.source,
            confidence
          )

          {:duplicate, match.event}
      end
    end
  end

  defp find_existing_venue_coordinates(venue_name, city_name) do
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
        lat_f = if is_struct(lat, Decimal), do: Decimal.to_float(lat), else: lat
        lng_f = if is_struct(lng, Decimal), do: Decimal.to_float(lng), else: lng
        {lat_f, lng_f}

      nil ->
        {nil, nil}
    end
  rescue
    _e -> {nil, nil}
  end

  defp calculate_match_confidence(pubquiz_event, existing_event) do
    scores = []

    # Venue name similarity (50% - primary signal for recurring events)
    venue_name = get_in(pubquiz_event, [:venue_data, :name])

    scores =
      if venue_name && similar_venue?(venue_name, existing_event.venue.name),
        do: [0.5 | scores],
        else: scores

    # GPS proximity (40%)
    lat = get_in(pubquiz_event, [:venue_data, :latitude])
    lng = get_in(pubquiz_event, [:venue_data, :longitude])

    scores =
      if lat && lng &&
           BaseDedupHandler.same_location?(
             lat,
             lng,
             existing_event.venue.latitude,
             existing_event.venue.longitude,
             threshold_meters: 50
           ),
         do: [0.4 | scores],
         else: scores

    # Title similarity (10% - weak signal)
    scores =
      if similar_title?(pubquiz_event[:title], existing_event.title),
        do: [0.1 | scores],
        else: scores

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
    |> String.replace(~r/^pubquiz\.pl\s*-\s*/i, "")
    |> String.replace(~r/[^\w\s]/u, "")
    |> String.trim()
  end
end
