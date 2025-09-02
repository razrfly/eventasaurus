IO.puts "=== Phase 2: Testing Query Batching Optimization ==="
IO.puts "User: holden@gmail.com (ID: 2)"
IO.puts "Testing new batched count query...\n"

# Test the new function directly first
user = EventasaurusApp.Accounts.get_user!(2)
{time_us, counts} = :timer.tc(fn ->
  EventasaurusApp.Events.get_dashboard_filter_counts(user)
end)

time_ms = time_us / 1000
IO.puts "Single Batched Query Result:"
IO.puts "  Time: #{Float.round(time_ms, 2)}ms"
IO.puts "  Counts: #{inspect(counts)}"

IO.puts "\n=== Running Full Benchmark with Phase 2 Optimization ==="

# Run benchmark with optimization
phase2_results = EventasaurusApp.PerformanceBenchmark.benchmark_dashboard_load(2, iterations: 10)

IO.puts "=== Phase 2 Results Summary ==="
IO.puts "Average Total Load Time: #{Float.round(phase2_results.avg_total_time_ms, 1)}ms"
IO.puts "Average Query Times:"
IO.puts "  • Upcoming Events: #{Float.round(phase2_results.avg_upcoming_query_ms, 1)}ms"
IO.puts "  • Past Events: #{Float.round(phase2_results.avg_past_query_ms, 1)}ms"  
IO.puts "  • Archived Events: #{Float.round(phase2_results.avg_archived_query_ms, 1)}ms"
IO.puts "  • Filter Counts (OPTIMIZED): #{Float.round(phase2_results.avg_filter_counts_ms, 1)}ms"

# Load baseline for comparison
baseline_results = "baseline_results.json"
|> File.read!()
|> Jason.decode!(keys: :atoms)

# Compare results
improvement = EventasaurusApp.PerformanceBenchmark.compare_benchmarks(
  baseline_results, 
  phase2_results, 
  "Phase 2: Query Batching"
)

# Save Phase 2 results
File.write!("phase2_results.json", Jason.encode!(phase2_results, pretty: true))
IO.puts "\n✅ Phase 2 results saved to phase2_results.json"