IO.puts "=== Phase 1: Baseline Performance Measurement ==="
IO.puts "User: holden@gmail.com (ID: 2)"
IO.puts "Testing with current indexes...\n"

baseline_results = EventasaurusApp.PerformanceBenchmark.benchmark_dashboard_load(2, iterations: 10)

IO.puts "=== Baseline Results Summary ==="
IO.puts "Average Total Load Time: #{Float.round(baseline_results.avg_total_time_ms, 1)}ms"
IO.puts "Average Query Times:"
IO.puts "  • Upcoming Events: #{Float.round(baseline_results.avg_upcoming_query_ms, 1)}ms"
IO.puts "  • Past Events: #{Float.round(baseline_results.avg_past_query_ms, 1)}ms"  
IO.puts "  • Archived Events: #{Float.round(baseline_results.avg_archived_query_ms, 1)}ms"
IO.puts "  • Filter Counts: #{Float.round(baseline_results.avg_filter_counts_ms, 1)}ms"

IO.puts "\nEvent Counts:"
IO.puts "  • Upcoming: #{baseline_results.event_counts.upcoming}"
IO.puts "  • Past: #{baseline_results.event_counts.past}"
IO.puts "  • Archived: #{baseline_results.event_counts.archived}"
IO.puts "  • Created: #{baseline_results.event_counts.created}"
IO.puts "  • Participating: #{baseline_results.event_counts.participating}"
IO.puts "  • Total Events Loaded: #{baseline_results.total_events_loaded}"

# Store baseline for comparison
File.write!("baseline_results.json", Jason.encode!(baseline_results, pretty: true))
IO.puts "\n✅ Baseline results saved to baseline_results.json"