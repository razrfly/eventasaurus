#!/usr/bin/env elixir

# Script to collect baseline data for scrapers with actual execution data

alias EventasaurusDiscovery.Monitoring.{Baseline, Errors, Health}

defmodule BaselineCollector do
  def collect_for_source(source_name) do
    IO.puts("📊 Collecting #{source_name} Baseline Data...")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("")

    # Create baseline (all available data, up to 500 executions)
    case Baseline.create(source_name, hours: 720, limit: 500) do
      {:ok, baseline} ->
        # Save baseline
        {:ok, filepath} = Baseline.save(baseline, source_name)

        IO.puts("✅ Baseline Created")
        IO.puts("   Saved to: #{filepath}")
        IO.puts("   Sample size: #{baseline["sample_size"]} executions")
        IO.puts("   Success rate: #{Float.round(baseline["success_rate"], 1)}%")
        IO.puts("   Failed: #{baseline["failed"]}")
        IO.puts("   Cancelled: #{baseline["cancelled"]}")
        IO.puts("   Avg duration: #{Float.round(baseline["avg_duration"], 0)}ms")
        IO.puts("   P50: #{Float.round(baseline["p50"], 0)}ms")
        IO.puts("   P95: #{Float.round(baseline["p95"], 0)}ms")
        IO.puts("   P99: #{Float.round(baseline["p99"], 0)}ms")
        IO.puts("")

        # Chain health
        if baseline["chain_health"] && length(baseline["chain_health"]) > 0 do
          IO.puts("✅ Chain Health (by job type):")
          Enum.each(baseline["chain_health"], fn job ->
            IO.puts("   #{job["name"]}: #{Float.round(job["success_rate"], 1)}% (#{job["total"]} executions)")
          end)
          IO.puts("")
        end

        # Get error analysis
        case Errors.analyze(source_name, hours: 720, limit: 50) do
          {:ok, analysis} ->
            summary = Errors.summary(analysis)
            IO.puts("✅ Error Analysis")
            IO.puts("   Total failures: #{summary.total_failures} out of #{summary.total_executions} executions")
            IO.puts("   Error rate: #{Float.round(summary.error_rate, 1)}%")
            IO.puts("   Top category: #{summary.top_category || "none"}")
            IO.puts("   Unique error types: #{summary.unique_error_types}")
            IO.puts("")

            # Show error categories
            if length(analysis.category_distribution) > 0 do
              IO.puts("   Error Categories:")
              Enum.take(analysis.category_distribution, 5)
              |> Enum.each(fn {category, count} ->
                percentage = count / summary.total_failures * 100
                IO.puts("   - #{category}: #{count} (#{Float.round(percentage, 1)}%)")
              end)
              IO.puts("")
            end

            # Show top error messages
            if length(analysis.error_messages) > 0 do
              IO.puts("   Top Error Messages:")
              Enum.take(analysis.error_messages, 5)
              |> Enum.each(fn {{category, message}, count} ->
                IO.puts("   - [#{category}] #{String.slice(message, 0..60)}: #{count} occurrences")
              end)
              IO.puts("")
            end

          {:error, reason} ->
            IO.puts("⚠️  Error analysis: #{inspect(reason)}")
            IO.puts("")
        end

        # Get health check
        case Health.check(source_name, hours: 720) do
          {:ok, health} ->
            score = Health.score(health)
            IO.puts("✅ Health Check")
            IO.puts("   Health score: #{Float.round(score, 1)}/100")
            IO.puts("   Meeting SLOs: #{health.meeting_slos}")
            IO.puts("   SLO Targets: #{health.slo_targets.success_rate}% success, #{health.slo_targets.p95_duration}ms P95")
            IO.puts("")

            # Show degraded workers
            degraded = Health.degraded_workers(health, threshold: 90.0)
            if length(degraded) > 0 do
              IO.puts("   ⚠️  Degraded Workers (<90% success):")
              Enum.each(degraded, fn {name, rate} ->
                IO.puts("   - #{name}: #{Float.round(rate, 1)}%")
              end)
              IO.puts("")
            end

            # Show recent failures
            recent = Health.recent_failures(health, limit: 3)
            if length(recent) > 0 do
              IO.puts("   Recent Failures:")
              Enum.each(recent, fn failure ->
                IO.puts("   - #{failure.worker} (#{failure.error_category})")
              end)
              IO.puts("")
            end

          {:error, reason} ->
            IO.puts("⚠️  Health check: #{inspect(reason)}")
            IO.puts("")
        end

        {:ok, baseline, filepath}

      {:error, :no_executions} ->
        IO.puts("⚠️  No executions found for #{source_name}")
        IO.puts("")
        {:error, :no_executions}

      {:error, reason} ->
        IO.puts("❌ Baseline creation failed: #{inspect(reason)}")
        IO.puts("")
        {:error, reason}
    end
  end
end

# Collect baselines for sources with actual data
IO.puts("")
IO.puts("🎯 SCRAPER BASELINE COLLECTION")
IO.puts("=" |> String.duplicate(60))
IO.puts("")
IO.puts("NOTE: Collecting data for sources with actual execution history")
IO.puts("")

# Inquizition (has 96 executions)
inquizition_result = BaselineCollector.collect_for_source("inquizition")

IO.puts("")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# Waw4Free (has 1 execution)
waw4free_result = BaselineCollector.collect_for_source("waw4free")

IO.puts("")
IO.puts("=" |> String.duplicate(60))
IO.puts("")
IO.puts("✅ Baseline collection complete!")
IO.puts("")

# Summary
case {inquizition_result, waw4free_result} do
  {{:ok, _, inquizition_path}, {:ok, _, waw4free_path}} ->
    IO.puts("Baseline files saved:")
    IO.puts("- #{inquizition_path}")
    IO.puts("- #{waw4free_path}")

  {{:ok, _, inquizition_path}, _} ->
    IO.puts("Baseline files saved:")
    IO.puts("- #{inquizition_path}")
    IO.puts("⚠️  Waw4Free baseline could not be collected (insufficient data)")

  _ ->
    IO.puts("⚠️  Some baselines could not be collected")
end

IO.puts("")
