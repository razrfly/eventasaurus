defmodule EventasaurusDiscovery.Admin.DiscoveryStatsCache do
  @moduledoc """
  GenServer-based cache for discovery stats page.

  Precomputes all expensive stats queries in the background and caches results in memory.
  Refreshes every 10 minutes automatically.

  This dramatically improves page load time from 30+ seconds to milliseconds.

  ## Usage

      # Get cached stats (fast - just reads from memory)
      DiscoveryStatsCache.get_stats()

      # Force immediate refresh (slow - recomputes everything)
      DiscoveryStatsCache.refresh()

  ## Architecture

  - Stats are computed on GenServer startup
  - Background refresh every 10 minutes
  - If refresh fails, keeps serving old data
  - Logs errors but doesn't crash the cache
  """

  use GenServer
  require Logger

  alias EventasaurusDiscovery.Sources.SourceRegistry
  alias EventasaurusDiscovery.Locations.{City, CityHierarchy}
  alias EventasaurusDiscovery.PublicEvents.PublicEvent

  alias EventasaurusDiscovery.Admin.{
    DiscoveryStatsCollector,
    SourceHealthCalculator,
    EventChangeTracker,
    DataQualityChecker
  }

  import Ecto.Query
  alias EventasaurusApp.Repo

  # Refresh every 10 minutes
  @refresh_interval :timer.minutes(10)

  # Client API

  @doc """
  Start the stats cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get cached stats (fast - reads from memory).

  Returns nil on timeout or if the cache process is not running.
  The cache is always initialized on startup with either computed stats or empty fallback data.
  """
  def get_stats do
    try do
      GenServer.call(__MODULE__, :get_stats, 5_000)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Stats cache timeout - returning nil")
        nil

      :exit, {:noproc, _} ->
        Logger.warning("Stats cache not started - returning nil")
        nil
    end
  end

  @doc """
  Force an immediate refresh of stats (slow - recomputes everything).

  Returns :ok and refreshes in the background.
  """
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Get the timestamp of the last successful cache refresh.
  """
  def last_refreshed_at do
    try do
      GenServer.call(__MODULE__, :last_refreshed_at, 5_000)
    catch
      :exit, _ -> nil
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting DiscoveryStatsCache...")

    # Schedule first refresh
    schedule_refresh()

    # Compute initial stats (this will block startup for ~5-10 seconds)
    initial_stats =
      case compute_stats() do
        {:ok, stats} ->
          Logger.info("DiscoveryStatsCache initialized successfully")
          stats

        {:error, reason} ->
          Logger.error("Failed to initialize DiscoveryStatsCache: #{inspect(reason)}")
          # Return empty stats as fallback
          empty_stats()
      end

    {:ok, %{stats: initial_stats, last_refresh: DateTime.utc_now(), refreshing: false}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call(:last_refreshed_at, _from, state) do
    {:reply, state.last_refresh, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    # Skip if refresh already in progress to prevent concurrent compute_stats operations
    if state.refreshing do
      Logger.info("Refresh already in progress, skipping duplicate request")
      {:noreply, state}
    else
      # Spawn async task to avoid blocking the GenServer
      # This ensures get_stats() calls can still be served during refresh
      Task.start(fn ->
        case compute_stats() do
          {:ok, new_stats} ->
            GenServer.cast(__MODULE__, {:stats_computed, new_stats, :manual})

          {:error, reason} ->
            Logger.error("Failed to refresh stats cache: #{inspect(reason)}")
            # Reset refreshing flag on error
            GenServer.cast(__MODULE__, :refresh_failed)
        end
      end)

      {:noreply, Map.put(state, :refreshing, true)}
    end
  end

  @impl true
  def handle_cast({:stats_computed, new_stats, source}, state) do
    log_message =
      case source do
        :manual -> "Stats cache manually refreshed"
        :auto -> "Stats cache auto-refreshed successfully"
      end

    Logger.info(log_message)
    {:noreply, %{state | stats: new_stats, last_refresh: DateTime.utc_now(), refreshing: false}}
  end

  @impl true
  def handle_cast(:refresh_failed, state) do
    Logger.warning("Resetting refresh flag after failure")
    {:noreply, Map.put(state, :refreshing, false)}
  end

  @impl true
  def handle_info(:refresh, state) do
    # Schedule next refresh
    schedule_refresh()

    # Skip if refresh already in progress to prevent concurrent compute_stats operations
    if state.refreshing do
      Logger.info("Auto-refresh skipped - manual refresh already in progress")
      {:noreply, state}
    else
      # Spawn async task to avoid blocking the GenServer
      Task.start(fn ->
        case compute_stats() do
          {:ok, new_stats} ->
            GenServer.cast(__MODULE__, {:stats_computed, new_stats, :auto})

          {:error, reason} ->
            Logger.error("Failed to auto-refresh stats cache: #{inspect(reason)}")
            # Reset refreshing flag on error
            GenServer.cast(__MODULE__, :refresh_failed)
        end
      end)

      {:noreply, Map.put(state, :refreshing, true)}
    end
  end

  # Private Functions

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp compute_stats do
    try do
      Logger.info("Computing discovery stats...")
      start_time = System.monotonic_time(:millisecond)

      # Get all registered sources
      source_names = SourceRegistry.all_sources()

      # Query stats aggregated across ALL cities
      source_stats = DiscoveryStatsCollector.get_metadata_based_source_stats(nil, source_names)

      # Get change tracking data aggregated across all cities
      change_stats = EventChangeTracker.get_all_source_changes(source_names, nil)

      # Batch count events for all sources at once
      event_counts = count_events_for_sources_batch(source_names)

      # Batch check quality for all sources at once
      quality_checks = DataQualityChecker.check_quality_batch(source_names)

      # Calculate enriched source data with health metrics
      sources_data =
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

      # Calculate overall health score
      overall_health = SourceHealthCalculator.overall_health_score(source_stats)

      # Get summary metrics
      total_sources = length(source_names)
      total_cities = count_cities()
      events_this_week = count_events_this_week()

      # Get city performance data
      city_stats = get_city_performance()

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      Logger.info("Stats computed in #{duration}ms")

      {:ok,
       %{
         sources_data: sources_data,
         overall_health: overall_health,
         total_sources: total_sources,
         total_cities: total_cities,
         events_this_week: events_this_week,
         city_stats: city_stats
       }}
    rescue
      e ->
        Logger.error("Error computing stats: #{Exception.message(e)}")
        Logger.error(Exception.format_stacktrace(__STACKTRACE__))
        {:error, e}
    end
  end

  defp empty_stats do
    %{
      sources_data: [],
      overall_health: 0,
      total_sources: 0,
      total_cities: 0,
      events_this_week: 0,
      city_stats: []
    }
  end

  # Query functions (copied from DiscoveryStatsLive)

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
    |> Repo.all(timeout: 30_000)
    |> Map.new()
  end

  defp count_cities do
    Repo.aggregate(City, :count, :id, timeout: 30_000)
  end

  defp count_events_this_week do
    week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

    query =
      from(e in PublicEvent,
        where: e.inserted_at >= ^week_ago,
        select: count(e.id)
      )

    Repo.one(query, timeout: 30_000) || 0
  end

  defp get_city_performance do
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
        order_by: [desc: count(e.id)]
      )

    cities = Repo.all(query, timeout: 30_000)

    # Apply geographic clustering to group metro areas
    clustered_cities = CityHierarchy.aggregate_stats_by_cluster(cities, 20.0)

    # Take top 10 after clustering
    top_cities = Enum.take(clustered_cities, 10)

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
      |> Repo.all(timeout: 30_000)
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
