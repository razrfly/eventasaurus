defmodule EventasaurusWeb.Jobs.CityPageCacheRefreshJob do
  @moduledoc """
  Oban background job for refreshing city page event cache.

  This job runs the expensive `list_events_with_aggregation_and_counts/1` query
  in the background to avoid OOM kills during user requests. The result is
  stored in Cachex for fast retrieval.

  ## Why Background Jobs?

  The event aggregation query can consume significant memory (loading up to 500
  events and aggregating in memory). Running this during a user request can:
  - Cause OOM kills on memory-constrained Fly machines (1GB limit)
  - Block the request for 15+ seconds causing timeouts

  By running in a background job, we:
  - Isolate memory consumption from user-facing processes
  - Allow the job to fail/retry without affecting user experience
  - Enable stale-while-revalidate pattern (serve old data, refresh in background)

  ## Usage

  Enqueue a cache refresh job:

      EventasaurusWeb.Jobs.CityPageCacheRefreshJob.enqueue("krakow", 50)

  Or with full options:

      EventasaurusWeb.Jobs.CityPageCacheRefreshJob.enqueue("krakow", 50,
        page: 1,
        page_size: 20,
        categories: ["music", "film"]
      )

  ## Uniqueness

  Jobs are unique by city_slug + radius_km + options hash to prevent duplicate
  refreshes for the same query. If a job is already queued, the new one is
  discarded.
  """

  use Oban.Worker,
    queue: :cache_refresh,
    max_attempts: 3,
    unique: [period: 300, fields: [:args, :queue]]

  require Logger

  alias EventasaurusDiscovery.PublicEventsEnhanced

  @cache_name :city_page_cache
  # Cache TTL: 2 hours (data updates daily, so this is conservative)
  @cache_ttl_ms :timer.hours(2)

  @doc """
  Enqueues a cache refresh job for a city.

  ## Parameters

    - `city_slug` - The city slug (e.g., "krakow")
    - `radius_km` - Search radius in kilometers
    - `opts` - Optional query parameters:
      - `:page` - Page number (default: 1)
      - `:page_size` - Results per page (default: 20)
      - `:categories` - List of category slugs to filter
      - `:date_range` - Date range filter
      - `:sort_by` - Sort field
      - `:sort_order` - Sort direction

  ## Returns

    - `{:ok, %Oban.Job{}}` on success
    - `{:ok, :duplicate}` if job already queued (unique constraint)
  """
  def enqueue(city_slug, radius_km, opts \\ []) do
    # Extract scheduling options from opts
    {schedule_in, query_opts} = Keyword.pop(opts, :schedule_in)

    args = build_args(city_slug, radius_km, query_opts)

    # Build job options
    job_opts = if schedule_in, do: [schedule_in: schedule_in], else: []

    case Oban.insert(new(args, job_opts)) do
      {:ok, %Oban.Job{conflict?: true}} ->
        Logger.debug("Cache refresh job already queued for #{city_slug}")
        {:ok, :duplicate}

      result ->
        result
    end
  end

  @doc """
  Builds the cache key for a city's aggregated events.

  The key includes city_slug, radius_km, and a hash of the query options
  to ensure different queries are cached separately.
  """
  def cache_key(city_slug, radius_km, opts \\ []) do
    opts_hash = opts |> Enum.sort() |> :erlang.phash2()
    "aggregated_events:#{city_slug}:#{radius_km}:#{opts_hash}"
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    city_slug = args["city_slug"]
    radius_km = args["radius_km"]

    # IMPORTANT: Build cache key using ORIGINAL string args (Issue #3357)
    # The LiveView looks up cache using string representations of dates,
    # so we must store using the same format to avoid key mismatch.
    cache_opts = build_cache_opts_from_args(args)

    # Parse opts for query execution (DateTime structs needed for SQL)
    opts = decode_opts(args)

    Logger.info("Starting cache refresh for city=#{city_slug} radius=#{radius_km}km")
    start_time = System.monotonic_time(:millisecond)

    # Build the query options for PublicEventsEnhanced
    # Need to look up city by slug and pass as viewing_city
    query_opts = build_query_opts(city_slug, radius_km, opts)

    # Use JobRepo (direct connection) instead of Repo (PgBouncer) - Issue #3353
    # PgBouncer in transaction mode kills long-running queries. The city page
    # aggregation query can take 30-60+ seconds with 800+ events.
    # JobRepo bypasses PgBouncer and connects directly to PostgreSQL.
    query_opts_with_repo = Map.put(query_opts, :repo, EventasaurusApp.JobRepo)

    # The function returns {events, total_count, all_events_count} tuple
    try do
      {events, total_count, all_events_count} =
        PublicEventsEnhanced.list_events_with_aggregation_and_counts(query_opts_with_repo)

      duration = System.monotonic_time(:millisecond) - start_time
      event_count = length(events)

      # Store in cache with TTL using ORIGINAL string-based opts for key
      key = cache_key(city_slug, radius_km, cache_opts)

      cache_value = %{
        events: events,
        total_count: total_count,
        all_events_count: all_events_count,
        cached_at: DateTime.utc_now(),
        duration_ms: duration
      }

      case Cachex.put(@cache_name, key, cache_value, ttl: @cache_ttl_ms) do
        {:ok, true} ->
          Logger.info(
            "Cache refreshed for city=#{city_slug}: #{event_count} events in #{duration}ms"
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to store cache for city=#{city_slug}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Cache refresh failed for city=#{city_slug}: #{inspect(e)}")
        {:error, Exception.message(e)}
    end
  end

  # Build query opts, looking up city by slug
  defp build_query_opts(city_slug, radius_km, opts) do
    alias EventasaurusDiscovery.Locations
    alias EventasaurusWeb.Live.Helpers.EventFilters

    # Look up the city by slug
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        raise "City not found: #{city_slug}"

      viewing_city ->
        build_query_opts_for_city(viewing_city, radius_km, opts)
    end
  end

  defp build_query_opts_for_city(viewing_city, radius_km, opts) do
    alias EventasaurusWeb.Live.Helpers.EventFilters

    # Extract coordinates for geographic filtering
    lat = if viewing_city.latitude, do: Decimal.to_float(viewing_city.latitude), else: nil
    lng = if viewing_city.longitude, do: Decimal.to_float(viewing_city.longitude), else: nil

    # Build base query filters matching what city_live/index.ex passes
    query_filters = %{
      center_lat: lat,
      center_lng: lng,
      radius_km: radius_km,
      sort_order: :asc,
      page_size: opts[:page_size] || 30,
      page: opts[:page] || 1
    }

    # Add optional filters from cache opts
    query_filters =
      query_filters
      |> maybe_put(:categories, opts[:categories])
      |> maybe_put(:date_range, opts[:date_range])
      |> maybe_put(:sort_by, opts[:sort_by])
      # Date filter params (Issue #3357)
      |> maybe_put(:start_date, opts[:start_date])
      |> maybe_put(:end_date, opts[:end_date])
      |> maybe_put(:show_past, opts[:show_past])

    # Build filters for "all events" count (without date restrictions)
    count_filters = Map.delete(query_filters, :page) |> Map.delete(:page_size)
    date_range_count_filters = EventFilters.build_date_range_count_filters(count_filters)

    # Build final query opts matching original city page behavior
    # IMPORTANT: Must return a Map (not keyword list) because aggregate_events uses is_map_key
    query_filters
    |> Map.put(:aggregate, true)
    |> Map.put(:ignore_city_in_aggregation, true)
    |> Map.put(:viewing_city, viewing_city)
    |> Map.put(
      :all_events_filters,
      date_range_count_filters
      |> Map.put(:aggregate, true)
      |> Map.put(:ignore_city_in_aggregation, true)
      |> Map.put(:viewing_city, viewing_city)
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Build job args from parameters
  defp build_args(city_slug, radius_km, opts) do
    base = %{
      "city_slug" => city_slug,
      "radius_km" => radius_km
    }

    # Add optional parameters if present
    opts
    |> Enum.reduce(base, fn
      {:page, v}, acc -> Map.put(acc, "page", v)
      {:page_size, v}, acc -> Map.put(acc, "page_size", v)
      {:categories, v}, acc -> Map.put(acc, "categories", v)
      {:date_range, v}, acc -> Map.put(acc, "date_range", to_string(v))
      {:sort_by, v}, acc -> Map.put(acc, "sort_by", to_string(v))
      {:sort_order, v}, acc -> Map.put(acc, "sort_order", to_string(v))
      # Date filter params (Issue #3357)
      {:start_date, v}, acc -> Map.put(acc, "start_date", v)
      {:end_date, v}, acc -> Map.put(acc, "end_date", v)
      {:show_past, v}, acc -> Map.put(acc, "show_past", v)
      _, acc -> acc
    end)
  end

  # Decode opts from job args back to keyword list
  defp decode_opts(args) do
    []
    |> maybe_add_opt(args, "page", :page, & &1)
    |> maybe_add_opt(args, "page_size", :page_size, & &1)
    |> maybe_add_opt(args, "categories", :categories, & &1)
    |> maybe_add_opt(args, "date_range", :date_range, &String.to_existing_atom/1)
    |> maybe_add_opt(args, "sort_by", :sort_by, &String.to_existing_atom/1)
    |> maybe_add_opt(args, "sort_order", :sort_order, &String.to_existing_atom/1)
    # Date filter params (Issue #3357)
    |> maybe_add_opt(args, "start_date", :start_date, &parse_datetime/1)
    |> maybe_add_opt(args, "end_date", :end_date, &parse_datetime/1)
    |> maybe_add_opt(args, "show_past", :show_past, & &1)
  end

  # Parse ISO8601 datetime string
  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
  defp parse_datetime(other), do: other

  defp maybe_add_opt(opts, args, key, atom_key, transform) do
    case Map.get(args, key) do
      nil -> opts
      value -> Keyword.put(opts, atom_key, transform.(value))
    end
  end

  # Build cache opts from job args using ORIGINAL string values (Issue #3357)
  # This ensures the cache key matches what the LiveView uses for lookup.
  # The LiveView stores dates as ISO8601 strings in cache opts, so we must
  # use the same format here to avoid cache key mismatch.
  defp build_cache_opts_from_args(args) do
    []
    |> maybe_add_opt_raw(args, "page", :page)
    |> maybe_add_opt_raw(args, "page_size", :page_size)
    |> maybe_add_opt_raw(args, "categories", :categories)
    |> maybe_add_opt_raw(args, "date_range", :date_range)
    |> maybe_add_opt_raw(args, "sort_by", :sort_by)
    |> maybe_add_opt_raw(args, "sort_order", :sort_order)
    # Date filter params - keep as strings to match LiveView format
    |> maybe_add_opt_raw(args, "start_date", :start_date)
    |> maybe_add_opt_raw(args, "end_date", :end_date)
    |> maybe_add_opt_raw(args, "show_past", :show_past)
  end

  # Add opt without transformation (keeps original value from args)
  defp maybe_add_opt_raw(opts, args, key, atom_key) do
    case Map.get(args, key) do
      nil -> opts
      value -> Keyword.put(opts, atom_key, value)
    end
  end
end
