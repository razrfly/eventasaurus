defmodule EventasaurusWeb.Live.Helpers.EventFilters do
  @moduledoc """
  Shared event filtering logic for City and Public Events pages.

  This module provides pure functions for transforming filter maps,
  calculating active filter counts, and managing date range filters.
  All functions are stateless and testable in isolation.
  """

  @doc """
  Parse and validate quick date range string.

  Returns `{:ok, atom}` for valid ranges, `:error` for invalid input.
  This provides defense against malicious client payloads.

  ## Examples

      iex> EventFilters.parse_quick_range("today")
      {:ok, :today}

      iex> EventFilters.parse_quick_range("invalid")
      :error
  """
  @quick_date_ranges ~w(today tomorrow this_weekend next_7_days next_30_days this_month next_month)

  @spec parse_quick_range(String.t()) :: {:ok, atom()} | :error
  def parse_quick_range("all"), do: {:ok, :all}
  def parse_quick_range("today"), do: {:ok, :today}
  def parse_quick_range("tomorrow"), do: {:ok, :tomorrow}
  def parse_quick_range("this_weekend"), do: {:ok, :this_weekend}
  def parse_quick_range("next_7_days"), do: {:ok, :next_7_days}
  def parse_quick_range("next_30_days"), do: {:ok, :next_30_days}
  def parse_quick_range("this_month"), do: {:ok, :this_month}
  def parse_quick_range("next_month"), do: {:ok, :next_month}
  def parse_quick_range(_), do: :error

  @doc """
  Check if a string is a valid quick date range (excluding "all").

  ## Examples

      iex> EventFilters.quick_date_range?("today")
      true

      iex> EventFilters.quick_date_range?("all")
      false

      iex> EventFilters.quick_date_range?("invalid")
      false
  """
  @spec quick_date_range?(String.t() | nil) :: boolean()
  def quick_date_range?(nil), do: false
  def quick_date_range?(range) when is_binary(range), do: range in @quick_date_ranges

  @doc """
  Apply quick date filter to filters map.

  Handles the special `:all` range by clearing date filters.
  For other ranges, calculates start/end dates and sets show_past to true.

  ## Parameters

    - filters: Current filters map
    - range_atom: Date range identifier (:all, :today, :tomorrow, etc.)

  ## Returns

  Updated filters map with date range applied.
  """
  @spec apply_quick_date_filter(map(), atom()) :: map()
  def apply_quick_date_filter(filters, :all) do
    filters
    |> Map.put(:start_date, nil)
    |> Map.put(:end_date, nil)
    |> Map.put(:page, 1)
    |> Map.put(:show_past, false)
  end

  def apply_quick_date_filter(filters, range_atom) do
    # Delegate to PublicEventsEnhanced for date calculation
    {start_date, end_date} =
      EventasaurusDiscovery.PublicEventsEnhanced.calculate_date_range(range_atom)

    filters
    |> Map.put(:start_date, start_date)
    |> Map.put(:end_date, end_date)
    |> Map.put(:page, 1)
    |> Map.put(:show_past, true)
  end

  @doc """
  Get date bounds for a quick date range.

  Returns `{start_date, end_date}` tuple for the given range atom.
  For `:all`, returns `{nil, nil}`.

  ## Examples

      iex> EventFilters.get_quick_date_bounds(:today)
      {~U[2026-01-22 00:00:00Z], ~U[2026-01-22 23:59:59Z]}

      iex> EventFilters.get_quick_date_bounds(:all)
      {nil, nil}
  """
  @spec get_quick_date_bounds(atom()) :: {DateTime.t() | nil, DateTime.t() | nil}
  def get_quick_date_bounds(:all), do: {nil, nil}

  def get_quick_date_bounds(range_atom) do
    EventasaurusDiscovery.PublicEventsEnhanced.calculate_date_range(range_atom)
  end

  @doc """
  Clear date filters from filters map.

  Removes start_date, end_date, resets to page 1, and sets show_past to false.
  """
  @spec clear_date_filter(map()) :: map()
  def clear_date_filter(filters) do
    filters
    |> Map.put(:start_date, nil)
    |> Map.put(:end_date, nil)
    |> Map.put(:page, 1)
    |> Map.put(:show_past, false)
  end

  @doc """
  Count active filters.

  Counts search, radius (if not default), categories, and date filters.
  Date filters (start_date + end_date) count as 1 filter, not 2.

  ## Parameters

    - filters: Current filters map
    - default_radius: Default radius to compare against (optional)
  """
  @spec active_filter_count(map(), number() | nil) :: non_neg_integer()
  def active_filter_count(filters, default_radius \\ nil) do
    count = 0
    count = if filters[:search] && filters[:search] != "", do: count + 1, else: count

    # Only count radius if it differs from default
    count =
      if default_radius && filters[:radius_km] && filters[:radius_km] != default_radius do
        count + 1
      else
        count
      end

    count = count + length(filters[:categories] || [])

    # Count date filters as 1 (not 2)
    count = if filters[:start_date] || filters[:end_date], do: count + 1, else: count

    count
  end

  @doc """
  Convert active date range to human-readable label.

  Returns the appropriate label for the active date range,
  or a formatted date string for custom ranges.
  """
  @spec date_range_label(atom() | nil, map()) :: String.t()
  def date_range_label(active_date_range, filters)

  def date_range_label(:today, _filters), do: "Today"
  def date_range_label(:tomorrow, _filters), do: "Tomorrow"
  def date_range_label(:this_weekend, _filters), do: "This Weekend"
  def date_range_label(:next_7_days, _filters), do: "Next 7 Days"
  def date_range_label(:next_30_days, _filters), do: "Next 30 Days"
  def date_range_label(:this_month, _filters), do: "This Month"
  def date_range_label(:next_month, _filters), do: "Next Month"

  def date_range_label(nil, filters) do
    # Custom date range - format the dates
    cond do
      filters[:start_date] && filters[:end_date] ->
        start_str = filters[:start_date] |> DateTime.to_date() |> Date.to_string()
        end_str = filters[:end_date] |> DateTime.to_date() |> Date.to_string()
        "#{start_str} - #{end_str}"

      filters[:start_date] ->
        date_str = filters[:start_date] |> DateTime.to_date() |> Date.to_string()
        "From #{date_str}"

      filters[:end_date] ->
        date_str = filters[:end_date] |> DateTime.to_date() |> Date.to_string()
        "Until #{date_str}"

      true ->
        "Date Filter"
    end
  end

  @doc """
  Build filters for date range counting.

  Removes existing date filters and pagination to get accurate counts
  for all date ranges independently of the current filter state.
  Enables aggregation to match what users actually see when browsing.
  """
  @spec build_date_range_count_filters(map()) :: map()
  def build_date_range_count_filters(filters) do
    filters
    |> Map.delete(:page)
    |> Map.delete(:page_size)
    |> Map.delete(:start_date)
    |> Map.delete(:end_date)
    |> Map.put(:show_past, false)
    |> Map.put(:aggregate, true)
  end
end
