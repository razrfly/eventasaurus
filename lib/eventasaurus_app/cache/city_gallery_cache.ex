defmodule EventasaurusApp.Cache.CityGalleryCache do
  @moduledoc """
  ETS-based cache for cities with Unsplash galleries.

  This cache dramatically reduces database load by caching the mapping of
  country_id -> cities with unsplash galleries. The underlying query was
  running ~12,740 times and accounting for 60% of total query duration.

  ## Usage

      # Get all cities with galleries for a country
      CityGalleryCache.get_cities_by_country(country_id)

      # Find nearest city with gallery (for fallback images)
      CityGalleryCache.find_nearest_city(country_id, latitude, longitude)

  ## Architecture

  - Loads all cities with galleries on startup (fast - one query)
  - Refreshes every 24 hours automatically (galleries rarely change)
  - Falls back to database query if cache miss
  - Only loads required columns to minimize data transfer (~16MB → ~10KB)
  """

  use GenServer
  require Logger

  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Repo
  import Ecto.Query

  @table_name :city_gallery_cache
  # Galleries rarely change - refresh once per day instead of hourly
  # This reduces DB queries from ~72/day to ~3/day (one per Fly.io instance)
  @refresh_interval :timer.hours(24)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get all cities with Unsplash galleries for a given country.
  Returns list of City structs, or empty list if none found.
  """
  def get_cities_by_country(nil), do: []

  def get_cities_by_country(country_id) do
    case :ets.lookup(@table_name, {:country, country_id}) do
      [{_, cities}] -> cities
      [] -> []
    end
  rescue
    ArgumentError ->
      # Table doesn't exist yet, fall back to database
      Logger.warning("CityGalleryCache not ready, falling back to database")
      query_cities_for_country(country_id)
  end

  @doc """
  Find the nearest city with an Unsplash gallery in the same country.
  Uses cached data for efficiency.
  """
  def find_nearest_city(nil, _lat, _lng), do: nil

  def find_nearest_city(country_id, lat, lng) when is_nil(lat) or is_nil(lng) do
    # No coordinates, just return first city
    case get_cities_by_country(country_id) do
      [city | _] -> city
      [] -> nil
    end
  end

  def find_nearest_city(country_id, lat, lng) do
    lat_float = to_float(lat)
    lng_float = to_float(lng)

    get_cities_by_country(country_id)
    |> Enum.filter(fn c -> not is_nil(c.latitude) and not is_nil(c.longitude) end)
    |> Enum.sort_by(fn c ->
      c_lat = to_float(c.latitude)
      c_lng = to_float(c.longitude)
      dlat = c_lat - lat_float
      dlng = c_lng - lng_float
      :math.sqrt(dlat * dlat + dlng * dlng)
    end)
    |> List.first()
  end

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
    Logger.info("Starting CityGalleryCache...")

    # Create ETS table
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    # In test environment, don't load data (sandbox issues)
    # In production/dev, load asynchronously to not block startup
    env = Application.get_env(:eventasaurus, :environment, :prod)

    if env == :test do
      Logger.info("CityGalleryCache: Test mode - skipping initial load")
    else
      # Load asynchronously to not block startup
      send(self(), :initial_load)
    end

    # Schedule periodic refresh (skipped in test)
    if env != :test do
      schedule_refresh()
    end

    {:ok, %{last_refresh: nil, city_count: 0}}
  end

  @impl true
  def handle_cast(:refresh, state) do
    Logger.info("Refreshing CityGalleryCache...")
    load_cache()
    {:noreply, %{state | last_refresh: DateTime.utc_now(), city_count: count_cached_cities()}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, Map.put(state, :status, :running), state}
  end

  @impl true
  def handle_info(:initial_load, state) do
    Logger.info("CityGalleryCache: Loading initial data...")
    load_cache()
    {:noreply, %{state | last_refresh: DateTime.utc_now(), city_count: count_cached_cities()}}
  end

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    Logger.info("Auto-refreshing CityGalleryCache...")
    load_cache()
    {:noreply, %{state | last_refresh: DateTime.utc_now(), city_count: count_cached_cities()}}
  end

  # Private Functions

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp load_cache do
    start_time = System.monotonic_time(:millisecond)

    # Query all cities with unsplash galleries (one query instead of 12,740)
    # Only select columns actually used by the cache to minimize data transfer:
    # - id: for identity
    # - latitude/longitude: for distance calculations in find_nearest_city
    # - country_id: for grouping by country
    # - unsplash_gallery: for the actual image data
    # This avoids loading: name, slug, discovery_enabled, discovery_config,
    # alternate_names, inserted_at, updated_at
    cities =
      from(c in City,
        where: not is_nil(c.unsplash_gallery),
        select: struct(c, [:id, :latitude, :longitude, :country_id, :unsplash_gallery])
      )
      |> Repo.all(timeout: 30_000)

    # Group by country_id
    cities_by_country =
      cities
      |> Enum.group_by(& &1.country_id)

    # Clear existing data and insert new
    :ets.delete_all_objects(@table_name)

    Enum.each(cities_by_country, fn {country_id, country_cities} ->
      :ets.insert(@table_name, {{:country, country_id}, country_cities})
    end)

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    Logger.info(
      "CityGalleryCache loaded #{length(cities)} cities across #{map_size(cities_by_country)} countries in #{duration}ms"
    )
  end

  defp count_cached_cities do
    :ets.foldl(fn {{:country, _}, cities}, acc -> acc + length(cities) end, 0, @table_name)
  rescue
    ArgumentError -> 0
  end

  defp query_cities_for_country(country_id) do
    # Same column selection as load_cache for consistency
    from(c in City,
      where: c.country_id == ^country_id,
      where: not is_nil(c.unsplash_gallery),
      select: struct(c, [:id, :latitude, :longitude, :country_id, :unsplash_gallery])
    )
    |> Repo.all(timeout: 30_000)
  end

  @spec to_float(Decimal.t() | float() | integer() | nil | term()) :: float()
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(f) when is_float(f), do: f
  defp to_float(i) when is_integer(i), do: i * 1.0

  defp to_float(other) do
    # City coordinates are :decimal type in schema, so this should never execute.
    # If it does, log the anomaly for investigation rather than silently returning 0.0
    Logger.warning("CityGalleryCache.to_float/1 received unexpected value: #{inspect(other)}")
    0.0
  end
end
