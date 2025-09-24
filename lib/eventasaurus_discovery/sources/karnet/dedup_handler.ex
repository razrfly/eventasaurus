defmodule EventasaurusDiscovery.Sources.Karnet.DedupHandler do
  @moduledoc """
  Simple deduplication handler for Karnet Kraków events.

  Since Karnet is localized to Kraków and lower priority, this provides
  basic deduplication against events from other sources (Ticketmaster/BandsInTown)
  that likely have better coverage of major Kraków events.
  """

  require Logger
  # alias EventasaurusApp.Events  # TODO: Re-enable when we have proper event lookup

  @doc """
  Check if an event already exists from other sources.
  Uses fuzzy matching on title, date, and venue.

  Returns {:duplicate, existing_event} or {:unique, nil}
  """
  def check_duplicate(event_data) do
    # Extract key fields for matching
    title = normalize_title(event_data[:title])
    date = event_data[:starts_at]
    venue_name = get_in(event_data, [:venue_data, :name])

    # Look for potential duplicates
    case find_similar_event(title, date, venue_name) do
      nil ->
        {:unique, nil}

      existing ->
        confidence = calculate_match_confidence(event_data, existing)

        if confidence > 0.8 do
          Logger.info("🔍 Found likely duplicate from higher-priority source: #{existing.title}")
          {:duplicate, existing}
        else
          {:unique, nil}
        end
    end
  end

  @doc """
  Enrich Karnet event data with information from existing events.
  This helps fill gaps when Karnet has less detailed information.
  """
  def enrich_event_data(event_data) do
    # Since Karnet is lower priority, we prefer data from other sources
    # but can use Karnet data to fill missing fields

    case check_duplicate(event_data) do
      {:duplicate, existing} ->
        # Use existing event but add any unique Karnet data
        merge_with_existing(event_data, existing)

      {:unique, _} ->
        # Check if we can enrich with partial matches
        enrich_with_partial_matches(event_data)
    end
  end

  defp find_similar_event(title, date, venue_name) do
    # Simple query for events with similar characteristics
    # In production, this would use more sophisticated matching

    # TODO: Implement actual event lookup when Events module has the proper function
    # events = Events.list_events_by_date_range(
    #   DateTime.add(date, -86400, :second),  # 1 day before
    #   DateTime.add(date, 86400, :second)    # 1 day after
    # )

    # Temporary - no deduplication until we have proper event lookup
    events = []

    Enum.find(events, fn event ->
      title_match = similar_title?(title, event.title)
      venue_match = venue_name && similar_venue?(venue_name, event.venue_name)

      title_match && (venue_match || same_date?(date, event.starts_at))
    end)
  rescue
    _ -> nil
  end

  defp calculate_match_confidence(karnet_event, existing_event) do
    scores = []

    # Title similarity (40% weight)
    scores =
      if similar_title?(karnet_event[:title], existing_event.title) do
        [0.4 | scores]
      else
        scores
      end

    # Date match (30% weight)
    scores =
      if same_date?(karnet_event[:starts_at], existing_event.starts_at) do
        [0.3 | scores]
      else
        scores
      end

    # Venue match (30% weight)
    venue_name = get_in(karnet_event, [:venue_data, :name])

    scores =
      if venue_name && similar_venue?(venue_name, existing_event.venue_name) do
        [0.3 | scores]
      else
        scores
      end

    Enum.sum(scores)
  end

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
    # In production, use Jaro-Winkler or similar algorithm
    normalized1 == normalized2 ||
      String.contains?(normalized1, normalized2) ||
      String.contains?(normalized2, normalized1)
  end

  defp similar_venue?(venue1, venue2) do
    cond do
      is_nil(venue1) || is_nil(venue2) ->
        false

      true ->
        normalized1 = normalize_title(venue1)
        normalized2 = normalize_title(venue2)

        normalized1 == normalized2 ||
          String.contains?(normalized1, normalized2) ||
          String.contains?(normalized2, normalized1)
    end
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

  defp merge_with_existing(karnet_data, existing) do
    # Return existing event with any unique Karnet data in metadata
    %{
      id: existing.id,
      action: :skip,
      reason: "Event already exists from higher-priority source",
      karnet_metadata: %{
        "karnet_url" => karnet_data[:source_url],
        "karnet_category" => karnet_data[:category],
        "karnet_description" => karnet_data[:description]
      }
    }
  end

  defp enrich_with_partial_matches(event_data) do
    # For unique events, try to enrich with performer or venue data
    # from other sources if available

    enriched = event_data

    # Try to match venue with existing venues
    enriched =
      if venue_data = event_data[:venue_data] do
        enrich_venue_data(enriched, venue_data)
      else
        enriched
      end

    # Try to match performers with existing performers
    enriched =
      if performers = event_data[:performer_names] do
        enrich_performer_data(enriched, performers)
      else
        enriched
      end

    enriched
  end

  defp enrich_venue_data(event_data, venue_data) do
    # Since all Karnet events are in Kraków, we can be more specific
    # about venue matching and enrichment
    venue_data =
      Map.merge(venue_data, %{
        city: "Kraków",
        state: "Lesser Poland",
        country: "Poland",
        country_code: "PL",
        timezone: "Europe/Warsaw"
      })

    Map.put(event_data, :venue_data, venue_data)
  end

  defp enrich_performer_data(event_data, _performer_names) do
    # Basic performer enrichment
    # In production, would match against performer database
    event_data
  end

  @doc """
  Validate event data quality before processing.
  Returns {:ok, event_data} or {:error, reason}
  """
  def validate_event_quality(event_data) do
    with :ok <- validate_required_fields(event_data),
         :ok <- validate_date_sanity(event_data),
         :ok <- validate_venue_data(event_data) do
      {:ok, event_data}
    else
      {:error, reason} ->
        Logger.warning("Event quality validation failed: #{reason}")
        {:error, reason}
    end
  end

  defp validate_required_fields(event_data) do
    required = [:title, :source_url]

    missing =
      Enum.filter(required, fn field ->
        is_nil(event_data[field]) || event_data[field] == ""
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required fields: #{inspect(missing)}"}
    end
  end

  defp validate_date_sanity(event_data) do
    starts_at = event_data[:starts_at]

    cond do
      is_nil(starts_at) ->
        # Date might be unparseable Polish format
        # Allow it through with warning
        Logger.warning("No parsed date for event: #{event_data[:title]}")
        :ok

      DateTime.compare(starts_at, DateTime.utc_now()) == :lt ->
        # Past event - skip
        {:error, "Event is in the past"}

      DateTime.compare(starts_at, DateTime.add(DateTime.utc_now(), 365 * 2, :day)) == :gt ->
        # More than 2 years in future - likely parsing error
        {:error, "Event date seems incorrect (>2 years in future)"}

      true ->
        :ok
    end
  end

  defp validate_venue_data(_event_data) do
    # For Karnet, venue data might be missing or incomplete
    # This is acceptable since we know all events are in Kraków
    :ok
  end
end
