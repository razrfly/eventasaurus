defmodule EventasaurusWeb.Admin.UnifiedDashboardStats do
  @moduledoc """
  Aggregates stats from multiple sources for the unified admin dashboard.

  Provides staged loading with parallel data fetching to prevent timeout issues.
  Uses Task.async_stream with controlled concurrency for database queries.

  Stats are organized into tiers:
  - Tier 1 (Critical): System health, errors, queue status
  - Tier 2 (Important): Events, venues, movies, images
  - Tier 3 (Context): Geocoding, collisions, detailed breakdowns
  """

  require Logger

  alias EventasaurusApp.Cache.DashboardStats
  alias EventasaurusApp.Images.ImageCacheStatsCache
  alias EventasaurusDiscovery.Metrics.GeocodingStats
  alias EventasaurusDiscovery.Monitoring.Health
  alias EventasaurusDiscovery.Movies.MatchingStats

  @doc """
  Fetches Tier 1 critical stats (health, errors, queue, alerts, freshness).
  These load first as they're most important for operations.
  """
  def fetch_tier1_stats do
    tasks = [
      {:health, fn -> fetch_health_summary() end},
      {:queue, fn -> fetch_queue_stats() end},
      {:alerts, fn -> fetch_alerts_summary() end},
      {:freshness, fn -> fetch_data_freshness() end}
    ]

    tasks
    |> Task.async_stream(fn {key, func} -> {key, func.()} end,
      max_concurrency: 4,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {key, value}}, acc -> Map.put(acc, key, value)
      {:exit, _reason}, acc -> acc
    end)
  end

  @doc """
  Fetches Tier 2 important stats (events, movies, images, geocoding, data quality).
  """
  def fetch_tier2_stats do
    tasks = [
      {:events, fn -> fetch_event_stats() end},
      {:movies, fn -> fetch_movie_stats() end},
      {:images, fn -> fetch_image_stats() end},
      {:geocoding, fn -> fetch_geocoding_stats() end},
      {:data_quality, fn -> fetch_data_quality_stats() end}
    ]

    tasks
    |> Task.async_stream(fn {key, func} -> {key, func.()} end,
      max_concurrency: 3,
      timeout: 15_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {key, value}}, acc -> Map.put(acc, key, value)
      {:exit, _reason}, acc -> acc
    end)
  end

  @doc """
  Fetches Tier 3 context stats (geocoding, collisions).
  """
  def fetch_tier3_stats do
    tasks = [
      {:geocoding, fn -> fetch_geocoding_stats() end},
      {:collisions, fn -> fetch_collision_stats() end},
      {:sources, fn -> fetch_source_stats() end}
    ]

    tasks
    |> Task.async_stream(fn {key, func} -> {key, func.()} end,
      max_concurrency: 2,
      timeout: 15_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {key, value}}, acc -> Map.put(acc, key, value)
      {:exit, _reason}, acc -> acc
    end)
  end

  @doc """
  Fetches all stats in one call (for simpler use cases).
  Not recommended for initial page load due to potential timeout.
  """
  def fetch_all_stats do
    tier1 = fetch_tier1_stats()
    tier2 = fetch_tier2_stats()
    tier3 = fetch_tier3_stats()

    Map.merge(tier1, tier2) |> Map.merge(tier3)
  end

  # Private fetch functions

  defp fetch_health_summary do
    sources = discover_sources()

    health_results =
      sources
      |> Task.async_stream(
        fn source ->
          case Health.check(source, hours: 24) do
            {:ok, health} ->
              score = Health.score(health)
              meeting_slos = Health.meeting_slos?(health)
              {source, %{score: score, meeting_slos: meeting_slos, status: :ok}}

            {:error, _reason} ->
              {source, %{score: 0, meeting_slos: false, status: :error}}
          end
        end,
        max_concurrency: 3,
        timeout: 5_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{}, fn
        {:ok, {source, data}}, acc -> Map.put(acc, source, data)
        {:exit, _}, acc -> acc
      end)

    # Calculate aggregate health
    scores = health_results |> Map.values() |> Enum.map(& &1.score)

    avg_score =
      if Enum.empty?(scores), do: 0, else: Enum.sum(scores) / length(scores)

    sources_meeting_slo =
      health_results
      |> Map.values()
      |> Enum.count(& &1.meeting_slos)

    %{
      sources: health_results,
      avg_score: Float.round(avg_score, 1),
      sources_meeting_slo: sources_meeting_slo,
      total_sources: length(sources),
      status: health_status(avg_score)
    }
  rescue
    e ->
      Logger.error("Failed to fetch health summary: #{Exception.message(e)}")
      %{sources: %{}, avg_score: 0, sources_meeting_slo: 0, total_sources: 0, status: :error}
  end

  defp fetch_queue_stats do
    case DashboardStats.get_queue_statistics() do
      stats when is_map(stats) ->
        %{
          available: stats[:available] || 0,
          scheduled: stats[:scheduled] || 0,
          executing: stats[:executing] || 0,
          retryable: stats[:retryable] || 0,
          discarded: stats[:discarded] || 0,
          total_pending: (stats[:available] || 0) + (stats[:scheduled] || 0)
        }

      _ ->
        %{available: 0, scheduled: 0, executing: 0, retryable: 0, discarded: 0, total_pending: 0}
    end
  rescue
    e ->
      Logger.error("Failed to fetch queue stats: #{Exception.message(e)}")
      %{available: 0, scheduled: 0, executing: 0, retryable: 0, discarded: 0, total_pending: 0}
  end

  defp fetch_alerts_summary do
    # Aggregate alerts from multiple sources
    alerts = []

    # Check for sources not meeting SLO
    sources = discover_sources()

    source_alerts =
      sources
      |> Enum.reduce([], fn source, acc ->
        case Health.check(source, hours: 24) do
          {:ok, health} ->
            if not Health.meeting_slos?(health) do
              score = Health.score(health)
              severity = if score < 70, do: :critical, else: :warning

              [
                %{
                  type: :source_health,
                  source: source,
                  message: "#{format_source_name(source)} health at #{Float.round(score, 1)}%",
                  severity: severity,
                  timestamp: DateTime.utc_now()
                }
                | acc
              ]
            else
              acc
            end

          {:error, _} ->
            [
              %{
                type: :source_error,
                source: source,
                message: "#{format_source_name(source)} health check failed",
                severity: :critical,
                timestamp: DateTime.utc_now()
              }
              | acc
            ]
        end
      end)

    # Check for retryable jobs
    queue_stats = fetch_queue_stats()

    queue_alerts =
      if queue_stats.retryable > 0 do
        severity = if queue_stats.retryable > 10, do: :critical, else: :warning

        [
          %{
            type: :queue,
            source: "oban",
            message: "#{queue_stats.retryable} jobs retrying",
            severity: severity,
            timestamp: DateTime.utc_now()
          }
        ]
      else
        []
      end

    # Check for image failures
    image_alerts =
      case ImageCacheStatsCache.get_stats() do
        %{stats: stats} when is_map(stats) ->
          summary = stats[:summary] || stats["summary"] || %{}
          failed = summary[:failed_images] || summary["failed_images"] || 0

          if failed > 0 do
            severity = if failed > 10, do: :warning, else: :info

            [
              %{
                type: :image_cache,
                source: "images",
                message: "#{failed} image downloads failed",
                severity: severity,
                timestamp: DateTime.utc_now()
              }
            ]
          else
            []
          end

        _ ->
          []
      end

    all_alerts = alerts ++ source_alerts ++ queue_alerts ++ image_alerts

    # Count by severity
    critical_count = Enum.count(all_alerts, &(&1.severity == :critical))
    warning_count = Enum.count(all_alerts, &(&1.severity == :warning))
    info_count = Enum.count(all_alerts, &(&1.severity == :info))

    overall_severity =
      cond do
        critical_count > 0 -> :critical
        warning_count > 0 -> :warning
        info_count > 0 -> :info
        true -> :ok
      end

    %{
      total: length(all_alerts),
      critical: critical_count,
      warning: warning_count,
      info: info_count,
      severity: overall_severity,
      recent: Enum.take(all_alerts, 5)
    }
  rescue
    e ->
      Logger.error("Failed to fetch alerts summary: #{Exception.message(e)}")
      %{total: 0, critical: 0, warning: 0, info: 0, severity: :ok, recent: []}
  end

  defp fetch_data_freshness do
    sources = discover_sources()

    # Get source statistics for last sync times
    source_stats =
      case DashboardStats.get_source_statistics() do
        stats when is_list(stats) ->
          stats
          |> Enum.map(fn source ->
            name = source[:source] || source["source"]
            last_sync = source[:last_sync] || source["last_sync"]
            {name, last_sync}
          end)
          |> Enum.into(%{})

        _ ->
          %{}
      end

    now = DateTime.utc_now()

    # Calculate freshness for each source
    source_freshness =
      sources
      |> Enum.map(fn source ->
        last_sync = Map.get(source_stats, source)

        {synced_today, hours_ago} =
          case last_sync do
            %DateTime{} = dt ->
              hours = DateTime.diff(now, dt, :hour)
              {hours < 24, hours}

            %NaiveDateTime{} = ndt ->
              dt = DateTime.from_naive!(ndt, "Etc/UTC")
              hours = DateTime.diff(now, dt, :hour)
              {hours < 24, hours}

            _ ->
              {false, nil}
          end

        %{
          source: source,
          last_sync: last_sync,
          synced_today: synced_today,
          hours_ago: hours_ago
        }
      end)

    synced_today_count = Enum.count(source_freshness, & &1.synced_today)

    # Find most recent sync
    most_recent =
      source_freshness
      |> Enum.filter(&(&1.hours_ago != nil))
      |> Enum.min_by(& &1.hours_ago, fn -> nil end)

    most_recent_ago =
      case most_recent do
        %{hours_ago: hours} when is_integer(hours) -> hours
        _ -> nil
      end

    status =
      cond do
        synced_today_count == length(sources) -> :fresh
        synced_today_count >= length(sources) - 1 -> :mostly_fresh
        synced_today_count > 0 -> :stale
        true -> :very_stale
      end

    %{
      sources: source_freshness,
      synced_today: synced_today_count,
      total_sources: length(sources),
      most_recent_hours_ago: most_recent_ago,
      status: status
    }
  rescue
    e ->
      Logger.error("Failed to fetch data freshness: #{Exception.message(e)}")
      %{sources: [], synced_today: 0, total_sources: 0, most_recent_hours_ago: nil, status: :unknown}
  end

  defp fetch_event_stats do
    total_events = DashboardStats.get_total_events() || 0
    upcoming_events = DashboardStats.get_upcoming_events() || 0
    past_events = DashboardStats.get_past_events() || 0
    unique_venues = DashboardStats.get_unique_venues() || 0
    unique_performers = DashboardStats.get_unique_performers() || 0

    %{
      total_events: total_events,
      upcoming_events: upcoming_events,
      past_events: past_events,
      unique_venues: unique_venues,
      unique_performers: unique_performers
    }
  rescue
    e ->
      Logger.error("Failed to fetch event stats: #{Exception.message(e)}")
      %{total_events: 0, upcoming_events: 0, past_events: 0, unique_venues: 0, unique_performers: 0}
  end

  defp fetch_movie_stats do
    case MatchingStats.get_overview_stats(24) do
      stats when is_map(stats) ->
        total = MatchingStats.get_total_movie_count() || 0
        unmatched = MatchingStats.get_unmatched_movies_blocking_showtimes(168)
        unmatched_count = if is_list(unmatched), do: length(unmatched), else: 0

        match_rate =
          if total > 0 do
            matched = total - unmatched_count
            Float.round(matched / total * 100, 1)
          else
            0.0
          end

        %{
          total_movies: total,
          unmatched_blocking: unmatched_count,
          match_rate: match_rate,
          recent_matches: stats[:matched_count] || 0
        }

      _ ->
        %{total_movies: 0, unmatched_blocking: 0, match_rate: 0.0, recent_matches: 0}
    end
  rescue
    e ->
      Logger.error("Failed to fetch movie stats: #{Exception.message(e)}")
      %{total_movies: 0, unmatched_blocking: 0, match_rate: 0.0, recent_matches: 0}
  end

  defp fetch_image_stats do
    case ImageCacheStatsCache.get_stats() do
      %{stats: stats} when is_map(stats) ->
        summary = stats[:summary] || stats["summary"] || %{}

        %{
          total: summary[:total_images] || summary["total_images"] || 0,
          cached: summary[:cached_images] || summary["cached_images"] || 0,
          pending: summary[:pending_images] || summary["pending_images"] || 0,
          failed: summary[:failed_images] || summary["failed_images"] || 0,
          storage_bytes: summary[:total_storage_bytes] || summary["total_storage_bytes"] || 0
        }

      _ ->
        %{total: 0, cached: 0, pending: 0, failed: 0, storage_bytes: 0}
    end
  rescue
    e ->
      Logger.error("Failed to fetch image stats: #{Exception.message(e)}")
      %{total: 0, cached: 0, pending: 0, failed: 0, storage_bytes: 0}
  end

  defp fetch_geocoding_stats do
    # Use overall_success_rate which is available in GeocodingStats
    case GeocodingStats.overall_success_rate() do
      {:ok, stats} ->
        %{
          total_requests: stats.total_attempts || 0,
          success_rate: stats.success_rate || 0.0,
          # Note: cache_hit_rate not available from this API
          cache_hit_rate: 0.0,
          avg_latency_ms: 0,
          failed_count: stats.total_attempts - (stats.successful || 0)
        }

      {:error, _reason} ->
        %{total_requests: 0, success_rate: 0.0, cache_hit_rate: 0.0, avg_latency_ms: 0, failed_count: 0}
    end
  rescue
    e ->
      Logger.error("Failed to fetch geocoding stats: #{Exception.message(e)}")
      %{total_requests: 0, success_rate: 0.0, cache_hit_rate: 0.0, avg_latency_ms: 0, failed_count: 0}
  end

  defp fetch_data_quality_stats do
    # Get collision stats
    collision_stats =
      case DashboardStats.get_collision_summary(24) do
        summary when is_map(summary) ->
          %{
            total_collisions: summary[:total_collisions] || 0,
            cross_source: summary[:cross_source_collisions] || 0,
            same_source: summary[:same_source_collisions] || 0
          }

        _ ->
          %{total_collisions: 0, cross_source: 0, same_source: 0}
      end

    # Get venue duplicate count
    duplicate_count =
      case DashboardStats.get_venue_duplicates(100, 0.7) do
        groups when is_list(groups) -> length(groups)
        _ -> 0
      end

    # Calculate collision rate if we have total events
    total_events = DashboardStats.get_total_events() || 0

    collision_rate =
      if total_events > 0 do
        Float.round(collision_stats.total_collisions / total_events * 100, 2)
      else
        0.0
      end

    %{
      duplicate_groups: duplicate_count,
      total_collisions: collision_stats.total_collisions,
      cross_source_collisions: collision_stats.cross_source,
      same_source_collisions: collision_stats.same_source,
      collision_rate: collision_rate
    }
  rescue
    e ->
      Logger.error("Failed to fetch data quality stats: #{Exception.message(e)}")
      %{duplicate_groups: 0, total_collisions: 0, cross_source_collisions: 0, same_source_collisions: 0, collision_rate: 0.0}
  end

  defp fetch_collision_stats do
    case DashboardStats.get_collision_summary(24) do
      summary when is_map(summary) ->
        %{
          total_collisions: summary[:total_collisions] || 0,
          cross_source: summary[:cross_source_collisions] || 0,
          same_source: summary[:same_source_collisions] || 0
        }

      _ ->
        %{total_collisions: 0, cross_source: 0, same_source: 0}
    end
  rescue
    e ->
      Logger.error("Failed to fetch collision stats: #{Exception.message(e)}")
      %{total_collisions: 0, cross_source: 0, same_source: 0}
  end

  defp fetch_source_stats do
    case DashboardStats.get_source_statistics() do
      stats when is_list(stats) ->
        stats
        |> Enum.map(fn source ->
          %{
            name: source[:source] || source["source"],
            event_count: source[:event_count] || source["event_count"] || 0,
            last_sync: source[:last_sync] || source["last_sync"]
          }
        end)
        |> Enum.sort_by(& &1.event_count, :desc)

      _ ->
        []
    end
  rescue
    e ->
      Logger.error("Failed to fetch source stats: #{Exception.message(e)}")
      []
  end

  @doc """
  Fetches comprehensive source table stats including health, trends, and coverage.
  Used for the Source Status table in the dashboard.
  """
  def fetch_source_table_stats do
    sources = discover_sources()

    # Fetch health and trends in parallel for each source
    source_data =
      sources
      |> Task.async_stream(
        fn source ->
          {source, fetch_single_source_stats(source)}
        end,
        max_concurrency: 3,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce([], fn
        {:ok, {_source, data}}, acc -> [data | acc]
        {:exit, _}, acc -> acc
      end)
      |> Enum.sort_by(& &1.health_score, :desc)

    source_data
  rescue
    e ->
      Logger.error("Failed to fetch source table stats: #{Exception.message(e)}")
      []
  end

  defp fetch_single_source_stats(source) do
    # Get 24-hour health check
    health_data =
      case Health.check(source, hours: 24) do
        {:ok, health} ->
          %{
            health_score: Float.round(Health.score(health), 1),
            success_rate: health.success_rate,
            p95_duration: health.p95_duration,
            meeting_slos: health.meeting_slos,
            total_executions: health.total_executions,
            last_execution: get_last_execution_time(health)
          }

        {:error, _} ->
          %{
            health_score: 0.0,
            success_rate: 0.0,
            p95_duration: 0.0,
            meeting_slos: false,
            total_executions: 0,
            last_execution: nil
          }
      end

    # Get 7-day trend data for sparkline
    trend_data =
      case Health.trend_data(source, hours: 168) do
        {:ok, trend} ->
          # Convert hourly data to daily aggregates for the sparkline (7 bars)
          daily_rates = aggregate_to_daily(trend.data_points)

          %{
            trend_direction: trend.trend_direction,
            daily_rates: daily_rates,
            coverage_days: count_coverage_days(trend.data_points)
          }

        {:error, _} ->
          %{
            trend_direction: :stable,
            daily_rates: [],
            coverage_days: 0
          }
      end

    # Combine all data
    %{
      name: source,
      display_name: format_source_name(source),
      health_score: health_data.health_score,
      health_status: health_status(health_data.health_score),
      success_rate: health_data.success_rate,
      p95_duration: health_data.p95_duration,
      meeting_slos: health_data.meeting_slos,
      total_executions: health_data.total_executions,
      last_execution: health_data.last_execution,
      trend_direction: trend_data.trend_direction,
      daily_rates: trend_data.daily_rates,
      coverage_days: trend_data.coverage_days
    }
  end

  defp get_last_execution_time(health) do
    # Get the most recent execution from recent_failures or worker_health
    # This is a simplification - in production you might want to query directly
    case health.recent_failures do
      [latest | _] -> Map.get(latest, :attempted_at)
      _ -> nil
    end
  end

  defp aggregate_to_daily(hourly_points) when is_list(hourly_points) do
    # Group by day and calculate average success rate per day
    hourly_points
    |> Enum.group_by(fn point ->
      case point.hour do
        %DateTime{} = dt -> Date.to_string(DateTime.to_date(dt))
        %NaiveDateTime{} = ndt -> Date.to_string(NaiveDateTime.to_date(ndt))
        _ -> "unknown"
      end
    end)
    |> Enum.reject(fn {day, _} -> day == "unknown" end)
    |> Enum.map(fn {day, points} ->
      total = Enum.sum(Enum.map(points, & &1.total))
      avg_rate = if total > 0, do: Enum.sum(Enum.map(points, & &1.success_rate)) / length(points), else: 0.0
      %{day: day, success_rate: Float.round(avg_rate, 1), total: total}
    end)
    |> Enum.sort_by(& &1.day)
    |> Enum.take(-7)
  end

  defp aggregate_to_daily(_), do: []

  defp count_coverage_days(hourly_points) when is_list(hourly_points) do
    # Count unique days with at least one execution
    hourly_points
    |> Enum.filter(fn point -> point.total > 0 end)
    |> Enum.map(fn point ->
      case point.hour do
        %DateTime{} = dt -> Date.to_string(DateTime.to_date(dt))
        %NaiveDateTime{} = ndt -> Date.to_string(NaiveDateTime.to_date(ndt))
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
    |> min(7)
  end

  defp count_coverage_days(_), do: 0

  # Helper functions

  defp health_status(score) when score >= 95, do: :healthy
  defp health_status(score) when score >= 85, do: :degraded
  defp health_status(score) when score >= 70, do: :warning
  defp health_status(_score), do: :critical

  @doc """
  Formats bytes into human-readable format.
  """
  def format_bytes(nil), do: "0 B"
  def format_bytes(0), do: "0 B"
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_bytes(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  def format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  @doc """
  Formats a source name for display.
  """
  def format_source_name("cinema_city"), do: "Cinema City"
  def format_source_name("repertuary"), do: "Repertuary"
  def format_source_name("bandsintown"), do: "Bandsintown"
  def format_source_name("resident_advisor"), do: "Resident Advisor"
  def format_source_name("resident-advisor"), do: "Resident Advisor"
  def format_source_name("week_pl"), do: "Week.pl"
  def format_source_name("kino_krakow"), do: "Kino Kraków"
  def format_source_name("tmdb"), do: "TMDB"
  def format_source_name("google_places"), do: "Google Places"
  def format_source_name("karnet"), do: "Karnet"
  def format_source_name("pubquiz"), do: "Pubquiz"
  def format_source_name("question_one"), do: "Question One"
  def format_source_name("ticketmaster"), do: "Ticketmaster"
  def format_source_name("waw4_free"), do: "Waw4 Free"
  def format_source_name(name) when is_binary(name), do: String.capitalize(name)
  def format_source_name(_), do: "Unknown"

  @doc """
  Dynamically discovers active sources from job execution data in the last 7 days.
  Returns a list of source names (e.g., ["cinema_city", "repertuary", "karnet"]).
  """
  def discover_sources do
    import Ecto.Query

    query =
      from(j in EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary,
        where: j.attempted_at > ago(7, "day"),
        select: j.worker,
        distinct: true
      )

    EventasaurusApp.Repo.all(query)
    |> Enum.map(&extract_source_from_worker/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Extract source name from worker module name
  # e.g., "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob" -> "cinema_city"
  defp extract_source_from_worker(worker) when is_binary(worker) do
    case Regex.run(~r/Sources\.(\w+)\.Jobs/, worker) do
      [_, source] -> Macro.underscore(source)
      _ -> nil
    end
  end

  defp extract_source_from_worker(_), do: nil
end
