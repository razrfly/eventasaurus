defmodule EventasaurusWeb.Live.Helpers.EventPagination do
  @moduledoc """
  Shared event pagination and filtering logic for entity pages.

  This module provides pure functions for in-memory event filtering
  and pagination, used by venue, performer, and other entity pages
  that load all events upfront and filter client-side.

  ## Usage

      alias EventasaurusWeb.Live.Helpers.EventPagination
      alias EventasaurusDiscovery.Pagination

      # Filter events by date range
      filtered = EventPagination.filter_by_date_range(events, :next_30_days)

      # Calculate counts for date filter buttons
      counts = EventPagination.calculate_date_range_counts(events)

      # Paginate a list of events
      {page_events, pagination} = EventPagination.paginate(events, 1, 30)

  ## Design Principles

  1. **Client-Side Filtering**: These functions work on in-memory event lists
  2. **Pure Functions**: No side effects, easily testable
  3. **Consistent API**: Same interface across venue, performer, activity pages
  """

  alias EventasaurusDiscovery.Pagination
  alias EventasaurusDiscovery.PublicEventsEnhanced

  @doc """
  Filter events by date range.

  Returns events that fall within the specified date range.
  Pass `nil` to return all events (no filtering).

  ## Parameters

    - events: List of events with `starts_at` DateTime field
    - range_atom: Date range identifier (:today, :tomorrow, :next_7_days, etc.) or nil

  ## Examples

      # Get events for the next 30 days
      filtered = EventPagination.filter_by_date_range(events, :next_30_days)

      # Get all events (no date filter)
      all = EventPagination.filter_by_date_range(events, nil)
  """
  @spec filter_by_date_range(list(), atom() | nil) :: list()
  def filter_by_date_range(events, nil) do
    # "All Events" - return unfiltered
    events
  end

  def filter_by_date_range(events, range_atom) do
    {start_date, end_date} = PublicEventsEnhanced.calculate_date_range(range_atom)
    now = DateTime.utc_now()

    Enum.filter(events, fn event ->
      starts_at = event.starts_at

      cond do
        DateTime.compare(starts_at, now) == :lt -> false
        start_date && DateTime.compare(starts_at, start_date) == :lt -> false
        end_date && DateTime.compare(starts_at, end_date) == :gt -> false
        true -> true
      end
    end)
  end

  @doc """
  Calculate event counts for each date range filter button.

  Returns a map of range atoms to counts, used to show counts on
  quick date filter buttons.

  ## Parameters

    - events: List of events with `starts_at` DateTime field

  ## Returns

  Map with date range atoms as keys and event counts as values:

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
  @spec calculate_date_range_counts(list()) :: map()
  def calculate_date_range_counts(events) do
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

  @doc """
  Paginate a list of events.

  Returns a tuple of {page_entries, pagination_struct} for the requested page.

  ## Parameters

    - events: List of events to paginate
    - page: Page number (1-indexed)
    - page_size: Number of items per page

  ## Returns

  Tuple of {entries, pagination} where:
    - entries: List of events for the current page
    - pagination: Pagination struct with metadata

  ## Example

      {events, pagination} = EventPagination.paginate(all_events, 2, 30)
      # events = list of up to 30 events for page 2
      # pagination.total_pages = total number of pages
  """
  @spec paginate(list(), pos_integer(), pos_integer()) :: {list(), Pagination.t()}
  def paginate(events, page, page_size) do
    total_entries = length(events)
    total_pages = max(1, ceil(total_entries / page_size))
    # Clamp page to valid range
    page = min(max(1, page), total_pages)

    offset = (page - 1) * page_size
    entries = Enum.slice(events, offset, page_size)

    pagination = %Pagination{
      entries: entries,
      page_number: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }

    {entries, pagination}
  end

  @doc """
  Filter events by time filter (upcoming, past, or all).

  Returns events filtered by their temporal status relative to now.

  ## Parameters

    - events: List of events with `starts_at` DateTime field
    - time_filter: :upcoming (default), :past, or :all

  ## Examples

      # Get only upcoming events (default behavior)
      upcoming = EventPagination.filter_by_time(events, :upcoming)

      # Get only past events
      past = EventPagination.filter_by_time(events, :past)

      # Get all events regardless of time
      all = EventPagination.filter_by_time(events, :all)
  """
  @spec filter_by_time(list(), atom()) :: list()
  def filter_by_time(events, :all), do: events

  def filter_by_time(events, :upcoming) do
    now = DateTime.utc_now()

    Enum.filter(events, fn event ->
      DateTime.compare(event.starts_at, now) != :lt
    end)
  end

  def filter_by_time(events, :past) do
    now = DateTime.utc_now()

    Enum.filter(events, fn event ->
      DateTime.compare(event.starts_at, now) == :lt
    end)
  end

  def filter_by_time(events, nil), do: filter_by_time(events, :upcoming)

  @doc """
  Calculate time filter counts (upcoming, past, all).

  Returns a map with counts for each time filter option.

  ## Parameters

    - events: List of events with `starts_at` DateTime field

  ## Returns

      %{
        upcoming: 5,
        past: 3,
        all: 8
      }
  """
  @spec calculate_time_filter_counts(list()) :: map()
  def calculate_time_filter_counts(events) do
    now = DateTime.utc_now()

    {upcoming, past} =
      Enum.reduce(events, {0, 0}, fn event, {up, past} ->
        if DateTime.compare(event.starts_at, now) == :lt do
          {up, past + 1}
        else
          {up + 1, past}
        end
      end)

    %{
      upcoming: upcoming,
      past: past,
      all: upcoming + past
    }
  end

  @doc """
  Filter events by search term.

  Filters events where the title contains the search term (case-insensitive).
  Returns all events if search_term is nil or empty.

  ## Parameters

    - events: List of events with `display_title` and/or `title` fields
    - search_term: String to search for (case-insensitive)

  ## Example

      filtered = EventPagination.filter_by_search(events, "jazz")
  """
  @spec filter_by_search(list(), String.t() | nil) :: list()
  def filter_by_search(events, nil), do: events
  def filter_by_search(events, ""), do: events

  def filter_by_search(events, search_term) do
    search_lower = String.downcase(search_term)

    Enum.filter(events, fn event ->
      title = (event.display_title || event.title || "") |> String.downcase()
      String.contains?(title, search_lower)
    end)
  end

  @doc """
  Apply multiple filters and paginate in one call.

  Convenience function that applies time filter, date range filter, search filter,
  and pagination in sequence.

  ## Parameters

    - events: List of all events
    - opts: Keyword list of options
      - :time_filter - :upcoming, :past, or :all (default: :upcoming)
      - :date_range - atom or nil for date filtering
      - :search - string for title search
      - :page - page number (default: 1)
      - :page_size - items per page (default: 30)

  ## Returns

  Tuple of {page_entries, pagination, filtered_count} where:
    - page_entries: Events for the current page
    - pagination: Pagination struct
    - filtered_count: Total matching events (before pagination)

  ## Example

      {events, pagination, total} = EventPagination.filter_and_paginate(all_events,
        time_filter: :upcoming,
        date_range: :next_7_days,
        search: "concert",
        page: 1,
        page_size: 30
      )
  """
  @spec filter_and_paginate(list(), keyword()) :: {list(), Pagination.t(), non_neg_integer()}
  def filter_and_paginate(events, opts \\ []) do
    time_filter = Keyword.get(opts, :time_filter, :upcoming)
    date_range = Keyword.get(opts, :date_range)
    search_term = Keyword.get(opts, :search)
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 30)

    filtered =
      events
      |> filter_by_time(time_filter)
      |> filter_by_date_range(date_range)
      |> filter_by_search(search_term)

    filtered_count = length(filtered)
    {page_entries, pagination} = paginate(filtered, page, page_size)

    {page_entries, pagination, filtered_count}
  end
end
