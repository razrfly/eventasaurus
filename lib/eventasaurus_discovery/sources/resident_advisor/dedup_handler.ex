defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.DedupHandler do
  @moduledoc """
  Deduplication handler for Resident Advisor events.

  Resident Advisor is a high-priority international source (priority 75) for electronic music events.

  ## Deduplication Strategy

  1. **Title + Date + Venue Matching**: Same event, same location, same time
  2. **External ID Lookup**: Check if RA event already imported
  3. **Quality Assessment**: Ensure RA event meets minimum quality standards
  4. **Enrichment**: Add RA-specific data to existing events
  """

  require Logger

  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainers
  alias EventasaurusDiscovery.Sources.BaseDedupHandler

  @umbrella_venue_ids ["267425"]  # Various venues - Kraków

  @doc """
  Validate event quality before processing.
  """
  def validate_event_quality(event_data) do
    cond do
      # Check for umbrella event FIRST
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

      not BaseDedupHandler.is_date_sane?(event_data[:starts_at]) ->
        {:error, "Event date is not sane (past or >2 years future)"}

      true ->
        {:ok, event_data}
    end
  end

  @doc """
  Check if event is a duplicate.

  Uses BaseDedupHandler for shared logic, implements RA-specific fuzzy matching.
  """
  def check_duplicate(event_data, source) do
    # PHASE 1: Same-source dedup
    case BaseDedupHandler.find_by_external_id(event_data[:external_id], source.id) do
      %Event{} = existing ->
        Logger.info("🔍 Found existing RA event by external_id (same source)")
        {:duplicate, existing}

      nil ->
        check_fuzzy_duplicate(event_data, source)
    end
  end

  # RA-specific fuzzy matching logic
  defp check_fuzzy_duplicate(event_data, source) do
    title = normalize_title(event_data[:title])
    date = event_data[:starts_at]
    venue_lat = event_data[:venue_data][:latitude]
    venue_lng = event_data[:venue_data][:longitude]

    # Find potential matches
    matches = BaseDedupHandler.find_events_by_date_and_proximity(
      date, venue_lat, venue_lng, proximity_meters: 500
    )

    # Filter by title similarity
    title_matches = Enum.filter(matches, fn %{event: event} ->
      similar_title?(title, event.title)
    end)

    # Apply domain compatibility filtering
    higher_priority_matches = BaseDedupHandler.filter_higher_priority_matches(title_matches, source)

    case higher_priority_matches do
      [] ->
        {:unique, event_data}

      [match | _] ->
        confidence = calculate_match_confidence(event_data, match.event)

        if BaseDedupHandler.should_defer_to_match?(match, source, confidence) do
          BaseDedupHandler.log_duplicate(source, event_data, match.event, match.source, confidence)

          # Check if we can enrich the existing event
          if can_enrich?(event_data, match.event) do
            Logger.info("✨ RA event can enrich existing event")
            {:enriched, enrich_existing_event(match.event, match.source, event_data)}
          else
            {:duplicate, match.event}
          end
        else
          {:unique, event_data}
        end
    end
  end

  defp calculate_match_confidence(ra_event, existing_event) do
    scores = []

    # Title similarity (40%)
    scores = if similar_title?(ra_event[:title], existing_event.title), do: [0.4 | scores], else: scores

    # Date match (30%)
    scores = if same_date?(ra_event[:starts_at], existing_event.start_at), do: [0.3 | scores], else: scores

    # Venue proximity (30%)
    scores = if BaseDedupHandler.same_location?(
           ra_event[:venue_data][:latitude],
           ra_event[:venue_data][:longitude],
           existing_event.venue.latitude,
           existing_event.venue.longitude,
           threshold_meters: 500
         ), do: [0.3 | scores], else: scores

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
      is_nil(date1) || is_nil(date2) -> false
      true ->
        d1 = if is_struct(date1, DateTime), do: DateTime.to_date(date1), else: NaiveDateTime.to_date(date1)
        d2 = if is_struct(date2, DateTime), do: DateTime.to_date(date2), else: NaiveDateTime.to_date(date2)
        Date.compare(d1, d2) == :eq
    end
  end

  defp can_enrich?(ra_data, existing) do
    has_editorial = not is_nil(ra_data[:description]) && ra_data[:description] != ""
    has_better_image = not is_nil(ra_data[:image_url]) && is_nil(existing.image_url)
    has_artist_info = not is_nil(ra_data[:performer]) && is_nil(existing.performer_id)
    has_attendance = not is_nil(ra_data[:attending_count])

    has_editorial || has_better_image || has_artist_info || has_attendance
  end

  defp enrich_existing_event(existing, source, ra_data) do
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

    # Attach source for context
    existing_with_source = Map.put(existing, :source, source)
    Map.merge(existing_with_source, enrichments)
  end

  # Umbrella Event Detection
  defp is_umbrella_event?(raw_event) when is_map(raw_event) do
    venue_id = get_in(raw_event, ["event", "venue", "id"])
    venue_name = get_in(raw_event, ["event", "venue", "name"]) || ""

    cond do
      venue_id in @umbrella_venue_ids -> true
      String.contains?(String.downcase(venue_name), "various venues") -> true
      check_umbrella_heuristics(raw_event) -> true
      true -> false
    end
  end

  defp is_umbrella_event?(_), do: false

  defp check_umbrella_heuristics(raw_event) do
    event = raw_event["event"] || %{}

    start_time = get_in(event, ["startTime"])
    end_time = get_in(event, ["endTime"])
    artist_count = length(event["artists"] || [])
    attending_count = event["attending"] || 0

    has_generic_times = start_time == "12:00" && end_time == "23:59"
    high_artist_count = artist_count > 30
    high_attendance = attending_count > 500

    signals = [has_generic_times, high_artist_count, high_attendance]
    true_count = Enum.count(signals, & &1)

    true_count >= 2
  end

  defp handle_umbrella_event(event_data) do
    Logger.info("🎪 Detected umbrella event: #{event_data[:title]}")

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
