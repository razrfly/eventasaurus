defmodule EventasaurusWeb.Cache.CityEventsFallback do
  @moduledoc """
  Fallback data source for city page events using the materialized view.

  This module provides a guaranteed data source when Cachex misses occur,
  querying the `city_events_mv` materialized view directly. The view is
  refreshed hourly and contains denormalized event data for fast queries.

  ## Why This Exists

  The city page had a UX bug where date filter counts (e.g., "79 events")
  didn't match the displayed grid ("No Events Found"). This happened because
  counts and events came from different cache keys that could be out of sync.

  The materialized view provides a single source of truth - both counts
  and events come from the same query, guaranteeing consistency.

  ## Usage

      alias EventasaurusWeb.Cache.CityEventsFallback

      # Get events for a city (returns format compatible with CityPageCache)
      {:ok, result} = CityEventsFallback.get_events("krakow", page: 1, page_size: 30)

      # Get date counts for filter badges
      {:ok, counts} = CityEventsFallback.get_date_counts("krakow")

  ## Performance

  The materialized view has indexes on city_slug and starts_at, providing
  sub-5ms query times for typical city pages (~100-500 events per city).

  See: https://github.com/anthropics/eventasaurus/issues/3373
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEventsEnhanced

  @doc """
  Get events from the materialized view for a city.

  Returns events in the same format as `CityPageCache.get_base_events/2`,
  making it a drop-in fallback when cache misses occur.

  ## Options

    * `:page` - Page number (default: 1)
    * `:page_size` - Events per page (default: 30)
    * `:start_date` - Filter events starting after this DateTime
    * `:end_date` - Filter events starting before this DateTime

  ## Returns

      {:ok, %{
        events: [event1, event2, ...],
        total_count: 150,
        all_events_count: 150,
        cached_at: ~U[...],
        duration_ms: 2,
        from_fallback: true
      }}

  Or `{:error, reason}` on failure.
  """
  @spec get_events(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_events(city_slug, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 30)
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

    try do
      # Build base query
      query = base_query(city_slug)

      # Apply date filters if provided
      query = apply_date_filters(query, start_date, end_date)

      # Get total count
      total_count = Repo.replica().aggregate(query, :count, :event_id)

      # Get paginated events
      offset = (page - 1) * page_size

      events =
        query
        |> order_by([e], asc: e.starts_at)
        |> limit(^page_size)
        |> offset(^offset)
        |> Repo.replica().all()
        |> Enum.map(&transform_row/1)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      {:ok,
       %{
         events: events,
         total_count: total_count,
         all_events_count: total_count,
         cached_at: DateTime.utc_now(),
         duration_ms: duration_ms,
         from_fallback: true
       }}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Get all events from the materialized view for a city (unpaginated).

  Used for in-memory filtering by `CityPageFilters`. Returns all events
  for the city without pagination, allowing quick date range filtering.

  ## Returns

      {:ok, %{
        events: [event1, event2, ...],
        all_events_count: 150,
        cached_at: ~U[...],
        duration_ms: 3,
        from_fallback: true
      }}
  """
  @spec get_all_events(String.t()) :: {:ok, map()} | {:error, term()}
  def get_all_events(city_slug) do
    start_time = System.monotonic_time(:millisecond)

    try do
      events =
        base_query(city_slug)
        |> order_by([e], asc: e.starts_at)
        |> Repo.replica().all()
        |> Enum.map(&transform_row/1)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      {:ok,
       %{
         events: events,
         all_events_count: length(events),
         cached_at: DateTime.utc_now(),
         duration_ms: duration_ms,
         from_fallback: true
       }}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Get date range counts for filter badges from the materialized view.

  Calculates event counts for each quick date filter button using the
  same data source as `get_events/2`, ensuring consistency.

  ## Returns

      {:ok, %{
        today: 5,
        tomorrow: 3,
        this_weekend: 12,
        next_7_days: 25,
        next_30_days: 87,
        this_month: 45,
        next_month: 32
      }}
  """
  @spec get_date_counts(String.t()) :: {:ok, map()} | {:error, term()}
  def get_date_counts(city_slug) do
    try do
      # Get all events with just the starts_at field for counting
      # Use a minimal query instead of base_query since we only need starts_at
      events =
        from(e in "city_events_mv",
          where: e.city_slug == ^city_slug,
          select: %{starts_at: e.starts_at}
        )
        |> Repo.replica().all()
        # Convert NaiveDateTime to DateTime for comparison functions
        |> Enum.map(fn row ->
          %{starts_at: naive_to_utc_datetime(row.starts_at)}
        end)

      # Calculate counts for each date range
      counts = calculate_date_range_counts(events)

      {:ok, counts}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Get combined events and date counts in a single call.

  Optimized for city page initial load - fetches all events once and
  calculates both paginated results and date counts from the same data.

  ## Returns

      {:ok, %{
        events: [event1, event2, ...],
        total_count: 150,
        all_events_count: 150,
        date_counts: %{today: 5, tomorrow: 3, ...},
        cached_at: ~U[...],
        duration_ms: 3,
        from_fallback: true
      }}
  """
  @spec get_events_with_counts(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_events_with_counts(city_slug, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 30)

    try do
      # Get all events in one query
      all_events =
        base_query(city_slug)
        |> order_by([e], asc: e.starts_at)
        |> Repo.replica().all()
        |> Enum.map(&transform_row/1)

      total_count = length(all_events)

      # Calculate date counts from the full list
      date_counts = calculate_date_range_counts(all_events)

      # Paginate
      offset = (page - 1) * page_size
      page_events = Enum.slice(all_events, offset, page_size)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      {:ok,
       %{
         events: page_events,
         total_count: total_count,
         all_events_count: total_count,
         date_counts: date_counts,
         cached_at: DateTime.utc_now(),
         duration_ms: duration_ms,
         from_fallback: true
       }}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  # Build base query for the materialized view
  defp base_query(city_slug) do
    from(e in "city_events_mv",
      where: e.city_slug == ^city_slug,
      select: %{
        event_id: e.event_id,
        title: e.title,
        event_slug: e.event_slug,
        starts_at: e.starts_at,
        ends_at: e.ends_at,
        occurrences: e.occurrences,
        city_id: e.city_id,
        city_slug: e.city_slug,
        city_name: e.city_name,
        city_timezone: e.city_timezone,
        venue_id: e.venue_id,
        venue_name: e.venue_name,
        venue_slug: e.venue_slug,
        venue_lat: e.venue_lat,
        venue_lng: e.venue_lng,
        venue_is_public: e.venue_is_public,
        category_id: e.category_id,
        category_name: e.category_name,
        category_slug: e.category_slug,
        # Image columns added in migration 20260124154631
        movie_poster_url: e.movie_poster_url,
        movie_backdrop_url: e.movie_backdrop_url,
        source_image_url: e.source_image_url
      }
    )
  end

  # Apply optional date filters to the query
  defp apply_date_filters(query, nil, nil), do: query

  defp apply_date_filters(query, start_date, nil) do
    where(query, [e], e.starts_at >= ^start_date)
  end

  defp apply_date_filters(query, nil, end_date) do
    where(query, [e], e.starts_at <= ^end_date)
  end

  defp apply_date_filters(query, start_date, end_date) do
    query
    |> where([e], e.starts_at >= ^start_date)
    |> where([e], e.starts_at <= ^end_date)
  end

  # Transform a raw database row to the expected event format
  defp transform_row(row) do
    %{
      id: row.event_id,
      title: row.title,
      slug: row.event_slug,
      # Convert NaiveDateTime to DateTime for consistency with rest of app
      starts_at: naive_to_utc_datetime(row.starts_at),
      ends_at: naive_to_utc_datetime(row.ends_at),
      occurrences: row.occurrences,
      venue: %{
        id: row.venue_id,
        name: row.venue_name,
        slug: row.venue_slug,
        latitude: row.venue_lat,
        longitude: row.venue_lng,
        is_public: row.venue_is_public,
        city: %{
          id: row.city_id,
          name: row.city_name,
          slug: row.city_slug,
          timezone: row.city_timezone
        }
      },
      category:
        if row.category_id do
          %{
            id: row.category_id,
            name: row.category_name,
            slug: row.category_slug
          }
        else
          nil
        end,
      # Cover image using same priority as PublicEventsEnhanced.get_cover_image_url:
      # 1. Movie backdrop (highest quality)
      # 2. Movie poster
      # 3. Source image
      # 4. nil (Unsplash fallback handled by event card component)
      cover_image_url: derive_cover_image_url(row)
    }
  end

  # Derive cover image URL using same priority as PublicEventsEnhanced.get_cover_image_url
  defp derive_cover_image_url(row) do
    cond do
      is_non_empty_string?(row[:movie_backdrop_url]) -> row.movie_backdrop_url
      is_non_empty_string?(row[:movie_poster_url]) -> row.movie_poster_url
      is_non_empty_string?(row[:source_image_url]) -> row.source_image_url
      true -> nil
    end
  end

  defp is_non_empty_string?(nil), do: false
  defp is_non_empty_string?(str) when is_binary(str), do: String.trim(str) != ""
  defp is_non_empty_string?(_), do: false

  # Convert NaiveDateTime to DateTime with UTC timezone
  # Raw SQL queries return NaiveDateTime, but our comparison functions expect DateTime
  defp naive_to_utc_datetime(nil), do: nil
  defp naive_to_utc_datetime(%DateTime{} = dt), do: dt
  defp naive_to_utc_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  # Calculate date range counts from a list of events
  # Matches the format expected by CityPageFilters
  defp calculate_date_range_counts(events) do
    now = DateTime.utc_now()

    ranges = [
      :today,
      :tomorrow,
      :this_weekend,
      :next_7_days,
      :next_30_days,
      :this_month,
      :next_month
    ]

    Enum.reduce(ranges, %{}, fn range_atom, acc ->
      {start_date, end_date} = PublicEventsEnhanced.calculate_date_range(range_atom)

      count =
        Enum.count(events, fn event ->
          starts_at = event.starts_at

          cond do
            DateTime.compare(starts_at, now) == :lt -> false
            start_date && DateTime.compare(starts_at, start_date) == :lt -> false
            end_date && DateTime.compare(starts_at, end_date) == :gt -> false
            true -> true
          end
        end)

      Map.put(acc, range_atom, count)
    end)
  end
end
