defmodule EventasaurusDiscovery.Sources.BaseDedupHandler do
  @moduledoc """
  Shared deduplication logic for all event sources.

  This module provides common functionality for:
  1. Same-source deduplication (Phase 1)
  2. Cross-source domain-compatible deduplication (Phase 2)
  3. Confidence scoring and match filtering
  4. Collision data building for MetricsTracker integration

  ## Usage in Source-Specific Handlers

  Each source-specific dedup handler should:
  1. Call `find_by_external_id/2` for Phase 1 deduplication
  2. Implement source-specific fuzzy matching logic
  3. Call `filter_higher_priority_matches/2` to apply domain compatibility
  4. Use `should_defer_to_match?/3` to determine if a match should block import
  5. Build collision data for MetricsTracker using helper functions

  ## Collision Data Integration

  Use the collision data builders to record deduplication outcomes in
  job metadata for monitoring and analysis:

      alias EventasaurusDiscovery.Metrics.MetricsTracker
      alias EventasaurusDiscovery.Sources.BaseDedupHandler

      # Phase 1: Same-source dedup with collision tracking
      case BaseDedupHandler.find_by_external_id(external_id, source.id) do
        %Event{} = existing ->
          collision_data = BaseDedupHandler.build_same_source_collision(existing, "deferred")
          MetricsTracker.record_collision(job, external_id, collision_data)
          {:duplicate, existing}

        nil ->
          check_fuzzy_duplicate(event_data, source)
      end

      # Phase 2: Cross-source dedup with collision tracking
      case BaseDedupHandler.filter_higher_priority_matches(matches, source) do
        [] ->
          # No blocking matches - proceed with import
          {:unique, event_data}

        [%{event: existing, source: match_source} | _] ->
          # Found higher-priority match - defer
          collision_data = BaseDedupHandler.build_cross_source_collision(
            existing, match_source, confidence,
            ["performer", "venue", "date"], "deferred"
          )
          MetricsTracker.record_collision(job, external_id, collision_data)
          {:duplicate, existing}
      end

  ## Example

      defmodule MySource.DedupHandler do
        alias EventasaurusDiscovery.Sources.BaseDedupHandler

        def check_duplicate(event_data, source) do
          # Phase 1: Same-source dedup
          case BaseDedupHandler.find_by_external_id(event_data[:external_id], source.id) do
            %Event{} = existing -> {:duplicate, existing}
            nil -> check_fuzzy_duplicate(event_data, source)
          end
        end

        defp check_fuzzy_duplicate(event_data, source) do
          # Source-specific fuzzy matching logic
          matches = find_my_custom_matches(event_data)

          # Apply domain compatibility filtering
          case BaseDedupHandler.filter_higher_priority_matches(matches, source) do
            [] -> {:unique, event_data}
            [match | _] -> handle_match(event_data, match, source)
          end
        end
      end
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query

  @doc """
  Find an event by external_id for same-source deduplication (Phase 1).

  Only returns events that were imported by the specified source.
  This prevents a source from matching events imported by other sources.

  ## Parameters
  - `external_id` - The external ID from the source
  - `source_id` - The ID of the source that's checking

  ## Returns
  - `%Event{}` if found
  - `nil` if not found
  """
  def find_by_external_id(external_id, source_id) when is_binary(external_id) do
    query =
      from(e in Event,
        join: es in PublicEventSource,
        on: es.event_id == e.id,
        where:
          es.external_id == ^external_id and
            es.source_id == ^source_id and
            is_nil(e.deleted_at),
        limit: 1
      )

    Repo.one(query)
  end

  def find_by_external_id(_, _), do: nil

  @doc """
  Filter a list of potential matches to only those from higher-priority,
  domain-compatible sources.

  This implements the core domain compatibility logic that was previously
  duplicated across all dedup handlers.

  ## Parameters
  - `matches` - List of `%{event: event, source: source}` maps
  - `current_source` - The source struct that's checking for duplicates

  ## Returns
  List of matches that are:
  - Higher priority than current_source
  - Domain-compatible with current_source
  """
  def filter_higher_priority_matches(matches, current_source) do
    current_domains = current_source.domains || ["general"]
    current_priority = current_source.priority

    Enum.filter(matches, fn %{event: _event, source: source} ->
      is_higher_priority = source.priority > current_priority

      is_domain_compatible =
        Source.domains_compatible?(current_domains, source.domains || ["general"])

      is_higher_priority and is_domain_compatible
    end)
  end

  @doc """
  Determine if the current source should defer to a matched event.

  Checks if:
  1. The match is from a higher priority source
  2. The domains are compatible
  3. The confidence score is above threshold (default 0.8)

  ## Parameters
  - `match` - A `%{event: event, source: source}` map
  - `current_source` - The source struct that's checking
  - `confidence` - Match confidence score (0.0 to 1.0)
  - `opts` - Options
    - `:threshold` - Confidence threshold (default: 0.8)

  ## Returns
  - `true` if should defer (skip import)
  - `false` if should proceed with import
  """
  def should_defer_to_match?(match, current_source, confidence, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.8)
    %{source: match_source} = match

    is_higher_priority = match_source.priority > current_source.priority

    is_domain_compatible =
      Source.domains_compatible?(
        current_source.domains || ["general"],
        match_source.domains || ["general"]
      )

    meets_threshold = confidence > threshold

    is_higher_priority and is_domain_compatible and meets_threshold
  end

  @doc """
  Log a duplicate event detection with standardized format.

  ## Parameters
  - `current_source` - The source that found the duplicate
  - `event_data` - The event data being checked
  - `existing_event` - The existing event that was matched
  - `match_source` - The source of the existing event
  - `confidence` - Match confidence score
  """
  def log_duplicate(current_source, event_data, existing_event, match_source, confidence) do
    Logger.info("""
    🔍 Found likely duplicate from higher-priority, domain-compatible source
    #{current_source.name} Event: #{event_data[:title]}
    Existing: #{existing_event.title} (source: #{match_source.name}, priority: #{match_source.priority}, domains: #{inspect(match_source.domains)})
    Confidence: #{Float.round(confidence, 2)}
    """)
  end

  @doc """
  Query events within a date range and GPS proximity.

  This is a common pattern used by most dedup handlers for fuzzy matching.
  Returns events with their source information attached.

  ## Parameters
  - `date` - DateTime to search around
  - `latitude` - Venue latitude (optional)
  - `longitude` - Venue longitude (optional)
  - `opts` - Options
    - `:date_window_seconds` - Search window in seconds (default: 86400 = 1 day)
    - `:proximity_meters` - GPS proximity in meters (default: 500)

  ## Returns
  List of `%{event: event, source: source}` maps
  """
  def find_events_by_date_and_proximity(date, latitude, longitude, opts \\ []) do
    date_window = Keyword.get(opts, :date_window_seconds, 86400)
    proximity_meters = Keyword.get(opts, :proximity_meters, 500)

    date_start = DateTime.add(date, -date_window, :second)
    date_end = DateTime.add(date, date_window, :second)

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
            is_nil(e.deleted_at),
        preload: [venue: v],
        select: %{event: e, source: s}
      )

    # Add GPS proximity filter if coordinates available (using PostGIS)
    # Uses ST_MakePoint to match the venues_location_gist index definition
    query =
      if latitude && longitude do
        from([e, v, es, s] in query,
          where:
            fragment(
              "ST_DWithin(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
              v.longitude,
              v.latitude,
              ^longitude,
              ^latitude,
              ^proximity_meters
            )
        )
      else
        query
      end

    Repo.all(query)
  rescue
    e ->
      Logger.error("Error finding events by date and proximity: #{inspect(e)}")
      []
  end

  @doc """
  Check if a date is sane (not in the past, not too far in the future).

  ## Parameters
  - `datetime` - DateTime to validate
  - `opts` - Options
    - `:max_years_future` - Maximum years in future (default: 2)

  ## Returns
  - `true` if date is sane
  - `false` otherwise
  """
  def is_date_sane?(datetime, opts \\ []) do
    max_years = Keyword.get(opts, :max_years_future, 2)

    now = DateTime.utc_now()
    max_years_in_seconds = max_years * 365 * 24 * 60 * 60
    max_future = DateTime.add(now, max_years_in_seconds, :second)

    # Event should be in future (or current) but not more than max_years out
    DateTime.compare(datetime, now) in [:gt, :eq] &&
      DateTime.compare(datetime, max_future) == :lt
  end

  @doc """
  Calculate Haversine distance between two GPS coordinates.

  ## Parameters
  - `lat1` - First latitude
  - `lng1` - First longitude
  - `lat2` - Second latitude
  - `lng2` - Second longitude

  ## Returns
  Distance in meters
  """
  def calculate_distance(lat1, lng1, lat2, lng2) do
    # Earth radius in meters
    r = 6_371_000

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

  @doc """
  Check if two venues are at the same location within a threshold.

  ## Parameters
  - `lat1` - First latitude
  - `lng1` - First longitude
  - `lat2` - Second latitude (may be Decimal)
  - `lng2` - Second longitude (may be Decimal)
  - `opts` - Options
    - `:threshold_meters` - Maximum distance in meters (default: 500)

  ## Returns
  - `true` if within threshold
  - `false` otherwise
  """
  def same_location?(lat1, lng1, lat2, lng2, opts \\ []) do
    threshold = Keyword.get(opts, :threshold_meters, 500)

    cond do
      is_nil(lat1) || is_nil(lng1) || is_nil(lat2) || is_nil(lng2) ->
        false

      true ->
        # Convert Decimal to float if needed
        lat2_f = if is_struct(lat2, Decimal), do: Decimal.to_float(lat2), else: lat2
        lng2_f = if is_struct(lng2, Decimal), do: Decimal.to_float(lng2), else: lng2

        distance = calculate_distance(lat1, lng1, lat2_f, lng2_f)
        distance < threshold
    end
  end

  # ============================================================================
  # Collision Data Builders for MetricsTracker Integration
  # ============================================================================

  @doc """
  Build collision data for same-source deduplication (external_id match).

  Use this when Phase 1 deduplication finds an existing event from
  the same source with the same external_id.

  ## Parameters
  - `existing_event` - The existing event that was matched
  - `resolution` - How the collision was resolved: "deferred", "updated", "created"

  ## Returns
  Map suitable for passing to `MetricsTracker.record_collision/3` or
  `MetricsTracker.record_success/3` with collision_data option.

  ## Example

      case find_by_external_id(external_id, source.id) do
        %Event{} = existing ->
          collision_data = build_same_source_collision(existing, "deferred")
          MetricsTracker.record_collision(job, external_id, collision_data)
          {:duplicate, existing}
        nil ->
          check_fuzzy_duplicate(event_data, source)
      end
  """
  def build_same_source_collision(existing_event, resolution \\ "deferred") do
    %{
      type: :same_source,
      matched_event_id: existing_event.id,
      confidence: 1.0,
      resolution: resolution
    }
  end

  @doc """
  Build collision data for cross-source deduplication (fuzzy match).

  Use this when Phase 2 deduplication finds a matching event from
  a different source.

  ## Parameters
  - `existing_event` - The existing event that was matched
  - `match_source` - The source of the existing event
  - `confidence` - Match confidence score (0.0 to 1.0)
  - `match_factors` - List of factors used in matching (e.g., ["performer", "venue", "date", "gps"])
  - `resolution` - How the collision was resolved: "deferred", "created"

  ## Returns
  Map suitable for passing to `MetricsTracker.record_collision/3` or
  `MetricsTracker.record_success/3` with collision_data option.

  ## Example

      # When deferring to higher-priority source
      collision_data = build_cross_source_collision(
        existing_event, match_source, 0.85,
        ["performer", "venue", "date", "gps"], "deferred"
      )
      MetricsTracker.record_collision(job, external_id, collision_data)

      # When creating despite lower-priority match
      collision_data = build_cross_source_collision(
        existing_event, match_source, 0.75,
        ["performer", "date"], "created"
      )
      MetricsTracker.record_success(job, external_id, %{collision_data: collision_data})
  """
  def build_cross_source_collision(
        existing_event,
        match_source,
        confidence,
        match_factors,
        resolution \\ "deferred"
      ) do
    %{
      type: :cross_source,
      matched_event_id: existing_event.id,
      matched_source: match_source.slug || match_source.name,
      confidence: confidence,
      match_factors: match_factors,
      resolution: resolution
    }
  end

  @doc """
  Enhanced duplicate logging with collision data.

  Logs a duplicate event detection and returns collision_data suitable
  for MetricsTracker.

  ## Parameters
  - `current_source` - The source that found the duplicate
  - `event_data` - The event data being checked
  - `existing_event` - The existing event that was matched
  - `match_source` - The source of the existing event
  - `confidence` - Match confidence score
  - `match_factors` - List of factors used in matching
  - `resolution` - How the collision was resolved

  ## Returns
  Collision data map for MetricsTracker

  ## Example

      collision_data = log_duplicate_with_collision(
        source, event_data, existing, match_source,
        0.85, ["performer", "venue", "date"], "deferred"
      )
      MetricsTracker.record_collision(job, external_id, collision_data)
  """
  def log_duplicate_with_collision(
        current_source,
        event_data,
        existing_event,
        match_source,
        confidence,
        match_factors,
        resolution
      ) do
    Logger.info("""
    🔍 Found likely duplicate from higher-priority, domain-compatible source
    #{current_source.name} Event: #{event_data[:title]}
    Existing: #{existing_event.title} (source: #{match_source.name}, priority: #{match_source.priority}, domains: #{inspect(match_source.domains)})
    Confidence: #{Float.round(confidence, 2)}
    Match factors: #{inspect(match_factors)}
    Resolution: #{resolution}
    """)

    build_cross_source_collision(
      existing_event,
      match_source,
      confidence,
      match_factors,
      resolution
    )
  end
end
