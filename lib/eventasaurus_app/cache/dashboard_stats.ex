defmodule EventasaurusApp.Cache.DashboardStats do
  @moduledoc """
  Centralized caching for admin dashboard statistics.

  This module provides cached versions of expensive database queries used by both
  AdminDashboardLive and DiscoveryDashboardLive. Uses Cachex for in-memory caching
  with TTL-based expiration.

  ## Read Replica Strategy

  All read queries in this module use `Repo.replica()` to route traffic to the
  read replica, reducing load on the primary database. This is especially important
  for expensive aggregation queries on large tables like `oban_jobs`.

  ## Cache TTL Strategy

  - Basic counts (events, venues, performers): 10 minutes - changes slowly, high query cost
  - Time-based counts (upcoming/past): 5 minutes - daily changes, moderate cost
  - Queue statistics: 1 minute - changes frequently, lower cost acceptable
  - Source/city statistics: 10 minutes - changes slowly, very high query cost
  - Job counts: 2 minutes - moderate update frequency

  ## Usage

      # All functions return {:ok, value} | {:error, reason}
      {:ok, count} = DashboardStats.get_total_events()
      {:ok, venues} = DashboardStats.get_unique_venues()
  """

  alias EventasaurusApp.{Repo, Monitoring, Venues}
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventPerformer, PublicEventSource}
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  alias EventasaurusDiscovery.Admin.DiscoveryStatsCollector
  alias EventasaurusDiscovery.Monitoring.Collisions
  alias EventasaurusDiscovery.Locations.CityHierarchy

  import Ecto.Query
  require Logger

  @cache_name :dashboard_stats

  # ========================================
  # Basic Event Counts (10 min TTL)
  # ========================================

  @doc """
  Get total count of all public events.
  Cached for 10 minutes.
  """
  def get_total_events do
    Cachex.fetch(@cache_name, :total_events, fn ->
      count = Repo.replica().aggregate(PublicEvent, :count, :id)
      {:commit, count, expire: :timer.minutes(10)}
    end)
  end

  @doc """
  Get count of unique venues.
  Cached for 10 minutes.
  """
  def get_unique_venues do
    Cachex.fetch(@cache_name, :unique_venues, fn ->
      count =
        Repo.replica().one(
          from(e in PublicEvent,
            where: not is_nil(e.venue_id),
            select: count(e.venue_id, :distinct)
          )
        ) || 0

      {:commit, count, expire: :timer.minutes(10)}
    end)
  end

  @doc """
  Get count of unique performers.
  Cached for 10 minutes.
  """
  def get_unique_performers do
    Cachex.fetch(@cache_name, :unique_performers, fn ->
      count =
        Repo.replica().aggregate(
          from(pep in PublicEventPerformer, select: pep.performer_id, distinct: true),
          :count,
          :performer_id
        )

      {:commit, count, expire: :timer.minutes(10)}
    end)
  end

  @doc """
  Get count of total categories.
  Cached for 10 minutes.
  """
  def get_total_categories do
    Cachex.fetch(@cache_name, :total_categories, fn ->
      count = Repo.replica().aggregate(Category, :count, :id)
      {:commit, count, expire: :timer.minutes(10)}
    end)
  end

  @doc """
  Get count of unique sources.
  Cached for 10 minutes.
  """
  def get_unique_sources do
    Cachex.fetch(@cache_name, :unique_sources, fn ->
      count =
        Repo.replica().one(
          from(s in PublicEventSource,
            select: count(s.source_id, :distinct)
          )
        ) || 0

      {:commit, count, expire: :timer.minutes(10)}
    end)
  end

  # ========================================
  # Time-Based Event Counts (5 min TTL)
  # ========================================

  @doc """
  Get count of upcoming events (starts_at >= now).
  Cached for 5 minutes.
  """
  def get_upcoming_events do
    Cachex.fetch(@cache_name, :upcoming_events, fn ->
      today = DateTime.utc_now()

      count =
        Repo.replica().aggregate(
          from(e in PublicEvent, where: e.starts_at >= ^today),
          :count,
          :id
        )

      {:commit, count, expire: :timer.minutes(5)}
    end)
  end

  @doc """
  Get count of past events (starts_at < now).
  Cached for 5 minutes.
  """
  def get_past_events do
    Cachex.fetch(@cache_name, :past_events, fn ->
      today = DateTime.utc_now()

      count =
        Repo.replica().aggregate(
          from(e in PublicEvent, where: e.starts_at < ^today),
          :count,
          :id
        )

      {:commit, count, expire: :timer.minutes(5)}
    end)
  end

  # ========================================
  # Job & Queue Statistics (1-2 min TTL)
  # ========================================

  @doc """
  Get count of active jobs from Monitoring module.
  Cached for 2 minutes.
  """
  def get_active_jobs_count do
    Cachex.fetch(@cache_name, :active_jobs_count, fn ->
      count =
        case Monitoring.get_summary_stats() do
          %{total_jobs: count} -> count
          _ -> 0
        end

      {:commit, count, expire: :timer.minutes(2)}
    end)
  rescue
    _ -> {:ok, 0}
  end

  @doc """
  Get count of geocoding jobs in queue (available/scheduled).
  Cached for 1 minute.
  """
  def get_geocoding_queue_count do
    Cachex.fetch(@cache_name, :geocoding_queue_count, fn ->
      # Use replica for read-heavy Oban queries to reduce primary DB load
      count =
        Repo.replica().one(
          from(j in Oban.Job,
            where:
              j.worker in [
                "EventasaurusDiscovery.Geocoding.Workers.GeocodingWorker",
                "EventasaurusDiscovery.Geocoding.Workers.BulkGeocodingWorker"
              ],
            where: j.state in ["available", "scheduled"],
            select: count(j.id)
          )
        ) || 0

      {:commit, count, expire: :timer.minutes(1)}
    end)
  rescue
    _ -> {:ok, 0}
  end

  @doc """
  Get count of recent scraper errors (last 24 hours).
  Cached for 2 minutes.

  Note: Updated in Issue #3048 Phase 3 to use job_execution_summaries
  instead of the deprecated scraper_processing_logs table.
  """
  def get_recent_scraper_errors do
    Cachex.fetch(@cache_name, :recent_scraper_errors, fn ->
      twenty_four_hours_ago = DateTime.add(DateTime.utc_now(), -24, :hour)

      count =
        Repo.replica().one(
          from(j in JobExecutionSummary,
            where: j.state in ["discarded", "cancelled"],
            where: j.attempted_at >= ^twenty_four_hours_ago,
            select: count(j.id)
          )
        ) || 0

      {:commit, count, expire: :timer.minutes(2)}
    end)
  rescue
    _ -> {:ok, 0}
  end

  @doc """
  Get queue statistics for discovery queues.
  Cached for 1 minute.
  """
  def get_queue_statistics do
    Cachex.fetch(@cache_name, :queue_statistics, fn ->
      queues = [:discovery]

      # Use replica for all Oban queries - these are read-heavy dashboard stats
      # that don't need real-time consistency
      stats =
        Enum.map(queues, fn queue ->
          available =
            Repo.replica().aggregate(
              from(j in Oban.Job,
                where: j.queue == ^to_string(queue) and j.state == "available"
              ),
              :count,
              :id
            ) || 0

          executing =
            Repo.replica().aggregate(
              from(j in Oban.Job,
                where: j.queue == ^to_string(queue) and j.state == "executing"
              ),
              :count,
              :id
            ) || 0

          scheduled =
            Repo.replica().aggregate(
              from(j in Oban.Job,
                where: j.queue == ^to_string(queue) and j.state == "scheduled"
              ),
              :count,
              :id
            ) || 0

          completed =
            Repo.replica().aggregate(
              from(j in Oban.Job,
                where: j.queue == ^to_string(queue) and j.state == "completed"
              ),
              :count,
              :id
            ) || 0

          %{
            name: queue,
            available: available,
            executing: executing,
            scheduled: scheduled,
            completed: completed,
            total: available + executing + scheduled
          }
        end)

      {:commit, stats, expire: :timer.minutes(1)}
    end)
  rescue
    _ -> {:ok, []}
  end

  # ========================================
  # Source Statistics (10 min TTL)
  # ========================================

  @doc """
  Get per-source event statistics.
  Cached for 10 minutes.
  """
  def get_source_statistics do
    Cachex.fetch(@cache_name, :source_statistics, fn ->
      stats =
        Repo.replica().all(
          from(pes in PublicEventSource,
            join: e in PublicEvent,
            on: e.id == pes.event_id,
            join: s in EventasaurusDiscovery.Sources.Source,
            on: s.id == pes.source_id,
            group_by: [s.id, s.name],
            select: %{
              source: s.name,
              count: count(pes.id),
              last_sync: max(pes.inserted_at)
            },
            order_by: [desc: count(pes.id)]
          )
        )

      {:commit, stats, expire: :timer.minutes(10)}
    end)
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Get detailed source statistics with success rates.
  Cached for 10 minutes.

  Note: This includes job history which is expensive to compute.
  """
  def get_detailed_source_statistics(opts \\ []) do
    min_events = Keyword.get(opts, :min_events, 1)
    cache_key = {:detailed_source_statistics, min_events}

    Cachex.fetch(@cache_name, cache_key, fn ->
      stats =
        DiscoveryStatsCollector.get_detailed_source_statistics(min_events: min_events)
        |> Enum.map(fn stats ->
          # Fetch last 10 jobs for each source
          job_history = DiscoveryStatsCollector.get_complete_run_history(stats.source, 10)
          Map.put(stats, :recent_jobs, job_history)
        end)

      {:commit, stats, expire: :timer.minutes(10)}
    end)
  rescue
    _ -> {:ok, []}
  end

  # ========================================
  # City Statistics (10 min TTL)
  # ========================================

  @doc """
  Get per-city event statistics (for discovery dashboard).
  Cached for 10 minutes.

  This is a complex query that combines active and inactive city stats.
  Delegates to the original implementation in DiscoveryDashboardLive.
  """
  def get_city_statistics(get_active_fn, get_inactive_fn) do
    Cachex.fetch(@cache_name, :city_statistics, fn ->
      # Call the provided functions to get stats
      active_stats = get_active_fn.() |> Enum.map(&Map.put(&1, :is_geographic, true))
      inactive_stats = get_inactive_fn.() |> Enum.map(&Map.put(&1, :is_geographic, false))

      combined_stats = active_stats ++ inactive_stats

      # Cluster Warsaw/Warszawa variations
      clustered_stats = cluster_city_names(combined_stats)

      {:commit, clustered_stats, expire: :timer.minutes(10)}
    end)
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Get per-city event statistics with geographic clustering.
  Cached for 10 minutes.

  This runs the expensive O(n²) geographic clustering algorithm,
  so caching is essential for performance.
  """
  def get_city_statistics_with_clustering(
        get_active_fn,
        get_inactive_fn,
        cluster_radius_km \\ 20.0
      ) do
    cache_key = {:city_statistics_clustered, cluster_radius_km}

    Cachex.fetch(@cache_name, cache_key, fn ->
      Logger.info("Computing city statistics with clustering (cache miss)")

      # Get active and inactive city stats
      active_stats = get_active_fn.() |> Enum.map(&Map.put(&1, :is_geographic, true))
      inactive_stats = get_inactive_fn.() |> Enum.map(&Map.put(&1, :is_geographic, false))

      combined_stats = active_stats ++ inactive_stats

      # Run the expensive geographic clustering
      clustered_stats =
        CityHierarchy.aggregate_stats_by_cluster(combined_stats, cluster_radius_km)

      # Sort by count descending
      sorted_stats = Enum.sort_by(clustered_stats, & &1.count, :desc)

      {:commit, sorted_stats, expire: :timer.minutes(10)}
    end)
  rescue
    e ->
      Logger.error("Error computing city statistics with clustering: #{inspect(e)}")
      {:ok, []}
  end

  # ========================================
  # Collision Statistics (5 min TTL)
  # ========================================

  @doc """
  Get collision summary for the dashboard.
  Cached for 5 minutes.

  This loads job execution summaries which can be expensive on large datasets.
  """
  def get_collision_summary(hours \\ 24) do
    cache_key = {:collision_summary, hours}

    Cachex.fetch(@cache_name, cache_key, fn ->
      Logger.info("Computing collision summary (cache miss)")

      result =
        case Collisions.summary(hours: hours) do
          {:ok, summary} -> summary
          {:error, _reason} -> nil
        end

      {:commit, result, expire: :timer.minutes(5)}
    end)
  rescue
    e ->
      Logger.error("Error computing collision summary: #{inspect(e)}")
      {:ok, nil}
  end

  # ========================================
  # Venue Duplicates (10 min TTL)
  # ========================================

  @doc """
  Get venue duplicate groups for the dashboard.
  Cached for 10 minutes.

  This performs similarity matching across venues which is expensive.
  Uses row_limit to prevent OOM on large datasets.
  """
  def get_venue_duplicates(row_limit \\ 100, min_similarity \\ 0.7) do
    cache_key = {:venue_duplicates, row_limit, min_similarity}

    Cachex.fetch(@cache_name, cache_key, fn ->
      Logger.info("Computing venue duplicates (cache miss)")

      duplicates =
        Venues.find_duplicate_groups(
          min_similarity: min_similarity,
          row_limit: row_limit
        )

      {:commit, duplicates, expire: :timer.minutes(10)}
    end)
  rescue
    e ->
      Logger.error("Error computing venue duplicates: #{inspect(e)}")
      {:ok, []}
  end

  # ========================================
  # Cache Management
  # ========================================

  @doc """
  Clear all cached statistics.
  Use when you need to force refresh all stats.
  """
  def invalidate_all do
    Cachex.clear(@cache_name)
  end

  @doc """
  Clear a specific cached statistic.
  """
  def invalidate(key) do
    Cachex.del(@cache_name, key)
  end

  @doc """
  Warm the cache by pre-loading common statistics.
  Call this on application startup or via scheduled job.
  """
  def warm_cache do
    Logger.info("Warming dashboard stats cache...")

    # Fire off all the basic queries
    get_total_events()
    get_unique_venues()
    get_unique_performers()
    get_total_categories()
    get_unique_sources()
    get_upcoming_events()
    get_past_events()
    get_queue_statistics()
    get_source_statistics()

    Logger.info("Dashboard stats cache warmed successfully")
  end

  @doc """
  Get cache statistics for monitoring.
  Returns hit rate, miss rate, and total requests.
  """
  def cache_stats do
    case Cachex.stats(@cache_name) do
      {:ok, stats} ->
        %{
          hits: stats.hits || 0,
          misses: stats.misses || 0,
          hit_rate: calculate_hit_rate(stats.hits, stats.misses)
        }

      _ ->
        %{hits: 0, misses: 0, hit_rate: 0.0}
    end
  end

  # ========================================
  # Private Helpers
  # ========================================

  defp calculate_hit_rate(nil, _), do: 0.0
  defp calculate_hit_rate(_, nil), do: 0.0
  defp calculate_hit_rate(0, 0), do: 0.0

  defp calculate_hit_rate(hits, misses) do
    total = hits + misses
    Float.round(hits / total * 100, 2)
  end

  defp cluster_city_names(stats) do
    # Group Warsaw/Warszawa variations
    warsaw_variations = ["Warsaw", "Warszawa", "warsaw", "warszawa"]

    # Find all Warsaw stats
    warsaw_stats = Enum.filter(stats, fn s -> s.city_name in warsaw_variations end)

    # Sum up Warsaw stats if multiple exist
    clustered_warsaw =
      if length(warsaw_stats) > 0 do
        total_count = Enum.reduce(warsaw_stats, 0, fn s, acc -> acc + s.count end)

        # Take the first ID (prefer the one that exists)
        city_id = Enum.find_value(warsaw_stats, fn s -> s.city_id end)

        [
          %{
            city_id: city_id,
            city_name: "Warsaw",
            count: total_count,
            is_geographic: Enum.any?(warsaw_stats, fn s -> s.is_geographic end)
          }
        ]
      else
        []
      end

    # Remove all Warsaw variations from original stats
    non_warsaw_stats = Enum.reject(stats, fn s -> s.city_name in warsaw_variations end)

    # Combine clustered Warsaw with other stats
    non_warsaw_stats ++ clustered_warsaw
  end
end
