defmodule Mix.Tasks.Discovery.Freshness do
  @moduledoc """
  Check freshness health for discovery sources to verify EventFreshnessChecker effectiveness.

  ## What it checks

  This task monitors whether freshness checking is working correctly by analyzing
  actual Oban job execution rates vs expected rates. When freshness checking works,
  most events should be skipped because they were recently updated (within threshold).

  ## Usage

      # Check specific source
      mix discovery.freshness question-one

      # Check all sources
      mix discovery.freshness --all

      # Show only broken sources
      mix discovery.freshness --broken

      # Output as JSON for scripting
      mix discovery.freshness question-one --json

  ## Status Levels

  - **HEALTHY** (<40% processing rate) - Most events skipped, freshness checking works
  - **DEGRADED** (40-70% processing rate) - Some events skipped, partially working
  - **WARNING** (70-95% processing rate) - Few events skipped, mostly broken
  - **BROKEN** (95%+ processing rate) - No events skipped, completely broken

  ## Common Issues

  **BROKEN status usually means:**
  - External ID format mismatch between IndexJob and Transformer
  - last_seen_at not being updated by EventProcessor
  - EventFreshnessChecker not being called in IndexJob

  ## Examples

      # Quick check for Question One
      mix discovery.freshness question-one

      # Check all sources and show summary
      mix discovery.freshness --all

      # Find broken sources for monitoring/alerts
      mix discovery.freshness --broken

      # Get JSON output for automation
      mix discovery.freshness --all --json
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Services.FreshnessHealthChecker

  @shortdoc "Check freshness health for discovery sources"

  def run(args) do
    Application.ensure_all_started(:eventasaurus)

    {opts, remaining, _} =
      OptionParser.parse(args,
        switches: [
          all: :boolean,
          broken: :boolean,
          json: :boolean
        ]
      )

    source_slug = List.first(remaining)

    cond do
      opts[:all] ->
        check_all_sources(opts)

      opts[:broken] ->
        check_broken_sources(opts)

      source_slug ->
        check_single_source(source_slug, opts)

      true ->
        exit_with_error("Please specify a source slug or use --all")
    end
  end

  defp check_single_source(source_slug, opts) do
    case find_source(source_slug) do
      nil ->
        exit_with_error("Source not found: #{source_slug}")

      source ->
        health = FreshnessHealthChecker.check_health(source.id)

        if opts[:json] do
          output_json([Map.put(health, :source_slug, source_slug)])
        else
          print_source_health(source_slug, health)
        end
    end
  end

  defp check_all_sources(opts) do
    sources = Repo.all(Source)

    results =
      Enum.map(sources, fn source ->
        health = FreshnessHealthChecker.check_health(source.id)
        Map.put(health, :source_slug, source.slug)
      end)

    if opts[:json] do
      output_json(results)
    else
      Logger.info("\n" <> String.duplicate("=", 80))
      Logger.info("FRESHNESS HEALTH CHECK - ALL SOURCES")
      Logger.info(String.duplicate("=", 80) <> "\n")

      Enum.each(results, fn result ->
        print_source_health(result.source_slug, result)
        IO.puts("")
      end)

      print_summary(results)
    end
  end

  defp check_broken_sources(opts) do
    sources = Repo.all(Source)

    results =
      Enum.map(sources, fn source ->
        health = FreshnessHealthChecker.check_health(source.id)
        Map.put(health, :source_slug, source.slug)
      end)
      |> Enum.filter(fn result -> result.status == :broken end)

    if Enum.empty?(results) do
      Logger.info("✅ No broken sources found! All freshness checking is working.")
    else
      if opts[:json] do
        output_json(results)
      else
        Logger.info("\n" <> String.duplicate("=", 80))
        Logger.info("BROKEN FRESHNESS SOURCES (#{length(results)})")
        Logger.info(String.duplicate("=", 80) <> "\n")

        Enum.each(results, fn result ->
          print_source_health(result.source_slug, result)
          IO.puts("")
        end)
      end
    end
  end

  defp print_source_health(source_slug, health) do
    status_emoji = status_emoji(health.status)
    status_color = status_color(health.status)

    IO.puts([
      status_color,
      "\n#{status_emoji} ",
      String.upcase(source_slug),
      " - ",
      status_label(health.status),
      IO.ANSI.reset()
    ])

    IO.puts(String.duplicate("-", 80))

    IO.puts("Total Events:        #{format_number(health.total_events)}")
    IO.puts("Detail Jobs (7d):    #{format_number(health.detail_jobs_executed)}")
    IO.puts("Expected Jobs:       #{format_number(health.expected_jobs)}")
    IO.puts("Processing Rate:     #{Float.round(health.processing_rate * 100, 1)}% per run")
    IO.puts("Threshold:           #{health.threshold_hours}h")
    IO.puts("Runs in Period:      #{Float.round(health.runs_in_period, 1)}")

    IO.puts("\nDiagnosis:")
    IO.puts(health.diagnosis)
  end

  defp print_summary(results) do
    total = length(results)
    by_status = Enum.group_by(results, & &1.status)

    healthy_count = length(Map.get(by_status, :healthy, []))
    degraded_count = length(Map.get(by_status, :degraded, []))
    warning_count = length(Map.get(by_status, :warning, []))
    broken_count = length(Map.get(by_status, :broken, []))
    no_data_count = length(Map.get(by_status, :no_data, []))

    Logger.info(String.duplicate("=", 80))
    Logger.info("SUMMARY")
    Logger.info(String.duplicate("=", 80))
    Logger.info("Total Sources:   #{total}")
    Logger.info("✅ Healthy:      #{healthy_count}")
    Logger.info("⚡ Degraded:     #{degraded_count}")
    Logger.info("⚠️  Warning:      #{warning_count}")
    Logger.info("🔴 Broken:       #{broken_count}")
    Logger.info("⚪ No Data:      #{no_data_count}")

    if broken_count > 0 do
      broken_sources =
        Map.get(by_status, :broken, [])
        |> Enum.map(& &1.source_slug)
        |> Enum.join(", ")

      Logger.warning("\n⚠️  Broken sources need attention: #{broken_sources}")
    end
  end

  defp output_json(results) do
    results
    |> Jason.encode!(pretty: true)
    |> IO.puts()
  end

  defp find_source(slug) do
    Repo.get_by(Source, slug: slug)
  end

  defp status_emoji(:broken), do: "🔴"
  defp status_emoji(:warning), do: "⚠️"
  defp status_emoji(:degraded), do: "⚡"
  defp status_emoji(:healthy), do: "✅"
  defp status_emoji(:no_data), do: "⚪"

  defp status_label(:broken), do: "BROKEN - Freshness Checking Not Working"
  defp status_label(:warning), do: "WARNING - Mostly Not Working"
  defp status_label(:degraded), do: "DEGRADED - Partially Working"
  defp status_label(:healthy), do: "HEALTHY - Working Correctly"
  defp status_label(:no_data), do: "NO DATA - No Events Yet"

  defp status_color(:broken), do: IO.ANSI.red()
  defp status_color(:warning), do: IO.ANSI.yellow()
  defp status_color(:degraded), do: IO.ANSI.yellow()
  defp status_color(:healthy), do: IO.ANSI.green()
  defp status_color(:no_data), do: IO.ANSI.light_black()

  defp format_number(nil), do: "0"

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(num) when is_float(num), do: format_number(round(num))
  defp format_number(_), do: "0"

  defp exit_with_error(message) do
    Logger.error("❌ #{message}")

    Logger.info("""

    Usage: mix discovery.freshness [source_slug] [options]

    Examples:
      mix discovery.freshness question-one           # Check specific source
      mix discovery.freshness --all                  # Check all sources
      mix discovery.freshness --broken               # Show only broken sources
      mix discovery.freshness question-one --json    # JSON output
    """)

    System.halt(1)
  end
end
