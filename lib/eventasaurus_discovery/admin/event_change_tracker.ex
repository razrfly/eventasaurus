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
    * `window_hours` - Time window to consider (default: 24 hours)

  ## Returns

  Integer count of new events, or 0 if source not found.

  ## Examples

      iex> calculate_new_events("bandsintown", 24)
      15
  """
  def calculate_new_events(source_slug, window_hours \\ 24)
      when is_binary(source_slug) and is_integer(window_hours) do
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
    * `window_hours` - Time window to consider stale (default: 48 hours)

  ## Returns

  Integer count of dropped events, or 0 if source not found.

  ## Examples

      iex> calculate_dropped_events("bandsintown", 48)
      3
  """
  def calculate_dropped_events(source_slug, window_hours \\ 48)
      when is_binary(source_slug) and is_integer(window_hours) do
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

  ## Parameters

    * `source_slug` - The source name (string)
    * `city_id` - Optional city filter (integer or nil)

  ## Returns

  Percentage change as an integer (-100 to +infinity), or 0 if no previous data.

  ## Examples

      iex> calculate_percentage_change("bandsintown", 1)
      15

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

        if previous_week > 0 do
          ((current_week - previous_week) / previous_week * 100) |> round()
        else
          if current_week > 0, do: 100, else: 0
        end
    end
  end

  @doc """
  Get a trend indicator based on percentage change.

  ## Parameters

    * `percentage_change` - The percentage change value

  ## Returns

  A tuple of {emoji, text, css_class}

  ## Examples

      iex> get_trend_indicator(15)
      {"↑", "Up", "text-green-600"}

      iex> get_trend_indicator(-5)
      {"↓", "Down", "text-red-600"}

      iex> get_trend_indicator(0)
      {"→", "Stable", "text-gray-600"}
  """
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
    source_slugs
    |> Enum.map(fn slug ->
      stats = %{
        new_events: calculate_new_events(slug, 24),
        dropped_events: calculate_dropped_events(slug, 48),
        percentage_change: calculate_percentage_change(slug, city_id)
      }

      {slug, stats}
    end)
    |> Map.new()
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
end
