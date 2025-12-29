defmodule Mix.Tasks.Monitor.Errors do
  @moduledoc """
  Analyzes error patterns and categorization for scrapers.

  Provides detailed breakdown of error types, frequencies, and trends to help
  identify root causes and prioritize fixes.

  ## Usage

      # Analyze errors for Cinema City scraper
      mix monitor.errors --source cinema_city

      # Analyze errors from last 48 hours
      mix monitor.errors --source cinema_city --hours 48

      # Show only top 10 error messages
      mix monitor.errors --source cinema_city --limit 10

      # Filter by specific error category
      mix monitor.errors --source cinema_city --category network_error

  ## Output Example

      🔍 Cinema City Error Analysis
      ================================================================
      Period: Last 24 hours
      Total Failures: 14 (11.0% of 127 executions)

      Error Categories:
      ├─ network_error: 6 (42.9%)
      ├─ validation_error: 4 (28.6%)
      ├─ geocoding_error: 2 (14.3%)
      └─ data_quality_error: 2 (14.3%)

      Top Error Messages:
      ├─ [network_error] HTTP 404: Event not found (4 occurrences)
      ├─ [validation_error] Missing required field: title (3 occurrences)
      ├─ [geocoding_error] Address not found: ul. Unknown (2 occurrences)
      └─ [data_quality_error] No data extracted from HTML (2 occurrences)

      Error Timeline (hourly):
      00:00 ▓░░░ 1 error
      04:00 ▓▓▓░ 3 errors
      08:00 ▓▓░░ 2 errors
      12:00 ▓▓▓▓ 4 errors
      16:00 ▓▓░░ 2 errors
      20:00 ▓▓░░ 2 errors

      Most Affected Jobs:
      ├─ MovieDetailJob: 6 failures (13.0% error rate)
      ├─ ShowtimeProcessJob: 4 failures (5.3% error rate)
      └─ CinemaDateJob: 4 failures (7.7% error rate)

      💡 Recommendations:
      - network_error: Consider implementing retry logic with exponential backoff
      - validation_error: Add upstream validation before processing
      - geocoding_error: Implement fallback geocoding providers
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  import Ecto.Query

  @shortdoc "Analyzes error patterns and categorization for scrapers"

  @source_patterns %{
    "cinema_city" => "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%",
    "repertuary" => "EventasaurusDiscovery.Sources.Repertuary.Jobs.%",
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
        switches: [source: :string, hours: :integer, limit: :integer, category: :string],
        aliases: [s: :source, h: :hours, l: :limit, c: :category]
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
    limit = opts[:limit] || 20
    category_filter = opts[:category]

    worker_pattern = @source_patterns[source]

    # Query failed executions
    from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)

    base_query =
      from(j in JobExecutionSummary,
        where: like(j.worker, ^worker_pattern),
        where: j.attempted_at >= ^from_time,
        where: j.state in ["discarded", "cancelled"]
      )

    # Apply category filter if specified
    query =
      if category_filter do
        from(j in base_query,
          where: fragment("?->>'error_category' = ?", j.results, ^category_filter)
        )
      else
        base_query
      end

    failures = query |> Repo.all()

    # Also get total executions for context
    total_executions =
      from(j in JobExecutionSummary,
        where: like(j.worker, ^worker_pattern),
        where: j.attempted_at >= ^from_time,
        select: count(j.id)
      )
      |> Repo.one()

    if Enum.empty?(failures) do
      IO.puts(
        IO.ANSI.green() <>
          "✅ No errors found for #{source} in last #{hours} hours!" <> IO.ANSI.reset()
      )

      System.halt(0)
    end

    # Analyze errors
    analysis = analyze_errors(failures, total_executions, hours)

    # Display results
    display_errors(analysis, source, category_filter, limit)
  end

  defp analyze_errors(failures, total_executions, hours) do
    total_failures = length(failures)
    # Guard against division by zero
    error_rate = if total_executions > 0, do: total_failures / total_executions * 100, else: 0.0

    # Category distribution
    category_distribution =
      failures
      |> Enum.map(& &1.results["error_category"])
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_cat, count} -> -count end)

    # Top error messages (group by error message)
    error_messages =
      failures
      |> Enum.map(fn f ->
        {f.results["error_category"], f.error}
      end)
      |> Enum.reject(fn {_cat, msg} -> is_nil(msg) end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_msg, count} -> -count end)

    # Timeline (group by hour)
    timeline =
      failures
      |> Enum.group_by(fn f ->
        f.attempted_at
        |> DateTime.truncate(:second)
        |> Map.put(:minute, 0)
        |> Map.put(:second, 0)
      end)
      |> Enum.map(fn {hour, errors} -> {hour, length(errors)} end)
      |> Enum.sort_by(fn {hour, _} -> hour end)

    # Most affected jobs
    # Use the same from_time as the failures query to avoid time drift
    from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)

    affected_jobs =
      failures
      |> Enum.group_by(& &1.worker)
      |> Enum.map(fn {worker, job_failures} ->
        worker_name = worker |> String.split(".") |> List.last()
        failure_count = length(job_failures)

        # Get total executions for this worker using the same from_time
        worker_total =
          from(j in JobExecutionSummary,
            where: j.worker == ^worker,
            where: j.attempted_at >= ^from_time,
            select: count(j.id)
          )
          |> Repo.one()

        # Guard against division by zero
        error_rate = if worker_total > 0, do: failure_count / worker_total * 100, else: 0.0
        {worker_name, failure_count, error_rate}
      end)
      |> Enum.sort_by(fn {_, count, _} -> -count end)

    %{
      total_failures: total_failures,
      total_executions: total_executions,
      error_rate: error_rate,
      hours: hours,
      category_distribution: category_distribution,
      error_messages: error_messages,
      timeline: timeline,
      affected_jobs: affected_jobs
    }
  end

  defp display_errors(analysis, source, category_filter, limit) do
    source_display =
      source |> String.split("_") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")

    header =
      if category_filter do
        "🔍 #{source_display} Error Analysis (#{category_filter})"
      else
        "🔍 #{source_display} Error Analysis"
      end

    IO.puts("\n" <> IO.ANSI.cyan() <> header <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 64))

    IO.puts("Period: Last #{analysis.hours} hours")

    IO.puts(
      "Total Failures: #{analysis.total_failures} (#{format_percent(analysis.error_rate)} of #{analysis.total_executions} executions)"
    )

    IO.puts("")

    # Category distribution
    unless category_filter do
      IO.puts(IO.ANSI.yellow() <> "Error Categories:" <> IO.ANSI.reset())

      analysis.category_distribution
      |> Enum.with_index()
      |> Enum.each(fn {{category, count}, index} ->
        prefix =
          if index == length(analysis.category_distribution) - 1, do: "└─", else: "├─"

        percentage = count / analysis.total_failures * 100
        IO.puts("#{prefix} #{category}: #{count} (#{format_percent(percentage)})")
      end)

      IO.puts("")
    end

    # Top error messages
    IO.puts(IO.ANSI.red() <> "Top Error Messages:" <> IO.ANSI.reset())

    analysis.error_messages
    |> Enum.take(limit)
    |> Enum.with_index()
    |> Enum.each(fn {{{category, message}, count}, index} ->
      prefix = if index == min(limit, length(analysis.error_messages)) - 1, do: "└─", else: "├─"

      # Truncate long messages
      truncated_message =
        if String.length(message) > 60 do
          String.slice(message, 0, 57) <> "..."
        else
          message
        end

      category_display = if category, do: "[#{category}]", else: "[unknown]"
      IO.puts("#{prefix} #{category_display} #{truncated_message} (#{count} occurrences)")
    end)

    IO.puts("")

    # Timeline
    if length(analysis.timeline) > 0 do
      IO.puts(IO.ANSI.blue() <> "Error Timeline (hourly):" <> IO.ANSI.reset())
      max_count = analysis.timeline |> Enum.map(fn {_, count} -> count end) |> Enum.max()

      analysis.timeline
      |> Enum.each(fn {hour, count} ->
        hour_str = Calendar.strftime(hour, "%H:%M")
        bar_length = round(count / max_count * 10)
        bar = String.duplicate("▓", bar_length) <> String.duplicate("░", 10 - bar_length)

        count_display =
          if count == 1, do: "#{count} error", else: "#{count} errors"

        IO.puts("#{hour_str} #{bar} #{count_display}")
      end)

      IO.puts("")
    end

    # Most affected jobs
    if length(analysis.affected_jobs) > 0 do
      IO.puts(IO.ANSI.magenta() <> "Most Affected Jobs:" <> IO.ANSI.reset())

      analysis.affected_jobs
      |> Enum.take(5)
      |> Enum.with_index()
      |> Enum.each(fn {{name, count, rate}, index} ->
        prefix = if index == min(5, length(analysis.affected_jobs)) - 1, do: "└─", else: "├─"

        IO.puts("#{prefix} #{name}: #{count} failures (#{format_percent(rate)} error rate)")
      end)

      IO.puts("")
    end

    # Recommendations
    if length(analysis.category_distribution) > 0 do
      IO.puts(IO.ANSI.green() <> "💡 Recommendations:" <> IO.ANSI.reset())

      analysis.category_distribution
      |> Enum.take(3)
      |> Enum.each(fn {category, _count} ->
        recommendation = get_recommendation(category)
        IO.puts("- #{category}: #{recommendation}")
      end)

      IO.puts("")
    end
  end

  defp get_recommendation(category) do
    # 12 standard categories + 1 fallback (uncategorized_error)
    case category do
      "validation_error" ->
        "Add upstream validation before processing"

      "parsing_error" ->
        "Review HTML/JSON structure changes, add fallback parsing strategies"

      "data_quality_error" ->
        "Add data quality checks and handle site structure changes"

      "data_integrity_error" ->
        "Review database constraints and transaction handling"

      "dependency_error" ->
        "Add dependency health checks and graceful waiting/retry logic"

      "network_error" ->
        "Consider implementing retry logic with exponential backoff"

      "rate_limit_error" ->
        "Implement request throttling and respect rate limit headers"

      "authentication_error" ->
        "Verify API credentials and token refresh logic"

      "geocoding_error" ->
        "Implement fallback geocoding providers"

      "venue_error" ->
        "Improve venue matching algorithms or add manual verification"

      "performer_error" ->
        "Enhance performer/artist matching logic"

      "tmdb_error" ->
        "Check TMDB API quotas and implement caching for movie lookups"

      "uncategorized_error" ->
        "Review error logs and add specific error handling"

      # Legacy categories (for historical data compatibility)
      "unknown_error" ->
        "Review error logs and add specific error handling"

      "category_error" ->
        "Review and expand event categorization rules"

      "duplicate_error" ->
        "Fine-tune deduplication logic"

      _ ->
        "Review error logs and add specific error handling"
    end
  end

  defp format_percent(value) do
    "#{Float.round(value, 1)}%"
  end
end
