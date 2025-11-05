#!/usr/bin/env elixir

# Verify Speed Quizzing time quality improvement after fixes
# Compares before vs after metrics

alias EventasaurusDiscovery.Admin.DataQualityChecker

IO.puts("=" |> String.duplicate(100))
IO.puts("SPEED QUIZZING TIME QUALITY VERIFICATION")
IO.puts("=" |> String.duplicate(100))
IO.puts("")

# Run quality check on Speed Quizzing
slug = "speed-quizzing"

IO.puts("Running quality check on #{slug}...")
report = DataQualityChecker.check_quality(slug)

# Extract time metrics
time_metrics = get_in(report, [:occurrence_metrics, :time_quality_metrics]) || %{}

# Normalize percentage values (handles Decimal, integer, float, nil)
normalize_pct = fn
  nil -> 0.0
  %Decimal{} = value -> Decimal.to_float(value)
  value when is_integer(value) -> value / 1.0
  value when is_float(value) -> value
end

# Display current metrics
IO.puts("\n📊 CURRENT METRICS")
IO.puts("-" |> String.duplicate(100))
IO.puts("Total Events: #{report[:total_events] || 0}")
IO.puts("Events with Times: #{time_metrics[:total_occurrences] || 0}")

time_quality = normalize_pct.(time_metrics[:time_quality])
IO.puts("Time Quality Score: #{Float.round(time_quality, 1)}%")

diversity_float = normalize_pct.(time_metrics[:time_diversity_score])
IO.puts("Time Diversity: #{Float.round(diversity_float, 1)}%")

# Display time distribution
IO.puts("\n⏰ TIME DISTRIBUTION")
IO.puts("-" |> String.duplicate(100))

hour_dist = time_metrics[:hour_distribution] || %{}
total = time_metrics[:total_occurrences] || 1

# Sort by count descending
sorted_times = hour_dist
  |> Enum.sort_by(fn {_hour, count} -> -count end)
  |> Enum.take(15)

IO.puts("  #{"Hour"} #{"Count"} #{"Percentage"} #{"Bar"}")

Enum.each(sorted_times, fn {hour, count} ->
  percentage = (count / total * 100) |> Float.round(1)
  bar_length = trunc(percentage / 2)
  bar = "█" |> String.duplicate(bar_length)

  hour_str = String.pad_leading("#{hour}:00", 5)
  count_str = String.pad_leading("#{count}", 6)
  pct_str = String.pad_leading("#{percentage}%", 7)

  IO.puts("  #{hour_str} #{count_str} events #{pct_str} #{bar}")
end)

# Calculate midnight percentage
midnight_count = Map.get(hour_dist, 0, 0)
midnight_pct = if total > 0, do: (midnight_count / total * 100) |> Float.round(1), else: 0

IO.puts("\n🌙 MIDNIGHT ANALYSIS")
IO.puts("-" |> String.duplicate(100))
IO.puts("Midnight (00:00) Events: #{midnight_count} (#{midnight_pct}%)")

# Compare with baseline
IO.puts("\n📈 IMPROVEMENT ANALYSIS")
IO.puts("-" |> String.duplicate(100))
IO.puts("BEFORE: 59% time quality, 40.5% midnight, 48% diversity")
IO.puts("AFTER:  #{Float.round(time_quality, 1)}% time quality, #{midnight_pct}% midnight, #{Float.round(diversity_float, 1)}% diversity")

# Calculate improvements (using normalized float values)
time_qual_improvement = time_quality - 59.0
midnight_improvement = 40.5 - midnight_pct
diversity_improvement = Float.round(diversity_float, 1) - 48.0

if time_qual_improvement > 0 do
  IO.puts("✅ Time Quality: +#{:erlang.float_to_binary(time_qual_improvement, [:compact, decimals: 1])}%")
else
  IO.puts("⚠️  Time Quality: #{:erlang.float_to_binary(time_qual_improvement, [:compact, decimals: 1])}%")
end

if midnight_improvement > 0 do
  IO.puts("✅ Midnight Reduction: -#{:erlang.float_to_binary(midnight_improvement, [:compact, decimals: 1])}%")
else
  IO.puts("⚠️  Midnight Increase: +#{:erlang.float_to_binary(abs(midnight_improvement), [:compact, decimals: 1])}%")
end

if diversity_improvement > 0 do
  IO.puts("✅ Diversity: +#{:erlang.float_to_binary(diversity_improvement, [:compact, decimals: 1])}%")
else
  IO.puts("⚠️  Diversity: #{:erlang.float_to_binary(diversity_improvement, [:compact, decimals: 1])}%")
end

IO.puts("\n" <> ("=" |> String.duplicate(100)))
