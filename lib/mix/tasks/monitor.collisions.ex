defmodule Mix.Tasks.Monitor.Collisions do
  @moduledoc """
  CLI tool for monitoring collision/deduplication metrics.

  ## Usage

      mix monitor.collisions [command] [options]

  ## Commands

      mix monitor.collisions list                        # Show recent collisions (default: 50)
      mix monitor.collisions list --limit 100            # Show specific number
      mix monitor.collisions list --source kupbilecik    # Filter by source
      mix monitor.collisions list --type cross_source    # Filter by collision type

      mix monitor.collisions stats                       # Show statistics (default: last 24h)
      mix monitor.collisions stats --hours 168           # Last week
      mix monitor.collisions stats --source kupbilecik   # Source-specific stats

      mix monitor.collisions matrix                      # Show cross-source overlap matrix
      mix monitor.collisions matrix --hours 168          # Last week

      mix monitor.collisions confidence                  # Show confidence score distribution
      mix monitor.collisions confidence --source kupbilecik

  ## Options

      --limit      Number of results to show (default varies by command)
      --source     Filter by source name (e.g., kupbilecik, bandsintown)
      --type       Filter by collision type: same_source, cross_source
      --hours      Time range in hours (default: 24)

  ## Examples

      # Recent cross-source collisions from kupbilecik
      mix monitor.collisions list --source kupbilecik --type cross_source

      # Collision statistics for the last week
      mix monitor.collisions stats --hours 168

      # Which sources overlap the most?
      mix monitor.collisions matrix

  ## Output

  The tool provides formatted tables with collision metrics:
  - Same-source collisions (external_id matches)
  - Cross-source collisions (fuzzy matches)
  - Confidence scores for fuzzy matches
  - Match factors used in deduplication
  """

  use Mix.Task

  alias EventasaurusDiscovery.Monitoring.Collisions

  @shortdoc "Monitor collision/deduplication metrics from the command line"

  @impl Mix.Task
  def run(args) do
    # Start application to ensure Repo is available
    Mix.Task.run("app.start")

    case args do
      [] -> show_stats([])
      ["list" | opts] -> list_collisions(opts)
      ["stats" | opts] -> show_stats(opts)
      ["matrix" | opts] -> show_matrix(opts)
      ["confidence" | opts] -> show_confidence(opts)
      [command | _] -> unknown_command(command)
    end
  end

  defp list_collisions(opts) do
    parsed_opts = parse_options(opts)

    case Collisions.list(parsed_opts) do
      {:ok, collisions} ->
        print_collisions_table(collisions)
        print_collisions_summary(collisions)

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
    end
  end

  defp show_stats(opts) do
    parsed_opts = parse_options(opts)

    case Collisions.stats(parsed_opts) do
      {:ok, stats} ->
        print_stats(stats)

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
    end
  end

  defp show_matrix(opts) do
    parsed_opts = parse_options(opts)

    case Collisions.overlap_matrix(parsed_opts) do
      {:ok, matrix} ->
        print_matrix(matrix)

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
    end
  end

  defp show_confidence(opts) do
    parsed_opts = parse_options(opts)

    case Collisions.confidence_distribution(parsed_opts) do
      {:ok, distribution} ->
        print_confidence_distribution(distribution)

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
    end
  end

  defp unknown_command(command) do
    Mix.shell().error("Unknown command: #{command}")
    Mix.shell().info("\nAvailable commands:")
    Mix.shell().info("  list        - Show recent collision detections")
    Mix.shell().info("  stats       - Show collision statistics by source")
    Mix.shell().info("  matrix      - Show cross-source overlap matrix")
    Mix.shell().info("  confidence  - Show confidence score distribution")
    Mix.shell().info("\nRun 'mix help monitor.collisions' for detailed usage")
  end

  # Parse command line options
  defp parse_options(opts) do
    {parsed, _, _} =
      OptionParser.parse(opts,
        strict: [
          limit: :integer,
          source: :string,
          type: :string,
          hours: :integer
        ]
      )

    # Validate type if provided
    case Keyword.get(parsed, :type) do
      nil ->
        parsed

      type when type in ["same_source", "cross_source"] ->
        parsed

      invalid ->
        Mix.shell().error("Invalid type: #{invalid}. Must be: same_source or cross_source")
        Mix.shell().info("Ignoring --type filter")
        Keyword.delete(parsed, :type)
    end
  end

  # Printing Functions

  defp print_collisions_table(collisions) do
    IO.puts("\n" <> IO.ANSI.bright() <> "Recent Collision Detections:" <> IO.ANSI.reset())
    IO.puts(String.duplicate("━", 120))

    IO.puts(
      format_row([
        pad("Source", 15),
        pad("Type", 12),
        pad("Matched", 15),
        pad("Confidence", 10),
        pad("Resolution", 10),
        pad("Detected At", 20)
      ])
    )

    IO.puts(String.duplicate("━", 120))

    Enum.each(collisions, fn collision ->
      type_colored = colorize_type(collision.type)
      confidence = format_confidence(collision.confidence)

      matched =
        if collision.type == "cross_source",
          do: collision.matched_source || "unknown",
          else: "same source"

      IO.puts(
        format_row([
          pad(collision.source || "unknown", 15),
          pad(type_colored, 12),
          pad(matched, 15),
          pad(confidence, 10),
          pad(collision.resolution || "-", 10),
          pad(format_datetime(collision.detected_at), 20)
        ])
      )
    end)

    IO.puts(String.duplicate("━", 120) <> "\n")
  end

  defp print_collisions_summary(collisions) do
    total = length(collisions)

    same_source = Enum.count(collisions, &(&1.type == "same_source"))
    cross_source = Enum.count(collisions, &(&1.type == "cross_source"))

    confidences =
      collisions
      |> Enum.map(& &1.confidence)
      |> Enum.reject(&is_nil/1)

    avg_confidence =
      if length(confidences) > 0,
        do: Float.round(Enum.sum(confidences) / length(confidences), 2),
        else: nil

    IO.puts("#{IO.ANSI.cyan()}Summary:#{IO.ANSI.reset()}")
    IO.puts("  Total: #{total}")
    IO.puts("  Same-Source: #{IO.ANSI.yellow()}#{same_source}#{IO.ANSI.reset()}")
    IO.puts("  Cross-Source: #{IO.ANSI.magenta()}#{cross_source}#{IO.ANSI.reset()}")

    if avg_confidence do
      IO.puts("  Avg Confidence: #{format_confidence(avg_confidence)}")
    end

    IO.puts("")
  end

  defp print_stats(stats) do
    IO.puts(
      "\n" <>
        IO.ANSI.bright() <>
        "Collision Statistics (Last #{stats.period_hours} hours):" <> IO.ANSI.reset()
    )

    IO.puts(String.duplicate("━", 100))
    IO.puts("\n#{IO.ANSI.cyan()}Overall:#{IO.ANSI.reset()}")
    IO.puts("  Total Processed: #{stats.total_processed}")
    IO.puts("  Total Collisions: #{stats.total_collisions}")

    IO.puts(
      "  Same-Source: #{IO.ANSI.yellow()}#{stats.same_source_count}#{IO.ANSI.reset()} (#{percentage(stats.same_source_count, stats.total_collisions)})"
    )

    IO.puts(
      "  Cross-Source: #{IO.ANSI.magenta()}#{stats.cross_source_count}#{IO.ANSI.reset()} (#{percentage(stats.cross_source_count, stats.total_collisions)})"
    )

    IO.puts("  Collision Rate: #{stats.collision_rate}%")

    if stats.avg_confidence do
      IO.puts("  Avg Confidence: #{format_confidence(stats.avg_confidence)}")
    end

    if length(stats.by_source) > 0 do
      IO.puts("\n#{IO.ANSI.cyan()}By Source:#{IO.ANSI.reset()}")
      IO.puts(String.duplicate("─", 100))

      IO.puts(
        format_row([
          pad("Source", 20),
          pad("Processed", 12),
          pad("Same-Source", 12),
          pad("Cross-Source", 12),
          pad("Total", 10),
          pad("Rate", 10)
        ])
      )

      IO.puts(String.duplicate("─", 100))

      Enum.each(stats.by_source, fn source_stats ->
        IO.puts(
          format_row([
            pad(source_stats.source, 20),
            pad("#{source_stats.processed}", 12),
            pad("#{source_stats.same_source}", 12),
            pad("#{source_stats.cross_source}", 12),
            pad("#{source_stats.total_collisions}", 10),
            pad("#{source_stats.rate}%", 10)
          ])
        )
      end)
    else
      IO.puts("\n#{IO.ANSI.yellow()}No collisions detected in this period.#{IO.ANSI.reset()}")
    end

    IO.puts(String.duplicate("━", 100) <> "\n")
  end

  defp print_matrix(matrix) do
    IO.puts(
      "\n" <>
        IO.ANSI.bright() <>
        "Cross-Source Overlap Matrix (Last #{matrix.period_hours} hours):" <> IO.ANSI.reset()
    )

    IO.puts(String.duplicate("━", 90))

    if length(matrix.overlaps) > 0 do
      IO.puts("\n#{IO.ANSI.cyan()}Source Overlaps:#{IO.ANSI.reset()}")
      IO.puts(String.duplicate("─", 90))

      IO.puts(
        format_row([
          pad("Source", 20),
          pad("Matched Source", 20),
          pad("Count", 10),
          pad("Avg Confidence", 15)
        ])
      )

      IO.puts(String.duplicate("─", 90))

      Enum.each(matrix.overlaps, fn overlap ->
        confidence = format_confidence(overlap.avg_confidence)

        IO.puts(
          format_row([
            pad(overlap.source || "unknown", 20),
            pad(overlap.matched_source || "unknown", 20),
            pad("#{overlap.count}", 10),
            pad(confidence, 15)
          ])
        )
      end)

      IO.puts(String.duplicate("─", 90))

      # Show involved sources
      IO.puts("\n#{IO.ANSI.cyan()}Sources with Cross-Source Collisions:#{IO.ANSI.reset()}")
      IO.puts("  #{Enum.join(matrix.sources, ", ")}")
    else
      IO.puts(
        "\n#{IO.ANSI.yellow()}No cross-source collisions detected in this period.#{IO.ANSI.reset()}"
      )
    end

    IO.puts(String.duplicate("━", 90) <> "\n")
  end

  defp print_confidence_distribution(dist) do
    source_label = if dist.source, do: " for #{dist.source}", else: ""

    IO.puts(
      "\n" <>
        IO.ANSI.bright() <>
        "Confidence Distribution#{source_label} (Last #{dist.period_hours} hours):" <>
        IO.ANSI.reset()
    )

    IO.puts(String.duplicate("━", 60))

    if dist.count > 0 do
      IO.puts("\n#{IO.ANSI.cyan()}Statistics:#{IO.ANSI.reset()}")
      IO.puts("  Count: #{dist.count}")
      IO.puts("  Min: #{format_confidence(dist.min)}")
      IO.puts("  Max: #{format_confidence(dist.max)}")
      IO.puts("  Avg: #{format_confidence(dist.avg)}")
      IO.puts("  Median: #{format_confidence(dist.median)}")

      if length(dist.histogram) > 0 do
        IO.puts("\n#{IO.ANSI.cyan()}Histogram:#{IO.ANSI.reset()}")

        max_count = Enum.max_by(dist.histogram, & &1.count).count

        Enum.each(dist.histogram, fn bucket ->
          bar_width = if max_count > 0, do: round(bucket.count / max_count * 30), else: 0
          bar = String.duplicate("█", bar_width)

          IO.puts("  #{String.pad_trailing(bucket.range, 12)} #{bar} #{bucket.count}")
        end)
      end
    else
      IO.puts(
        "\n#{IO.ANSI.yellow()}No cross-source collisions with confidence scores found.#{IO.ANSI.reset()}"
      )
    end

    IO.puts(String.duplicate("━", 60) <> "\n")
  end

  # Helper Functions

  defp colorize_type("same_source"),
    do: IO.ANSI.yellow() <> "same_source" <> IO.ANSI.reset()

  defp colorize_type("cross_source"),
    do: IO.ANSI.magenta() <> "cross_source" <> IO.ANSI.reset()

  defp colorize_type(nil), do: "-"
  defp colorize_type(other), do: "#{other}"

  defp format_confidence(nil), do: "-"
  defp format_confidence(conf) when is_float(conf), do: "#{Float.round(conf * 100, 0)}%"
  defp format_confidence(conf), do: "#{conf}"

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end

  defp percentage(_, 0), do: "0%"
  defp percentage(part, total), do: "#{Float.round(part / total * 100, 1)}%"

  defp pad(string, width) do
    String.pad_trailing(to_string(string), width)
  end

  defp format_row(columns) do
    Enum.join(columns, " ")
  end
end
