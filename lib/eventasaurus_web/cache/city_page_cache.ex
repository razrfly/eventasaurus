defmodule EventasaurusWeb.Cache.CityPageCache do
  @moduledoc """
  Cachex-based caching for city page performance optimization.

  Caches:
  - Categories list (30 min TTL)
  - Date range counts per city (5 min TTL)
  """

  use GenServer
  require Logger
  import Cachex.Spec

  @cache_name :city_page_cache

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
    Cachex.fetch(@cache_name, "categories_list", fn ->
      categories = compute_fn.()
      {:commit, categories, ttl: :timer.minutes(30)}
    end)
    |> case do
      {:ok, categories} -> categories
      {:commit, categories} -> categories
      {:error, _} -> compute_fn.()
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
      {:ok, counts} -> counts
      {:commit, counts} -> counts
      {:error, _} -> compute_fn.()
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
  Clears all cached data.
  """
  def clear_all do
    Cachex.clear(@cache_name)
  end
end
