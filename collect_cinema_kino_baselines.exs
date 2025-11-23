#!/usr/bin/env elixir

# Script to collect baselines for Cinema City and Kino Krakow scrapers
# These are the target scrapers for Phase 2 baseline validation

alias EventasaurusDiscovery.Monitoring.Baseline
alias EventasaurusDiscovery.Monitoring.Health
alias EventasaurusDiscovery.Monitoring.Chain

IO.puts("\n🎯 Phase 2: Collecting Baselines for Cinema City and Kino Krakow\n")
IO.puts("=" <> String.duplicate("=", 79) <> "\n")

defmodule BaselineCollector do
  def collect_for_source(source_name, display_name) do
    IO.puts("📊 Collecting baseline for #{display_name}...")
    IO.puts("-" <> String.duplicate("-", 79))

    case Baseline.create(source_name, hours: 720, limit: 500) do
      {:ok, baseline} ->
        # Save baseline to file
        {:ok, filepath} = Baseline.save(baseline, source_name)

        # Display key metrics
        IO.puts("\n✅ Baseline collected successfully!")
        IO.puts("\n📈 Performance Metrics:")
        IO.puts("   Source: #{baseline.source}")
        IO.puts("   Sample Size: #{baseline.sample_size} executions")
        IO.puts("   Time Period: #{format_date(baseline.period_start)} to #{format_date(baseline.period_end)}")
        IO.puts("   Success Rate: #{Float.round(baseline.success_rate, 2)}%")
        IO.puts("   Completed: #{baseline.completed}")
        IO.puts("   Failed: #{baseline.failed}")
        IO.puts("   Cancelled: #{baseline.cancelled}")
        IO.puts("   Avg Duration: #{round(baseline.avg_duration)}ms")
        IO.puts("   P50: #{round(baseline.p50)}ms")
        IO.puts("   P95: #{round(baseline.p95)}ms")
        IO.puts("   P99: #{round(baseline.p99)}ms")
        IO.puts("   Std Dev: #{round(baseline.std_dev)}ms")
        IO.puts("   CI Margin: ±#{Float.round(baseline.ci_margin, 2)}%")

        # Display chain health
        if length(baseline.chain_health) > 0 do
          IO.puts("\n🔗 Job Chain Health:")
          Enum.each(baseline.chain_health, fn job ->
            success_rate = job["success_rate"] || 0.0
            status_icon = if success_rate >= 95.0, do: "✅", else: "⚠️ "
            IO.puts("   #{status_icon} #{job["name"]}: #{job["completed"]}/#{job["total"]} (#{Float.round(success_rate, 1)}%)")
          end)
        end

        # SLO compliance check
        IO.puts("\n📋 SLO Compliance:")
        success_slo = if baseline.success_rate >= 95.0, do: "✅", else: "⚠️ "
        p95_slo = if baseline.p95 <= 3000, do: "✅", else: "⚠️ "
        IO.puts("   #{success_slo} Success Rate: #{Float.round(baseline.success_rate, 2)}% (target: ≥95%)")
        IO.puts("   #{p95_slo} P95 Duration: #{round(baseline.p95)}ms (target: ≤3000ms)")

        # Error categories
        if length(baseline.error_categories) > 0 do
          IO.puts("\n🔍 Error Categories:")
          Enum.each(baseline.error_categories, fn {category, count} ->
            IO.puts("   - #{category}: #{count}")
          end)
        else
          IO.puts("\n🔍 Error Categories: None (MetricsTracker may not be enabled)")
        end

        IO.puts("\n💾 Baseline saved to: #{filepath}")
        IO.puts("\n" <> String.duplicate("=", 80) <> "\n")

        {:ok, baseline, filepath}

      {:error, :no_executions} ->
        IO.puts("\n❌ No executions found for #{display_name}")
        IO.puts("   This source may need to be run first to generate baseline data.\n")
        {:error, :no_executions}

      {:error, reason} ->
        IO.puts("\n❌ Error collecting baseline: #{inspect(reason)}\n")
        {:error, reason}
    end
  end

  defp format_date(%DateTime{} = dt) do
    DateTime.to_string(dt)
  end

  defp format_date(nil), do: "N/A"
end

# Collect Cinema City baseline
cinema_city_result = BaselineCollector.collect_for_source("cinema_city", "Cinema City")

# Collect Kino Krakow baseline
kino_krakow_result = BaselineCollector.collect_for_source("kino_krakow", "Kino Krakow")

# Summary
IO.puts("\n🎉 Phase 2 Baseline Collection Complete!\n")
IO.puts("=" <> String.duplicate("=", 79))

case {cinema_city_result, kino_krakow_result} do
  {{:ok, cc_baseline, cc_path}, {:ok, kk_baseline, kk_path}} ->
    IO.puts("\n✅ Both baselines collected successfully!")
    IO.puts("\nCinema City:")
    IO.puts("   Sample: #{cc_baseline.sample_size} executions")
    IO.puts("   Success: #{Float.round(cc_baseline.success_rate, 2)}%")
    IO.puts("   P95: #{round(cc_baseline.p95)}ms")
    IO.puts("   File: #{cc_path}")

    IO.puts("\nKino Krakow:")
    IO.puts("   Sample: #{kk_baseline.sample_size} executions")
    IO.puts("   Success: #{Float.round(kk_baseline.success_rate, 2)}%")
    IO.puts("   P95: #{round(kk_baseline.p95)}ms")
    IO.puts("   File: #{kk_path}")

    IO.puts("\n✅ Ready to create comprehensive baseline reports!")
    IO.puts("✅ Ready to create GitHub issue with findings!")

  _ ->
    IO.puts("\n⚠️  One or both baselines failed to collect.")
    IO.puts("   Review the errors above for details.")
end

IO.puts("\n" <> String.duplicate("=", 80) <> "\n")
