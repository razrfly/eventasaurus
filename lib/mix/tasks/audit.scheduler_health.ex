defmodule Mix.Tasks.Audit.SchedulerHealth do
  @moduledoc """
  Audit scheduler health for all scrapers.

  Verifies that scrapers are running daily as scheduled and identifies
  any gaps in execution or failures.

  ## Usage

      # Check last 7 days for all sources (default)
      mix audit.scheduler_health

      # Check specific number of days
      mix audit.scheduler_health --days 14

      # Check specific source only
      mix audit.scheduler_health --source cinema_city
      mix audit.scheduler_health --source bandsintown

  ## Output

  Shows a day-by-day breakdown of SyncJob executions including:
  - Execution status (success/failure)
  - Duration
  - Jobs spawned (child jobs scheduled)
  - Alerts for missing days or failures
  """

  use Mix.Task
  require Logger

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  alias EventasaurusDiscovery.Sources.SourcePatterns

  @shortdoc "Audit scheduler health for scrapers"

  # Source-specific child job key configuration
  # Falls back to "jobs_scheduled" if not specified
  @child_job_keys %{
    "repertuary" => "movie_jobs_scheduled"
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

    # Validate and normalize source if provided
    source =
      if source do
        normalized = SourcePatterns.normalize_cli_key(source)

        if !SourcePatterns.valid_source?(normalized) do
          IO.puts(IO.ANSI.red() <> "❌ Unknown source: #{source}" <> IO.ANSI.reset())
          SourcePatterns.print_available_sources()
          System.halt(1)
        end

        normalized
      else
        nil
      end

    sources_to_check =
      if source do
        [source]
      else
        SourcePatterns.all_cli_keys()
      end

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "🗓️  Scheduler Health Report" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 70) <> IO.ANSI.reset())

    IO.puts(
      "Period: Last #{days} days (#{format_date(days_ago(days))} to #{format_date(Date.utc_today())})"
    )

    IO.puts("")

    all_alerts = []

    all_alerts =
      Enum.reduce(sources_to_check, all_alerts, fn source_key, alerts ->
        source_alerts = display_source_health(source_key, days)
        alerts ++ source_alerts
      end)

    # Summary section
    display_summary(all_alerts, days)
  end

  defp display_source_health(source_key, days) do
    display_name = SourcePatterns.get_display_name(source_key)

    case SourcePatterns.get_sync_worker(source_key) do
      {:ok, sync_worker} ->
        display_source_health_with_worker(source_key, display_name, sync_worker, days)

      {:error, _reason} ->
        IO.puts(IO.ANSI.blue() <> "📊 #{display_name}" <> IO.ANSI.reset())
        IO.puts(String.duplicate("─", 70))
        IO.puts(IO.ANSI.red() <> "  ❌ Could not resolve worker for source" <> IO.ANSI.reset())
        IO.puts("")
        [{source_key, :worker_not_found, "Could not resolve worker module"}]
    end
  end

  defp display_source_health_with_worker(source_key, display_name, sync_worker, days) do
    child_job_key = Map.get(@child_job_keys, source_key, "jobs_scheduled")

    IO.puts(IO.ANSI.blue() <> "📊 #{display_name}" <> IO.ANSI.reset())
    IO.puts(String.duplicate("─", 70))

    # Get all SyncJob executions for this source in the time range
    from_date = days_ago(days)
    executions = fetch_sync_job_executions(sync_worker, from_date)

    if Enum.empty?(executions) do
      IO.puts(
        IO.ANSI.yellow() <>
          "  ⚠️  No SyncJob executions found in the last #{days} days" <> IO.ANSI.reset()
      )

      IO.puts("")
      [{source_key, :no_executions, "No executions found in last #{days} days"}]
    else
      # Group executions by date
      by_date = group_by_date(executions)

      # Generate expected dates
      expected_dates = generate_date_range(days)

      # Display table header
      IO.puts(
        "  #{pad("Date", 12)} #{pad("Status", 10)} #{pad("Duration", 10)} #{pad("Jobs Spawned", 15)} Error"
      )

      IO.puts("  #{String.duplicate("─", 65)}")

      alerts =
        Enum.flat_map(expected_dates, fn date ->
          case Map.get(by_date, date) do
            nil ->
              # Missing day
              IO.puts(
                "  #{pad(format_date(date), 12)} " <>
                  IO.ANSI.red() <>
                  pad("MISSING", 10) <>
                  IO.ANSI.reset() <>
                  " #{pad("-", 10)} #{pad("-", 15)}"
              )

              [{source_key, :missing, "Missing execution on #{format_date(date)}"}]

            execs ->
              # Find the latest execution for this date
              latest = Enum.max_by(execs, & &1.attempted_at)
              display_execution(latest, child_job_key)

              if latest.state != "completed" do
                error_msg = get_in(latest.results || %{}, ["error_message"]) || "Unknown error"

                [
                  {source_key, :failure,
                   "Failed on #{format_date(date)}: #{String.slice(error_msg, 0, 50)}"}
                ]
              else
                []
              end
          end
        end)

      # Show execution statistics
      total = length(executions)
      successful = Enum.count(executions, &(&1.state == "completed"))
      _failed = total - successful
      success_rate = if total > 0, do: Float.round(successful / total * 100, 1), else: 0.0

      IO.puts("")
      IO.puts("  Summary: #{successful}/#{total} successful (#{success_rate}%)")

      # Check for recent execution (last 24 hours)
      recent_cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

      has_recent =
        Enum.any?(executions, fn exec ->
          DateTime.compare(exec.attempted_at, recent_cutoff) == :gt
        end)

      alerts =
        if has_recent do
          alerts
        else
          last_exec = Enum.max_by(executions, & &1.attempted_at)
          hours_ago = div(DateTime.diff(DateTime.utc_now(), last_exec.attempted_at), 3600)

          IO.puts(
            IO.ANSI.yellow() <>
              "  ⚠️  No execution in last 24 hours (last run: #{hours_ago}h ago)" <>
              IO.ANSI.reset()
          )

          [{source_key, :stale, "No execution in last 24 hours"} | alerts]
        end

      IO.puts("")
      alerts
    end
  end

  defp display_execution(exec, child_job_key) do
    status =
      case exec.state do
        "completed" -> IO.ANSI.green() <> pad("✅ OK", 10) <> IO.ANSI.reset()
        "discarded" -> IO.ANSI.red() <> pad("❌ FAIL", 10) <> IO.ANSI.reset()
        "cancelled" -> IO.ANSI.yellow() <> pad("⚠️ SKIP", 10) <> IO.ANSI.reset()
        other -> pad(other, 10)
      end

    duration =
      if exec.duration_ms do
        format_duration(exec.duration_ms)
      else
        "-"
      end

    jobs_spawned =
      case get_in(exec.results || %{}, [child_job_key]) do
        nil -> "-"
        count -> "#{count}"
      end

    error_preview =
      if exec.state != "completed" do
        error_msg = get_in(exec.results || %{}, ["error_message"]) || ""
        String.slice(error_msg, 0, 30)
      else
        ""
      end

    date_str = format_date(DateTime.to_date(exec.attempted_at))

    IO.puts(
      "  #{pad(date_str, 12)} #{status} #{pad(duration, 10)} #{pad(jobs_spawned, 15)} #{error_preview}"
    )
  end

  defp display_summary(alerts, _days) do
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 70) <> IO.ANSI.reset())

    if Enum.empty?(alerts) do
      IO.puts(IO.ANSI.green() <> "✅ All scrapers healthy - no issues detected" <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.yellow() <> "⚠️  #{length(alerts)} Alert(s) Detected:" <> IO.ANSI.reset())
      IO.puts("")

      alerts
      |> Enum.group_by(fn {source, _type, _msg} -> source end)
      |> Enum.each(fn {source, source_alerts} ->
        source_name = SourcePatterns.get_display_name(source)
        IO.puts("  #{source_name}:")

        Enum.each(source_alerts, fn {_source, type, msg} ->
          icon =
            case type do
              :missing -> "📅"
              :failure -> "❌"
              :stale -> "⏰"
              :no_executions -> "🚫"
              :worker_not_found -> "🔧"
            end

          IO.puts("    #{icon} #{msg}")
        end)
      end)
    end

    IO.puts("")

    # Recommendations
    missing_count = Enum.count(alerts, fn {_, type, _} -> type == :missing end)
    failure_count = Enum.count(alerts, fn {_, type, _} -> type == :failure end)
    stale_count = Enum.count(alerts, fn {_, type, _} -> type == :stale end)
    worker_not_found_count = Enum.count(alerts, fn {_, type, _} -> type == :worker_not_found end)

    if missing_count > 0 || failure_count > 0 || stale_count > 0 || worker_not_found_count > 0 do
      IO.puts(IO.ANSI.blue() <> "💡 Recommendations:" <> IO.ANSI.reset())

      if missing_count > 0 do
        IO.puts("  • Check Oban scheduler configuration and ensure jobs are queued daily")
      end

      if failure_count > 0 do
        IO.puts("  • Run `mix monitor.jobs failures --source <source>` to investigate failures")
      end

      if stale_count > 0 do
        IO.puts("  • Verify the scraper is enabled in Admin > Discovery > City Config")
        IO.puts("  • Check if Oban worker is running: `mix monitor.jobs stats --hours 24`")
      end

      if worker_not_found_count > 0 do
        IO.puts("  • Check SourceRegistry for missing source definitions")
        IO.puts("  • Verify source key format matches registry (hyphens vs underscores)")
      end

      IO.puts("")
    end
  end

  # Database queries

  defp fetch_sync_job_executions(worker_pattern, from_date) do
    from_datetime = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")

    from(j in JobExecutionSummary,
      where: j.worker == ^worker_pattern,
      where: j.attempted_at >= ^from_datetime,
      order_by: [desc: j.attempted_at]
    )
    |> Repo.replica().all()
  end

  defp group_by_date(executions) do
    Enum.group_by(executions, fn exec ->
      DateTime.to_date(exec.attempted_at)
    end)
  end

  # Helper functions

  defp days_ago(days) do
    Date.add(Date.utc_today(), -days + 1)
  end

  defp generate_date_range(days) do
    today = Date.utc_today()

    (days - 1)..0//-1
    |> Enum.map(fn offset -> Date.add(today, -offset) end)
  end

  defp format_date(date) do
    Calendar.strftime(date, "%Y-%m-%d")
  end

  defp format_duration(ms) when is_integer(ms) or is_float(ms) do
    cond do
      ms < 1000 -> "#{round(ms)}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end

  defp format_duration(_), do: "-"

  defp pad(str, width) do
    str
    |> to_string()
    |> String.pad_trailing(width)
  end
end
