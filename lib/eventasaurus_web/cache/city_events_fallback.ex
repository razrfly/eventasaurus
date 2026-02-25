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

  ## Aggregation (v2)

  Movies showing at multiple venues are aggregated into `AggregatedMovieGroup`
  structs. Source events (pub quizzes, etc.) with `aggregate_on_index = true`
  are aggregated into `AggregatedEventGroup` structs by `{source_id, aggregation_type}`.

  Container events appear as regular events in the MV path (documented gap —
  containers are rare, 0-3 per city, and require live table queries).

  See: https://github.com/razrfly/eventasaurus/issues/3686
  See: https://github.com/razrfly/eventasaurus/issues/3423

  ## Usage

      alias EventasaurusWeb.Cache.CityEventsFallback

      # Get events for a city (returns format compatible with CityPageCache)
      {:ok, result} = CityEventsFallback.get_events("krakow", page: 1, page_size: 30)

      # Get date counts for filter badges
      {:ok, counts} = CityEventsFallback.get_date_counts("krakow")

  ## Performance

  The materialized view has indexes on city_slug and starts_at, providing
  sub-5ms query times for typical city pages (~100-500 events per city).
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup

  require Logger

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
      query = base_query(city_slug)
      query = apply_date_filters(query, start_date, end_date)

      all_raw_events =
        query
        |> order_by([e], asc: e.starts_at)
        |> Repo.replica().all()
        |> Enum.map(&transform_row/1)

      aggregated = aggregate_mv_events(all_raw_events, city_slug)
      total_count = length(aggregated)

      offset = (page - 1) * page_size
      page_events = Enum.slice(aggregated, offset, page_size)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      {:ok,
       %{
         events: page_events,
         total_count: total_count,
         all_events_count: total_count,
         cached_at: DateTime.utc_now(),
         duration_ms: duration_ms,
         from_fallback: true
       }}
    rescue
      e ->
        Logger.error(
          "[CityEventsFallback] get_events failed for #{city_slug}: #{Exception.message(e)}"
        )

        {:error, Exception.message(e)}
    end
  end

  @doc """
  Get all events from the materialized view for a city (unpaginated).

  Used for in-memory filtering by `CityPageFilters`. Returns all events
  for the city without pagination, allowing quick date range filtering.
  """
  @spec get_all_events(String.t()) :: {:ok, map()} | {:error, term()}
  def get_all_events(city_slug) do
    start_time = System.monotonic_time(:millisecond)

    try do
      raw_events =
        base_query(city_slug)
        |> order_by([e], asc: e.starts_at)
        |> Repo.replica().all()
        |> Enum.map(&transform_row/1)

      events = aggregate_mv_events(raw_events, city_slug)
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
        Logger.error(
          "[CityEventsFallback] get_all_events failed for #{city_slug}: #{Exception.message(e)}"
        )

        {:error, Exception.message(e)}
    end
  end

  @doc """
  Get date range counts for filter badges from the materialized view.

  Calculates event counts for each quick date filter button using the
  same data source as `get_events/2`, ensuring consistency.
  """
  @spec get_date_counts(String.t()) :: {:ok, map()} | {:error, term()}
  def get_date_counts(city_slug) do
    try do
      raw_events =
        base_query(city_slug)
        |> order_by([e], asc: e.starts_at)
        |> Repo.replica().all()
        |> Enum.map(&transform_row/1)

      aggregated = aggregate_mv_events(raw_events, city_slug)
      counts = calculate_date_range_counts(aggregated)
      {:ok, counts}
    rescue
      e ->
        Logger.error(
          "[CityEventsFallback] get_date_counts failed for #{city_slug}: #{Exception.message(e)}"
        )

        {:error, Exception.message(e)}
    end
  end

  @doc """
  Get combined events and date counts in a single call.

  Optimized for city page initial load - fetches all events once and
  calculates both paginated results and date counts from the same data.
  """
  @spec get_events_with_counts(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_events_with_counts(city_slug, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 30)

    try do
      raw_events =
        base_query(city_slug)
        |> order_by([e], asc: e.starts_at)
        |> Repo.replica().all()
        |> Enum.map(&transform_row/1)

      all_events = aggregate_mv_events(raw_events, city_slug)
      total_count = length(all_events)

      # Calculate date counts from aggregated list so counts match displayed cards
      date_counts = calculate_date_range_counts(all_events)

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
        Logger.error(
          "[CityEventsFallback] get_events_with_counts failed for #{city_slug}: #{Exception.message(e)}"
        )

        {:error, Exception.message(e)}
    end
  end

  # Build base query for the materialized view (v2 — includes source columns)
  defp base_query(city_slug) do
    from(e in "city_events_mv",
      where: e.city_slug == ^city_slug and not is_nil(e.event_slug),
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
        # Movie columns
        movie_id: e.movie_id,
        movie_title: e.movie_title,
        movie_slug: e.movie_slug,
        movie_release_date: e.movie_release_date,
        movie_runtime: e.movie_runtime,
        movie_metadata: e.movie_metadata,
        movie_poster_url: e.movie_poster_url,
        movie_backdrop_url: e.movie_backdrop_url,
        source_image_url: e.source_image_url,
        # Source aggregation columns (new in v2)
        source_id: e.source_id,
        source_slug: e.source_slug,
        source_name: e.source_name,
        aggregation_type: e.aggregation_type,
        aggregate_on_index: e.aggregate_on_index
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
      # Movie fields
      movie_id: row.movie_id,
      movie_title: row.movie_title,
      movie_slug: row.movie_slug,
      movie_release_date: row.movie_release_date,
      movie_runtime: row.movie_runtime,
      movie_metadata: row.movie_metadata,
      movie_poster_url: row.movie_poster_url,
      movie_backdrop_url: row.movie_backdrop_url,
      # Source aggregation fields (new in v2)
      source_id: row.source_id,
      source_slug: row.source_slug,
      source_name: row.source_name,
      aggregation_type: row.aggregation_type,
      aggregate_on_index: row.aggregate_on_index,
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
  defp naive_to_utc_datetime(nil), do: nil
  defp naive_to_utc_datetime(%DateTime{} = dt), do: dt

  defp naive_to_utc_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  # ── Aggregation (v2) ──────────────────────────────────────────────────

  # Aggregate MV events into movie groups AND source event groups.
  #
  # 1. Split rows: movie events (movie_id != nil) vs others
  # 2. From others, split: aggregatable (aggregate_on_index == true) vs regular
  # 3. Group movie events by movie_id → AggregatedMovieGroup
  # 4. Group aggregatable events by {source_id, aggregation_type} → AggregatedEventGroup
  # 5. Combine + sort by starts_at
  defp aggregate_mv_events(events, city_slug) do
    # Separate movie events from non-movie events
    {movie_events, non_movie_events} =
      Enum.split_with(events, fn event -> event.movie_id != nil end)

    # From non-movie events, separate aggregatable source events from regular events
    {aggregatable_events, regular_events} =
      Enum.split_with(non_movie_events, fn event ->
        event.aggregate_on_index == true and event.source_id != nil
      end)

    # Build movie groups
    movie_groups =
      movie_events
      |> Enum.group_by(& &1.movie_id)
      |> Enum.map(fn {movie_id, grouped} -> build_movie_group(movie_id, grouped) end)
      |> Enum.reject(&is_nil/1)

    # Build source event groups
    source_groups =
      aggregatable_events
      |> Enum.group_by(fn e -> {e.source_id, e.aggregation_type} end)
      |> Enum.map(fn {{source_id, agg_type}, grouped} ->
        build_source_event_group(source_id, agg_type, grouped, city_slug)
      end)
      |> Enum.reject(&is_nil/1)

    # Combine all items and sort by earliest start time
    far_future = DateTime.add(DateTime.utc_now(), 365 * 24 * 60 * 60, :second)

    (movie_groups ++ source_groups ++ regular_events)
    |> Enum.sort_by(fn
      %AggregatedMovieGroup{earliest_starts_at: starts_at} -> starts_at || far_future
      %AggregatedEventGroup{} -> far_future
      event -> event.starts_at || far_future
    end)
  end

  # Build an AggregatedMovieGroup from a list of events for the same movie
  defp build_movie_group(movie_id, events) do
    first_event = List.first(events)

    if first_event do
      unique_venue_count =
        events
        |> Enum.map(fn e -> e.venue.id end)
        |> Enum.uniq()
        |> length()

      all_categories =
        events
        |> Enum.map(fn e -> e.category end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(fn cat -> cat.id end)

      earliest_starts_at =
        events
        |> Enum.map(fn e -> e.starts_at end)
        |> Enum.reject(&is_nil/1)
        |> Enum.min(DateTime, fn -> nil end)

      city = first_event.venue.city
      metadata = first_event.movie_metadata || %{}

      %AggregatedMovieGroup{
        movie_id: movie_id,
        movie_slug: first_event.movie_slug,
        movie_title: first_event.movie_title,
        movie_backdrop_url: first_event.movie_backdrop_url,
        movie_poster_url: first_event.movie_poster_url,
        movie_release_date: first_event.movie_release_date,
        movie_runtime: first_event.movie_runtime,
        movie_vote_average: extract_vote_average(metadata),
        movie_genres: extract_genres(metadata),
        movie_tagline: extract_tagline(metadata),
        city_id: city.id,
        city: city,
        screening_count: length(events),
        venue_count: unique_venue_count,
        categories: all_categories,
        earliest_starts_at: earliest_starts_at
      }
    else
      nil
    end
  end

  # Build an AggregatedEventGroup from a list of events for the same source + aggregation_type
  defp build_source_event_group(source_id, aggregation_type, events, _city_slug) do
    first_event = List.first(events)

    if first_event do
      unique_venue_count =
        events
        |> Enum.map(fn e -> e.venue.id end)
        |> Enum.uniq()
        |> length()

      all_categories =
        events
        |> Enum.map(fn e -> e.category end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(fn cat -> cat.id end)

      # Use first event's image as cover (MV can't call get_city_general_image/2)
      cover_image_url = first_event.cover_image_url

      # Heuristic: recurring if more than 1 event (MV lacks PublicEvent.recurring? check)
      is_recurring = length(events) > 1

      city = first_event.venue.city

      %AggregatedEventGroup{
        source_id: source_id,
        source_slug: first_event.source_slug,
        source_name: first_event.source_name,
        aggregation_type: aggregation_type,
        city_id: city.id,
        city: city,
        event_count: length(events),
        venue_count: unique_venue_count,
        categories: all_categories,
        cover_image_url: cover_image_url,
        is_recurring: is_recurring
      }
    else
      nil
    end
  end

  # ── JSONB metadata extractors (copied from PublicEventsEnhanced) ──────

  # Extract vote_average from movie metadata (stored by TMDB sync)
  # Always coerce to float to match AggregatedMovieGroup.movie_vote_average spec
  defp extract_vote_average(%{"vote_average" => v}) when is_number(v) and v > 0, do: v * 1.0

  defp extract_vote_average(%{"tmdb_data" => %{"vote_average" => v}}) when is_number(v) and v > 0,
    do: v * 1.0

  defp extract_vote_average(_), do: nil

  # Extract genre names from movie metadata
  defp extract_genres(%{"genres" => genres}) when is_list(genres) do
    Enum.map(genres, fn
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_genres(_), do: []

  # Extract tagline from movie metadata
  defp extract_tagline(%{"tagline" => t}) when is_binary(t) and t != "", do: t
  defp extract_tagline(_), do: nil

  # ── Date range counting ───────────────────────────────────────────────

  # Calculate date range counts from a list of events/groups
  # Handles regular events, AggregatedMovieGroup, and AggregatedEventGroup
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
          starts_at = get_starts_at(event)

          cond do
            is_nil(starts_at) -> false
            DateTime.compare(starts_at, now) == :lt -> false
            start_date && DateTime.compare(starts_at, start_date) == :lt -> false
            end_date && DateTime.compare(starts_at, end_date) == :gt -> false
            true -> true
          end
        end)

      Map.put(acc, range_atom, count)
    end)
  end

  # Extract starts_at from either a regular event, AggregatedMovieGroup, or AggregatedEventGroup
  defp get_starts_at(%AggregatedMovieGroup{earliest_starts_at: starts_at}), do: starts_at
  defp get_starts_at(%AggregatedEventGroup{}), do: nil
  defp get_starts_at(%{starts_at: starts_at}), do: starts_at
  defp get_starts_at(_), do: nil
end
