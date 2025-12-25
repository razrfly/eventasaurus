defmodule EventasaurusDiscovery.Services.EventFreshnessChecker do
  @moduledoc """
  Checks if events need processing based on last_seen_at timestamps.
  Uses batch queries for performance.
  Universal across all scrapers.

  ## Source-Specific Thresholds

  Supports source-specific freshness thresholds configured in config files:

      config :eventasaurus, :event_discovery,
        freshness_threshold_hours: 168,  # Default: 7 days
        source_freshness_overrides: %{
          "repertuary" => 24,    # Daily scraping
          "cinema-city" => 48      # Every 2 days
        }

  Sources without overrides use the default `freshness_threshold_hours`.

  ## Recurring Events

  Events with a `recurrence_rule` are ALWAYS processed (bypass freshness check).
  This is because recurring events need their `starts_at` updated to the next
  occurrence on each scraper run. The event record stays the same (same external_id),
  but the date/time advances to show the upcoming occurrence.

  See docs/EXTERNAL_ID_CONVENTIONS.md for the external_id patterns that distinguish
  recurring events from single-occurrence events.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusApp.Venues.Venue
  require Logger

  @doc """
  Filters events to only those needing processing.
  Returns events NOT recently seen.

  ## Parameters
  - events: List of event maps with external_id
  - source_id: The source identifier
  - threshold_hours: Optional override, defaults to application config (168 hours / 7 days)

  ## Examples

      iex> events = [%{"external_id" => "bit_123"}, %{"external_id" => "bit_456"}]
      iex> filter_events_needing_processing(events, 1)
      [%{"external_id" => "bit_456"}]  # bit_123 was seen recently

  """
  @spec filter_events_needing_processing([map()], integer(), integer() | nil) :: [map()]
  def filter_events_needing_processing(events, source_id, threshold_hours \\ nil) do
    threshold = threshold_hours || get_threshold_for_source(source_id)

    # CRITICAL: Recurring events bypass freshness check entirely
    # They need their starts_at updated to the next occurrence on each run
    # See docs/EXTERNAL_ID_CONVENTIONS.md - recurring events use venue-only external_ids
    {recurring_events, single_events} = Enum.split_with(events, &has_recurrence_rule?/1)

    if Enum.any?(recurring_events) do
      Logger.debug(
        "🔄 Recurring event bypass: #{length(recurring_events)} recurring events will always be processed"
      )
    end

    # Extract external_ids from single events only (recurring events bypass this check)
    external_ids =
      single_events
      |> Enum.map(&extract_external_id/1)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(external_ids) do
      # If no valid external_ids in single events, process all single events + all recurring
      single_events ++ recurring_events
    else
      # Query for recently seen external_ids
      threshold_datetime = DateTime.add(DateTime.utc_now(), -threshold, :hour)

      # Get both fresh external_ids AND the event_ids they belong to
      fresh_data =
        from(pes in PublicEventSource,
          where: pes.source_id == ^source_id,
          where: pes.external_id in ^external_ids,
          where: pes.last_seen_at > ^threshold_datetime,
          select: %{external_id: pes.external_id, event_id: pes.event_id}
        )
        |> Repo.all()

      fresh_external_ids = MapSet.new(fresh_data, & &1.external_id)
      fresh_event_ids = MapSet.new(fresh_data, & &1.event_id)

      # Also find event_ids for all external_ids being checked
      # This helps us identify recurring events that share the same event_id
      external_id_to_event_id =
        from(pes in PublicEventSource,
          where: pes.source_id == ^source_id,
          where: pes.external_id in ^external_ids,
          select: %{external_id: pes.external_id, event_id: pes.event_id}
        )
        |> Repo.all()
        |> Map.new(fn %{external_id: ext_id, event_id: evt_id} -> {ext_id, evt_id} end)

      # For new events (external_id not yet in DB), predict which event they'll merge into
      # by looking at title + venue similarity
      predicted_event_ids =
        predict_recurring_event_ids(single_events, external_id_to_event_id, source_id)

      # Return single events NOT in fresh set
      # An event is fresh if EITHER:
      # 1. Its external_id was recently seen, OR
      # 2. Its parent event_id was recently updated (for multi-date events), OR
      # 3. The event it WILL merge into was recently updated (predicted multi-date events)
      filtered_single_events =
        Enum.filter(single_events, fn event ->
          external_id = extract_external_id(event)

          cond do
            is_nil(external_id) ->
              # No external_id, process it
              true

            MapSet.member?(fresh_external_ids, external_id) ->
              # This exact external_id was recently seen, skip it
              false

            true ->
              # Check if this external_id maps to a recently updated event
              existing_event_id = Map.get(external_id_to_event_id, external_id)
              predicted_event_id = Map.get(predicted_event_ids, external_id)

              cond do
                existing_event_id && MapSet.member?(fresh_event_ids, existing_event_id) ->
                  # This external_id belongs to a multi-date event that was recently updated
                  false

                predicted_event_id && MapSet.member?(fresh_event_ids, predicted_event_id) ->
                  # This NEW external_id will merge into a recently updated event
                  false

                true ->
                  # Process this event
                  true
              end
          end
        end)

      # Combine filtered single events with ALL recurring events (recurring bypass freshness)
      filtered_single_events ++ recurring_events
    end
  end

  @doc """
  Get the freshness threshold for a specific source by ID.
  Checks for source-specific overrides, falls back to default.

  ## Parameters
  - source_id: The source identifier (integer)

  ## Examples

      iex> get_threshold_for_source(repertuary_source_id)
      24  # Daily scraping for Repertuary

      iex> get_threshold_for_source(bandsintown_source_id)
      168  # Default 7 days for sources without override

  """
  @spec get_threshold_for_source(integer()) :: integer()
  def get_threshold_for_source(source_id) when is_integer(source_id) do
    case Repo.get(Source, source_id) do
      nil ->
        # Source not found, use default threshold
        Logger.warning("Source #{source_id} not found, using default freshness threshold")
        get_threshold()

      source ->
        get_threshold_for_slug(source.slug)
    end
  end

  @doc """
  Get the freshness threshold for a specific source by slug.
  Checks for source-specific overrides in config, falls back to default.

  ## Parameters
  - source_slug: The source slug (string like "repertuary", "cinema-city")

  ## Examples

      iex> get_threshold_for_slug("repertuary")
      24  # Daily scraping

      iex> get_threshold_for_slug("cinema-city")
      48  # Every 2 days

      iex> get_threshold_for_slug("bandsintown")
      168  # Default 7 days

  """
  @spec get_threshold_for_slug(String.t()) :: integer()
  def get_threshold_for_slug(source_slug) when is_binary(source_slug) do
    overrides =
      Application.get_env(:eventasaurus, :event_discovery, [])
      |> Keyword.get(:source_freshness_overrides, %{})

    Map.get(overrides, source_slug, get_threshold())
  end

  @doc """
  Get the default configured freshness threshold in hours.
  This is the fallback threshold used when no source-specific override exists.

  ## Examples

      iex> get_threshold()
      168  # 7 days default

  """
  @spec get_threshold() :: integer()
  def get_threshold do
    Application.get_env(:eventasaurus, :event_discovery, [])
    |> Keyword.get(:freshness_threshold_hours, 168)
  end

  # Extract external_id from event map (works with different scraper formats)
  defp extract_external_id(%{"external_id" => id}) when not is_nil(id), do: id
  defp extract_external_id(%{external_id: id}) when not is_nil(id), do: id
  defp extract_external_id(_), do: nil

  # Predict which event_id new events will merge into based on title + venue matching
  # This mimics the recurring event detection logic from EventProcessor
  #
  # This is critical for performance optimization:
  # - Ticketmaster returns 196 "Muzeum Banksy" events (one per day for 6+ months)
  # - Without prediction, all 196 would be processed as "stale" on every sync
  # - With prediction, if ANY of the 196 was recently processed, ALL are skipped
  # - Result: 196 jobs → 0-1 jobs (99.5% reduction)
  defp predict_recurring_event_ids(events, existing_mappings, _source_id) do
    # Only predict for events not already in the database
    new_events =
      events
      |> Enum.filter(fn event ->
        external_id = extract_external_id(event)
        external_id && !Map.has_key?(existing_mappings, external_id)
      end)

    Logger.debug(
      "🔮 Recurring prediction: #{length(new_events)} new events to check out of #{length(events)} total"
    )

    if Enum.empty?(new_events) do
      %{}
    else
      # Group by normalized title to find potential recurring series
      events_by_title =
        new_events
        |> Enum.group_by(fn event ->
          title = get_event_title(event)
          normalize_title(title)
        end)

      Logger.debug("🔮 Found #{map_size(events_by_title)} unique title groups")

      # For each group with multiple events, find the parent event they'll merge into
      predictions =
        events_by_title
        |> Enum.flat_map(fn {normalized_title, events_in_group} ->
          # Only check groups with 2+ events (potential recurring series)
          if length(events_in_group) >= 2 do
            # Get venue info from first event
            sample_event = List.first(events_in_group)
            venue_name = get_venue_name(sample_event)
            event_title = get_event_title(sample_event)

            Logger.debug(
              "🔮 Checking group '#{normalized_title}' with #{length(events_in_group)} events, venue: #{venue_name}"
            )

            if venue_name do
              # Find existing events with matching title at same/similar venue
              # Query timeout added for safety (typical: 5-15ms, max: 5s)
              matching_events =
                from(e in PublicEvent,
                  join: v in Venue,
                  on: e.venue_id == v.id,
                  where: fragment("similarity(?, ?) > ?", e.title, ^event_title, 0.85),
                  where: fragment("similarity(?, ?) > ?", v.name, ^venue_name, 0.7),
                  order_by: [asc: e.starts_at],
                  limit: 1,
                  select: e.id
                )
                |> Repo.all(timeout: 5_000)

              case matching_events do
                [event_id | _] ->
                  mappings =
                    events_in_group
                    |> Enum.map(fn event -> {extract_external_id(event), event_id} end)
                    |> Enum.reject(fn {ext_id, _} -> is_nil(ext_id) end)

                  Logger.info(
                    "🎯 Predicted #{length(events_in_group)} events will merge into event ##{event_id} (#{event_title}), created #{length(mappings)} mappings"
                  )

                  # Map all events in this group to the found parent event
                  mappings

                [] ->
                  Logger.debug(
                    "🔮 No existing event found for '#{normalized_title}', will create new"
                  )

                  # No parent found, won't merge
                  []
              end
            else
              Logger.debug(
                "🔮 No venue name found for group '#{normalized_title}', skipping prediction"
              )

              []
            end
          else
            []
          end
        end)
        |> Map.new()

      Logger.info("🔮 Predicted #{map_size(predictions)} events will merge into existing events")

      Logger.debug(
        "🔮 Prediction map size: #{map_size(predictions)}, sample: #{inspect(Enum.take(predictions, 3))}"
      )

      predictions
    end
  end

  defp get_event_title(%{"title" => title}), do: title
  defp get_event_title(%{title: title}), do: title
  defp get_event_title(_), do: nil

  defp get_venue_name(%{"venue_data" => %{"name" => name}}), do: name
  defp get_venue_name(%{"venue_data" => %{name: name}}), do: name
  defp get_venue_name(%{venue_data: %{"name" => name}}), do: name
  defp get_venue_name(%{venue_data: %{name: name}}), do: name
  defp get_venue_name(%{"venue" => %{"name" => name}}), do: name
  defp get_venue_name(%{venue: %{name: name}}), do: name
  defp get_venue_name(_), do: nil

  defp normalize_title(nil), do: ""

  defp normalize_title(title) do
    # Simple normalization for grouping events with identical titles
    # We use PostgreSQL's similarity() for fuzzy matching in the query,
    # so we don't need aggressive normalization here
    title
    |> String.downcase()
    |> String.trim()
  end

  # Check if an event has a recurrence_rule (recurring event)
  # Recurring events bypass freshness checking because they need starts_at updated
  # to the next occurrence on each scraper run
  defp has_recurrence_rule?(%{"recurrence_rule" => rule}) when not is_nil(rule), do: true
  defp has_recurrence_rule?(%{recurrence_rule: rule}) when not is_nil(rule), do: true
  defp has_recurrence_rule?(_), do: false
end
