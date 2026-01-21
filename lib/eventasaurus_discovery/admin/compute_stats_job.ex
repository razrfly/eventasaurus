defmodule EventasaurusDiscovery.Admin.ComputeStatsJob do
  @moduledoc """
  Oban worker for computing discovery stats in the background.

  This job runs every 15 minutes and computes all stats for the admin dashboard,
  storing the results in the discovery_stats_snapshots table.

  This architecture solves the OOM issue where stats computation was too memory-intensive
  for the 1GB web VM. The Oban job runs on a worker process and can be configured to
  run on a machine with more memory if needed.

  ## Why Background Computation?

  The stats computation involves:
  - 15 sources × 12+ quality check queries each
  - Multiple aggregation queries across 10K+ events
  - ~283 seconds of computation time
  - Peak memory usage that exceeds 1GB

  By computing in the background and storing results, the admin page load is instant.
  """

  use Oban.Worker,
    queue: :reports,
    max_attempts: 3,
    unique: [period: 300, states: [:available, :scheduled, :executing]]

  require Logger

  alias EventasaurusDiscovery.Admin.{
    DiscoveryStatsSnapshot,
    DiscoveryStatsCollector,
    SourceHealthCalculator,
    EventChangeTracker,
    DataQualityChecker
  }

  alias EventasaurusDiscovery.Sources.SourceRegistry
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  # Repo: Used for Repo.replica() read-only queries (uses read replica for performance)
  # This job only performs reads, so JobRepo is not needed
  alias EventasaurusApp.Repo

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: attempt}) do
    if attempt > 1 do
      Logger.info("🔄 Stats computation retry attempt #{attempt}/3")
    end

    Logger.info("📊 Starting background stats computation...")
    start_time = System.monotonic_time(:millisecond)

    try do
      stats = compute_all_stats()
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      # Store the snapshot with proper error handling
      case DiscoveryStatsSnapshot.insert(%{
             stats_data: stats,
             computed_at: DateTime.utc_now(),
             computation_time_ms: duration_ms,
             status: "completed"
           }) do
        {:ok, snapshot} ->
          # Cleanup old snapshots (keep last 10)
          DiscoveryStatsSnapshot.cleanup(10)

          Logger.info(
            "✅ Stats computation completed in #{duration_ms}ms (snapshot ##{snapshot.id})"
          )

          # Notify the cache that new stats are available
          notify_cache_updated()

          :ok

        {:error, changeset} ->
          Logger.error("❌ Failed to save stats snapshot: #{inspect(changeset.errors)}")
          {:error, "Failed to save snapshot"}
      end
    rescue
      e ->
        Logger.error("❌ Stats computation failed: #{Exception.message(e)}")
        Logger.error(Exception.format_stacktrace(__STACKTRACE__))
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Manually trigger stats computation (for admin use).
  """
  def trigger_now do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  # Notify DiscoveryStatsCache that new data is available
  defp notify_cache_updated do
    # Send a message to the cache GenServer to reload from database
    try do
      GenServer.cast(EventasaurusDiscovery.Admin.DiscoveryStatsCache, :reload_from_database)
    catch
      :exit, _ -> :ok
    end
  end

  # Main computation function - mirrors the old DiscoveryStatsCache.compute_stats/0
  # Includes explicit garbage collection between phases to reduce peak memory usage
  defp compute_all_stats do
    Logger.info("  → Fetching source list...")
    source_names = SourceRegistry.all_sources()

    Logger.info("  → Computing source stats for #{length(source_names)} sources...")
    source_stats = DiscoveryStatsCollector.get_metadata_based_source_stats(nil, source_names)
    gc_and_log("source stats")

    Logger.info("  → Computing change tracking...")
    change_stats = EventChangeTracker.get_all_source_changes(source_names, nil)
    gc_and_log("change tracking")

    Logger.info("  → Counting events per source...")
    event_counts = count_events_for_sources_batch(source_names)
    gc_and_log("event counts")

    # DISABLED: Quality checks cause OOM on 1GB VM (~783MB RAM used in 2 seconds)
    # The DataQualityChecker runs 15+ queries per source with Task.async_stream
    # Even with max_concurrency: 2, this exceeds available memory
    # TODO: Re-enable when we have a dedicated worker VM or larger instance
    Logger.info("  → Skipping quality checks (disabled due to memory constraints)...")
    quality_checks = %{}

    Logger.info("  → Building source data...")

    sources_data =
      build_sources_data(source_names, source_stats, change_stats, event_counts, quality_checks)

    # Clear intermediate data to free memory before final phase
    # These variables are no longer needed after building sources_data
    _ = {source_stats, change_stats, event_counts, quality_checks}
    gc_and_log("sources data build")

    Logger.info("  → Calculating overall health...")
    # Recalculate health from sources_data instead of keeping source_stats in scope
    overall_health = calculate_overall_health_from_sources(sources_data)

    Logger.info("  → Getting summary metrics...")
    total_sources = length(source_names)
    total_cities = count_cities()
    events_this_week = count_events_this_week()

    Logger.info("  → Getting city performance...")
    city_stats = get_city_performance()
    gc_and_log("city performance")

    %{
      sources_data: sources_data,
      overall_health: overall_health,
      total_sources: total_sources,
      total_cities: total_cities,
      events_this_week: events_this_week,
      city_stats: city_stats
    }
  end

  # Run garbage collection and log memory reclaimed
  defp gc_and_log(phase) do
    before = :erlang.memory(:total)
    :erlang.garbage_collect()
    after_gc = :erlang.memory(:total)
    freed_mb = Float.round((before - after_gc) / 1_048_576, 1)

    if freed_mb > 1 do
      Logger.info("  → GC after #{phase}: freed #{freed_mb}MB")
    end
  end

  # Calculate overall health from already-computed sources_data
  # This avoids keeping the full source_stats map in memory
  defp calculate_overall_health_from_sources(sources_data) do
    if Enum.empty?(sources_data) do
      0
    else
      {total_success, total_runs} =
        Enum.reduce(sources_data, {0, 0}, fn source, {success_acc, run_acc} ->
          stats = Map.get(source, :stats, %{})
          processed = Map.get(stats, :events_processed, 0)
          succeeded = Map.get(stats, :events_succeeded, 0)
          {success_acc + succeeded, run_acc + processed}
        end)

      if total_runs > 0 do
        (total_success / total_runs * 100) |> round()
      else
        0
      end
    end
  end

  defp build_sources_data(source_names, source_stats, change_stats, event_counts, quality_checks) do
    source_names
    |> Enum.map(fn source_name ->
      stats =
        Map.get(source_stats, source_name, %{
          events_processed: 0,
          events_succeeded: 0,
          events_failed: 0,
          run_count: 0,
          success_count: 0,
          error_count: 0,
          last_run_at: nil,
          last_error: nil
        })

      health_status = SourceHealthCalculator.calculate_health_score(stats)
      success_rate = SourceHealthCalculator.success_rate_percentage(stats)

      scope =
        case SourceRegistry.get_scope(source_name) do
          {:ok, scope} -> scope
          {:error, :not_found} -> "unknown"
        end

      event_count = Map.get(event_counts, source_name, 0)

      changes =
        Map.get(change_stats, source_name, %{
          new_events: 0,
          dropped_events: 0,
          percentage_change: 0
        })

      {trend_emoji, trend_text, trend_class} =
        EventChangeTracker.get_trend_indicator(changes.percentage_change)

      quality_data =
        Map.get(quality_checks, source_name, %{
          quality_score: 0,
          total_events: 0,
          not_found: true
        })

      {quality_emoji, quality_text, quality_class} =
        if Map.get(quality_data, :not_found, false) ||
             Map.get(quality_data, :total_events, 0) == 0 do
          {"⚪", "N/A", "text-gray-600"}
        else
          DataQualityChecker.quality_status(quality_data.quality_score)
        end

      %{
        name: source_name,
        scope: scope,
        stats: stats,
        health_status: health_status,
        success_rate: success_rate,
        event_count: event_count,
        new_events: changes.new_events,
        dropped_events: changes.dropped_events,
        percentage_change: changes.percentage_change,
        trend_emoji: trend_emoji,
        trend_text: trend_text,
        trend_class: trend_class,
        quality_score: quality_data.quality_score,
        quality_emoji: quality_emoji,
        quality_text: quality_text,
        quality_class: quality_class
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp count_events_for_sources_batch(source_names) when is_list(source_names) do
    query =
      from(pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
        join: s in EventasaurusDiscovery.Sources.Source,
        on: s.id == pes.source_id,
        where: s.slug in ^source_names,
        group_by: s.slug,
        select: {s.slug, count(pes.id)}
      )

    query
    |> Repo.replica().all(timeout: 60_000)
    |> Map.new()
  end

  defp count_cities do
    Repo.replica().aggregate(City, :count, :id, timeout: 30_000)
  end

  defp count_events_this_week do
    week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

    query =
      from(e in PublicEvent,
        where: e.inserted_at >= ^week_ago,
        select: count(e.id)
      )

    Repo.replica().one(query, timeout: 30_000) || 0
  end

  defp get_city_performance do
    # Get top 10 cities by event count directly from the database
    # We skip geographic clustering to avoid O(n²) memory issues
    query =
      from(e in PublicEvent,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == e.venue_id,
        join: c in City,
        on: c.id == v.city_id,
        group_by: [c.id, c.name, c.slug],
        having: count(e.id) >= 1,
        select: %{
          city_id: c.id,
          city_name: c.name,
          city_slug: c.slug,
          count: count(e.id)
        },
        order_by: [desc: count(e.id)],
        limit: 10
      )

    top_cities = Repo.replica().all(query, timeout: 30_000)

    # Batch calculate city changes for all top cities at once
    city_ids = Enum.map(top_cities, & &1.city_id)
    city_changes = calculate_city_changes_batch(city_ids)

    # Map the batched changes back to cities
    top_cities
    |> Enum.map(fn city ->
      change = Map.get(city_changes, city.city_id)

      city
      |> Map.put(:event_count, city.count)
      |> Map.put(:weekly_change, change)
    end)
  end

  defp calculate_city_changes_batch(city_ids) when is_list(city_ids) do
    now = DateTime.utc_now()
    one_week_ago = DateTime.add(now, -7, :day)
    two_weeks_ago = DateTime.add(now, -14, :day)

    query =
      from(e in PublicEvent,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == e.venue_id,
        where: v.city_id in ^city_ids,
        where: e.inserted_at >= ^two_weeks_ago,
        group_by: v.city_id,
        select: %{
          city_id: v.city_id,
          this_week: fragment("COUNT(CASE WHEN ? >= ? THEN 1 END)", e.inserted_at, ^one_week_ago),
          last_week:
            fragment(
              "COUNT(CASE WHEN ? >= ? AND ? < ? THEN 1 END)",
              e.inserted_at,
              ^two_weeks_ago,
              e.inserted_at,
              ^one_week_ago
            )
        }
      )

    city_stats =
      query
      |> Repo.replica().all(timeout: 30_000)
      |> Map.new(fn stats ->
        change =
          if stats.last_week > 0 do
            ((stats.this_week - stats.last_week) / stats.last_week * 100) |> round()
          else
            nil
          end

        {stats.city_id, change}
      end)

    city_stats
  end
end
