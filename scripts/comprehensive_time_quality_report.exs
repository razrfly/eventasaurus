# Comprehensive Time Quality Report for All Sources
alias EventasaurusDiscovery.Admin.DataQualityChecker
alias EventasaurusApp.Repo

IO.puts("\n" <> String.duplicate("=", 100))
IO.puts("COMPREHENSIVE TIME QUALITY REPORT - ALL ACTIVE SOURCES")
IO.puts(String.duplicate("=", 100) <> "\n")

# Get all active sources from database
query = "SELECT id, slug, name FROM sources WHERE is_active = true ORDER BY slug"
{:ok, result} = Repo.query(query)

sources = Enum.map(result.rows, fn [id, slug, name] -> {id, slug, name} end)

IO.puts("Found #{length(sources)} active sources\n")

# Collect results
results = Enum.map(sources, fn {id, slug, name} ->
  try do
    report = DataQualityChecker.check_quality(slug)
    time_metrics = get_in(report, [:occurrence_metrics, :time_quality_metrics]) || %{}

    %{
      id: id,
      slug: slug,
      name: name,
      event_count: report[:total_events] || 0,
      overall_score: report[:quality_score],
      time_quality_score: time_metrics[:time_quality] || 0,
      time_diversity: time_metrics[:time_diversity_score] || 0.0,
      events_with_times: time_metrics[:total_occurrences] || 0,
      time_distribution: time_metrics[:hour_distribution] || %{},
      suspicious_patterns: []
    }
  rescue
    e ->
      IO.puts("Error checking #{name}: #{inspect(e)}")
      %{
        id: id,
        slug: slug,
        name: name,
        event_count: 0,
        overall_score: nil,
        time_quality_score: 0,
        time_diversity: 0.0,
        events_with_times: 0,
        time_distribution: [],
        suspicious_patterns: []
      }
  end
end)

# Filter to only sources with events
results_with_events = Enum.filter(results, fn r -> r.event_count > 0 end)
results_without_events = Enum.filter(results, fn r -> r.event_count == 0 end)

# Sort by event count (desc)
sorted_results = Enum.sort_by(results_with_events, & &1.event_count, :desc)

IO.puts("\n📊 SUMMARY TABLE - SOURCES WITH EVENTS")
IO.puts(String.duplicate("-", 100))
IO.puts(
  String.pad_trailing("Source", 22) <> 
  String.pad_trailing("Events", 10) <> 
  String.pad_trailing("Overall", 10) <> 
  String.pad_trailing("Time Qual", 12) <> 
  String.pad_trailing("Diversity", 12) <> 
  "Status"
)
IO.puts(String.duplicate("-", 100))

Enum.each(sorted_results, fn r ->
  overall_str = if r.overall_score, do: "#{r.overall_score}%", else: "N/A"
  time_qual_str = if r.time_quality_score > 0, do: "#{r.time_quality_score}%", else: "N/A"
  diversity_str = if r.time_diversity > 0 do
    diversity_float = if is_float(r.time_diversity), do: r.time_diversity, else: r.time_diversity / 1.0
    "#{Float.round(diversity_float, 1)}%"
  else
    "N/A"
  end
  
  status = cond do
    r.time_quality_score < 70 && r.time_quality_score > 0 -> "⚠️  ISSUES"
    r.time_diversity < 30 && r.time_quality_score > 0 -> "⚠️  LOW DIV"
    r.time_quality_score >= 90 -> "✅ GOOD"
    r.time_quality_score >= 70 -> "🟡 OK"
    r.time_quality_score > 0 -> "🟠 POOR"
    true -> "❌ N/A"
  end
  
  IO.puts(
    String.pad_trailing(r.name, 22) <>
    String.pad_trailing("#{r.event_count}", 10) <>
    String.pad_trailing(overall_str, 10) <>
    String.pad_trailing(time_qual_str, 12) <>
    String.pad_trailing(diversity_str, 12) <>
    status
  )
end)

IO.puts(String.duplicate("-", 100))
IO.puts("Total sources with events: #{length(sorted_results)}")
IO.puts("Total sources without events: #{length(results_without_events)}")

# Detailed analysis for each source with events
IO.puts("\n\n📈 DETAILED TIME QUALITY ANALYSIS")
IO.puts(String.duplicate("=", 100))

Enum.each(sorted_results, fn r ->
  IO.puts("\n#{r.name} (#{r.slug})")
  IO.puts(String.duplicate("-", 100))
  IO.puts("  Total Events: #{r.event_count}")
  IO.puts("  Events with Times: #{r.events_with_times}")
  IO.puts("  Overall Quality: #{r.overall_score}%")
  IO.puts("  Time Quality Score: #{r.time_quality_score}%")
  diversity_float = if is_float(r.time_diversity), do: r.time_diversity, else: r.time_diversity / 1.0
  IO.puts("  Time Diversity: #{Float.round(diversity_float, 1)}%")
  
  if map_size(r.time_distribution) > 0 do
    IO.puts("\n  Time Distribution (Top 10):")
    r.time_distribution
    |> Enum.sort_by(fn {_hour, count} -> count end, :desc)
    |> Enum.take(10)
    |> Enum.each(fn {hour, count} ->
      pct = if r.events_with_times > 0, do: Float.round(count / r.events_with_times * 100, 1), else: 0.0
      bar = String.duplicate("█", round(pct / 2))
      time_str = "#{String.pad_leading(to_string(hour), 2, "0")}:00"
      IO.puts("    #{String.pad_trailing(time_str, 8)} #{String.pad_leading("#{count}", 4)} events (#{String.pad_leading("#{pct}%", 6)}) #{bar}")
    end)
  end
  
  # Check for quality issues
  issues = []
  issues = if r.time_quality_score < 70 && r.time_quality_score > 0, do: issues ++ ["Low time quality score (#{r.time_quality_score}%)"], else: issues
  issues = if r.time_diversity < 30 && r.time_diversity > 0 do
    div_float = if is_float(r.time_diversity), do: r.time_diversity, else: r.time_diversity / 1.0
    issues ++ ["Low time diversity (#{Float.round(div_float, 1)}%)"]
  else
    issues
  end

  if length(issues) > 0 do
    IO.puts("\n  ⚠️  Quality Issues:")
    Enum.each(issues, fn issue -> IO.puts("    - #{issue}") end)
  else
    IO.puts("\n  ✅ No time quality issues detected")
  end
end)

# Summary statistics
if length(sorted_results) > 0 do
  IO.puts("\n\n📊 OVERALL STATISTICS")
  IO.puts(String.duplicate("=", 100))
  
  total_events = Enum.reduce(sorted_results, 0, fn r, acc -> acc + r.event_count end)
  avg_time_quality = Enum.reduce(sorted_results, 0, fn r, acc -> acc + r.time_quality_score end) / length(sorted_results)
  avg_diversity = Enum.reduce(sorted_results, 0.0, fn r, acc -> acc + r.time_diversity end) / length(sorted_results)
  
  sources_with_issues = Enum.count(sorted_results, fn r -> r.time_quality_score < 70 || r.time_diversity < 30 end)
  sources_excellent = Enum.count(sorted_results, fn r -> r.time_quality_score >= 90 end)
  sources_good = Enum.count(sorted_results, fn r -> r.time_quality_score >= 70 && r.time_quality_score < 90 end)
  sources_poor = Enum.count(sorted_results, fn r -> r.time_quality_score > 0 && r.time_quality_score < 70 end)
  
  IO.puts("Total Events Across All Sources: #{total_events}")
  IO.puts("Average Time Quality Score: #{Float.round(avg_time_quality, 1)}%")
  IO.puts("Average Time Diversity: #{Float.round(avg_diversity, 1)}%")
  IO.puts("\nSource Distribution:")
  IO.puts("  ✅ Excellent (90%+): #{sources_excellent} sources")
  IO.puts("  🟡 Good (70-89%): #{sources_good} sources")
  IO.puts("  🟠 Poor (<70%): #{sources_poor} sources")
  IO.puts("  ⚠️  With Issues: #{sources_with_issues} sources")
end

# List sources without events
if length(results_without_events) > 0 do
  IO.puts("\n\n📝 SOURCES WITHOUT EVENTS")
  IO.puts(String.duplicate("-", 100))
  Enum.each(results_without_events, fn r ->
    IO.puts("  - #{r.name} (#{r.slug})")
  end)
end

IO.puts("\n" <> String.duplicate("=", 100))
IO.puts("END OF REPORT")
IO.puts(String.duplicate("=", 100) <> "\n")
