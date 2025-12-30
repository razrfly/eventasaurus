defmodule EventasaurusDiscovery.Monitoring.Coverage do
  @moduledoc """
  Programmatic API for date coverage monitoring.

  Audits whether scrapers are creating events for the expected date range
  (typically 7 days ahead) and identifies gaps in coverage.

  ## Examples

      # Check date coverage for next 7 days
      {:ok, coverage} = Coverage.check(days: 7)

      # Check specific source only
      {:ok, coverage} = Coverage.check(days: 7, source: "cinema_city")

      # Get alerts from coverage data
      alerts = Coverage.alerts(coverage)
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  import Ecto.Query

  @typedoc "Alert severity type"
  @type alert_type :: :missing_near | :missing_far | :low_near | :critical_gaps | :source_not_found

  @typedoc "Individual alert"
  @type alert :: %{
          source: String.t(),
          type: alert_type(),
          message: String.t(),
          date: Date.t() | nil
        }

  @typedoc "Coverage status"
  @type coverage_status :: :ok | :fair | :low | :missing

  @typedoc "Day coverage result"
  @type day_coverage :: %{
          date: Date.t(),
          day_name: String.t(),
          event_count: non_neg_integer(),
          expected: non_neg_integer(),
          status: coverage_status(),
          coverage_pct: non_neg_integer()
        }

  @typedoc "Source coverage result"
  @type source_coverage :: %{
          source: String.t(),
          display_name: String.t(),
          days: [day_coverage()],
          total_events: non_neg_integer(),
          days_with_events: non_neg_integer(),
          avg_events_per_day: non_neg_integer(),
          alerts: [alert()]
        }

  @typedoc "Overall coverage result"
  @type coverage_result :: %{
          sources: [source_coverage()],
          period_start: Date.t(),
          period_end: Date.t(),
          days: non_neg_integer(),
          total_alerts: non_neg_integer()
        }

  @sources %{
    "cinema_city" => %{
      slug: "cinema-city",
      display_name: "Cinema City",
      expected_days: 7,
      min_events_per_day: 20
    },
    "repertuary" => %{
      slug: "repertuary",
      display_name: "Repertuary",
      expected_days: 7,
      min_events_per_day: 10
    }
  }

  @doc """
  Returns the configured sources for coverage monitoring.
  """
  @spec sources() :: %{String.t() => map()}
  def sources, do: @sources

  @doc """
  Checks date coverage for configured sources.

  ## Options

    * `:days` - Number of days ahead to check (default: 7)
    * `:source` - Specific source to check (default: all sources)

  ## Examples

      {:ok, coverage} = Coverage.check(days: 7)
      {:ok, coverage} = Coverage.check(days: 14, source: "cinema_city")
      {:error, :unknown_source} = Coverage.check(source: "invalid")
  """
  @spec check(keyword()) :: {:ok, coverage_result()} | {:error, atom()}
  def check(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    source = Keyword.get(opts, :source)

    # Validate source if provided
    if source && !Map.has_key?(@sources, source) do
      {:error, :unknown_source}
    else
      sources_to_check =
        if source do
          [{source, @sources[source]}]
        else
          Map.to_list(@sources)
        end

      today = Date.utc_today()
      period_start = today
      period_end = Date.add(today, days - 1)

      source_results =
        Enum.map(sources_to_check, fn {source_key, config} ->
          check_source_coverage(source_key, config, days)
        end)

      total_alerts =
        source_results
        |> Enum.flat_map(& &1.alerts)
        |> length()

      {:ok,
       %{
         sources: source_results,
         period_start: period_start,
         period_end: period_end,
         days: days,
         total_alerts: total_alerts
       }}
    end
  end

  @doc """
  Extracts all alerts from coverage data.

  ## Examples

      {:ok, coverage} = Coverage.check()
      alerts = Coverage.alerts(coverage)
  """
  @spec alerts(coverage_result()) :: [alert()]
  def alerts(%{sources: sources}) do
    Enum.flat_map(sources, & &1.alerts)
  end

  @doc """
  Checks if all sources have good coverage (no alerts).
  """
  @spec healthy?(coverage_result()) :: boolean()
  def healthy?(%{total_alerts: 0}), do: true
  def healthy?(_), do: false

  @doc """
  Returns sources with critical coverage issues (missing near-term events or critical gaps).
  """
  @spec critical_sources(coverage_result()) :: [String.t()]
  def critical_sources(%{sources: sources}) do
    sources
    |> Enum.filter(fn source ->
      Enum.any?(source.alerts, fn alert ->
        alert.type in [:missing_near, :critical_gaps, :source_not_found]
      end)
    end)
    |> Enum.map(& &1.source)
  end

  @doc """
  Returns a summary of coverage health per source.
  Useful for dashboard display.
  """
  @spec summary(coverage_result()) :: [map()]
  def summary(%{sources: sources}) do
    Enum.map(sources, fn source ->
      critical_count =
        Enum.count(source.alerts, fn a ->
          a.type in [:missing_near, :critical_gaps]
        end)

      warning_count = length(source.alerts) - critical_count

      status =
        cond do
          critical_count > 0 -> :critical
          warning_count > 0 -> :warning
          true -> :ok
        end

      %{
        source: source.source,
        display_name: source.display_name,
        total_events: source.total_events,
        days_with_events: source.days_with_events,
        avg_events_per_day: source.avg_events_per_day,
        total_days: length(source.days),
        alert_count: length(source.alerts),
        status: status
      }
    end)
  end

  # Private helpers

  defp check_source_coverage(source_key, config, days) do
    case Repo.get_by(Source, slug: config.slug) do
      nil ->
        %{
          source: source_key,
          display_name: config.display_name,
          days: generate_empty_days(days, config),
          total_events: 0,
          days_with_events: 0,
          avg_events_per_day: 0,
          alerts: [
            %{
              source: source_key,
              type: :source_not_found,
              message: "Source #{config.slug} not found in database",
              date: nil
            }
          ]
        }

      source ->
        today = Date.utc_today()
        coverage_map = fetch_date_coverage(source.id, today, days)

        # Build day-by-day results
        day_results =
          0..(days - 1)
          |> Enum.map(fn offset ->
            date = Date.add(today, offset)
            event_count = Map.get(coverage_map, date, 0)
            build_day_result(date, event_count, config)
          end)

        # Calculate statistics
        total_events = coverage_map |> Map.values() |> Enum.sum()
        days_with_events = coverage_map |> Map.values() |> Enum.count(&(&1 > 0))
        avg_events = if days_with_events > 0, do: div(total_events, days_with_events), else: 0

        # Build alerts
        alerts = build_coverage_alerts(source_key, day_results, config, days, days_with_events)

        %{
          source: source_key,
          display_name: config.display_name,
          days: day_results,
          total_events: total_events,
          days_with_events: days_with_events,
          avg_events_per_day: avg_events,
          alerts: alerts
        }
    end
  end

  defp build_day_result(date, event_count, config) do
    day_name = date |> Date.day_of_week() |> day_abbreviation()
    expected = config.min_events_per_day

    {status, coverage_pct} =
      cond do
        event_count == 0 ->
          {:missing, 0}

        event_count < div(expected, 2) ->
          {:low, round(event_count / expected * 100)}

        event_count < expected ->
          {:fair, round(event_count / expected * 100)}

        true ->
          {:ok, min(round(event_count / expected * 100), 999)}
      end

    %{
      date: date,
      day_name: day_name,
      event_count: event_count,
      expected: expected,
      status: status,
      coverage_pct: coverage_pct
    }
  end

  defp build_coverage_alerts(source_key, day_results, config, days, days_with_events) do
    today = Date.utc_today()
    expected = config.min_events_per_day

    # Alerts for individual days
    day_alerts =
      Enum.flat_map(day_results, fn day ->
        days_ahead = Date.diff(day.date, today)

        cond do
          day.event_count == 0 && days_ahead <= 3 ->
            [
              %{
                source: source_key,
                type: :missing_near,
                message: "Missing events for #{format_date(day.date)} (#{days_ahead} days ahead)",
                date: day.date
              }
            ]

          day.event_count == 0 ->
            [
              %{
                source: source_key,
                type: :missing_far,
                message: "Missing events for #{format_date(day.date)}",
                date: day.date
              }
            ]

          day.event_count < div(expected, 2) && days_ahead <= 3 ->
            [
              %{
                source: source_key,
                type: :low_near,
                message: "Low event count (#{day.event_count}) for #{format_date(day.date)}",
                date: day.date
              }
            ]

          true ->
            []
        end
      end)

    # Critical gaps alert
    critical_alert =
      if days > 0 and days_with_events * 2 < days do
        [
          %{
            source: source_key,
            type: :critical_gaps,
            message: "Less than 50% date coverage",
            date: nil
          }
        ]
      else
        []
      end

    day_alerts ++ critical_alert
  end

  defp generate_empty_days(days, config) do
    today = Date.utc_today()

    0..(days - 1)
    |> Enum.map(fn offset ->
      date = Date.add(today, offset)

      %{
        date: date,
        day_name: date |> Date.day_of_week() |> day_abbreviation(),
        event_count: 0,
        expected: config.min_events_per_day,
        status: :missing,
        coverage_pct: 0
      }
    end)
  end

  defp fetch_date_coverage(source_id, from_date, days) do
    to_date = Date.add(from_date, days)

    from_datetime = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")
    to_datetime = DateTime.new!(to_date, ~T[00:00:00], "Etc/UTC")

    query =
      from(pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        where: pes.source_id == ^source_id,
        where: pe.starts_at >= ^from_datetime,
        where: pe.starts_at < ^to_datetime,
        group_by: fragment("DATE(?)", pe.starts_at),
        select: {fragment("DATE(?)", pe.starts_at), count(pe.id)}
      )

    query
    |> Repo.replica().all()
    |> Enum.map(fn {date, count} ->
      # Handle both Date and string responses
      date =
        case date do
          %Date{} = d -> d
          str when is_binary(str) -> Date.from_iso8601!(str)
        end

      {date, count}
    end)
    |> Map.new()
  end

  defp day_abbreviation(day_num) do
    case day_num do
      1 -> "Mon"
      2 -> "Tue"
      3 -> "Wed"
      4 -> "Thu"
      5 -> "Fri"
      6 -> "Sat"
      7 -> "Sun"
    end
  end

  defp format_date(date) do
    Calendar.strftime(date, "%Y-%m-%d")
  end
end
