defmodule EventasaurusDiscovery.Sources.KinoKrakow.DedupHandler do
  @moduledoc """
  Deduplication handler for Kino Krakow movie showtimes.

  Kino Krakow is a regional source (priority 15) focused on movie showtimes
  at Kino Krakow theaters in Kraków, Poland. It should defer to higher-priority sources.

  ## Deduplication Strategy

  1. **External ID Lookup**: Check if Kino Krakow event already imported
  2. **Title + Date + Venue Matching**: Fuzzy matching for duplicates
  3. **GPS Proximity**: Cinema location matching within 500m radius
  4. **Quality Assessment**: Ensure event meets minimum standards
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Geo.City
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

      not BaseDedupHandler.is_date_sane?(event_data[:starts_at]) ->
        {:error, "Event date is not sane (past or >2 years future)"}

      true ->
        {:ok, event_data}
    end
  end

  @doc """
  Check if event is a duplicate.

  Uses BaseDedupHandler for shared logic, implements Kino Krakow-specific fuzzy matching.
  """
  def check_duplicate(event_data, source) do
    # PHASE 1: Same-source dedup
    case BaseDedupHandler.find_by_external_id(event_data[:external_id], source.id) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing Kino Krakow event by external_id (same source)")
        {:duplicate, existing}

      nil ->
        check_fuzzy_duplicate(event_data, source)
    end
  end

  # Kino Krakow-specific fuzzy matching logic
  defp check_fuzzy_duplicate(event_data, source) do
    title = normalize_title(event_data[:title])
    date = event_data[:starts_at]
    venue_name = get_in(event_data, [:venue_data, :name])
    city_name = get_in(event_data, [:venue_data, :city])
    venue_lat = get_in(event_data, [:venue_data, :latitude])
    venue_lng = get_in(event_data, [:venue_data, :longitude])

    # Get coordinates from existing venue if needed
    {final_lat, final_lng} =
      if is_nil(venue_lat) or is_nil(venue_lng) do
        case find_existing_venue_coordinates(venue_name, city_name) do
          {lat, lng} when not is_nil(lat) and not is_nil(lng) ->
            {lat, lng}

          _ ->
            {nil, nil}
        end
      else
        {venue_lat, venue_lng}
      end

    if is_nil(final_lat) or is_nil(final_lng) do
      {:unique, event_data}
    else
      # Find potential matches
      matches =
        BaseDedupHandler.find_events_by_date_and_proximity(
          date,
          final_lat,
          final_lng,
          proximity_meters: 500
        )

      # Filter by title similarity
      title_matches =
        Enum.filter(matches, fn %{event: event} ->
          similar_title?(title, event.title)
        end)

      # Apply domain compatibility filtering
      higher_priority_matches =
        BaseDedupHandler.filter_higher_priority_matches(title_matches, source)

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

  defp calculate_match_confidence(kino_krakow_event, existing_event) do
    scores = []

    # Title similarity (40%)
    scores =
      if similar_title?(kino_krakow_event[:title], existing_event.title),
        do: [0.4 | scores],
        else: scores

    # Date match (30%)
    scores =
      if same_date?(kino_krakow_event[:starts_at], existing_event.start_at),
        do: [0.3 | scores],
        else: scores

    # Venue proximity (30%)
    scores =
      if BaseDedupHandler.same_location?(
           kino_krakow_event[:venue_data][:latitude],
           kino_krakow_event[:venue_data][:longitude],
           existing_event.venue.latitude,
           existing_event.venue.longitude,
           threshold_meters: 500
         ),
         do: [0.3 | scores],
         else: scores

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
end
