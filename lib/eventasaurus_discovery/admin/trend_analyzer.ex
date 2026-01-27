defmodule EventasaurusDiscovery.Admin.TrendAnalyzer do
  @moduledoc """
  Analyzes historical trends for discovery sources and cities.

  Provides functions to:
  - Get event count trends over time
  - Get success rate trends over time
  - Detect seasonal patterns
  - Compare performance across different time periods
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.{Source, SourceRegistry}

  # Use read replica for all read operations in this module
  defp repo, do: Repo.replica()

  @doc """
  Get event count trend for a source over the specified number of days.

  Returns a list of {date, count} tuples for each day.

  ## Parameters

    * `source_slug` - The source name (string)
    * `days` - Number of days to look back (default: 30)

  ## Returns

  List of maps with :date and :count keys.

  ## Examples

      iex> get_event_trend("bandsintown", 7)
      [
        %{date: ~D[2025-10-10], count: 5},
        %{date: ~D[2025-10-11], count: 3},
        ...
      ]
  """
  def get_event_trend(source_slug, days \\ 30) when is_binary(source_slug) and is_integer(days) do
    case get_source_id(source_slug) do
      nil ->
        []

      source_id ->
        today = Date.utc_today()

        0..(days - 1)
        |> Enum.map(fn days_ago ->
          date = Date.add(today, -days_ago)
          next_date = Date.add(date, 1)

          # Convert dates to datetime bounds for indexed query
          date_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          date_end = DateTime.new!(next_date, ~T[00:00:00], "Etc/UTC")

          count =
            from(pes in PublicEventSource,
              where: pes.source_id == ^source_id,
              where: pes.inserted_at >= ^date_start and pes.inserted_at < ^date_end,
              select: count(pes.id)
            )
            |> repo().one() || 0

          %{date: date, count: count}
        end)
        |> Enum.reverse()
    end
  end

  @doc """
  Get event count trend for a city (or cities) over the specified number of days.

  Returns a list of {date, count} tuples for each day.

  ## Parameters

    * `city_id_or_ids` - A single city ID (integer) or list of city IDs
    * `days` - Number of days to look back (default: 30)

  ## Returns

  List of maps with :date and :count keys.
  """
  def get_city_event_trend(city_id, days \\ 30)

  def get_city_event_trend(city_id, days) when is_integer(city_id) and is_integer(days) do
    get_city_event_trend([city_id], days)
  end

  def get_city_event_trend(city_ids, days) when is_list(city_ids) and is_integer(days) do
    today = Date.utc_today()

    0..(days - 1)
    |> Enum.map(fn days_ago ->
      date = Date.add(today, -days_ago)
      next_date = Date.add(date, 1)

      # Convert dates to datetime bounds for indexed query
      date_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      date_end = DateTime.new!(next_date, ~T[00:00:00], "Etc/UTC")

      count =
        from(e in PublicEvent,
          join: v in EventasaurusApp.Venues.Venue,
          on: v.id == e.venue_id,
          where: v.city_id in ^city_ids,
          where: e.inserted_at >= ^date_start and e.inserted_at < ^date_end,
          select: count(e.id)
        )
        |> Repo.one() || 0

      %{date: date, count: count}
    end)
    |> Enum.reverse()
  end

  @doc """
  Get success rate trend for a source over the specified number of days.

  Returns a list of {date, success_rate} tuples for each day.

  ## Parameters

    * `source_slug` - The source name (string)
    * `days` - Number of days to look back (default: 30)

  ## Returns

  List of maps with :date and :success_rate keys.

  ## Examples

      iex> get_success_rate_trend("bandsintown", 7)
      [
        %{date: ~D[2025-10-10], success_rate: 100},
        %{date: ~D[2025-10-11], success_rate: 67},
        ...
      ]
  """
  def get_success_rate_trend(source_slug, days \\ 30)
      when is_binary(source_slug) and is_integer(days) do
    case SourceRegistry.get_worker_name(source_slug) do
      {:error, :not_found} ->
        []

      {:ok, worker_name} ->
        today = Date.utc_today()

        0..(days - 1)
        |> Enum.map(fn days_ago ->
          date = Date.add(today, -days_ago)
          next_date = Date.add(date, 1)

          # Convert dates to datetime for comparison
          date_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          date_end = DateTime.new!(next_date, ~T[00:00:00], "Etc/UTC")

          # Get total runs for this day from oban_jobs
          total_runs =
            from(j in "oban_jobs",
              where: j.worker == ^worker_name,
              where: j.state in ["completed", "discarded"],
              where:
                fragment(
                  "COALESCE(?, ?, ?) >= ? AND COALESCE(?, ?, ?) < ?",
                  j.completed_at,
                  j.discarded_at,
                  j.attempted_at,
                  ^date_start,
                  j.completed_at,
                  j.discarded_at,
                  j.attempted_at,
                  ^date_end
                ),
              select: count(j.id)
            )
            |> repo().one() || 0

          # Get successful runs for this day from oban_jobs
          successful_runs =
            from(j in "oban_jobs",
              where: j.worker == ^worker_name,
              where: j.state == "completed",
              where:
                fragment(
                  "COALESCE(?, ?) >= ? AND COALESCE(?, ?) < ?",
                  j.completed_at,
                  j.attempted_at,
                  ^date_start,
                  j.completed_at,
                  j.attempted_at,
                  ^date_end
                ),
              select: count(j.id)
            )
            |> repo().one() || 0

          success_rate =
            if total_runs > 0 do
              (successful_runs / total_runs * 100) |> round()
            else
              0
            end

          %{date: date, success_rate: success_rate, total_runs: total_runs}
        end)
        |> Enum.reverse()
    end
  end

  @doc """
  Format trend data for Chart.js.

  Converts list of maps with :date and value keys into Chart.js dataset format.

  ## Parameters

    * `trend_data` - List of maps with :date and value key (e.g., :count or :success_rate)
    * `value_key` - The key to extract values from (e.g., :count, :success_rate)
    * `label` - Label for the dataset
    * `color` - Color for the line/bars (hex string)

  ## Returns

  Map with Chart.js-compatible structure.

  ## Examples

      iex> format_for_chartjs(trend_data, :count, "Events", "#3B82F6")
      %{
        labels: ["Oct 10", "Oct 11", ...],
        datasets: [
          %{
            label: "Events",
            data: [5, 3, ...],
            borderColor: "#3B82F6",
            backgroundColor: "rgba(59, 130, 246, 0.1)",
            tension: 0.4
          }
        ]
      }
  """
  def format_for_chartjs(trend_data, value_key, label, color) do
    labels =
      Enum.map(trend_data, fn item ->
        Calendar.strftime(item.date, "%b %d")
      end)

    data = Enum.map(trend_data, fn item -> Map.get(item, value_key, 0) end)

    # Convert hex color to rgba with 10% opacity for background
    background_color = hex_to_rgba(color, 0.1)

    %{
      labels: labels,
      datasets: [
        %{
          label: label,
          data: data,
          borderColor: color,
          backgroundColor: background_color,
          borderWidth: 2,
          tension: 0.4,
          fill: true,
          pointRadius: 3,
          pointHoverRadius: 5
        }
      ]
    }
  end

  @doc """
  Format multiple datasets for Chart.js (e.g., comparing multiple sources).

  ## Parameters

    * `datasets` - List of {trend_data, value_key, label, color} tuples

  ## Returns

  Map with Chart.js-compatible structure with multiple datasets.
  """
  def format_multi_datasets(datasets) do
    # Get labels from first dataset (assuming all have same dates)
    labels =
      case List.first(datasets) do
        {trend_data, _, _, _} ->
          Enum.map(trend_data, fn item ->
            Calendar.strftime(item.date, "%b %d")
          end)

        _ ->
          []
      end

    chart_datasets =
      Enum.map(datasets, fn {trend_data, value_key, label, color} ->
        data = Enum.map(trend_data, fn item -> Map.get(item, value_key, 0) end)
        background_color = hex_to_rgba(color, 0.1)

        %{
          label: label,
          data: data,
          borderColor: color,
          backgroundColor: background_color,
          borderWidth: 2,
          tension: 0.4,
          fill: true,
          pointRadius: 3,
          pointHoverRadius: 5
        }
      end)

    %{
      labels: labels,
      datasets: chart_datasets
    }
  end

  @doc """
  Detect if there's a weekly pattern in the data.

  Returns true if event counts show a consistent weekly pattern.
  """
  def has_weekly_pattern?(trend_data) when is_list(trend_data) do
    if length(trend_data) < 14 do
      false
    else
      # Group by day of week
      by_day_of_week =
        Enum.group_by(trend_data, fn item ->
          Date.day_of_week(item.date)
        end)

      # Calculate average count per day of week
      avg_by_day =
        Enum.map(by_day_of_week, fn {day, items} ->
          avg = Enum.reduce(items, 0, fn item, acc -> acc + item.count end) / length(items)
          {day, avg}
        end)
        |> Enum.into(%{})

      # Check if variance across days is significant
      values = Map.values(avg_by_day)
      mean = Enum.sum(values) / length(values)

      variance =
        Enum.reduce(values, 0, fn val, acc ->
          acc + :math.pow(val - mean, 2)
        end) / length(values)

      std_dev = :math.sqrt(variance)

      # If standard deviation is more than 30% of mean, consider it a pattern
      mean > 0 and std_dev / mean > 0.3
    end
  end

  # Private functions

  defp get_source_id(source_slug) do
    query =
      from(s in Source,
        where: s.slug == ^source_slug,
        select: s.id
      )

    repo().one(query)
  end

  defp hex_to_rgba(hex, opacity) do
    # Convert hex color like "#3B82F6" to "rgba(59, 130, 246, 0.1)"
    hex = String.replace(hex, "#", "")

    {r, _} = Integer.parse(String.slice(hex, 0..1), 16)
    {g, _} = Integer.parse(String.slice(hex, 2..3), 16)
    {b, _} = Integer.parse(String.slice(hex, 4..5), 16)

    "rgba(#{r}, #{g}, #{b}, #{opacity})"
  end
end
