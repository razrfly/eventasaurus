defmodule EventasaurusWeb.Cache.EventPageCache do
  @moduledoc """
  Cachex-based caching for event page performance optimization.

  Caches:
  - Event metadata with preloads (10 min TTL)
  - Image URLs (30 min TTL)
  - Nearby events (5 min TTL)
  """

  use GenServer
  require Logger
  import Cachex.Spec

  @cache_name :event_page_cache

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
            default: :timer.minutes(10),
            interval: :timer.minutes(2)
          )
      )

    Logger.info("EventPageCache started successfully")
    {:ok, %{}}
  end

  @doc """
  Gets event metadata from cache or computes and caches it.

  Includes: event with preloads, categories, primary_category_id, enriched images
  TTL: 10 minutes
  """
  def get_event_metadata(slug, language, compute_fn) when is_function(compute_fn, 0) do
    cache_key = "event_meta:#{slug}:#{language}"

    Cachex.fetch(@cache_name, cache_key, fn ->
      metadata = compute_fn.()
      {:commit, metadata, ttl: :timer.minutes(10)}
    end)
    |> case do
      {:ok, metadata} -> metadata
      {:commit, metadata} -> metadata
      {:error, _} -> compute_fn.()
    end
  end

  @doc """
  Gets nearby events from cache or computes and caches them.

  Cache key includes event_id, radius, and language for accuracy.
  TTL: 5 minutes
  """
  def get_nearby_events(event_id, radius_km, language, compute_fn)
      when is_function(compute_fn, 0) do
    cache_key = "nearby:#{event_id}:#{radius_km}:#{language}"

    Cachex.fetch(@cache_name, cache_key, fn ->
      events = compute_fn.()
      {:commit, events, ttl: :timer.minutes(5)}
    end)
    |> case do
      {:ok, events} -> events
      {:commit, events} -> events
      {:error, _} -> compute_fn.()
    end
  end

  @doc """
  Gets event image URL from cache or computes and caches it.

  TTL: 30 minutes (images change infrequently)
  """
  def get_event_image(event_id, compute_fn) when is_function(compute_fn, 0) do
    cache_key = "image:#{event_id}"

    Cachex.fetch(@cache_name, cache_key, fn ->
      image_url = compute_fn.()
      {:commit, image_url, ttl: :timer.minutes(30)}
    end)
    |> case do
      {:ok, image_url} -> image_url
      {:commit, image_url} -> image_url
      {:error, _} -> compute_fn.()
    end
  end

  @doc """
  Invalidates all cache entries for a specific event.
  Call this when an event is updated.
  """
  def invalidate_event(slug) do
    # Delete all entries for this event (all languages)
    prefix = "event_meta:#{slug}:"

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
  Invalidates nearby events cache for a specific event.
  """
  def invalidate_nearby(event_id) do
    prefix = "nearby:#{event_id}:"

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
  Invalidates image cache for a specific event.
  """
  def invalidate_image(event_id) do
    Cachex.del(@cache_name, "image:#{event_id}")
  end

  @doc """
  Clears all cached data.
  """
  def clear_all do
    Cachex.clear(@cache_name)
  end
end
