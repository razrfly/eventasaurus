defmodule EventasaurusDiscovery.Admin.CityHealthCalculator do
  @moduledoc """
  Calculates health scores for cities using a 4-component formula:

  - Event Coverage (40%): Days with events in last 14 days
  - Source Activity (30%): Recent sync job success rate for city
  - Data Quality (20%): Events with complete metadata
  - Venue Health (10%): Venues with complete information

  Health Score Thresholds:
  - Healthy (🟢): >= 80
  - Warning (🟡): 50-79
  - Critical (🔴): < 50
  - Disabled (⚪): Discovery not enabled
  """

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  # Component weights (must sum to 100)
  @event_coverage_weight 40
  @source_activity_weight 30
  @data_quality_weight 20
  @venue_health_weight 10

  # Thresholds
  @healthy_threshold 80
  @warning_threshold 50

  # Analysis window
  @coverage_days 14
  @job_activity_hours 168  # 7 days

  # PHASE 1 FIX: Reduced default timeout from 60s to 10s to prevent OOM
  @default_timeout 10_000

  @doc """
  Calculate the health score for a single city.

  Returns a map with:
  - health_score: Integer 0-100
  - health_status: :healthy | :warning | :critical | :disabled
  - components: Breakdown of each component score
  """
  def calculate_city_health(city_id, opts \\ []) do
    city = get_city(city_id)

    if city == nil do
      {:error, :city_not_found}
    else
      if not city.discovery_enabled do
        {:ok, %{
          city_id: city_id,
          health_score: 0,
          health_status: :disabled,
          components: %{
            event_coverage: 0,
            source_activity: 0,
            data_quality: 0,
            venue_health: 0
          }
        }}
      else
        components = calculate_components(city_id, opts)
        health_score = calculate_weighted_score(components)
        health_status = score_to_status(health_score)

        {:ok, %{
          city_id: city_id,
          health_score: health_score,
          health_status: health_status,
          components: components
        }}
      end
    end
  end

  @doc """
  Calculate health scores for all active cities.

  Options:
  - include_disabled: Include cities with discovery disabled (default: false)
  - limit: Maximum number of cities to return (default: nil - all cities)
  - offset: Number of cities to skip for pagination (default: 0)
  - timeout: Query timeout in milliseconds (default: 10_000)

  Returns a list of city health maps sorted by event count (descending).
  Filters to only cities with discovery_enabled by default.
  """
  def calculate_all_cities_health(opts \\ []) do
    include_disabled = Keyword.get(opts, :include_disabled, false)
    active_only = Keyword.get(opts, :active_only, false)
    limit = Keyword.get(opts, :limit, nil)
    offset = Keyword.get(opts, :offset, 0)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Get cities ordered by event count
    # When active_only is true, HAVING clause filters to event_count > 0 BEFORE pagination
    cities = get_cities_with_event_counts(include_disabled, limit, offset, timeout, active_only)

    # Batch calculate all component data
    city_ids = Enum.map(cities, & &1.id)

    # Batch queries for efficiency with configurable timeout
    event_coverage_data = batch_event_coverage(city_ids, timeout)
    source_activity_data = batch_source_activity(city_ids, timeout)
    data_quality_data = batch_data_quality(city_ids, timeout)
    venue_health_data = batch_venue_health(city_ids, timeout)

    # Build results
    Enum.map(cities, fn city ->
      if not city.discovery_enabled do
        %{
          city_id: city.id,
          city_name: city.name,
          city_slug: city.slug,
          discovery_enabled: false,
          event_count: city.event_count,
          venue_count: city.venue_count,
          health_score: 0,
          health_status: :disabled,
          components: %{
            event_coverage: 0,
            source_activity: 0,
            data_quality: 0,
            venue_health: 0
          }
        }
      else
        components = %{
          event_coverage: Map.get(event_coverage_data, city.id, 0),
          source_activity: Map.get(source_activity_data, city.id, 0),
          data_quality: Map.get(data_quality_data, city.id, 0),
          venue_health: Map.get(venue_health_data, city.id, 0)
        }

        health_score = calculate_weighted_score(components)
        health_status = score_to_status(health_score)

        %{
          city_id: city.id,
          city_name: city.name,
          city_slug: city.slug,
          discovery_enabled: true,
          event_count: city.event_count,
          venue_count: city.venue_count,
          health_score: health_score,
          health_status: health_status,
          components: components
        }
      end
    end)
  end

  @doc """
  Get only active cities (those with at least one event).
  Ordered by event count descending.

  Options:
  - limit: Maximum number of cities to return (default: 50)
  - offset: Number of cities to skip for pagination (default: 0)
  - timeout: Query timeout in milliseconds (default: 10_000)

  Note: event_count includes all events associated with the city,
  not just recent ones. The health score components (event_coverage,
  source_activity, etc.) use time-windowed queries for accuracy.

  Important: The active_only filter (event_count > 0) is applied BEFORE
  pagination to ensure consistent page sizes.
  """
  def get_active_cities_health(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Pass active_only: true to filter at query level BEFORE pagination
    # This ensures page sizes are consistent (no post-fetch filtering)
    calculate_all_cities_health(
      include_disabled: false,
      active_only: true,
      limit: limit,
      offset: offset,
      timeout: timeout
    )
  end

  @doc """
  Count the total number of active cities (those with events and discovery enabled).
  Used for pagination.
  """
  def count_active_cities(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    query =
      from(c in City,
        join: v in Venue,
        on: v.city_id == c.id,
        join: e in PublicEvent,
        on: e.venue_id == v.id,
        where: c.discovery_enabled == true,
        select: count(c.id, :distinct)
      )

    Repo.replica().one(query, timeout: timeout) || 0
  end

  @doc """
  Compute batch health scores for a list of city IDs.
  Returns a map of city_id -> health_score.
  Used by CityHealthMonitorJob for efficient monitoring.
  """
  def batch_health_scores(city_ids, opts \\ []) when is_list(city_ids) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    if Enum.empty?(city_ids) do
      %{}
    else
      # Batch queries for efficiency
      event_coverage_data = batch_event_coverage(city_ids, timeout)
      source_activity_data = batch_source_activity(city_ids, timeout)
      data_quality_data = batch_data_quality(city_ids, timeout)
      venue_health_data = batch_venue_health(city_ids, timeout)

      city_ids
      |> Enum.map(fn city_id ->
        components = %{
          event_coverage: Map.get(event_coverage_data, city_id, 0),
          source_activity: Map.get(source_activity_data, city_id, 0),
          data_quality: Map.get(data_quality_data, city_id, 0),
          venue_health: Map.get(venue_health_data, city_id, 0)
        }

        {city_id, calculate_weighted_score(components)}
      end)
      |> Map.new()
    end
  end

  # ============================================================================
  # Component Calculations
  # ============================================================================

  defp calculate_components(city_id, _opts) do
    %{
      event_coverage: calculate_event_coverage(city_id),
      source_activity: calculate_source_activity(city_id),
      data_quality: calculate_data_quality(city_id),
      venue_health: calculate_venue_health(city_id)
    }
  end

  @doc """
  Event Coverage (40%): Days with events in the last 14 days (including today).
  Score = (days_with_events / 14) * 100
  """
  def calculate_event_coverage(city_id) do
    today = Date.utc_today()
    # Use -(@coverage_days - 1) to get exactly @coverage_days days including today
    # E.g., for 14 days: today (0), -1, -2, ..., -13 = 14 days
    start_date = Date.add(today, -(@coverage_days - 1))

    # Count distinct dates with events
    query =
      from(pe in PublicEvent,
        join: v in Venue,
        on: v.id == pe.venue_id,
        where: v.city_id == ^city_id,
        where: fragment("?::date", pe.starts_at) >= ^start_date,
        where: fragment("?::date", pe.starts_at) <= ^today,
        select: count(fragment("DISTINCT ?::date", pe.starts_at))
      )

    days_with_events = Repo.replica().one(query, timeout: 30_000) || 0

    # Score: percentage of days covered
    min(100, round(days_with_events / @coverage_days * 100))
  end

  @doc """
  Source Activity (30%): Job success rate for city-related jobs in last 7 days.
  Score = (successful_jobs / total_jobs) * 100

  Note: JobExecutionSummary uses Oban states: 'completed' (success), 'retryable' (failed),
  'cancelled', 'discarded'. We count 'completed' as successful.
  """
  def calculate_source_activity(city_id) do
    city = get_city(city_id)

    if city == nil do
      0
    else
      hours_ago = DateTime.utc_now() |> DateTime.add(-@job_activity_hours, :hour)

      # Query jobs that have this city's slug in their args
      # Note: Oban uses 'completed' for successful jobs, not 'success'
      query =
        from(j in JobExecutionSummary,
          where: j.attempted_at >= ^hours_ago,
          where: fragment("?->>'city_slug' = ?", j.args, ^city.slug),
          select: %{
            total: count(j.id),
            successful: sum(fragment("CASE WHEN ? = 'completed' THEN 1 ELSE 0 END", j.state))
          }
        )

      result = Repo.replica().one(query, timeout: 30_000)

      cond do
        result == nil or result.total == 0 ->
          # No jobs = assume healthy (source may not have city-scoped jobs)
          100

        true ->
          successful = result.successful || 0
          round(successful / result.total * 100)
      end
    end
  end

  @doc """
  Data Quality (20%): Percentage of events with complete metadata.
  Checks: title, venue_id, and has at least one category in join table.

  Note: Categories use the public_event_categories join table, NOT the legacy
  category_id column on public_events (which is deprecated).
  """
  def calculate_data_quality(city_id) do
    query =
      from(pe in PublicEvent,
        join: v in Venue,
        on: v.id == pe.venue_id,
        where: v.city_id == ^city_id,
        select: %{
          total: count(pe.id),
          complete:
            sum(
              fragment(
                """
                CASE WHEN
                  ? IS NOT NULL AND ? != '' AND
                  ? IS NOT NULL AND
                  EXISTS (SELECT 1 FROM public_event_categories pec WHERE pec.event_id = ?)
                THEN 1 ELSE 0 END
                """,
                pe.title,
                pe.title,
                pe.venue_id,
                pe.id
              )
            )
        }
      )

    result = Repo.replica().one(query, timeout: 30_000)

    cond do
      result == nil or result.total == 0 -> 0
      true ->
        complete = result.complete || 0
        round(complete / result.total * 100)
    end
  end

  @doc """
  Venue Health (10%): Percentage of venues with complete information.
  Checks: name, address
  """
  def calculate_venue_health(city_id) do
    query =
      from(v in Venue,
        where: v.city_id == ^city_id,
        select: %{
          total: count(v.id),
          complete:
            sum(
              fragment(
                """
                CASE WHEN
                  ? IS NOT NULL AND ? != '' AND
                  ? IS NOT NULL AND ? != ''
                THEN 1 ELSE 0 END
                """,
                v.name,
                v.name,
                v.address,
                v.address
              )
            )
        }
      )

    result = Repo.replica().one(query, timeout: 30_000)

    cond do
      result == nil or result.total == 0 -> 0
      true ->
        complete = result.complete || 0
        round(complete / result.total * 100)
    end
  end

  # ============================================================================
  # Batch Calculations (for calculating all cities efficiently)
  # ============================================================================

  defp batch_event_coverage(city_ids, timeout) when is_list(city_ids) do
    today = Date.utc_today()
    # Use -(@coverage_days - 1) to get exactly @coverage_days days including today
    start_date = Date.add(today, -(@coverage_days - 1))

    query =
      from(pe in PublicEvent,
        join: v in Venue,
        on: v.id == pe.venue_id,
        where: v.city_id in ^city_ids,
        where: fragment("?::date", pe.starts_at) >= ^start_date,
        where: fragment("?::date", pe.starts_at) <= ^today,
        group_by: v.city_id,
        select: {v.city_id, count(fragment("DISTINCT ?::date", pe.starts_at))}
      )

    query
    |> Repo.replica().all(timeout: timeout)
    |> Enum.map(fn {city_id, days} ->
      {city_id, min(100, round(days / @coverage_days * 100))}
    end)
    |> Map.new()
  end

  defp batch_source_activity(city_ids, timeout) when is_list(city_ids) do
    # Get city slugs for the ids
    cities = Repo.replica().all(from(c in City, where: c.id in ^city_ids, select: {c.id, c.slug}), timeout: timeout)
    city_slugs = Map.new(cities)
    slugs = Map.values(city_slugs)

    if Enum.empty?(slugs) do
      %{}
    else
      hours_ago = DateTime.utc_now() |> DateTime.add(-@job_activity_hours, :hour)

      query =
        from(j in JobExecutionSummary,
          where: j.attempted_at >= ^hours_ago,
          where: fragment("?->>'city_slug' = ANY(?)", j.args, ^slugs),
          group_by: fragment("?->>'city_slug'", j.args),
          select: {
            fragment("?->>'city_slug'", j.args),
            count(j.id),
            sum(fragment("CASE WHEN ? = 'completed' THEN 1 ELSE 0 END", j.state))
          }
        )

      # Map slug -> score
      slug_scores =
        query
        |> Repo.replica().all(timeout: timeout)
        |> Enum.map(fn {slug, total, successful} ->
          successful = successful || 0
          score = if total > 0, do: round(successful / total * 100), else: 100
          {slug, score}
        end)
        |> Map.new()

      # Map city_id -> score
      city_ids
      |> Enum.map(fn city_id ->
        slug = Map.get(city_slugs, city_id)
        score = Map.get(slug_scores, slug, 100)  # Default 100 if no jobs
        {city_id, score}
      end)
      |> Map.new()
    end
  end

  defp batch_data_quality(city_ids, timeout) when is_list(city_ids) do
    query =
      from(pe in PublicEvent,
        join: v in Venue,
        on: v.id == pe.venue_id,
        where: v.city_id in ^city_ids,
        group_by: v.city_id,
        select: {
          v.city_id,
          count(pe.id),
          sum(
            fragment(
              """
              CASE WHEN
                ? IS NOT NULL AND ? != '' AND
                ? IS NOT NULL AND
                ? IS NOT NULL
              THEN 1 ELSE 0 END
              """,
              pe.title,
              pe.title,
              pe.venue_id,
              pe.category_id
            )
          )
        }
      )

    query
    |> Repo.replica().all(timeout: timeout)
    |> Enum.map(fn {city_id, total, complete} ->
      complete = complete || 0
      score = if total > 0, do: round(complete / total * 100), else: 0
      {city_id, score}
    end)
    |> Map.new()
  end

  defp batch_venue_health(city_ids, timeout) when is_list(city_ids) do
    query =
      from(v in Venue,
        where: v.city_id in ^city_ids,
        group_by: v.city_id,
        select: {
          v.city_id,
          count(v.id),
          sum(
            fragment(
              """
              CASE WHEN
                ? IS NOT NULL AND ? != '' AND
                ? IS NOT NULL AND ? != ''
              THEN 1 ELSE 0 END
              """,
              v.name,
              v.name,
              v.address,
              v.address
            )
          )
        }
      )

    query
    |> Repo.replica().all(timeout: timeout)
    |> Enum.map(fn {city_id, total, complete} ->
      complete = complete || 0
      score = if total > 0, do: round(complete / total * 100), else: 0
      {city_id, score}
    end)
    |> Map.new()
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp calculate_weighted_score(components) do
    score =
      components.event_coverage * @event_coverage_weight / 100 +
      components.source_activity * @source_activity_weight / 100 +
      components.data_quality * @data_quality_weight / 100 +
      components.venue_health * @venue_health_weight / 100

    round(score)
  end

  defp score_to_status(score) do
    cond do
      score >= @healthy_threshold -> :healthy
      score >= @warning_threshold -> :warning
      true -> :critical
    end
  end

  defp get_city(city_id) do
    Repo.replica().get(City, city_id)
  end

  defp get_cities_with_event_counts(include_disabled, limit, offset, timeout, active_only) do
    base_query =
      from(c in City,
        left_join: v in Venue,
        on: v.city_id == c.id,
        left_join: e in PublicEvent,
        on: e.venue_id == v.id,
        group_by: [c.id, c.name, c.slug, c.discovery_enabled],
        select: %{
          id: c.id,
          name: c.name,
          slug: c.slug,
          discovery_enabled: c.discovery_enabled,
          event_count: count(e.id, :distinct),
          venue_count: count(v.id, :distinct)
        },
        order_by: [desc: count(e.id, :distinct)]
      )

    query =
      if include_disabled do
        base_query
      else
        from([c, v, e] in base_query, where: c.discovery_enabled == true)
      end

    # Apply HAVING clause to filter cities with events BEFORE pagination
    # This ensures consistent page sizes when active_only is true
    query =
      if active_only do
        from([c, v, e] in query, having: count(e.id, :distinct) > 0)
      else
        query
      end

    query =
      if limit do
        from(q in query, limit: ^limit, offset: ^offset)
      else
        from(q in query, offset: ^offset)
      end

    Repo.replica().all(query, timeout: timeout)
  end

  # ============================================================================
  # Status Helpers (for UI consistency)
  # ============================================================================

  @doc """
  Get the status emoji for a health status.
  """
  def status_emoji(:healthy), do: "🟢"
  def status_emoji(:warning), do: "🟡"
  def status_emoji(:critical), do: "🔴"
  def status_emoji(:disabled), do: "⚪"
  def status_emoji(_), do: "⚪"

  @doc """
  Get the status text for a health status.
  """
  def status_text(:healthy), do: "Healthy"
  def status_text(:warning), do: "Warning"
  def status_text(:critical), do: "Critical"
  def status_text(:disabled), do: "Disabled"
  def status_text(_), do: "Unknown"

  @doc """
  Get CSS classes for a health status badge.
  """
  def status_classes(:healthy), do: "bg-green-100 text-green-800"
  def status_classes(:warning), do: "bg-yellow-100 text-yellow-800"
  def status_classes(:critical), do: "bg-red-100 text-red-800"
  def status_classes(:disabled), do: "bg-gray-100 text-gray-800"
  def status_classes(_), do: "bg-gray-100 text-gray-800"

  @doc """
  Get border color class for health status.
  """
  def status_border(:healthy), do: "border-green-500"
  def status_border(:warning), do: "border-yellow-500"
  def status_border(:critical), do: "border-red-500"
  def status_border(:disabled), do: "border-gray-400"
  def status_border(_), do: "border-gray-400"
end
