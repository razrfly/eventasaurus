defmodule EventasaurusWeb.Cache.CityPageCache do
  @moduledoc """
  Cachex-based caching for city page performance optimization.

  Caches (Issue #3331 Phase 3):
  - Categories list (30 min TTL) - global, rarely changes
  - City stats (30 min TTL) - events/venues count for SEO/JSON-LD
  - Available languages (30 min TTL) - per city, rarely changes
  - Date range counts (15 min TTL) - per city/radius, more dynamic

  Aggregated Events Cache (Issue #3347):
  - Uses stale-while-revalidate pattern
  - Returns stale data immediately, triggers background refresh
  - Prevents OOM by running expensive queries in Oban jobs

  Emits telemetry events for cache hits/misses via CityPageTelemetry.
  """

  use GenServer
  require Logger
  import Cachex.Spec

  alias EventasaurusWeb.Telemetry.CityPageTelemetry
  alias EventasaurusWeb.Jobs.CityPageCacheRefreshJob

  @cache_name :city_page_cache

  # Staleness threshold for aggregated events cache (30 minutes)
  # Data older than this triggers a background refresh, but is still returned
  @stale_threshold_ms :timer.minutes(30)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Start Cachex with expiration settings
    {:ok, _pid} =
      Cachex.start_link(@cache_name,
        expiration:
          expiration(
            default: :timer.minutes(30),
            interval: :timer.minutes(5)
          )
      )

    Logger.info("CityPageCache started successfully")
    {:ok, %{}}
  end

  @doc """
  Gets categories from cache or computes and caches them.

  TTL: 30 minutes
  """
  def get_categories(compute_fn) when is_function(compute_fn, 0) do
    cache_key = "categories_list"

    Cachex.fetch(@cache_name, cache_key, fn ->
      categories = compute_fn.()
      {:commit, categories, ttl: :timer.minutes(30)}
    end)
    |> case do
      {:ok, categories} ->
        # TELEMETRY: Cache hit
        CityPageTelemetry.cache_event(:hit, %{cache_key: cache_key, city_slug: "global"})
        categories

      {:commit, categories} ->
        # TELEMETRY: Cache miss - had to compute
        CityPageTelemetry.cache_event(:miss, %{cache_key: cache_key, city_slug: "global"})
        categories

      {:error, _} ->
        # TELEMETRY: Cache error - had to compute
        CityPageTelemetry.cache_event(:miss, %{cache_key: cache_key, city_slug: "global"})
        compute_fn.()
    end
  end

  @doc """
  Gets city stats (events count, venues count) from cache or computes and caches them.

  Used for SEO/JSON-LD metadata. These stats don't change frequently.
  Cache key includes city_slug and radius_km for accuracy.
  TTL: 30 minutes
  """
  def get_city_stats(city_slug, radius_km, compute_fn) when is_function(compute_fn, 0) do
    cache_key = "city_stats:#{city_slug}:#{radius_km}"

    Cachex.fetch(@cache_name, cache_key, fn ->
      stats = compute_fn.()
      {:commit, stats, ttl: :timer.minutes(30)}
    end)
    |> case do
      {:ok, stats} ->
        CityPageTelemetry.cache_event(:hit, %{cache_key: cache_key, city_slug: city_slug})
        stats

      {:commit, stats} ->
        CityPageTelemetry.cache_event(:miss, %{cache_key: cache_key, city_slug: city_slug})
        stats

      {:error, _} ->
        CityPageTelemetry.cache_event(:miss, %{cache_key: cache_key, city_slug: city_slug})
        compute_fn.()
    end
  end

  @doc """
  Gets available languages for a city from cache or computes and caches them.

  Languages for a city rarely change (based on country + DB translations).
  TTL: 30 minutes
  """
  def get_available_languages(city_slug, compute_fn) when is_function(compute_fn, 0) do
    cache_key = "languages:#{city_slug}"

    Cachex.fetch(@cache_name, cache_key, fn ->
      languages = compute_fn.()
      {:commit, languages, ttl: :timer.minutes(30)}
    end)
    |> case do
      {:ok, languages} ->
        CityPageTelemetry.cache_event(:hit, %{cache_key: cache_key, city_slug: city_slug})
        languages

      {:commit, languages} ->
        CityPageTelemetry.cache_event(:miss, %{cache_key: cache_key, city_slug: city_slug})
        languages

      {:error, _} ->
        CityPageTelemetry.cache_event(:miss, %{cache_key: cache_key, city_slug: city_slug})
        compute_fn.()
    end
  end

  @doc """
  Gets date range counts for a city from cache or computes and caches them.

  Cache key includes city_slug and radius_km for accuracy.
  TTL: 15 minutes (date counts rarely change, longer TTL reduces DB load)
  """
  def get_date_range_counts(city_slug, radius_km, compute_fn) when is_function(compute_fn, 0) do
    cache_key = "date_counts:#{city_slug}:#{radius_km}"

    Cachex.fetch(@cache_name, cache_key, fn ->
      counts = compute_fn.()
      {:commit, counts, ttl: :timer.minutes(15)}
    end)
    |> case do
      {:ok, counts} ->
        # TELEMETRY: Cache hit
        CityPageTelemetry.cache_event(:hit, %{cache_key: cache_key, city_slug: city_slug})
        counts

      {:commit, counts} ->
        # TELEMETRY: Cache miss - had to compute
        CityPageTelemetry.cache_event(:miss, %{cache_key: cache_key, city_slug: city_slug})
        counts

      {:error, _} ->
        # TELEMETRY: Cache error - had to compute
        CityPageTelemetry.cache_event(:miss, %{cache_key: cache_key, city_slug: city_slug})
        compute_fn.()
    end
  end

  @doc """
  Gets aggregated events for a city using stale-while-revalidate pattern.

  Unlike other cache functions, this does NOT compute on miss because the
  computation is expensive (can OOM on constrained machines). Instead:

  - **Cache hit (fresh)**: Returns cached data immediately
  - **Cache hit (stale)**: Returns cached data AND enqueues background refresh
  - **Cache miss**: Returns nil AND enqueues background refresh

  The LiveView should handle nil by showing a loading state. The background
  job will populate the cache, and subsequent requests will get data.

  ## Parameters

    - `city_slug` - The city slug (e.g., "krakow")
    - `radius_km` - Search radius in kilometers
    - `opts` - Optional query parameters (page, page_size, categories, etc.)

  ## Returns

    - `{:ok, data}` - Cache hit with data (may be stale)
    - `{:miss, nil}` - Cache miss, background refresh enqueued

  ## Example

      case CityPageCache.get_aggregated_events("krakow", 50) do
        {:ok, %{events: events, total_count: count}} ->
          # Render events
        {:miss, nil} ->
          # Show loading state, events will load on next request
      end
  """
  def get_aggregated_events(city_slug, radius_km, opts \\ []) do
    cache_key = CityPageCacheRefreshJob.cache_key(city_slug, radius_km, opts)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Cache miss - enqueue refresh and return nil
        CityPageTelemetry.cache_event(:miss, %{
          cache_key: cache_key,
          city_slug: city_slug,
          cache_type: "aggregated_events"
        })

        enqueue_refresh(city_slug, radius_km, opts)
        {:miss, nil}

      {:ok, cached_value} ->
        # Cache hit - check staleness
        if stale?(cached_value) do
          # Stale - return data but trigger background refresh
          CityPageTelemetry.cache_event(:stale, %{
            cache_key: cache_key,
            city_slug: city_slug,
            cache_type: "aggregated_events",
            cached_at: cached_value.cached_at
          })

          enqueue_refresh(city_slug, radius_km, opts)
          {:ok, cached_value}
        else
          # Fresh - just return data
          CityPageTelemetry.cache_event(:hit, %{
            cache_key: cache_key,
            city_slug: city_slug,
            cache_type: "aggregated_events"
          })

          {:ok, cached_value}
        end

      {:error, reason} ->
        # Cache error - log and return miss
        Logger.warning("Cache error for #{cache_key}: #{inspect(reason)}")

        CityPageTelemetry.cache_event(:miss, %{
          cache_key: cache_key,
          city_slug: city_slug,
          cache_type: "aggregated_events",
          error: true
        })

        enqueue_refresh(city_slug, radius_km, opts)
        {:miss, nil}
    end
  end

  @doc """
  Checks if there's any cached data for aggregated events (even if stale).

  Useful for determining whether to show loading state vs skeleton.
  """
  def has_cached_events?(city_slug, radius_km, opts \\ []) do
    cache_key = CityPageCacheRefreshJob.cache_key(city_slug, radius_km, opts)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Forces an immediate cache refresh for a city's aggregated events.

  Useful for admin actions or after bulk data imports.
  """
  def force_refresh_events(city_slug, radius_km, opts \\ []) do
    # Invalidate existing cache
    invalidate_aggregated_events(city_slug)

    # Enqueue refresh job
    enqueue_refresh(city_slug, radius_km, opts)
  end

  # Check if cached value is stale (older than threshold)
  defp stale?(%{cached_at: cached_at}) do
    age_ms = DateTime.diff(DateTime.utc_now(), cached_at, :millisecond)
    age_ms > @stale_threshold_ms
  end

  defp stale?(_), do: true

  # Enqueue a background refresh job (handles duplicates via job uniqueness)
  defp enqueue_refresh(city_slug, radius_km, opts) do
    case CityPageCacheRefreshJob.enqueue(city_slug, radius_km, opts) do
      {:ok, _} ->
        Logger.debug("Enqueued cache refresh for city=#{city_slug}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to enqueue cache refresh for #{city_slug}: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Invalidates categories cache.
  Call this when categories are added/modified.
  """
  def invalidate_categories do
    Cachex.del(@cache_name, "categories_list")
  end

  @doc """
  Invalidates date range counts for a specific city.
  Call this when events are added/modified for a city.
  """
  def invalidate_date_counts(city_slug) do
    # Delete all date count entries for this city (all radii)
    # Use Cachex stream to find and delete matching keys
    prefix = "date_counts:#{city_slug}:"

    @cache_name
    |> Cachex.stream!()
    |> Stream.filter(fn {key, _entry} ->
      is_binary(key) && String.starts_with?(key, prefix)
    end)
    |> Enum.each(fn {key, _entry} ->
      Cachex.del(@cache_name, key)
    end)
  end

  @doc """
  Invalidates city stats cache for a specific city.
  Call this when events or venues are added/modified for a city.
  """
  def invalidate_city_stats(city_slug) do
    # Delete all city stats entries for this city (all radii)
    prefix = "city_stats:#{city_slug}:"

    @cache_name
    |> Cachex.stream!()
    |> Stream.filter(fn {key, _entry} ->
      is_binary(key) && String.starts_with?(key, prefix)
    end)
    |> Enum.each(fn {key, _entry} ->
      Cachex.del(@cache_name, key)
    end)
  end

  @doc """
  Invalidates available languages cache for a specific city.
  Call this when event translations are added for a city.
  """
  def invalidate_languages(city_slug) do
    Cachex.del(@cache_name, "languages:#{city_slug}")
  end

  @doc """
  Invalidates aggregated events cache for a specific city.
  Call this when events are added/modified for a city.
  """
  def invalidate_aggregated_events(city_slug) do
    # Delete all aggregated events entries for this city (all radii and options)
    prefix = "aggregated_events:#{city_slug}:"

    @cache_name
    |> Cachex.stream!()
    |> Stream.filter(fn {key, _entry} ->
      is_binary(key) && String.starts_with?(key, prefix)
    end)
    |> Enum.each(fn {key, _entry} ->
      Cachex.del(@cache_name, key)
    end)
  end

  @doc """
  Clears all cached data.
  """
  def clear_all do
    Cachex.clear(@cache_name)
  end
end
