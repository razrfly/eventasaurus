defmodule Mix.Tasks.Monitor.Health do
  @moduledoc """
  Displays overall health metrics and SLO status for scrapers.

  Provides at-a-glance health dashboard showing success rates, performance metrics,
  and SLO compliance for scraper jobs.

  ## Usage

      # Check health for Cinema City scraper
      mix monitor.health --source cinema_city

      # Check health from last 48 hours
      mix monitor.health --source cinema_city --hours 48

      # Show all scrapers
      mix monitor.health --all

  ## Output Example

      🏥 Cinema City Health Dashboard
      ================================================================
      Period: Last 24 hours
      Overall Status: ⚠️  Below Target

      Summary:
      ├─ Total Executions: 127
      ├─ Success Rate: 87.4% (Target: 95.0%)
      ├─ Avg Duration: 1,847ms (Target: 2,000ms)
      └─ SLO Status: Below Target

      Job Performance:
      ┌──────────────────────┬─────────┬──────────┬──────────┬────────┐
      │ Job                  │ Success │ Avg Time │ SLO      │ Status │
      ├──────────────────────┼─────────┼──────────┼──────────┼────────┤
      │ SyncJob              │  98.2%  │  1,234ms │  95.0%   │   ✅   │
      │ CinemaDateJob        │  92.3%  │  2,845ms │  95.0%   │   ⚠️   │
      │ MovieDetailJob       │  85.1%  │  1,987ms │  85.0%   │   ✅   │
      │ ShowtimeProcessJob   │  89.5%  │  1,456ms │  90.0%   │   ⚠️   │
      └──────────────────────┴─────────┴──────────┴──────────┴────────┘

      Recent Trend (last 6 hours):
      00:00-02:00: 89.2% ▓▓▓▓▓▓▓▓▓░
      02:00-04:00: 91.5% ▓▓▓▓▓▓▓▓▓▓
      04:00-06:00: 85.3% ▓▓▓▓▓▓▓▓░░
      06:00-08:00: 88.7% ▓▓▓▓▓▓▓▓▓░
      08:00-10:00: 86.1% ▓▓▓▓▓▓▓▓░░
      10:00-12:00: 87.9% ▓▓▓▓▓▓▓▓▓░

      Active Issues:
      ├─ 6 network errors in MovieDetailJob
      ├─ 4 validation errors in ShowtimeProcessJob
      └─ 2 geocoding errors in CinemaDateJob

      💡 Action Items:
      - CinemaDateJob: 2.7% below SLO target - investigate network errors
      - ShowtimeProcessJob: 0.5% below SLO target - review validation logic
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  alias EventasaurusDiscovery.Metrics.ScraperSLOs
  alias EventasaurusDiscovery.Sources.SourcePatterns
  import Ecto.Query

  @shortdoc "Displays overall health metrics and SLO status for scrapers"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [source: :string, hours: :integer, all: :boolean],
        aliases: [s: :source, h: :hours, a: :all]
      )

    if opts[:all] do
      display_all_sources(opts[:hours] || 24)
    else
      source = opts[:source]

      unless source do
        IO.puts(
          IO.ANSI.red() <> "❌ Error: --source is required (or use --all)" <> IO.ANSI.reset()
        )

        SourcePatterns.print_available_sources()
        System.halt(1)
      end

      # Normalize source key (handles both underscores and hyphens)
      source = SourcePatterns.normalize_cli_key(source)

      unless SourcePatterns.valid_source?(source) do
        IO.puts(IO.ANSI.red() <> "❌ Error: Unknown source '#{source}'" <> IO.ANSI.reset())
        SourcePatterns.print_available_sources()
        System.halt(1)
      end

      hours = opts[:hours] || 24
      display_health(source, hours)
    end
  end

  defp display_all_sources(hours) do
    IO.puts("\n" <> IO.ANSI.cyan() <> "🏥 All Scrapers Health Dashboard" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 64))
    IO.puts("")

    SourcePatterns.all_cli_keys()
    |> Enum.each(fn source ->
      health = calculate_health(source, hours)

      if health.total_executions > 0 do
        source_display = SourcePatterns.get_display_name(source)
        status_icon = get_overall_status_icon(health.overall_status)

        IO.puts(
          "#{status_icon} #{source_display}: #{format_percent(health.success_rate)} (#{health.total_executions} executions)"
        )
      end
    end)

    IO.puts("")
  end

  defp display_health(source, hours) do
    health = calculate_health(source, hours)

    if health.total_executions == 0 do
      IO.puts(
        IO.ANSI.yellow() <>
          "⚠️  No executions found for #{source} in last #{hours} hours" <> IO.ANSI.reset()
      )

      System.halt(0)
    end

    source_display = SourcePatterns.get_display_name(source)

    IO.puts("\n" <> IO.ANSI.cyan() <> "🏥 #{source_display} Health Dashboard" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 64))
    IO.puts("Period: Last #{hours} hours")

    status_icon = get_overall_status_icon(health.overall_status)
    status_text = format_status(health.overall_status)

    IO.puts("Overall Status: #{status_icon} #{status_text}")
    IO.puts("")

    # Summary
    IO.puts(IO.ANSI.green() <> "Summary:" <> IO.ANSI.reset())
    IO.puts("├─ Total Executions: #{health.total_executions}")

    target_text =
      if health.target_success_rate do
        " (Target: #{format_percent(health.target_success_rate * 100)})"
      else
        ""
      end

    IO.puts("├─ Success Rate: #{format_percent(health.success_rate)}#{target_text}")

    avg_duration_text =
      if health.target_avg_duration do
        " (Target: #{format_duration(health.target_avg_duration)})"
      else
        ""
      end

    IO.puts("├─ Avg Duration: #{format_duration(health.avg_duration)}#{avg_duration_text}")
    IO.puts("└─ SLO Status: #{status_text}")
    IO.puts("")

    # Job performance table
    if length(health.job_performance) > 0 do
      IO.puts(IO.ANSI.blue() <> "Job Performance:" <> IO.ANSI.reset())
      display_job_table(health.job_performance)
      IO.puts("")
    end

    # Recent trend
    if length(health.trend) > 0 do
      IO.puts(
        IO.ANSI.magenta() <> "Recent Trend (last #{min(hours, 6)} hours):" <> IO.ANSI.reset()
      )

      health.trend
      |> Enum.take(6)
      |> Enum.each(fn {range, rate} ->
        bar_length = round(rate / 100 * 10)
        bar = String.duplicate("▓", bar_length) <> String.duplicate("░", 10 - bar_length)
        IO.puts("#{range}: #{format_percent(rate)} #{bar}")
      end)

      IO.puts("")
    end

    # Active issues
    if length(health.active_issues) > 0 do
      IO.puts(IO.ANSI.yellow() <> "Active Issues:" <> IO.ANSI.reset())

      health.active_issues
      |> Enum.take(5)
      |> Enum.with_index()
      |> Enum.each(fn {issue, index} ->
        prefix = if index == min(5, length(health.active_issues)) - 1, do: "└─", else: "├─"
        IO.puts("#{prefix} #{issue}")
      end)

      IO.puts("")
    end

    # Action items
    if length(health.action_items) > 0 do
      IO.puts(IO.ANSI.red() <> "💡 Action Items:" <> IO.ANSI.reset())

      health.action_items
      |> Enum.each(fn item ->
        IO.puts("- #{item}")
      end)

      IO.puts("")
    end
  end

  defp calculate_health(source, hours) do
    case SourcePatterns.get_worker_pattern(source) do
      {:ok, worker_pattern} ->
        calculate_health_with_pattern(worker_pattern, hours)

      {:error, _reason} ->
        # Return empty health data if worker pattern cannot be resolved
        return_empty_health()
    end
  end

  defp calculate_health_with_pattern(worker_pattern, hours) do
    from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)

    # Get all executions
    executions =
      from(j in JobExecutionSummary,
        where: like(j.worker, ^worker_pattern),
        where: j.attempted_at >= ^from_time
      )
      |> Repo.all()

    total_executions = length(executions)

    if total_executions == 0 do
      %{
        total_executions: 0,
        success_rate: 0,
        avg_duration: 0,
        overall_status: :unknown,
        target_success_rate: nil,
        target_avg_duration: nil,
        job_performance: [],
        trend: [],
        active_issues: [],
        action_items: []
      }
    else
      # Overall metrics
      completed = Enum.count(executions, &(&1.state == "completed"))
      success_rate = completed / total_executions * 100

      durations =
        executions
        |> Enum.map(& &1.duration_ms)
        |> Enum.reject(&is_nil/1)

      avg_duration =
        if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0

      # Get SLO targets (use first worker's SLO as overall target)
      first_worker = executions |> List.first() |> Map.get(:worker)
      slo = ScraperSLOs.get_slo(first_worker)
      target_success_rate = slo.target_success_rate
      target_avg_duration = slo.target_avg_duration_ms

      # Determine overall status
      overall_status = ScraperSLOs.check_slo_status(slo, success_rate, avg_duration)

      # Job performance breakdown
      job_performance =
        executions
        |> Enum.group_by(& &1.worker)
        |> Enum.map(fn {worker, jobs} ->
          worker_name = worker |> String.split(".") |> List.last()
          worker_total = length(jobs)
          worker_completed = Enum.count(jobs, &(&1.state == "completed"))
          worker_success_rate = worker_completed / worker_total * 100

          worker_durations =
            jobs
            |> Enum.map(& &1.duration_ms)
            |> Enum.reject(&is_nil/1)

          worker_avg_duration =
            if length(worker_durations) > 0,
              do: Enum.sum(worker_durations) / length(worker_durations),
              else: 0

          worker_slo = ScraperSLOs.get_slo(worker)

          worker_status =
            ScraperSLOs.check_slo_status(worker_slo, worker_success_rate, worker_avg_duration)

          %{
            name: worker_name,
            success_rate: worker_success_rate,
            avg_duration: worker_avg_duration,
            slo_target: worker_slo.target_success_rate * 100,
            status: worker_status
          }
        end)
        |> Enum.sort_by(& &1.success_rate, :desc)

      # Recent trend (2-hour windows)
      trend =
        executions
        |> Enum.group_by(fn exec ->
          hour = exec.attempted_at.hour
          window = div(hour, 2) * 2

          "#{String.pad_leading(to_string(window), 2, "0")}:00-#{String.pad_leading(to_string(window + 2), 2, "0")}:00"
        end)
        |> Enum.map(fn {range, jobs} ->
          window_completed = Enum.count(jobs, &(&1.state == "completed"))
          window_rate = window_completed / length(jobs) * 100
          {range, window_rate}
        end)
        |> Enum.sort()
        |> Enum.reverse()

      # Active issues (error summary)
      failures = Enum.filter(executions, &(&1.state in ["discarded", "cancelled"]))

      active_issues =
        failures
        |> Enum.group_by(fn f ->
          {f.results["error_category"], f.worker |> String.split(".") |> List.last()}
        end)
        |> Enum.map(fn {{category, job_name}, errors} ->
          count = length(errors)
          "#{count} #{category || "unknown"} errors in #{job_name}"
        end)
        |> Enum.sort()

      # Action items (jobs below SLO)
      action_items =
        job_performance
        |> Enum.filter(&(&1.status != :meets_target))
        |> Enum.map(fn job ->
          gap = job.slo_target - job.success_rate
          "#{job.name}: #{format_percent(gap)} below SLO target - investigate errors"
        end)

      %{
        total_executions: total_executions,
        success_rate: success_rate,
        avg_duration: avg_duration,
        overall_status: overall_status,
        target_success_rate: target_success_rate,
        target_avg_duration: target_avg_duration,
        job_performance: job_performance,
        trend: trend,
        active_issues: active_issues,
        action_items: action_items
      }
    end
  end

  defp display_job_table(jobs) do
    # Table header
    IO.puts("┌──────────────────────┬─────────┬──────────┬──────────┬────────┐")
    IO.puts("│ Job                  │ Success │ Avg Time │ SLO      │ Status │")
    IO.puts("├──────────────────────┼─────────┼──────────┼──────────┼────────┤")

    # Table rows
    jobs
    |> Enum.each(fn job ->
      name = String.pad_trailing(String.slice(job.name, 0, 20), 20)
      success = String.pad_leading(format_percent(job.success_rate), 7)
      avg_time = String.pad_leading(format_duration(job.avg_duration), 8)
      slo = String.pad_leading(format_percent(job.slo_target), 8)
      status = get_status_icon(job.status)

      IO.puts("│ #{name} │ #{success} │ #{avg_time} │ #{slo} │   #{status}   │")
    end)

    # Table footer
    IO.puts("└──────────────────────┴─────────┴──────────┴──────────┴────────┘")
  end

  defp get_status_icon(status) do
    case status do
      :meets_target -> IO.ANSI.green() <> "✅" <> IO.ANSI.reset()
      :below_target -> IO.ANSI.yellow() <> "⚠️ " <> IO.ANSI.reset()
      :critical -> IO.ANSI.red() <> "❌" <> IO.ANSI.reset()
      _ -> "❓"
    end
  end

  defp get_overall_status_icon(status) do
    case status do
      :meets_target -> IO.ANSI.green() <> "✅" <> IO.ANSI.reset()
      :below_target -> IO.ANSI.yellow() <> "⚠️ " <> IO.ANSI.reset()
      :critical -> IO.ANSI.red() <> "❌" <> IO.ANSI.reset()
      _ -> "❓"
    end
  end

  defp format_status(status) do
    case status do
      :meets_target -> IO.ANSI.green() <> "Meets Target" <> IO.ANSI.reset()
      :below_target -> IO.ANSI.yellow() <> "Below Target" <> IO.ANSI.reset()
      :critical -> IO.ANSI.red() <> "Critical" <> IO.ANSI.reset()
      _ -> "Unknown"
    end
  end

  defp format_percent(value) do
    "#{Float.round(value, 1)}%"
  end

  defp format_duration(ms) when is_float(ms) or is_integer(ms) do
    "#{Float.round(ms * 1.0, 0) |> trunc() |> format_number()}ms"
  end

  defp format_duration(_), do: "N/A"

  defp format_number(num) when num >= 1000 do
    num
    |> to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(num), do: to_string(num)

  defp return_empty_health do
    %{
      total_executions: 0,
      success_rate: 0,
      avg_duration: 0,
      overall_status: :unknown,
      target_success_rate: nil,
      target_avg_duration: nil,
      job_performance: [],
      trend: [],
      active_issues: [],
      action_items: []
    }
  end
end
