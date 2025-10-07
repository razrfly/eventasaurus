defmodule EventasaurusDiscovery.Sources.Pubquiz.DedupHandler do
  @moduledoc """
  Deduplication handler for PubQuiz recurring trivia events.

  PubQuiz is a Polish trivia night source (priority 50) that provides
  recurring weekly events. This handler ensures we don't create duplicates
  when updating recurring event schedules.

  ## Deduplication Strategy

  1. **Venue + Recurrence Pattern**: Primary deduplication
  2. **GPS Coordinates**: Venue proximity matching
  3. **Schedule Matching**: Same day of week + time

  ## Recurring Events Handling

  PubQuiz events are recurring (weekly trivia nights). We need to:
  - Detect if a recurrence rule already exists for this venue
  - Update next_occurrence without creating new events
  - Handle schedule changes (day/time updates)
  """

  require Logger

  @doc """
  Check if a recurring trivia event already exists for this venue.
  Uses venue matching and recurrence pattern comparison.

  Returns {:duplicate, existing_event} or {:unique, nil}
  """
  def check_duplicate(event_data) do
    # Extract key fields for matching
    venue_name = get_in(event_data, [:venue_data, :name])
    recurrence_rule = event_data[:recurrence_rule]
    latitude = get_in(event_data, [:venue_data, :latitude])
    longitude = get_in(event_data, [:venue_data, :longitude])

    # Look for existing recurring events at this venue
    case find_similar_recurring_event(venue_name, recurrence_rule, latitude, longitude) do
      nil ->
        {:unique, nil}

      existing ->
        confidence = calculate_match_confidence(event_data, existing)

        if confidence > 0.8 do
          Logger.info("🔍 Found existing recurring trivia event at venue: #{venue_name}")
          {:duplicate, existing}
        else
          {:unique, nil}
        end
    end
  end

  @doc """
  Handle recurring event updates.
  For PubQuiz, we want to update the next_occurrence rather than
  create duplicate recurring events.
  """
  def enrich_event_data(event_data) do
    case check_duplicate(event_data) do
      {:duplicate, existing} ->
        # Update the existing recurring event's next_occurrence
        handle_recurring_update(event_data, existing)

      {:unique, _} ->
        # New recurring event, enrich with venue data
        enrich_with_venue_data(event_data)
    end
  end

  defp find_similar_recurring_event(venue_name, recurrence_rule, latitude, longitude) do
    # TODO: Implement actual recurring event lookup
    # For now, venue_id + recurrence_rule uniqueness is handled by database

    # recurring_events = Events.list_recurring_events_by_venue(venue_name)

    # Temporary - no cross-run deduplication until we have proper event lookup
    events = []

    Enum.find(events, fn event ->
      venue_match = similar_venue?(venue_name, event.venue_name)
      location_match = latitude && longitude && nearby_location?(latitude, longitude, event)
      schedule_match = similar_schedule?(recurrence_rule, event.recurrence_rule)

      (venue_match || location_match) && schedule_match
    end)
  rescue
    _ -> nil
  end

  defp calculate_match_confidence(pubquiz_event, existing_event) do
    scores = []

    # Venue name similarity (40% weight)
    venue_name = get_in(pubquiz_event, [:venue_data, :name])

    scores =
      if venue_name && similar_venue?(venue_name, existing_event.venue_name) do
        [0.4 | scores]
      else
        scores
      end

    # GPS proximity match (30% weight)
    latitude = get_in(pubquiz_event, [:venue_data, :latitude])
    longitude = get_in(pubquiz_event, [:venue_data, :longitude])

    scores =
      if latitude && longitude && nearby_location?(latitude, longitude, existing_event) do
        [0.3 | scores]
      else
        scores
      end

    # Recurrence pattern match (30% weight)
    scores =
      if similar_schedule?(pubquiz_event[:recurrence_rule], existing_event.recurrence_rule) do
        [0.3 | scores]
      else
        scores
      end

    Enum.sum(scores)
  end

  defp handle_recurring_update(pubquiz_data, existing) do
    # Check if schedule changed
    schedule_changed = !similar_schedule?(pubquiz_data[:recurrence_rule], existing.recurrence_rule)

    if schedule_changed do
      # Schedule changed (different day or time)
      %{
        id: existing.id,
        action: :update,
        reason: "Recurring event schedule updated",
        updates: %{
          recurrence_rule: pubquiz_data[:recurrence_rule],
          starts_at: pubquiz_data[:starts_at]
        }
      }
    else
      # Same schedule, just skip
      %{
        id: existing.id,
        action: :skip,
        reason: "Recurring event already exists with same schedule",
        pubquiz_metadata: %{
          "pubquiz_schedule" => get_in(pubquiz_data, [:source_metadata, "schedule_text"]),
          "host" => get_in(pubquiz_data, [:source_metadata, "host"])
        }
      }
    end
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

  defp similar_schedule?(rule1, rule2) do
    cond do
      is_nil(rule1) || is_nil(rule2) ->
        false

      true ->
        # Compare frequency, day of week, and time
        same_frequency?(rule1, rule2) &&
          same_days?(rule1, rule2) &&
          same_time?(rule1, rule2)
    end
  end

  defp same_frequency?(rule1, rule2) do
    rule1["frequency"] == rule2["frequency"]
  end

  defp same_days?(rule1, rule2) do
    days1 = rule1["days_of_week"] || []
    days2 = rule2["days_of_week"] || []

    MapSet.equal?(MapSet.new(days1), MapSet.new(days2))
  end

  defp same_time?(rule1, rule2) do
    rule1["time"] == rule2["time"]
  end

  defp nearby_location?(lat1, lon1, event) do
    cond do
      is_nil(event.latitude) || is_nil(event.longitude) ->
        false

      true ->
        # Calculate distance using Haversine formula
        distance_meters = calculate_distance(lat1, lon1, event.latitude, event.longitude)

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

  defp enrich_with_venue_data(event_data) do
    # For unique recurring events, ensure venue data is complete

    enriched = event_data

    if venue_data = event_data[:venue_data] do
      # PubQuiz events are in Poland, add timezone if missing
      venue_data =
        Map.merge(
          %{
            country: "Poland",
            timezone: "Europe/Warsaw",
            # Will be geocoded if coordinates missing
            needs_geocoding: is_nil(venue_data[:latitude]) || is_nil(venue_data[:longitude])
          },
          venue_data
        )

      Map.put(enriched, :venue_data, venue_data)
    else
      enriched
    end
  end

  @doc """
  Validate recurring event data quality before processing.
  Returns {:ok, event_data} or {:error, reason}
  """
  def validate_event_quality(event_data) do
    with :ok <- validate_required_fields(event_data),
         :ok <- validate_recurrence_rule(event_data),
         :ok <- validate_venue_data(event_data) do
      {:ok, event_data}
    else
      {:error, reason} ->
        Logger.warning("⚠️ Recurring event quality validation failed: #{reason}")
        {:error, reason}
    end
  end

  defp validate_required_fields(event_data) do
    required = [:title, :venue_id, :recurrence_rule, :starts_at]

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

  defp validate_recurrence_rule(event_data) do
    rule = event_data[:recurrence_rule]

    cond do
      is_nil(rule) ->
        {:error, "Missing recurrence_rule"}

      !is_map(rule) ->
        {:error, "recurrence_rule must be a map"}

      !rule["frequency"] || !rule["days_of_week"] || !rule["time"] ->
        {:error, "recurrence_rule missing required fields"}

      rule["frequency"] != "weekly" ->
        {:error, "Only weekly frequency supported for PubQuiz"}

      true ->
        :ok
    end
  end

  defp validate_venue_data(event_data) do
    # Must have venue_id (from VenueProcessor)
    if event_data[:venue_id] do
      :ok
    else
      {:error, "Missing venue_id (event must be processed through VenueProcessor first)"}
    end
  end
end
