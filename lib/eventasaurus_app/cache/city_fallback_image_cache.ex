defmodule EventasaurusApp.Cache.CityFallbackImageCache do
  @moduledoc """
  ETS-based cache for city fallback images.

  Pre-computes and caches fallback images for each city + category combination,
  eliminating per-event computation. The cache stores Unsplash image URLs with
  Unsplash's native image parameters (not CDN-wrapped).

  ## Performance Impact

  Before: Each event without an image triggers:
  - Category determination
  - City lookup
  - Gallery category chain lookup
  - Image selection
  - URL transformation

  After: Simple ETS lookup: city_id + category + venue_id → cached URL

  ## Cache Structure

  Key: {city_id, category} → list of Unsplash URLs with native params

  The venue_id-based image selection happens at lookup time (fast in-memory),
  while URL transformation is pre-computed and cached.

  ## Why Unsplash Params Instead of CDN

  Unsplash images already serve from a global CDN with optimized caching.
  Wrapping them in our CDN is wasteful. Instead, we use Unsplash's native
  image transformation params: `?w=800&q=85&fit=crop`

  ## Refresh Strategy

  - Refreshes every 24 hours (galleries rarely change)
  - Manual refresh via `refresh/0`
  - Only loads required columns to minimize data transfer
  """

  use GenServer
  require Logger

  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Repo
  import Ecto.Query

  @table_name :city_fallback_image_cache
  # Galleries rarely change - refresh once per day instead of hourly
  # This reduces DB queries from ~72/day to ~3/day (one per Fly.io instance)
  @refresh_interval :timer.hours(24)

  # Standard categories that get pre-computed
  @categories [
    "general",
    "music",
    "film",
    "nightlife",
    "theater",
    "art",
    "sports",
    "food",
    "festival",
    "comedy",
    "trivia"
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get a pre-computed fallback image URL for a city + category + venue_id combination.

  Returns an Unsplash image URL with native params, or nil if not available.
  The venue_id is used to select a specific image from the category (for variety).
  """
  def get_fallback_image(city_id, category, venue_id) when is_integer(city_id) do
    cache_key = {city_id, category || "general"}

    case :ets.lookup(@table_name, cache_key) do
      [{_, images}] when is_list(images) and length(images) > 0 ->
        # Select image based on day + venue_id for stable but varied selection
        select_image(images, venue_id)

      _ ->
        nil
    end
  rescue
    ArgumentError ->
      # Table doesn't exist yet
      nil
  end

  def get_fallback_image(_, _, _), do: nil

  @doc """
  Force a cache refresh.
  """
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Get cache statistics.
  """
  def stats do
    try do
      GenServer.call(__MODULE__, :stats, 5_000)
    catch
      :exit, _ -> %{status: :not_running}
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting CityFallbackImageCache...")

    # Create ETS table
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    # In test environment, don't load data (sandbox issues)
    env = Application.get_env(:eventasaurus, :environment, :prod)

    if env == :test do
      Logger.info("CityFallbackImageCache: Test mode - skipping initial load")
    else
      # Load asynchronously to not block startup
      send(self(), :initial_load)
    end

    # Schedule periodic refresh (skipped in test)
    if env != :test do
      schedule_refresh()
    end

    {:ok, %{last_refresh: nil, entry_count: 0}}
  end

  @impl true
  def handle_cast(:refresh, state) do
    Logger.info("Refreshing CityFallbackImageCache...")
    load_cache()
    {:noreply, %{state | last_refresh: DateTime.utc_now(), entry_count: count_entries()}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, Map.put(state, :status, :running), state}
  end

  @impl true
  def handle_info(:initial_load, state) do
    Logger.info("CityFallbackImageCache: Loading initial data...")
    load_cache()
    {:noreply, %{state | last_refresh: DateTime.utc_now(), entry_count: count_entries()}}
  end

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    Logger.info("Auto-refreshing CityFallbackImageCache...")
    load_cache()
    {:noreply, %{state | last_refresh: DateTime.utc_now(), entry_count: count_entries()}}
  end

  # Private Functions

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp load_cache do
    start_time = System.monotonic_time(:millisecond)

    # Query all cities with unsplash galleries
    # Only select columns needed: id for cache key, unsplash_gallery for image data
    # This avoids loading: name, slug, latitude, longitude, discovery_enabled,
    # discovery_config, alternate_names, country_id, inserted_at, updated_at
    cities =
      from(c in City,
        where: not is_nil(c.unsplash_gallery),
        select: struct(c, [:id, :unsplash_gallery])
      )
      |> Repo.all(timeout: 30_000)

    # Clear existing data
    :ets.delete_all_objects(@table_name)

    # Pre-compute images for each city + category combination
    entry_count =
      cities
      |> Enum.map(fn city ->
        process_city(city)
      end)
      |> Enum.sum()

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    Logger.info(
      "CityFallbackImageCache loaded #{entry_count} entries for #{length(cities)} cities in #{duration}ms"
    )
  end

  defp process_city(%City{id: city_id, unsplash_gallery: gallery} = _city) do
    categories = get_gallery_categories(gallery)

    # Process each standard category
    @categories
    |> Enum.map(fn category ->
      images = get_category_images(categories, category)

      if length(images) > 0 do
        # Pre-compute Unsplash URLs with native params (NOT CDN-wrapped)
        transformed_images =
          images
          |> Enum.map(fn image ->
            url = get_image_url(image)
            if url, do: apply_unsplash_params(url), else: nil
          end)
          |> Enum.reject(&is_nil/1)

        if length(transformed_images) > 0 do
          :ets.insert(@table_name, {{city_id, category}, transformed_images})
          1
        else
          0
        end
      else
        0
      end
    end)
    |> Enum.sum()
  end

  defp get_gallery_categories(%{"categories" => categories}) when is_map(categories),
    do: categories

  defp get_gallery_categories(_), do: %{}

  defp get_category_images(categories, category) do
    case Map.get(categories, category) do
      %{"images" => images} when is_list(images) -> images
      _ -> []
    end
  end

  defp get_image_url(%{"url" => url}) when is_binary(url), do: url
  defp get_image_url(%{url: url}) when is_binary(url), do: url
  defp get_image_url(_), do: nil

  # Apply Unsplash's native image transformation params
  # Unsplash already serves from a global CDN - no need to wrap in ours
  defp apply_unsplash_params(url) when is_binary(url) do
    uri = URI.parse(url)
    # Build URL with Unsplash's native params
    "#{uri.scheme}://#{uri.host}#{uri.path}?w=800&q=85&fit=crop"
  end

  defp apply_unsplash_params(_), do: nil

  defp select_image(images, venue_id) when is_list(images) and length(images) > 0 do
    # Combine day + venue_id for unique but stable selection per venue
    day_of_year = Date.utc_today() |> Date.day_of_year()
    offset = day_of_year + (venue_id || 0)
    index = rem(offset, length(images))
    Enum.at(images, index)
  end

  defp select_image(_, _), do: nil

  defp count_entries do
    :ets.info(@table_name, :size)
  rescue
    ArgumentError -> 0
  end
end
