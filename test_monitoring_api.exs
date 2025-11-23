#!/usr/bin/env elixir

# Test script for programmatic monitoring API

alias EventasaurusDiscovery.Monitoring.{Baseline, Errors, Health, Chain, Compare}

IO.puts("Testing Monitoring API...")
IO.puts("")

# Test Baseline
IO.puts("1. Testing Baseline.create/2...")

case Baseline.create("inquizition", hours: 24, limit: 100) do
  {:ok, baseline} ->
    IO.puts("   ✅ Baseline created:")
    IO.puts("      - Sample size: #{baseline.sample_size} executions")
    IO.puts("      - Success rate: #{Float.round(baseline.success_rate, 1)}%")
    IO.puts("      - Avg duration: #{Float.round(baseline.avg_duration, 0)}ms")

  {:error, reason} ->
    IO.puts("   ❌ Error: #{inspect(reason)}")
end

IO.puts("")

# Test Health
IO.puts("2. Testing Health.check/2...")

case Health.check("inquizition", hours: 24) do
  {:ok, health} ->
    score = Health.score(health)
    IO.puts("   ✅ Health checked:")
    IO.puts("      - Health score: #{Float.round(score, 1)}/100")
    IO.puts("      - Success rate: #{Float.round(health.success_rate, 1)}%")
    IO.puts("      - Meeting SLOs: #{health.meeting_slos}")

  {:error, reason} ->
    IO.puts("   ❌ Error: #{inspect(reason)}")
end

IO.puts("")

# Test Errors
IO.puts("3. Testing Errors.analyze/2...")

case Errors.analyze("inquizition", hours: 24) do
  {:ok, analysis} ->
    summary = Errors.summary(analysis)
    IO.puts("   ✅ Errors analyzed:")
    IO.puts("      - Total failures: #{analysis.total_failures}")
    IO.puts("      - Total executions: #{analysis.total_executions}")
    IO.puts("      - Error rate: #{Float.round(analysis.error_rate, 1)}%")

  {:error, reason} ->
    IO.puts("   ❌ Error: #{inspect(reason)}")
end

IO.puts("")

# Test Chain (if there are recent sync jobs)
IO.puts("4. Testing Chain.recent_chains/2...")

case Chain.recent_chains("inquizition", limit: 1) do
  {:ok, chains} when length(chains) > 0 ->
    chain = hd(chains)
    stats = Chain.statistics(chain)
    IO.puts("   ✅ Chain analyzed:")
    IO.puts("      - Total jobs in chain: #{stats.total}")
    IO.puts("      - Completed: #{stats.completed}")
    IO.puts("      - Chain success rate: #{Float.round(stats.success_rate, 1)}%")

  {:ok, []} ->
    IO.puts("   ⚠️  No chains found")

  {:error, reason} ->
    IO.puts("   ❌ Error: #{inspect(reason)}")
end

IO.puts("")

# Test Compare (using baseline files if they exist)
IO.puts("5. Testing Compare.from_files/2...")

baseline_dir = Path.join([File.cwd!(), ".taskmaster", "baselines"])

case File.ls(baseline_dir) do
  {:ok, files} ->
    baseline_files =
      files
      |> Enum.filter(&String.starts_with?(&1, "inquizition_"))
      |> Enum.sort()

    if length(baseline_files) >= 2 do
      [before_file, after_file] = Enum.take(baseline_files, 2)
      before_path = Path.join(baseline_dir, before_file)
      after_path = Path.join(baseline_dir, after_file)

      case Compare.from_files(before_path, after_path) do
        {:ok, comparison} ->
          summary = Compare.summary(comparison)
          IO.puts("   ✅ Baselines compared:")
          IO.puts("      - Success rate change: #{Float.round(summary.success_rate_change, 1)}pp")
          IO.puts("      - Overall improved: #{summary.improved}")

        {:error, reason} ->
          IO.puts("   ❌ Error: #{inspect(reason)}")
      end
    else
      IO.puts("   ⚠️  Not enough baseline files (need at least 2)")
    end

  {:error, _} ->
    IO.puts("   ⚠️  Baseline directory not found")
end

IO.puts("")
IO.puts("✅ All tests completed!")
