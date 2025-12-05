defmodule Mix.Tasks.Quality.Countries do
  use Mix.Task

  @shortdoc "Check venue country assignments against GPS coordinates"

  @moduledoc """
  Check for venue country mismatches based on GPS coordinates.

  This tool scans venues and compares their assigned country with what
  reverse geocoding determines from their GPS coordinates.

  ## Examples

      # Check all venues (up to 1000)
      mix quality.countries

      # Check venues from specific source
      mix quality.countries --source speed_quizzing

      # Check venues currently assigned to UK
      mix quality.countries --country "United Kingdom"

      # Check with higher limit
      mix quality.countries --limit 5000

      # Export report to JSON file
      mix quality.countries --export report.json

      # Show UK -> Ireland mismatches only
      mix quality.countries --from "United Kingdom" --to Ireland

      # JSON output
      mix quality.countries --json

  ## Output

  The default output shows:
  - Summary statistics (total checked, mismatches found)
  - Breakdown by confidence level (high/medium/low)
  - Country pair summary (e.g., "UK -> Ireland: 5 venues")
  - Detailed mismatch list (venue name, coordinates, current/expected country)

  ## Confidence Levels

  - HIGH: Clear mismatch, safe for bulk migration
  - MEDIUM: Border regions or territories, needs review
  - LOW: Geocoding failed or ambiguous, manual investigation needed

  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _args, _} =
      OptionParser.parse(args,
        strict: [
          source: :string,
          country: :string,
          limit: :integer,
          json: :boolean,
          export: :string,
          from: :string,
          to: :string
        ],
        aliases: [s: :source, c: :country, l: :limit, j: :json, e: :export, f: :from, t: :to]
      )

    alias EventasaurusDiscovery.Admin.DataQualityChecker

    # Build options for the check
    check_opts = []
    check_opts = if opts[:source], do: [{:source, opts[:source]} | check_opts], else: check_opts
    check_opts = if opts[:country], do: [{:country, opts[:country]} | check_opts], else: check_opts
    check_opts = if opts[:limit], do: [{:limit, opts[:limit]} | check_opts], else: check_opts

    # Run the check
    result = DataQualityChecker.check_venue_countries(check_opts)

    # Filter by country pair if specified
    mismatches =
      if opts[:from] && opts[:to] do
        Enum.filter(result.mismatches, fn m ->
          m.current_country == opts[:from] && m.expected_country == opts[:to]
        end)
      else
        result.mismatches
      end

    result = %{result | mismatches: mismatches, mismatch_count: length(mismatches)}

    cond do
      opts[:export] ->
        # Export to JSON file
        report = DataQualityChecker.export_venue_country_report(check_opts)
        json = Jason.encode!(report, pretty: true)
        File.write!(opts[:export], json)
        Mix.shell().info("Report exported to: #{opts[:export]}")

      opts[:json] ->
        # Print JSON to stdout
        print_json(result)

      true ->
        # Print formatted output
        print_report(result, opts)
    end
  end

  defp print_report(result, opts) do
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.bright() <> "Venue Country Mismatch Report" <> IO.ANSI.reset())
    Mix.shell().info("=" |> String.duplicate(60))
    Mix.shell().info("")

    # Summary
    Mix.shell().info(IO.ANSI.bright() <> "Summary:" <> IO.ANSI.reset())
    Mix.shell().info("  Venues Checked: #{result.total_checked}")

    mismatch_color = if result.mismatch_count > 0, do: IO.ANSI.yellow(), else: IO.ANSI.green()

    Mix.shell().info(
      "  Mismatches Found: " <>
        mismatch_color <>
        "#{result.mismatch_count}" <>
        IO.ANSI.reset()
    )

    Mix.shell().info("")

    # Confidence breakdown
    if result.mismatch_count > 0 do
      Mix.shell().info(IO.ANSI.bright() <> "By Confidence:" <> IO.ANSI.reset())
      Mix.shell().info("  HIGH:   #{result.by_confidence[:high] || 0} (safe for migration)")
      Mix.shell().info("  MEDIUM: #{result.by_confidence[:medium] || 0} (needs review)")
      Mix.shell().info("  LOW:    #{result.by_confidence[:low] || 0} (manual investigation)")
      Mix.shell().info("")

      # Country pair breakdown
      if map_size(result.by_country_pair) > 0 do
        Mix.shell().info(IO.ANSI.bright() <> "By Country Pair:" <> IO.ANSI.reset())

        result.by_country_pair
        |> Enum.sort_by(fn {_k, v} -> -v end)
        |> Enum.each(fn {{from, to}, count} ->
          Mix.shell().info("  #{from} -> #{to}: #{count} venues")
        end)

        Mix.shell().info("")
      end

      # Mismatch details (limited to first 20 unless filtering)
      display_limit = if opts[:from] && opts[:to], do: length(result.mismatches), else: 20

      if length(result.mismatches) > 0 do
        Mix.shell().info(IO.ANSI.bright() <> "Mismatch Details:" <> IO.ANSI.reset())
        Mix.shell().info("")

        result.mismatches
        |> Enum.take(display_limit)
        |> Enum.each(&print_mismatch/1)

        if length(result.mismatches) > display_limit do
          remaining = length(result.mismatches) - display_limit
          Mix.shell().info("")

          Mix.shell().info(
            IO.ANSI.faint() <>
              "  ... and #{remaining} more. Use --export to see all." <>
              IO.ANSI.reset()
          )
        end
      end
    else
      Mix.shell().info(
        IO.ANSI.green() <>
          "No country mismatches found!" <>
          IO.ANSI.reset()
      )
    end

    Mix.shell().info("")
  end

  defp print_mismatch(m) do
    confidence_color =
      case m.confidence do
        :high -> IO.ANSI.green()
        :medium -> IO.ANSI.yellow()
        _ -> IO.ANSI.red()
      end

    confidence_text = m.confidence |> to_string() |> String.upcase()

    Mix.shell().info(
      "  " <>
        confidence_color <>
        "[#{confidence_text}]" <>
        IO.ANSI.reset() <>
        " " <>
        IO.ANSI.bright() <>
        "#{truncate(m.venue_name, 35)}" <>
        IO.ANSI.reset()
    )

    Mix.shell().info("    ID: #{m.venue_id} | Source: #{m.source || "unknown"}")
    Mix.shell().info("    GPS: #{Float.round(m.latitude, 4)}, #{Float.round(m.longitude, 4)}")

    Mix.shell().info(
      "    Current:  " <>
        IO.ANSI.red() <>
        "#{m.current_city}, #{m.current_country}" <>
        IO.ANSI.reset()
    )

    Mix.shell().info(
      "    Expected: " <>
        IO.ANSI.green() <>
        "#{m.expected_city}, #{m.expected_country}" <>
        IO.ANSI.reset()
    )

    Mix.shell().info("")
  end

  defp truncate(str, max_len) when byte_size(str) > max_len do
    String.slice(str, 0, max_len - 3) <> "..."
  end

  defp truncate(str, _max_len), do: str

  defp print_json(result) do
    output = %{
      total_checked: result.total_checked,
      mismatch_count: result.mismatch_count,
      by_confidence: result.by_confidence,
      by_country_pair:
        result.by_country_pair
        |> Enum.map(fn {{from, to}, count} ->
          %{from: from, to: to, count: count}
        end),
      mismatches:
        result.mismatches
        |> Enum.map(fn m ->
          %{
            venue_id: m.venue_id,
            venue_name: m.venue_name,
            latitude: m.latitude,
            longitude: m.longitude,
            current_country: m.current_country,
            current_city: m.current_city,
            expected_country: m.expected_country,
            expected_city: m.expected_city,
            confidence: m.confidence,
            source: m.source
          }
        end)
    }

    Mix.shell().info(Jason.encode!(output, pretty: true))
  end
end
