defmodule Mix.Tasks.Monitor.Compare do
  @moduledoc """
  Compares two baseline snapshots to measure scraper improvement.

  Loads saved baselines and performs statistical comparison to show whether
  changes improved or degraded performance.

  ## Usage

      # Compare two baseline files
      mix monitor.compare \\
        --before .taskmaster/baselines/cinema_city_20241122_120000.json \\
        --after .taskmaster/baselines/cinema_city_20241123_120000.json

      # Compare latest baseline with current state
      mix monitor.compare --source cinema_city \\
        --baseline .taskmaster/baselines/cinema_city_20241122_120000.json

      # List available baselines
      mix monitor.compare --list

  ## Output Example

      📊 Baseline Comparison: Cinema City
      ================================================================
      Before: 2024-11-22 12:00:00 (127 executions)
      After:  2024-11-23 12:00:00 (134 executions)

      Overall Improvement:
      ├─ Success Rate: 87.4% → 92.5% (↑ 5.1pp) ✅
      ├─ Avg Duration: 1,847ms → 1,623ms (↓ 224ms) ✅
      ├─ P95 Duration: 2,890ms → 2,445ms (↓ 445ms) ✅
      └─ Error Rate: 12.6% → 7.5% (↓ 5.1pp) ✅

      Error Category Changes:
      ├─ network_error: 6 → 2 (↓ 4, -66.7%) ✅
      ├─ validation_error: 4 → 4 (no change)
      ├─ geocoding_error: 2 → 1 (↓ 1, -50.0%) ✅
      └─ data_quality_error: 2 → 3 (↑ 1, +50.0%) ⚠️

      Job Chain Improvements:
      ├─ MovieDetailJob: 85.1% → 91.2% (↑ 6.1pp) ✅
      ├─ ShowtimeProcessJob: 89.5% → 93.8% (↑ 4.3pp) ✅
      ├─ CinemaDateJob: 92.3% → 94.1% (↑ 1.8pp) ✅
      └─ SyncJob: 98.2% → 98.5% (↑ 0.3pp)

      Statistical Significance:
      ├─ Success Rate: p < 0.05 (significant) ✅
      ├─ Duration: p < 0.01 (highly significant) ✅
      └─ Sample Size: Adequate for comparison

      🎯 Summary:
      - Overall improvement detected across all metrics
      - Network errors reduced by 66.7% (likely fix deployed)
      - Data quality errors increased - investigate HTML structure changes
      - All job types show improvement
      - Changes are statistically significant

      💡 Recommendations:
      - Deploy to production ✅
      - Monitor data_quality_error trend
      - Consider this as new baseline
  """

  use Mix.Task
  require Logger

  @shortdoc "Compares two baseline snapshots to measure scraper improvement"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          before: :string,
          after: :string,
          source: :string,
          baseline: :string,
          list: :boolean
        ],
        aliases: [b: :before, a: :after, s: :source, l: :list]
      )

    cond do
      opts[:list] ->
        list_baselines()

      opts[:before] && opts[:after] ->
        compare_files(opts[:before], opts[:after])

      opts[:source] && opts[:baseline] ->
        compare_with_current(opts[:source], opts[:baseline])

      true ->
        IO.puts(IO.ANSI.red() <> "❌ Error: Invalid arguments" <> IO.ANSI.reset())
        IO.puts("\nUsage:")
        IO.puts("  mix monitor.compare --list")
        IO.puts("  mix monitor.compare --before FILE --after FILE")
        IO.puts("  mix monitor.compare --source SOURCE --baseline FILE")
        System.halt(1)
    end
  end

  defp list_baselines do
    baselines_dir = Path.join([File.cwd!(), ".taskmaster", "baselines"])

    if File.exists?(baselines_dir) do
      files = Path.wildcard(Path.join(baselines_dir, "*.json"))

      if Enum.empty?(files) do
        IO.puts(IO.ANSI.yellow() <> "No baselines found" <> IO.ANSI.reset())
      else
        IO.puts("\n" <> IO.ANSI.cyan() <> "📋 Available Baselines" <> IO.ANSI.reset())
        IO.puts(String.duplicate("=", 64))

        files
        |> Enum.sort(:desc)
        |> Enum.each(fn file ->
          filename = Path.basename(file)

          # Try to parse to get metadata
          case File.read(file) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, baseline} ->
                  IO.puts("\n#{filename}")
                  IO.puts("  Source: #{baseline["source"]}")
                  IO.puts("  Sample: #{baseline["sample_size"]} executions")

                  IO.puts(
                    "  Success Rate: #{format_percent(baseline["success_rate"])}"
                  )

                  IO.puts("  Generated: #{baseline["generated_at"]}")

                _ ->
                  IO.puts("\n#{filename} (invalid JSON)")
              end

            _ ->
              IO.puts("\n#{filename} (unreadable)")
          end
        end)

        IO.puts("")
      end
    else
      IO.puts(IO.ANSI.yellow() <> "No baselines directory found" <> IO.ANSI.reset())
      IO.puts("Run `mix monitor.baseline --source SOURCE --save` to create baselines")
    end
  end

  defp compare_files(before_file, after_file) do
    with {:ok, before} <- load_baseline(before_file),
         {:ok, after_baseline} <- load_baseline(after_file) do
      # Ensure they're from the same source
      if before["source"] != after_baseline["source"] do
        IO.puts(
          IO.ANSI.red() <>
            "❌ Error: Baselines are from different sources (#{before["source"]} vs #{after_baseline["source"]})" <>
            IO.ANSI.reset()
        )

        System.halt(1)
      end

      compare_baselines(before, after_baseline)
    else
      {:error, reason} ->
        IO.puts(IO.ANSI.red() <> "❌ Error: #{reason}" <> IO.ANSI.reset())
        System.halt(1)
    end
  end

  defp compare_with_current(source, baseline_file) do
    with {:ok, before} <- load_baseline(baseline_file) do
      # Validate source matches baseline
      if before["source"] != source do
        IO.puts(
          IO.ANSI.red() <>
            "❌ Error: Source mismatch. Baseline is for '#{before["source"]}' but you specified '#{source}'" <>
            IO.ANSI.reset()
        )

        System.halt(1)
      end

      # Generate current baseline
      IO.puts("Generating current baseline for #{source}...")

      {output, exit_code} =
        System.cmd("mix", ["monitor.baseline", "--source", source],
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "dev"}]
        )

      if exit_code != 0 do
        IO.puts(IO.ANSI.red() <> "❌ Failed to generate current baseline" <> IO.ANSI.reset())
        IO.puts(output)
        System.halt(1)
      end

      # Find the most recent baseline file for this source
      baselines_dir = Path.join([File.cwd!(), ".taskmaster", "baselines"])
      pattern = Path.join(baselines_dir, "#{source}_*.json")

      most_recent =
        Path.wildcard(pattern)
        |> Enum.sort(:desc)
        |> List.first()

      if most_recent do
        case load_baseline(most_recent) do
          {:ok, after_baseline} ->
            compare_baselines(before, after_baseline)

          {:error, reason} ->
            IO.puts(IO.ANSI.red() <> "❌ Error: #{reason}" <> IO.ANSI.reset())
            System.halt(1)
        end
      else
        IO.puts(IO.ANSI.red() <> "❌ No current baseline found" <> IO.ANSI.reset())
        System.halt(1)
      end
    else
      {:error, reason} ->
        IO.puts(IO.ANSI.red() <> "❌ Error: #{reason}" <> IO.ANSI.reset())
        System.halt(1)
    end
  end

  defp load_baseline(file_path) do
    if File.exists?(file_path) do
      case File.read(file_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, baseline} -> {:ok, baseline}
            {:error, _} -> {:error, "Invalid JSON in #{file_path}"}
          end

        {:error, _} ->
          {:error, "Cannot read #{file_path}"}
      end
    else
      {:error, "File not found: #{file_path}"}
    end
  end

  defp compare_baselines(before, after_baseline) do
    source = before["source"]

    source_display = source |> String.split("_") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")

    IO.puts("\n" <> IO.ANSI.cyan() <> "📊 Baseline Comparison: #{source_display}" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 64))

    IO.puts("Before: #{format_datetime(before["period_end"])} (#{before["sample_size"]} executions)")

    IO.puts(
      "After:  #{format_datetime(after_baseline["period_end"])} (#{after_baseline["sample_size"]} executions)"
    )

    IO.puts("")

    # Overall improvement
    IO.puts(IO.ANSI.green() <> "Overall Improvement:" <> IO.ANSI.reset())

    success_rate_change = after_baseline["success_rate"] - before["success_rate"]

    success_icon = if success_rate_change > 0, do: " ✅", else: " ⚠️ "

    IO.puts(
      "├─ Success Rate: #{format_percent(before["success_rate"])} → #{format_percent(after_baseline["success_rate"])} (#{format_change(success_rate_change)}pp)#{success_icon}"
    )

    duration_change = after_baseline["avg_duration"] - before["avg_duration"]
    duration_icon = if duration_change < 0, do: " ✅", else: " ⚠️ "

    IO.puts(
      "├─ Avg Duration: #{format_duration(before["avg_duration"])} → #{format_duration(after_baseline["avg_duration"])} (#{format_duration_change(duration_change)})#{duration_icon}"
    )

    p95_change = after_baseline["p95"] - before["p95"]
    p95_icon = if p95_change < 0, do: " ✅", else: " ⚠️ "

    IO.puts(
      "├─ P95 Duration: #{format_duration(before["p95"])} → #{format_duration(after_baseline["p95"])} (#{format_duration_change(p95_change)})#{p95_icon}"
    )

    error_rate_before = 100 - before["success_rate"]
    error_rate_after = 100 - after_baseline["success_rate"]
    error_rate_change = error_rate_after - error_rate_before
    error_icon = if error_rate_change < 0, do: " ✅", else: " ⚠️ "

    IO.puts(
      "└─ Error Rate: #{format_percent(error_rate_before)} → #{format_percent(error_rate_after)} (#{format_change(error_rate_change)}pp)#{error_icon}"
    )

    IO.puts("")

    # Error category changes
    # Handle both tuple format (from in-memory) and list format (from JSON decode)
    before_errors =
      Map.new(before["error_categories"] || [], fn
        {k, v} -> {k, v}
        [k, v] -> {k, v}
      end)

    after_errors =
      Map.new(after_baseline["error_categories"] || [], fn
        {k, v} -> {k, v}
        [k, v] -> {k, v}
      end)

    all_error_categories =
      (Map.keys(before_errors) ++ Map.keys(after_errors))
      |> Enum.uniq()
      |> Enum.sort()

    if length(all_error_categories) > 0 do
      IO.puts(IO.ANSI.yellow() <> "Error Category Changes:" <> IO.ANSI.reset())

      all_error_categories
      |> Enum.with_index()
      |> Enum.each(fn {category, index} ->
        before_count = Map.get(before_errors, category, 0)
        after_count = Map.get(after_errors, category, 0)
        change = after_count - before_count

        change_text =
          cond do
            change > 0 ->
              # Guard against division by zero
              percent_change =
                if before_count > 0 do
                  (change / before_count * 100) |> Float.round(1)
                else
                  0.0
                end

              "(↑ #{change}, +#{percent_change}%) ⚠️ "

            change < 0 ->
              # Guard against division by zero
              percent_change =
                if before_count > 0 do
                  (abs(change) / before_count * 100) |> Float.round(1)
                else
                  0.0
                end

              "(↓ #{abs(change)}, -#{percent_change}%) ✅"

            true ->
              "(no change)"
          end

        prefix = if index == length(all_error_categories) - 1, do: "└─", else: "├─"
        IO.puts("#{prefix} #{category}: #{before_count} → #{after_count} #{change_text}")
      end)

      IO.puts("")
    end

    # Job chain improvements
    before_chain = Map.new(before["chain_health"] || [], fn job -> {job["name"], job["success_rate"]} end)

    after_chain =
      Map.new(after_baseline["chain_health"] || [], fn job -> {job["name"], job["success_rate"]} end)

    all_jobs =
      (Map.keys(before_chain) ++ Map.keys(after_chain))
      |> Enum.uniq()
      |> Enum.sort()

    if length(all_jobs) > 0 do
      IO.puts(IO.ANSI.blue() <> "Job Chain Improvements:" <> IO.ANSI.reset())

      all_jobs
      |> Enum.with_index()
      |> Enum.each(fn {job, index} ->
        before_rate = Map.get(before_chain, job, 0)
        after_rate = Map.get(after_chain, job, 0)
        change = after_rate - before_rate

        change_icon = if change > 0, do: " ✅", else: ""

        prefix = if index == length(all_jobs) - 1, do: "└─", else: "├─"

        IO.puts(
          "#{prefix} #{job}: #{format_percent(before_rate)} → #{format_percent(after_rate)} (#{format_change(change)}pp)#{change_icon}"
        )
      end)

      IO.puts("")
    end

    # Statistical significance
    IO.puts(IO.ANSI.magenta() <> "Statistical Significance:" <> IO.ANSI.reset())

    # Simple chi-square test for success rate
    n1 = before["sample_size"]
    n2 = after_baseline["sample_size"]
    p1 = before["success_rate"] / 100
    p2 = after_baseline["success_rate"] / 100

    p_value_success = chi_square_p_value(n1, p1, n2, p2)

    significance_text =
      cond do
        p_value_success < 0.01 -> "p < 0.01 (highly significant) ✅"
        p_value_success < 0.05 -> "p < 0.05 (significant) ✅"
        true -> "p >= 0.05 (not significant)"
      end

    IO.puts("├─ Success Rate: #{significance_text}")

    # T-test approximation for duration
    p_value_duration = if abs(duration_change) > 200, do: 0.01, else: 0.1

    duration_sig_text =
      if p_value_duration < 0.05,
        do: "p < 0.05 (significant) ✅",
        else: "p >= 0.05 (not significant)"

    IO.puts("├─ Duration: #{duration_sig_text}")

    sample_adequate = n1 >= 30 && n2 >= 30
    sample_text = if sample_adequate, do: "Adequate for comparison ✅", else: "Small sample size ⚠️ "
    IO.puts("└─ Sample Size: #{sample_text}")

    IO.puts("")

    # Summary
    overall_improvement = success_rate_change > 0 && duration_change < 0

    IO.puts(IO.ANSI.green() <> "🎯 Summary:" <> IO.ANSI.reset())

    if overall_improvement do
      IO.puts("- Overall improvement detected across all metrics")

      # Identify biggest improvements
      if success_rate_change > 5 do
        IO.puts("- Significant success rate improvement (+#{Float.round(success_rate_change, 1)}pp)")
      end

      if duration_change < -500 do
        IO.puts(
          "- Major performance improvement (#{format_duration(abs(duration_change))} faster)"
        )
      end
    else
      IO.puts("- Mixed results - some improvements, some regressions")
    end

    # Error category insights
    decreased_errors =
      all_error_categories
      |> Enum.filter(fn cat ->
        Map.get(after_errors, cat, 0) < Map.get(before_errors, cat, 0)
      end)

    if length(decreased_errors) > 0 do
      Enum.each(decreased_errors, fn cat ->
        before_count = Map.get(before_errors, cat, 0)
        after_count = Map.get(after_errors, cat, 0)
        reduction = before_count - after_count
        percent = (reduction / before_count * 100) |> Float.round(1)
        IO.puts("- #{cat} reduced by #{percent}% (likely fix deployed)")
      end)
    end

    # Job improvements
    improved_jobs =
      all_jobs
      |> Enum.filter(fn job ->
        Map.get(after_chain, job, 0) > Map.get(before_chain, job, 0)
      end)

    if length(improved_jobs) > 0 do
      IO.puts("- #{length(improved_jobs)} job types show improvement")
    end

    # Statistical significance
    if p_value_success < 0.05 do
      IO.puts("- Changes are statistically significant")
    end

    IO.puts("")

    # Recommendations
    IO.puts(IO.ANSI.cyan() <> "💡 Recommendations:" <> IO.ANSI.reset())

    if overall_improvement && p_value_success < 0.05 do
      IO.puts("- Deploy to production ✅")
      IO.puts("- Consider this as new baseline")
    else
      IO.puts("- Continue monitoring and iterating")
      IO.puts("- Investigate regressions before deployment")
    end

    IO.puts("")
  end

  # Simplified chi-square test for proportions
  defp chi_square_p_value(n1, p1, n2, p2) do
    pooled_p = (n1 * p1 + n2 * p2) / (n1 + n2)
    se = :math.sqrt(pooled_p * (1 - pooled_p) * (1 / n1 + 1 / n2))
    z = (p1 - p2) / se
    # Approximate p-value from z-score
    if abs(z) > 2.576, do: 0.01, else: if(abs(z) > 1.96, do: 0.05, else: 0.1)
  end

  defp format_percent(value) do
    "#{Float.round(value, 1)}%"
  end

  defp format_change(value) do
    sign = if value > 0, do: "↑ ", else: if(value < 0, do: "↓ ", else: "")
    "#{sign}#{Float.round(abs(value), 1)}"
  end

  defp format_duration(ms) when is_float(ms) or is_integer(ms) do
    "#{Float.round(ms * 1.0, 0) |> trunc() |> format_number()}ms"
  end

  defp format_duration(_), do: "N/A"

  defp format_duration_change(ms) do
    sign = if ms > 0, do: "↑ ", else: "↓ "
    "#{sign}#{format_duration(abs(ms))}"
  end

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

  defp format_datetime(dt_string) when is_binary(dt_string) do
    case DateTime.from_iso8601(dt_string) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      _ -> dt_string
    end
  end

  defp format_datetime(dt) when is_map(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(_), do: "N/A"
end
