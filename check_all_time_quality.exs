# Check time quality for all active sources
alias EventasaurusDiscovery.Admin.DataQualityChecker

sources = [
  {"bandsintown", "Bandsintown"},
  {"cinema-city", "Cinema City"},
  {"geeks-who-drink", "Geeks Who Drink"},
  {"inquizition", "Inquizition"},
  {"karnet", "Karnet Kraków"},
  {"kino-krakow", "Kino Krakow"},
  {"pubquiz-pl", "PubQuiz Poland"},
  {"question-one", "Question One"},
  {"quizmeisters", "Quizmeisters"},
  {"resident-advisor", "Resident Advisor"},
  {"sortiraparis", "Sortiraparis"},
  {"speed-quizzing", "Speed Quizzing"},
  {"ticketmaster", "Ticketmaster"},
  {"waw4free", "Waw4Free"}
]

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TIME QUALITY REPORT - ALL SOURCES")
IO.puts(String.duplicate("=", 80) <> "\n")

results = Enum.map(sources, fn {slug, name} ->
  try do
    report = DataQualityChecker.check_quality(slug)
    time_quality = get_in(report, [:dimensions, :time_quality])
    
    %{
      slug: slug,
      name: name,
      overall_score: report[:overall_score],
      event_count: report[:event_count],
      time_quality: time_quality || %{},
      issues: report[:issues] || []
    }
  rescue
    e ->
      IO.puts("⚠️  Error checking #{name}: #{inspect(e)}")
      %{
        slug: slug,
        name: name,
        overall_score: nil,
        event_count: 0,
        time_quality: %{},
        issues: []
      }
  end
end)

# Sort by event count (most events first)
sorted_results = Enum.sort_by(results, & &1.event_count, :desc)

# Print summary table
IO.puts("\n📊 SUMMARY TABLE")
IO.puts(String.duplicate("-", 80))
IO.puts(String.pad_trailing("Source", 25) <> 
        String.pad_trailing("Events", 10) <> 
        String.pad_trailing("Overall", 10) <> 
        String.pad_trailing("Time Quality", 15) <> 
        "Time Diversity")
IO.puts(String.duplicate("-", 80))

Enum.each(sorted_results, fn result ->
  time_score = result.time_quality[:time_quality] || 0
  time_diversity = result.time_quality[:time_diversity] || 0
  
  time_quality_str = if time_score > 0, do: "#{time_score}%", else: "N/A"
  time_diversity_str = if time_diversity > 0, do: "#{Float.round(time_diversity, 1)}%", else: "N/A"
  
  overall_str = if result.overall_score, do: "#{result.overall_score}%", else: "N/A"
  
  IO.puts(
    String.pad_trailing(result.name, 25) <>
    String.pad_trailing("#{result.event_count}", 10) <>
    String.pad_trailing(overall_str, 10) <>
    String.pad_trailing(time_quality_str, 15) <>
    time_diversity_str
  )
end)

IO.puts(String.duplicate("-", 80))

# Print detailed time quality analysis
IO.puts("\n\n📈 DETAILED TIME QUALITY ANALYSIS")
IO.puts(String.duplicate("=", 80))

Enum.each(sorted_results, fn result ->
  if result.event_count > 0 do
    IO.puts("\n#{result.name} (#{result.slug})")
    IO.puts(String.duplicate("-", 80))
    IO.puts("  Events: #{result.event_count}")
    IO.puts("  Overall Quality: #{result.overall_score}%")
    
    if map_size(result.time_quality) > 0 do
      IO.puts("\n  Time Quality Metrics:")
      IO.puts("    Time Quality Score: #{result.time_quality[:time_quality] || 0}%")
      IO.puts("    Time Diversity: #{Float.round(result.time_quality[:time_diversity] || 0.0, 1)}%")
      IO.puts("    Events with Times: #{result.time_quality[:events_with_times] || 0}/#{result.event_count}")
      
      if result.time_quality[:time_distribution] do
        IO.puts("\n  Time Distribution:")
        Enum.each(result.time_quality[:time_distribution], fn {time, count} ->
          pct = Float.round(count / result.event_count * 100, 1)
          IO.puts("    #{time}: #{count} events (#{pct}%)")
        end)
      end
      
      if result.time_quality[:suspicious_patterns] && length(result.time_quality[:suspicious_patterns]) > 0 do
        IO.puts("\n  ⚠️  Suspicious Patterns:")
        Enum.each(result.time_quality[:suspicious_patterns], fn pattern ->
          IO.puts("    - #{pattern}")
        end)
      end
    else
      IO.puts("\n  ℹ️  No time quality data available")
    end
    
    if length(result.issues) > 0 do
      time_issues = Enum.filter(result.issues, fn issue ->
        String.contains?(String.downcase(issue), ["time", "occurrence", "schedule"])
      end)
      
      if length(time_issues) > 0 do
        IO.puts("\n  ⚠️  Time-Related Issues:")
        Enum.each(time_issues, fn issue ->
          IO.puts("    - #{issue}")
        end)
      end
    end
  end
end)

IO.puts("\n\n" <> String.duplicate("=", 80))
IO.puts("END OF REPORT")
IO.puts(String.duplicate("=", 80) <> "\n")
