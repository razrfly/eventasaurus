defmodule EventasaurusWeb.Jobs.CityPageCacheWarmupJob do
  @moduledoc """
  Oban job for pre-warming city page caches on application startup.

  This job ensures that popular city pages have cached data immediately
  available, preventing cold-start delays and OOM issues when users
  first visit city pages after a deployment.

  ## Pre-warming Strategy

  1. On app startup, enqueue warmup job with short delay (let app settle)
  2. Fetch all discovery-enabled cities
  3. Enqueue cache refresh jobs for each city in staggered batches
  4. Each batch uses default radius (50km) and default page options

  ## Usage

  Automatically scheduled during application startup via Application supervisor.

  Manual trigger:
      EventasaurusWeb.Jobs.CityPageCacheWarmupJob.enqueue()

  ## Uniqueness

  Job is unique by current date to prevent multiple warmups per day.
  """

  use Oban.Worker,
    queue: :cache_refresh,
    max_attempts: 1,
    # Only one warmup per day
    unique: [period: :timer.hours(24), fields: [:args, :queue]]

  require Logger

  alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
  alias EventasaurusWeb.Jobs.CityPageCacheRefreshJob

  # Default radius for pre-warming (matches city page default)
  @default_radius_km 50

  # Stagger between cities to avoid overwhelming the system
  @stagger_seconds 5

  @doc """
  Enqueues a cache warmup job.

  ## Options

    - `:delay` - Delay in seconds before running (default: 30, allows app to settle)
  """
  def enqueue(opts \\ []) do
    delay = Keyword.get(opts, :delay, 30)

    args = %{
      "date" => Date.to_iso8601(Date.utc_today()),
      "triggered_at" => DateTime.to_iso8601(DateTime.utc_now())
    }

    case Oban.insert(new(args, schedule_in: delay)) do
      {:ok, %Oban.Job{conflict?: true}} ->
        Logger.info("[CacheWarmup] Already scheduled for today, skipping")
        {:ok, :already_scheduled}

      result ->
        Logger.info("[CacheWarmup] Scheduled to run in #{delay}s")
        result
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.info("[CacheWarmup] Starting cache pre-warming for discovery-enabled cities")

    cities = DiscoveryConfigManager.list_discovery_enabled_cities()
    city_count = length(cities)

    if city_count == 0 do
      Logger.info("[CacheWarmup] No discovery-enabled cities found, skipping")
      {:ok, %{cities_warmed: 0}}
    else
      Logger.info("[CacheWarmup] Found #{city_count} discovery-enabled cities")

      # Enqueue BASE cache refresh for each city first (Issue #3363)
      # Base cache is the foundation - warm it before per-filter caches
      base_scheduled =
        cities
        |> Enum.with_index()
        |> Enum.map(fn {city, index} ->
          # Base cache jobs run first (small delay)
          delay = index * @stagger_seconds

          case CityPageCacheRefreshJob.enqueue_base(city.slug, @default_radius_km, schedule_in: delay) do
            {:ok, :duplicate} ->
              Logger.debug("[CacheWarmup] Base cache already queued for #{city.slug}")
              :duplicate

            {:ok, _} ->
              Logger.debug("[CacheWarmup] Scheduled BASE cache for #{city.slug} (delay: #{delay}s)")
              :ok

            {:error, reason} ->
              Logger.warning("[CacheWarmup] Failed to schedule base for #{city.slug}: #{inspect(reason)}")
              :error
          end
        end)

      base_successful = Enum.count(base_scheduled, &(&1 == :ok))
      base_duplicates = Enum.count(base_scheduled, &(&1 == :duplicate))

      Logger.info("[CacheWarmup] Base cache jobs: #{base_successful} scheduled, #{base_duplicates} already queued")

      # Also enqueue per-filter cache refresh for default view (no filters)
      # This runs after base cache with additional delay
      scheduled =
        cities
        |> Enum.with_index()
        |> Enum.map(fn {city, index} ->
          # Per-filter jobs run after base cache (larger delay)
          delay = (city_count + index) * @stagger_seconds

          case CityPageCacheRefreshJob.enqueue(city.slug, @default_radius_km, schedule_in: delay) do
            {:ok, :duplicate} ->
              Logger.debug("[CacheWarmup] Refresh already queued for #{city.slug}")
              :duplicate

            {:ok, _} ->
              Logger.debug("[CacheWarmup] Scheduled refresh for #{city.slug} (delay: #{delay}s)")
              :ok

            {:error, reason} ->
              Logger.warning("[CacheWarmup] Failed to schedule #{city.slug}: #{inspect(reason)}")
              :error
          end
        end)

      successful = Enum.count(scheduled, &(&1 == :ok))
      duplicates = Enum.count(scheduled, &(&1 == :duplicate))

      Logger.info("""
      [CacheWarmup] Pre-warming complete
      Cities processed: #{city_count}
      Base cache jobs: #{base_successful} scheduled, #{base_duplicates} already queued
      Filter cache jobs: #{successful} scheduled, #{duplicates} already queued
      """)

      {:ok, %{
        cities_warmed: city_count,
        base_jobs_scheduled: base_successful,
        base_duplicates: base_duplicates,
        jobs_scheduled: successful,
        duplicates: duplicates
      }}
    end
  end
end
