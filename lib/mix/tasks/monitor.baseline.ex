defmodule Mix.Tasks.Monitor.Baseline do
  @moduledoc """
  Establishes statistical baseline for scraper performance.

  Analyzes recent job executions to create a performance baseline that can be
  compared against future runs to measure improvement.

  ## Usage

      # Create baseline for Cinema City scraper
      mix monitor.baseline --source cinema_city

      # Create baseline with custom time window
      mix monitor.baseline --source cinema_city --hours 48

      # Create baseline with custom sample size
      mix monitor.baseline --source cinema_city --limit 200

      # Save baseline to file for later comparison
      mix monitor.baseline --source cinema_city --save

  ## Output Example

      📊 Cinema City Scraper Baseline
      ================================================================
      Sample: 127 executions over last 24 hours
      Period: 2024-11-22 12:00:00Z to 2024-11-23 12:00:00Z

      Success Rate: 87.4% ± 2.9% (95% CI)
      ├─ Completed: 111 (87.4%)
      ├─ Failed: 14 (11.0%)
      └─ Cancelled: 2 (1.6%)

      Error Distribution:
      ├─ network_error: 6 (42.9%)
      ├─ validation_error: 4 (28.6%)
      ├─ geocoding_error: 2 (14.3%)
      └─ data_quality_error: 2 (14.3%)

      Performance Metrics:
      ├─ Avg Duration: 1,847ms ± 342ms
      ├─ P50: 1,650ms
      ├─ P95: 2,890ms
      └─ P99: 3,420ms

      Job Chain Health:
      ├─ SyncJob: 98.2% (56/57)
      ├─ CinemaDateJob: 92.3% (48/52)
      ├─ MovieDetailJob: 85.1% (40/47)
      └─ ShowtimeProcessJob: 89.5% (68/76)

      ✅ Baseline saved to .taskmaster/baselines/cinema_city_20241123_120000.json
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  import Ecto.Query

  @shortdoc "Establishes statistical baseline for scraper performance"

  @source_patterns %{
    "cinema_city" => "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%",
    "kino_krakow" => "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.%",
    "karnet" => "EventasaurusDiscovery.Sources.Karnet.Jobs.%",
    "week_pl" => "EventasaurusDiscovery.Sources.WeekPl.Jobs.%",
    "bandsintown" => "EventasaurusDiscovery.Sources.Bandsintown.Jobs.%",
    "resident_advisor" => "EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.%",
    "sortiraparis" => "EventasaurusDiscovery.Sources.Sortiraparis.Jobs.%",
    "inquizition" => "EventasaurusDiscovery.Sources.Inquizition.Jobs.%",
    "waw4free" => "EventasaurusDiscovery.Sources.Waw4Free.Jobs.%"
  }

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [source: :string, hours: :integer, limit: :integer, save: :boolean],
        aliases: [s: :source, h: :hours, l: :limit]
      )

    source = opts[:source]

    unless source do
      IO.puts(IO.ANSI.red() <> "❌ Error: --source is required" <> IO.ANSI.reset())
      IO.puts("\nAvailable sources:")
      Enum.each(@source_patterns, fn {name, _} -> IO.puts("  - #{name}") end)
      System.halt(1)
    end

    unless Map.has_key?(@source_patterns, source) do
      IO.puts(IO.ANSI.red() <> "❌ Error: Unknown source '#{source}'" <> IO.ANSI.reset())
      IO.puts("\nAvailable sources:")
      Enum.each(@source_patterns, fn {name, _} -> IO.puts("  - #{name}") end)
      System.halt(1)
    end

    hours = opts[:hours] || 24
    limit = opts[:limit] || 500
    save = opts[:save] || false

    worker_pattern = @source_patterns[source]

    # Query executions
    from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)
    to_time = DateTime.utc_now()

    executions =
      from(j in JobExecutionSummary,
        where: like(j.worker, ^worker_pattern),
        where: j.attempted_at >= ^from_time and j.attempted_at <= ^to_time,
        order_by: [desc: j.attempted_at],
        limit: ^limit
      )
      |> Repo.all()

    if Enum.empty?(executions) do
      IO.puts(
        IO.ANSI.yellow() <>
          "⚠️  No executions found for #{source} in last #{hours} hours" <> IO.ANSI.reset()
      )

      System.halt(0)
    end

    # Calculate baseline metrics
    baseline = calculate_baseline(executions, source, from_time, to_time)

    # Display results
    display_baseline(baseline, source)

    # Save if requested
    if save do
      save_baseline(baseline, source)
    end
  end

  defp calculate_baseline(executions, source, from_time, to_time) do
    total = length(executions)

    # State distribution
    completed = Enum.count(executions, &(&1.state == "completed"))
    failed = Enum.count(executions, &(&1.state == "discarded"))
    cancelled = Enum.count(executions, &(&1.state == "cancelled"))

    success_rate = completed / total * 100

    # 95% confidence interval for success rate
    # Using Wilson score interval
    z = 1.96
    p = completed / total
    n = total

    ci_margin =
      z * :math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n) * 100

    # Error distribution
    error_categories =
      executions
      |> Enum.filter(&(&1.state != "completed"))
      |> Enum.map(& &1.results["error_category"])
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_cat, count} -> -count end)

    # Performance metrics (durations in ms)
    durations =
      executions
      |> Enum.map(& &1.duration_ms)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    avg_duration = if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0

    std_dev =
      if length(durations) > 1 do
        variance =
          durations
          |> Enum.map(&((&1 - avg_duration) * (&1 - avg_duration)))
          |> Enum.sum()
          |> Kernel./(length(durations) - 1)

        :math.sqrt(variance)
      else
        0
      end

    p50 = percentile(durations, 0.50)
    p95 = percentile(durations, 0.95)
    p99 = percentile(durations, 0.99)

    # Job chain health (group by worker type)
    chain_health =
      executions
      |> Enum.group_by(& &1.worker)
      |> Enum.map(fn {worker, jobs} ->
        worker_total = length(jobs)
        worker_completed = Enum.count(jobs, &(&1.state == "completed"))
        worker_rate = worker_completed / worker_total * 100

        %{
          name: worker |> String.split(".") |> List.last(),
          success_rate: worker_rate,
          completed: worker_completed,
          total: worker_total
        }
      end)
      |> Enum.sort_by(fn %{success_rate: rate} -> -rate end)

    %{
      source: source,
      sample_size: total,
      period_start: from_time,
      period_end: to_time,
      success_rate: success_rate,
      ci_margin: ci_margin,
      completed: completed,
      failed: failed,
      cancelled: cancelled,
      error_categories: error_categories,
      avg_duration: avg_duration,
      std_dev: std_dev,
      p50: p50,
      p95: p95,
      p99: p99,
      chain_health: chain_health,
      generated_at: DateTime.utc_now()
    }
  end

  defp percentile([], _p), do: 0

  defp percentile(sorted_list, p) do
    k = (length(sorted_list) - 1) * p
    f = floor(k)
    c = ceil(k)

    if f == c do
      Enum.at(sorted_list, round(k))
    else
      lower = Enum.at(sorted_list, f)
      upper = Enum.at(sorted_list, c)
      lower + (upper - lower) * (k - f)
    end
  end

  defp display_baseline(baseline, source) do
    source_display =
      source |> String.split("_") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")

    IO.puts("\n" <> IO.ANSI.cyan() <> "📊 #{source_display} Scraper Baseline" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 64))

    IO.puts(
      "Sample: #{baseline.sample_size} executions over last #{hours_ago(baseline.period_start)} hours"
    )

    IO.puts(
      "Period: #{format_datetime(baseline.period_start)} to #{format_datetime(baseline.period_end)}"
    )

    IO.puts("")

    # Success rate
    IO.puts(
      IO.ANSI.green() <>
        "Success Rate: #{format_percent(baseline.success_rate)} ± #{format_percent(baseline.ci_margin)} (95% CI)" <>
        IO.ANSI.reset()
    )

    IO.puts(
      "├─ Completed: #{baseline.completed} (#{format_percent(baseline.completed / baseline.sample_size * 100)})"
    )

    IO.puts(
      "├─ Failed: #{baseline.failed} (#{format_percent(baseline.failed / baseline.sample_size * 100)})"
    )

    IO.puts(
      "└─ Cancelled: #{baseline.cancelled} (#{format_percent(baseline.cancelled / baseline.sample_size * 100)})"
    )

    # Error distribution
    if length(baseline.error_categories) > 0 do
      IO.puts("")
      IO.puts(IO.ANSI.yellow() <> "Error Distribution:" <> IO.ANSI.reset())
      total_errors = baseline.failed + baseline.cancelled

      baseline.error_categories
      |> Enum.with_index()
      |> Enum.each(fn {{category, count}, index} ->
        prefix = if index == length(baseline.error_categories) - 1, do: "└─", else: "├─"

        IO.puts("#{prefix} #{category}: #{count} (#{format_percent(count / total_errors * 100)})")
      end)
    end

    # Performance metrics
    IO.puts("")
    IO.puts(IO.ANSI.blue() <> "Performance Metrics:" <> IO.ANSI.reset())

    IO.puts(
      "├─ Avg Duration: #{format_duration(baseline.avg_duration)} ± #{format_duration(baseline.std_dev)}"
    )

    IO.puts("├─ P50: #{format_duration(baseline.p50)}")
    IO.puts("├─ P95: #{format_duration(baseline.p95)}")
    IO.puts("└─ P99: #{format_duration(baseline.p99)}")

    # Job chain health
    if length(baseline.chain_health) > 0 do
      IO.puts("")
      IO.puts(IO.ANSI.magenta() <> "Job Chain Health:" <> IO.ANSI.reset())

      baseline.chain_health
      |> Enum.with_index()
      |> Enum.each(fn {job, index} ->
        prefix = if index == length(baseline.chain_health) - 1, do: "└─", else: "├─"

        status_icon =
          cond do
            job.success_rate >= 95 -> IO.ANSI.green() <> "✅" <> IO.ANSI.reset()
            job.success_rate >= 85 -> IO.ANSI.yellow() <> "⚠️ " <> IO.ANSI.reset()
            true -> IO.ANSI.red() <> "❌" <> IO.ANSI.reset()
          end

        IO.puts(
          "#{prefix} #{status_icon} #{job.name}: #{format_percent(job.success_rate)} (#{job.completed}/#{job.total})"
        )
      end)
    end

    IO.puts("")
  end

  defp save_baseline(baseline, source) do
    # Create baselines directory if it doesn't exist
    baselines_dir = Path.join([File.cwd!(), ".taskmaster", "baselines"])
    File.mkdir_p!(baselines_dir)

    # Generate filename with timestamp
    timestamp = baseline.generated_at |> DateTime.to_iso8601(:basic) |> String.replace(":", "")
    filename = "#{source}_#{timestamp}.json"
    filepath = Path.join(baselines_dir, filename)

    # Save baseline to file
    json = Jason.encode!(baseline, pretty: true)
    File.write!(filepath, json)

    IO.puts(IO.ANSI.green() <> "✅ Baseline saved to #{filepath}" <> IO.ANSI.reset())
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

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp hours_ago(from_time) do
    DateTime.diff(DateTime.utc_now(), from_time, :hour)
  end
end
