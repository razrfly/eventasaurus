defmodule EventasaurusDiscovery.Sources.Karnet.DedupHandler do
  @moduledoc """
  Deduplication handler for Karnet Kraków events.

  Karnet is a regional source (priority 60) focused on Kraków cultural events.
  It should defer to higher-priority sources:
  - Ticketmaster (90) - International ticketing platform
  - Bandsintown (80) - Artist tour tracking platform
  - Resident Advisor (75) - Electronic music events

  ## Priority System

  Karnet has priority 60, so it should defer to higher-priority sources
  but takes precedence over lower-priority regional scrapers.

  ## Deduplication Strategy

  1. **External ID Lookup**: Check if Karnet event already imported
  2. **Title + Date + Venue Matching**: Fuzzy matching for duplicates
  3. **GPS Proximity**: Venue matching within 500m radius
  4. **Quality Assessment**: Ensure Karnet event meets minimum standards

  ## Karnet-Specific Features

  - Polish and English bilingual content
  - Comprehensive Kraków cultural calendar
  - Official city cultural partnership
  - Category-based event classification
  """

  require Logger

  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.Sources.BaseDedupHandler

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

  @doc """
  Check if event is a duplicate of existing higher-priority source.

  ## Parameters
  - `event_data` - Event data with external_id, title, starts_at, venue_data
  - `source` - Source struct with priority and domains

  ## Returns
  - `{:unique, event_data}` - Event is unique, safe to import
  - `{:duplicate, existing_event}` - Event exists from higher priority source
  - `{:enriched, event_data}` - Event exists but Karnet provides additional data
  """
  def check_duplicate(event_data, source) do
    # PHASE 1: Check if THIS source already imported this event (same-source dedup)
    case BaseDedupHandler.find_by_external_id(event_data[:external_id], source.id) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing Karnet event by external_id (same source)")
        {:duplicate, existing}

      nil ->
        # PHASE 2: Check by title + date + venue (cross-source fuzzy match)
        check_fuzzy_duplicate(event_data, source)
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

    case higher_priority_matches do
      [] ->
        {:unique, event_data}

      [match | _] ->
        confidence = calculate_match_confidence(event_data, match.event)

        if BaseDedupHandler.should_defer_to_match?(match, source, confidence) do
          BaseDedupHandler.log_duplicate(
            source,
            event_data,
            match.event,
            match.source,
            confidence
          )

          # Check if we can enrich the existing event
          if can_enrich?(event_data, match.event) do
            Logger.info("✨ Karnet event can enrich existing event")
            {:enriched, enrich_existing_event(match.event, match.source, event_data)}
          else
            {:duplicate, match.event}
          end
        else
          {:unique, event_data}
        end
    end
  end

  defp calculate_match_confidence(karnet_event, existing_event) do
    scores = []

    # Title similarity (40%)
    scores =
      if similar_title?(karnet_event[:title], existing_event.title),
        do: [0.4 | scores],
        else: scores

    # Date match (30%)
    scores =
      if same_date?(karnet_event[:starts_at], existing_event.start_at),
        do: [0.3 | scores],
        else: scores

    # Venue proximity (30%)
    scores =
      if BaseDedupHandler.same_location?(
           karnet_event[:venue_data][:latitude],
           karnet_event[:venue_data][:longitude],
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

  defp can_enrich?(karnet_data, existing) do
    # Karnet can enrich if it has:
    # - Bilingual content (Polish and English)
    # - Category information
    # - Additional venue details

    has_translations =
      not is_nil(karnet_data[:title_translations]) ||
        not is_nil(karnet_data[:description_translations])

    has_category = not is_nil(karnet_data[:category]) && karnet_data[:category] != ""
    has_description = not is_nil(karnet_data[:description]) && is_nil(existing.description)

    has_translations || has_category || has_description
  end

  defp enrich_existing_event(existing, source, karnet_data) do
    enrichments = %{}

    # Add bilingual content if available
    enrichments =
      if karnet_data[:title_translations] do
        Map.put(enrichments, :title_translations, karnet_data[:title_translations])
      else
        enrichments
      end

    enrichments =
      if karnet_data[:description_translations] do
        Map.put(enrichments, :description_translations, karnet_data[:description_translations])
      else
        enrichments
      end

    # Add Karnet-specific metadata
    enrichments =
      Map.put(enrichments, :karnet_metadata, %{
        karnet_external_id: karnet_data[:external_id],
        karnet_url: karnet_data[:source_url],
        category: karnet_data[:category],
        is_free: karnet_data[:is_free]
      })

    # Attach source for context
    existing_with_source = Map.put(existing, :source, source)
    Map.merge(existing_with_source, enrichments)
  end
end
