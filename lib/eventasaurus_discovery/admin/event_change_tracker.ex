defmodule EventasaurusDiscovery.Admin.EventChangeTracker do
  @moduledoc """
  Tracks changes in events between scrapes for discovery sources.

  This module provides functions to calculate:
  - New events discovered in the last scrape
  - Dropped events (no longer being updated)
  - Percentage changes week-over-week
  - Trend indicators

  All calculations are based on the `last_seen_at` timestamp in the
  `public_event_sources` table, which is updated each time a source
  sees an event during scraping.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  require Logger

  @doc """
  Calculate the number of new events discovered in the last run for a source.

  New events are those where both `inserted_at` and `last_seen_at` are recent,
  indicating they were just discovered by the source.

  ## Parameters

    * `source_slug` - The source name (string)
    * `window_hours` - Time window to consider (default: from config)

  ## Returns

  Integer count of new events, or 0 if source not found.

  ## Examples

      iex> calculate_new_events("bandsintown", 24)
      15
  """
  def calculate_new_events(source_slug, window_hours \\ nil)
      when is_binary(source_slug) and (is_integer(window_hours) or is_nil(window_hours)) do
    window_hours = window_hours || get_new_events_window()

    case get_source_id(source_slug) do
      nil ->
        0

      source_id ->
        cutoff = DateTime.utc_now() |> DateTime.add(-window_hours, :hour)

        query =
          from(pes in PublicEventSource,
            where: pes.source_id == ^source_id,
            where: pes.last_seen_at >= ^cutoff,
            where: pes.inserted_at >= ^cutoff,
            select: count(pes.id)
          )

        Repo.one(query) || 0
    end
  end

  @doc """
  Calculate the number of dropped events for a source.

  Dropped events are those that haven't been seen in recent scrapes
  but are still for future dates (not past events that naturally expired).

  ## Parameters

    * `source_slug` - The source name (string)
    * `window_hours` - Time window to consider stale (default: from config)

  ## Returns

  Integer count of dropped events, or 0 if source not found.

  ## Examples

      iex> calculate_dropped_events("bandsintown", 48)
      3
  """
  def calculate_dropped_events(source_slug, window_hours \\ nil)
      when is_binary(source_slug) and (is_integer(window_hours) or is_nil(window_hours)) do
    window_hours = window_hours || get_dropped_events_window()

    case get_source_id(source_slug) do
      nil ->
        0

      source_id ->
        cutoff = DateTime.utc_now() |> DateTime.add(-window_hours, :hour)
        now = DateTime.utc_now()

        query =
          from(pes in PublicEventSource,
            join: e in PublicEvent,
            on: e.id == pes.event_id,
            where: pes.source_id == ^source_id,
            where: pes.last_seen_at < ^cutoff,
            where: e.starts_at > ^now,
            select: count(pes.id)
          )

        Repo.one(query) || 0
    end
  end

  @doc """
  Calculate the percentage change in event count week-over-week for a source.

  Compares events discovered this week vs. last week.

  Returns :first_scrape atom for brand new sources (no events older than 14 days),
  which allows the UI to display "N/A - First Scrape" instead of misleading percentages.

  ## Parameters

    * `source_slug` - The source name (string)
    * `city_id` - Optional city filter (integer or nil)

  ## Returns

  Percentage change as an integer (-100 to +infinity), 0 if no data, or :first_scrape
  for sources with their first scrape.

  ## Examples

      iex> calculate_percentage_change("bandsintown", 1)
      15

      iex> calculate_percentage_change("brand-new-source", nil)
      :first_scrape

      iex> calculate_percentage_change("bandsintown", nil)
      -5
  """
  def calculate_percentage_change(source_slug, city_id \\ nil)
      when is_binary(source_slug) and (is_integer(city_id) or is_nil(city_id)) do
    case get_source_id(source_slug) do
      nil ->
        0

      source_id ->
        current_week = get_event_count(source_id, city_id, 0, 7)
        previous_week = get_event_count(source_id, city_id, 7, 14)

        # Check if this is truly a first scrape by looking at total historical events
        # If no events exist older than 14 days, this is the first scrape
        historical_count = get_event_count(source_id, city_id, 14, 365)

        cond do
          # First scrape: has current events but no previous or historical events
          previous_week == 0 && historical_count == 0 && current_week > 0 ->
            :first_scrape

          # Normal week-over-week calculation
          previous_week > 0 ->
            ((current_week - previous_week) / previous_week * 100) |> round()

          # No previous week but has historical data - treat as 100% growth
          historical_count > 0 && current_week > 0 ->
            100

          # No data at all
          true ->
            0
        end
    end
  end

  @doc """
  Get a trend indicator based on percentage change.

  ## Parameters

    * `percentage_change` - The percentage change value (integer or :first_scrape atom)

  ## Returns

  A tuple of {emoji, text, css_class}

  ## Examples

      iex> get_trend_indicator(15)
      {"↑", "Up", "text-green-600"}

      iex> get_trend_indicator(-5)
      {"↓", "Down", "text-red-600"}

      iex> get_trend_indicator(0)
      {"→", "Stable", "text-gray-600"}

      iex> get_trend_indicator(:first_scrape)
      {"🆕", "First Scrape", "text-blue-600"}
  """
  def get_trend_indicator(:first_scrape) do
    {"🆕", "First Scrape", "text-blue-600"}
  end

  def get_trend_indicator(percentage_change) when is_integer(percentage_change) do
    cond do
      percentage_change > 5 ->
        {"↑", "Up", "text-green-600"}

      percentage_change < -5 ->
        {"↓", "Down", "text-red-600"}

      true ->
        {"→", "Stable", "text-gray-600"}
    end
  end

  def get_trend_indicator(_), do: {"→", "Stable", "text-gray-600"}

  @doc """
  Get change statistics for all sources.

  Returns a map of source_slug => change stats.

  Optimized to batch queries instead of making individual queries per source (N+1 fix).

  ## Parameters

    * `source_slugs` - List of source names (list of strings)
    * `city_id` - Optional city filter (integer or nil)

  ## Returns

  A map where keys are source slugs and values are change stats maps.

  ## Examples

      iex> get_all_source_changes(["bandsintown", "ticketmaster"], nil)
      %{
        "bandsintown" => %{new_events: 15, dropped_events: 3, percentage_change: 12},
        "ticketmaster" => %{new_events: 8, dropped_events: 1, percentage_change: 5}
      }
  """
  def get_all_source_changes(source_slugs, city_id \\ nil)
      when is_list(source_slugs) and (is_integer(city_id) or is_nil(city_id)) do
    if Enum.empty?(source_slugs) do
      %{}
    else
      # Batch fetch source IDs
      slug_to_id = get_all_source_ids(source_slugs)
      source_ids = Map.values(slug_to_id)

      if Enum.empty?(source_ids) do
        # No valid sources found, return default stats
        source_slugs
        |> Enum.map(fn slug -> {slug, default_change_stats()} end)
        |> Map.new()
      else
        # Batch fetch new events (configured window)
        new_events_by_id = batch_calculate_new_events(source_ids, get_new_events_window())

        # Batch fetch dropped events (configured window)
        dropped_events_by_id =
          batch_calculate_dropped_events(source_ids, get_dropped_events_window())

        # Batch fetch percentage changes
        percentage_changes_by_id = batch_calculate_percentage_changes(source_ids, city_id)

        # Map results back to source slugs
        source_slugs
        |> Enum.map(fn slug ->
          source_id = Map.get(slug_to_id, slug)

          stats =
            if source_id do
              %{
                new_events: Map.get(new_events_by_id, source_id, 0),
                dropped_events: Map.get(dropped_events_by_id, source_id, 0),
                percentage_change: Map.get(percentage_changes_by_id, source_id, 0)
              }
            else
              default_change_stats()
            end

          {slug, stats}
        end)
        |> Map.new()
      end
    end
  end

  # Private Functions

  defp get_source_id(source_slug) do
    query =
      from(s in Source,
        where: s.slug == ^source_slug,
        select: s.id
      )

    Repo.one(query)
  end

  defp get_event_count(source_id, city_id, days_ago_start, days_ago_end) do
    now = DateTime.utc_now()
    start_date = DateTime.add(now, -days_ago_end, :day)
    end_date = DateTime.add(now, -days_ago_start, :day)

    base_query =
      from(pes in PublicEventSource,
        where: pes.source_id == ^source_id,
        where: pes.inserted_at >= ^start_date,
        where: pes.inserted_at < ^end_date
      )

    query =
      if city_id do
        from([pes] in base_query,
          join: e in PublicEvent,
          on: e.id == pes.event_id,
          join: v in EventasaurusApp.Venues.Venue,
          on: v.id == e.venue_id,
          where: v.city_id == ^city_id,
          select: count(pes.id)
        )
      else
        from([pes] in base_query,
          select: count(pes.id)
        )
      end

    Repo.one(query) || 0
  end

  # Batched query helpers for get_all_source_changes/2

  defp default_change_stats do
    %{new_events: 0, dropped_events: 0, percentage_change: 0}
  end

  defp get_all_source_ids(source_slugs) do
    query =
      from(s in Source,
        where: s.slug in ^source_slugs,
        select: {s.slug, s.id}
      )

    query
    |> Repo.all()
    |> Map.new()
  end

  defp batch_calculate_new_events(source_ids, window_hours) do
    cutoff = DateTime.utc_now() |> DateTime.add(-window_hours, :hour)

    query =
      from(pes in PublicEventSource,
        where: pes.source_id in ^source_ids,
        where: pes.last_seen_at >= ^cutoff,
        where: pes.inserted_at >= ^cutoff,
        group_by: pes.source_id,
        select: {pes.source_id, count(pes.id)}
      )

    query
    |> Repo.all()
    |> Map.new()
  end

  defp batch_calculate_dropped_events(source_ids, window_hours) do
    cutoff = DateTime.utc_now() |> DateTime.add(-window_hours, :hour)
    now = DateTime.utc_now()

    query =
      from(pes in PublicEventSource,
        join: e in PublicEvent,
        on: e.id == pes.event_id,
        where: pes.source_id in ^source_ids,
        where: pes.last_seen_at < ^cutoff,
        where: e.starts_at > ^now,
        group_by: pes.source_id,
        select: {pes.source_id, count(pes.id)}
      )

    query
    |> Repo.all()
    |> Map.new()
  end

  defp batch_calculate_percentage_changes(source_ids, city_id) do
    now = DateTime.utc_now()

    # Current week (last 7 days)
    current_week_start = DateTime.add(now, -7, :day)
    current_week_counts = batch_get_event_counts(source_ids, city_id, current_week_start, now)

    # Previous week (7-14 days ago)
    previous_week_start = DateTime.add(now, -14, :day)
    previous_week_end = DateTime.add(now, -7, :day)

    previous_week_counts =
      batch_get_event_counts(source_ids, city_id, previous_week_start, previous_week_end)

    # Calculate percentage change for each source
    source_ids
    |> Enum.map(fn source_id ->
      current = Map.get(current_week_counts, source_id, 0)
      previous = Map.get(previous_week_counts, source_id, 0)

      percentage_change =
        if previous > 0 do
          ((current - previous) / previous * 100) |> round()
        else
          if current > 0, do: 100, else: 0
        end

      {source_id, percentage_change}
    end)
    |> Map.new()
  end

  defp batch_get_event_counts(source_ids, city_id, start_date, end_date) do
    base_query =
      from(pes in PublicEventSource,
        where: pes.source_id in ^source_ids,
        where: pes.inserted_at >= ^start_date,
        where: pes.inserted_at < ^end_date
      )

    query =
      if city_id do
        from([pes] in base_query,
          join: e in PublicEvent,
          on: e.id == pes.event_id,
          join: v in EventasaurusApp.Venues.Venue,
          on: v.id == e.venue_id,
          where: v.city_id == ^city_id,
          group_by: pes.source_id,
          select: {pes.source_id, count(pes.id)}
        )
      else
        from([pes] in base_query,
          group_by: pes.source_id,
          select: {pes.source_id, count(pes.id)}
        )
      end

    query
    |> Repo.all()
    |> Map.new()
  end

  defp get_new_events_window do
    config = Application.get_env(:eventasaurus_discovery, :change_tracking, [])
    Keyword.get(config, :new_events_window_hours, 24)
  end

  defp get_dropped_events_window do
    config = Application.get_env(:eventasaurus_discovery, :change_tracking, [])
    Keyword.get(config, :dropped_events_window_hours, 48)
  end
end
