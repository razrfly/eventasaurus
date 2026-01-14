defmodule Mix.Tasks.Audit.DateCoverage do
  @moduledoc """
  Audit date coverage for all scrapers.

  Verifies that scrapers are creating events for the expected date range
  (typically 7 days ahead) and identifies any gaps in coverage.

  ## Usage

      # Check default 7-day coverage for all sources
      mix audit.date_coverage

      # Check specific number of days ahead
      mix audit.date_coverage --days 14

      # Check specific source only
      mix audit.date_coverage --source cinema_city
      mix audit.date_coverage --source bandsintown

  ## Output

  Shows a day-by-day breakdown of event counts including:
  - Date and day of week
  - Event count for that date
  - Status (OK, LOW, MISSING)
  - Percentage of expected coverage
  """

  use Mix.Task
  require Logger

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.SourcePatterns
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource

  @shortdoc "Audit date coverage for cinema scrapers"

  # Source-specific threshold configuration
  # Sources not listed here use default thresholds
  @source_thresholds %{
    "cinema_city" => %{
      # From Config.days_ahead()
      expected_days: 7,
      # Minimum events expected per day (cinemas × movies per cinema)
      min_events_per_day: 20
    },
    "repertuary" => %{
      # From SyncJob - fetches days 0-6
      expected_days: 7,
      # Minimum events expected per day
      min_events_per_day: 10
    }
  }

  @default_thresholds %{
    expected_days: 7,
    min_events_per_day: 10
  }

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [days: :integer, source: :string],
        aliases: [d: :days, s: :source]
      )

    days = opts[:days] || 7
    source = opts[:source]

    # Validate source if provided
    if source && !SourcePatterns.valid_source?(source) do
      IO.puts(IO.ANSI.red() <> "❌ Unknown source: #{source}" <> IO.ANSI.reset())
      SourcePatterns.print_available_sources()
      System.halt(1)
    end

    sources_to_check =
      if source do
        [source]
      else
        SourcePatterns.all_cli_keys()
      end

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "📅 Date Coverage Report" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 70) <> IO.ANSI.reset())
    today = Date.utc_today()
    end_date = Date.add(today, days - 1)
    IO.puts("Period: #{format_date(today)} to #{format_date(end_date)} (#{days} days)")
    IO.puts("")

    all_alerts = []

    all_alerts =
      Enum.reduce(sources_to_check, all_alerts, fn source_key, alerts ->
        source_alerts = display_source_coverage(source_key, days)
        alerts ++ source_alerts
      end)

    # Summary section
    display_summary(all_alerts, days)
  end

  defp display_source_coverage(source_key, days) do
    display_name = SourcePatterns.get_display_name(source_key)
    # Convert CLI key (underscore) to registry slug (hyphen)
    source_slug = String.replace(source_key, "_", "-")
    # Get thresholds for this source or use defaults
    thresholds = Map.get(@source_thresholds, source_key, @default_thresholds)

    IO.puts(IO.ANSI.blue() <> "📊 #{display_name}" <> IO.ANSI.reset())
    IO.puts(String.duplicate("─", 70))

    # Get source ID from database
    case Repo.get_by(Source, slug: source_slug) do
      nil ->
        IO.puts(
          IO.ANSI.red() <>
            "  ❌ Source not found in database: #{source_slug}" <> IO.ANSI.reset()
        )

        IO.puts("")
        [{source_key, :source_not_found, "Source #{source_slug} not found in database"}]

      source ->
        # Get event counts by date
        today = Date.utc_today()
        coverage = fetch_date_coverage(source.id, today, days)

        # Display table header
        IO.puts(
          "  #{pad("Date", 12)} #{pad("Day", 4)} #{pad("Events", 8)} #{pad("Status", 10)} Coverage"
        )

        IO.puts("  #{String.duplicate("─", 55)}")

        # Generate expected dates and check coverage
        alerts =
          0..(days - 1)
          |> Enum.flat_map(fn offset ->
            date = Date.add(today, offset)
            event_count = Map.get(coverage, date, 0)
            display_date_row(source_key, thresholds, date, event_count)
          end)

        # Show coverage statistics
        total_events = coverage |> Map.values() |> Enum.sum()
        days_with_events = coverage |> Map.values() |> Enum.count(&(&1 > 0))
        avg_events = if days_with_events > 0, do: div(total_events, days_with_events), else: 0

        IO.puts("")

        IO.puts(
          "  Summary: #{total_events} events across #{days_with_events}/#{days} days (avg: #{avg_events}/day)"
        )

        # Check for critical gaps
        alerts =
          if days > 0 and days_with_events * 2 < days do
            IO.puts(
              IO.ANSI.red() <>
                "  🚨 Critical: Less than 50% date coverage!" <> IO.ANSI.reset()
            )

            [{source_key, :critical_gaps, "Less than 50% date coverage"} | alerts]
          else
            alerts
          end

        IO.puts("")
        alerts
    end
  end

  defp display_date_row(source_key, thresholds, date, event_count) do
    day_name = date |> Date.day_of_week() |> day_abbreviation()
    expected = thresholds.min_events_per_day

    {status, status_color, coverage_pct} =
      cond do
        event_count == 0 ->
          {"MISSING", IO.ANSI.red(), 0}

        event_count < div(expected, 2) ->
          {"LOW", IO.ANSI.yellow(), round(event_count / expected * 100)}

        event_count < expected ->
          {"FAIR", IO.ANSI.cyan(), round(event_count / expected * 100)}

        true ->
          {"OK", IO.ANSI.green(), min(round(event_count / expected * 100), 999)}
      end

    coverage_bar = build_coverage_bar(coverage_pct)

    IO.puts(
      "  #{pad(format_date(date), 12)} #{pad(day_name, 4)} " <>
        "#{pad(Integer.to_string(event_count), 8)} " <>
        status_color <>
        pad(status, 10) <>
        IO.ANSI.reset() <>
        "#{coverage_bar} #{coverage_pct}%"
    )

    # Return alerts for problematic dates
    today = Date.utc_today()
    days_ahead = Date.diff(date, today)

    cond do
      event_count == 0 && days_ahead <= 3 ->
        [
          {source_key, :missing_near,
           "Missing events for #{format_date(date)} (#{days_ahead} days ahead)"}
        ]

      event_count == 0 ->
        [{source_key, :missing_far, "Missing events for #{format_date(date)}"}]

      event_count < div(expected, 2) && days_ahead <= 3 ->
        [{source_key, :low_near, "Low event count (#{event_count}) for #{format_date(date)}"}]

      true ->
        []
    end
  end

  defp display_summary(alerts, _days) do
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 70) <> IO.ANSI.reset())

    if Enum.empty?(alerts) do
      IO.puts(IO.ANSI.green() <> "✅ All scrapers have good date coverage" <> IO.ANSI.reset())
    else
      critical =
        Enum.count(alerts, fn {_, type, _} -> type in [:critical_gaps, :missing_near] end)

      warnings = length(alerts) - critical

      color = if critical > 0, do: IO.ANSI.red(), else: IO.ANSI.yellow()
      IO.puts(color <> "⚠️  #{length(alerts)} Issue(s) Detected:" <> IO.ANSI.reset())
      IO.puts("")

      alerts
      |> Enum.group_by(fn {source, _type, _msg} -> source end)
      |> Enum.each(fn {source, source_alerts} ->
        source_name = SourcePatterns.get_display_name(source)
        IO.puts("  #{source_name}:")

        # Limit displayed alerts per source
        {shown, remaining} = Enum.split(source_alerts, 5)

        Enum.each(shown, fn {_source, type, msg} ->
          icon =
            case type do
              :missing_near -> "🚨"
              :missing_far -> "📅"
              :low_near -> "⚠️"
              :critical_gaps -> "💀"
              :source_not_found -> "❌"
              _ -> "ℹ️"
            end

          IO.puts("    #{icon} #{msg}")
        end)

        if length(remaining) > 0 do
          IO.puts("    ... and #{length(remaining)} more issues")
        end
      end)

      IO.puts("")

      # Recommendations
      if critical > 0 or warnings > 0 do
        IO.puts(IO.ANSI.blue() <> "💡 Recommendations:" <> IO.ANSI.reset())

        missing_count =
          Enum.count(alerts, fn {_, type, _} -> type in [:missing_near, :missing_far] end)

        low_count = Enum.count(alerts, fn {_, type, _} -> type == :low_near end)

        if missing_count > 0 do
          IO.puts("  • Check if scraper jobs ran successfully: mix audit.scheduler_health")
          IO.puts("  • Verify API endpoints are responding: curl the cinema URLs manually")
        end

        if low_count > 0 do
          IO.puts("  • Low event counts may indicate partial scraper failures")
          IO.puts("  • Check job execution details: mix monitor.jobs failures --source <source>")
        end

        IO.puts("")
      end
    end
  end

  # Database queries

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

  # Helper functions

  defp format_date(date) do
    Calendar.strftime(date, "%Y-%m-%d")
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

  defp build_coverage_bar(pct) do
    filled = min(div(pct, 10), 10)
    empty = 10 - filled

    bar =
      String.duplicate("█", filled) <>
        String.duplicate("░", empty)

    "[#{bar}]"
  end

  defp pad(str, width) do
    str
    |> to_string()
    |> String.pad_trailing(width)
  end
end
