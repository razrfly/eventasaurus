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

  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.Sources.BaseDedupHandler

  @doc """
  Check if a Ticketmaster event already exists.

  Since Ticketmaster is the highest priority source (90), we only check for
  duplicates within Ticketmaster itself, not from other sources.

  ## Parameters
  - `event_data` - Event data with external_id, title, starts_at, venue_data
  - `source` - Source struct (should be Ticketmaster with priority 90)

  ## Returns
  - `{:unique, event_data}` - Event is unique within Ticketmaster
  - `{:duplicate, existing_event}` - Event already exists in Ticketmaster
  """
  def check_duplicate(event_data, source) do
    # PHASE 1: Check by external_id (exact match within Ticketmaster)
    case BaseDedupHandler.find_by_external_id(event_data[:external_id], source.id) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing Ticketmaster event by external_id (same source)")
        {:duplicate, existing}

      nil ->
        # PHASE 2: Fuzzy match within Ticketmaster only
        check_fuzzy_duplicate(event_data, source)
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

      not BaseDedupHandler.is_date_sane?(event_data[:starts_at]) ->
        {:error, "Event date is not sane (past or >2 years future)"}

      true ->
        {:ok, event_data}
    end
  end

  # Private functions

  defp check_fuzzy_duplicate(event_data, source) do
    title = normalize_title(event_data[:title])
    date = event_data[:starts_at]
    venue_lat = get_in(event_data, [:venue_data, :latitude])
    venue_lng = get_in(event_data, [:venue_data, :longitude])

    # Find potential matches using BaseDedupHandler
    matches =
      BaseDedupHandler.find_events_by_date_and_proximity(
        date,
        venue_lat,
        venue_lng,
        proximity_meters: 100
      )

    # Filter by title similarity
    title_matches =
      Enum.filter(matches, fn %{event: event} ->
        similar_title?(title, event.title)
      end)

    # Ticketmaster is highest priority (90), so only check against itself
    # Filter to only Ticketmaster events (same source_id)
    ticketmaster_matches =
      Enum.filter(title_matches, fn %{source: match_source} ->
        match_source.id == source.id
      end)

    case ticketmaster_matches do
      [] ->
        # No Ticketmaster matches found
        # Even if lower-priority sources exist, Ticketmaster imports anyway
        {:unique, event_data}

      [match | _] ->
        # Found a Ticketmaster match
        confidence = calculate_match_confidence(event_data, match.event)

        if confidence > 0.8 do
          Logger.info("""
          🔍 Found likely duplicate Ticketmaster event
          New: #{event_data[:title]}
          Existing: #{match.event.title} (ID: #{match.event.id})
          Confidence: #{Float.round(confidence, 2)}
          """)

          {:duplicate, match.event}
        else
          {:unique, event_data}
        end
    end
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
           BaseDedupHandler.same_location?(
             venue_lat,
             venue_lng,
             existing_event.venue.latitude,
             existing_event.venue.longitude,
             threshold_meters: 100
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
