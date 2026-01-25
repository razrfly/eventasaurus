defmodule EventasaurusWeb.Live.Helpers.CityPageFilters do
  @moduledoc """
  Helper functions for city page base cache filtering.

  This module determines when the base cache can be used and provides
  in-memory filtering functions for instant date filter responses.

  ## Base Cache Strategy (Issue #3363)

  The city page caches a single large dataset per city (~500 events covering
  ~30 days) called the "base cache". When users click date filters like
  "Today" or "Next 7 Days", we filter the base cache in-memory rather than
  making a new database query.

  This solves the "cache key explosion" problem where each filter combination
  created a unique cache key, causing cache misses on first click.

  ## Usage

      alias EventasaurusWeb.Live.Helpers.CityPageFilters
      alias EventasaurusWeb.Cache.CityPageCache

      # Check if we can use base cache
      if CityPageFilters.can_use_base_cache?(filters) do
        case CityPageCache.get_base_events(city_slug, radius_km) do
          {:ok, base_data} ->
            # Filter in-memory
            result = CityPageFilters.filter_base_events(base_data, filters, page_opts)
            {:ok, result}

          {:miss, nil} ->
            # No base cache yet, fall back to per-filter cache
            {:miss, nil}
        end
      else
        # Category/search filters require per-filter cache
        CityPageCache.get_aggregated_events(city_slug, radius_km, opts)
      end
  """

  alias EventasaurusWeb.Live.Helpers.EventPagination

  @doc """
  Determines if the current filters allow using the base cache.

  The base cache can be used when:
  - No category filters are applied
  - No search term is active

  Date filters (start_date, end_date) are handled by in-memory filtering,
  so they don't disqualify base cache usage.

  ## Parameters

    - filters: Current filter map

  ## Returns

  `true` if base cache can be used, `false` if per-filter cache is needed.

  ## Examples

      # Date-only filters can use base cache
      iex> CityPageFilters.can_use_base_cache?(%{start_date: ~U[...], end_date: ~U[...]})
      true

      # Category filters require per-filter cache
      iex> CityPageFilters.can_use_base_cache?(%{categories: ["music"]})
      false

      # Search requires per-filter cache
      iex> CityPageFilters.can_use_base_cache?(%{search: "jazz"})
      false
  """
  @spec can_use_base_cache?(map()) :: boolean()
  def can_use_base_cache?(filters) do
    no_categories? = empty_list?(filters[:categories])
    no_search? = empty_string?(filters[:search])

    no_categories? && no_search?
  end

  @doc """
  Filters base cache events in-memory and returns paginated results.

  This function applies date filtering and pagination to the base cache data,
  providing instant responses for date filter changes.

  ## Parameters

    - base_data: Base cache data map with `:events` key
    - filters: Current filter map with optional `:start_date`, `:end_date`
    - page_opts: Pagination options (`:page`, `:page_size`)

  ## Returns

  A result map matching the format returned by `get_aggregated_events/3`:

      %{
        events: [...],           # Paginated events for current page
        total_count: 123,        # Total matching events (after filtering)
        all_events_count: 500,   # Total events in base cache
        cached_at: ~U[...],      # Original cache timestamp
        filtered_from_base: true # Marker for telemetry/debugging
      }
  """
  @spec filter_base_events(map(), map(), keyword()) :: map()
  def filter_base_events(base_data, filters, page_opts \\ []) do
    base_events = Map.get(base_data, :events, [])
    page = Keyword.get(page_opts, :page, 1)
    page_size = Keyword.get(page_opts, :page_size, 30)

    # Apply date filter in-memory
    filtered_events = apply_date_filter(base_events, filters)

    # Paginate the filtered results
    {page_events, pagination} = EventPagination.paginate(filtered_events, page, page_size)

    %{
      events: page_events,
      total_count: pagination.total_entries,
      all_events_count: Map.get(base_data, :all_events_count, length(base_events)),
      cached_at: Map.get(base_data, :cached_at),
      duration_ms: 0,
      filtered_from_base: true
    }
  end

  @doc """
  Calculates date range counts from base cache events.

  Returns counts for each quick date filter button (Today, Tomorrow, etc.)
  computed in-memory from the base cache.

  ## Parameters

    - base_data: Base cache data map with `:events` key

  ## Returns

  Map of date range atoms to counts:

      %{
        today: 5,
        tomorrow: 3,
        this_weekend: 12,
        next_7_days: 25,
        next_30_days: 87,
        this_month: 45,
        next_month: 32
      }
  """
  @spec calculate_date_range_counts(map()) :: map()
  def calculate_date_range_counts(base_data) do
    events = Map.get(base_data, :events, [])
    EventPagination.calculate_date_range_counts(events)
  end

  # Apply date filter to events in-memory
  defp apply_date_filter(events, filters) do
    start_date = filters[:start_date]
    end_date = filters[:end_date]

    cond do
      # No date filters - return all events
      is_nil(start_date) && is_nil(end_date) ->
        events

      # Both dates specified - filter by range
      !is_nil(start_date) && !is_nil(end_date) ->
        filter_by_date_bounds(events, start_date, end_date)

      # Only start date
      !is_nil(start_date) ->
        filter_by_start_date(events, start_date)

      # Only end date
      true ->
        filter_by_end_date(events, end_date)
    end
  end

  defp filter_by_date_bounds(events, start_date, end_date) do
    Enum.filter(events, fn event ->
      starts_at = get_event_start(event)

      starts_at && DateTime.compare(starts_at, start_date) != :lt &&
        DateTime.compare(starts_at, end_date) != :gt
    end)
  end

  defp filter_by_start_date(events, start_date) do
    Enum.filter(events, fn event ->
      starts_at = get_event_start(event)
      starts_at && DateTime.compare(starts_at, start_date) != :lt
    end)
  end

  defp filter_by_end_date(events, end_date) do
    Enum.filter(events, fn event ->
      starts_at = get_event_start(event)
      starts_at && DateTime.compare(starts_at, end_date) != :gt
    end)
  end

  # Get the start time from either a regular event or aggregated container
  # Regular events have :starts_at, aggregated containers have :start_date
  defp get_event_start(%{starts_at: starts_at}) when not is_nil(starts_at), do: starts_at
  defp get_event_start(%{start_date: start_date}) when not is_nil(start_date), do: start_date
  defp get_event_start(_), do: nil

  defp empty_list?(nil), do: true
  defp empty_list?([]), do: true
  defp empty_list?(_), do: false

  defp empty_string?(nil), do: true
  defp empty_string?(""), do: true
  defp empty_string?(_), do: false
end
