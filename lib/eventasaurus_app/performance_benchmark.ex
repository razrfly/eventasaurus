defmodule EventasaurusApp.PerformanceBenchmark do
  @moduledoc """
  Performance benchmarking utilities for measuring dashboard optimization phases.
  """
  
  alias EventasaurusApp.{Events, Accounts}
  require Logger

  @doc """
  Benchmarks dashboard load performance for a given user.
  
  Returns metrics including:
  - Total time
  - Individual query times
  - Query counts
  - Event counts by filter
  
  ## Options
  - `:iterations` - Number of iterations to run (default: 10)
  - `:log_results` - Whether to log results (default: true)
  """
  def benchmark_dashboard_load(user_id, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 10)
    log_results = Keyword.get(opts, :log_results, true)
    
    user = Accounts.get_user!(user_id)
    
    results = 
      1..iterations
      |> Enum.map(fn _i ->
        measure_dashboard_queries(user)
      end)
    
    # Calculate averages
    avg_results = calculate_averages(results)
    
    if log_results do
      log_benchmark_results(user, avg_results, iterations)
    end
    
    avg_results
  end
  
  defp measure_dashboard_queries(user) do
    start_time = System.monotonic_time(:millisecond)
    
    # Measure upcoming events query
    {upcoming_time, upcoming_events} = :timer.tc(fn ->
      Events.list_unified_events_for_user_optimized(user, [
        time_filter: :upcoming,
        ownership_filter: :all,
        limit: 50
      ])
    end)
    
    # Measure past events query  
    {past_time, past_events} = :timer.tc(fn ->
      Events.list_unified_events_for_user_optimized(user, [
        time_filter: :past,
        ownership_filter: :all,
        limit: 50
      ])
    end)
    
    # Measure archived events query
    {archived_time, archived_events} = :timer.tc(fn ->
      Events.list_deleted_events_by_user(user)
    end)
    
    # Measure filter counts using new optimized function
    {filter_counts_time, filter_counts} = :timer.tc(fn ->
      Events.get_dashboard_filter_counts(user)
    end)
    
    total_time = System.monotonic_time(:millisecond) - start_time
    
    %{
      total_time_ms: total_time,
      upcoming_query_us: upcoming_time,
      past_query_us: past_time, 
      archived_query_us: archived_time,
      filter_counts_us: filter_counts_time,
      event_counts: filter_counts,
      total_events_loaded: length(upcoming_events) + length(past_events) + length(archived_events)
    }
  end
  
  defp count_events_by_filter(user, time_filter, ownership_filter) do
    Events.list_unified_events_for_user_optimized(user, [
      time_filter: time_filter,
      ownership_filter: ownership_filter,
      limit: 1000
    ])
    |> length()
  end
  
  defp calculate_averages(results) do
    count = length(results)
    
    %{
      avg_total_time_ms: avg_field(results, :total_time_ms),
      avg_upcoming_query_ms: avg_field(results, :upcoming_query_us) / 1000,
      avg_past_query_ms: avg_field(results, :past_query_us) / 1000,
      avg_archived_query_ms: avg_field(results, :archived_query_us) / 1000,
      avg_filter_counts_ms: avg_field(results, :filter_counts_us) / 1000,
      iterations: count,
      event_counts: hd(results).event_counts,
      total_events_loaded: hd(results).total_events_loaded
    }
  end
  
  defp avg_field(results, field) do
    results
    |> Enum.map(&Map.get(&1, field))
    |> Enum.sum()
    |> Kernel./(length(results))
  end
  
  defp log_benchmark_results(user, results, iterations) do
    Logger.info("""
    
    === Dashboard Performance Benchmark ===
    User ID: #{user.id}
    Email: #{user.email}
    Iterations: #{iterations}
    
    Performance Metrics:
    • Total Load Time: #{Float.round(results.avg_total_time_ms, 1)}ms
    • Upcoming Events Query: #{Float.round(results.avg_upcoming_query_ms, 1)}ms 
    • Past Events Query: #{Float.round(results.avg_past_query_ms, 1)}ms
    • Archived Events Query: #{Float.round(results.avg_archived_query_ms, 1)}ms
    • Filter Counts Query: #{Float.round(results.avg_filter_counts_ms, 1)}ms
    
    Event Counts:
    • Upcoming: #{results.event_counts.upcoming}
    • Past: #{results.event_counts.past} 
    • Archived: #{results.event_counts.archived}
    • Created: #{results.event_counts.created}
    • Participating: #{results.event_counts.participating}
    • Total Events Loaded: #{results.total_events_loaded}
    
    =======================================
    """)
  end
  
  @doc """
  Compares two benchmark results and shows improvement percentages.
  """
  def compare_benchmarks(before_results, after_results, phase_name) do
    total_improvement = calculate_improvement_percentage(
      before_results.avg_total_time_ms, 
      after_results.avg_total_time_ms
    )
    
    upcoming_improvement = calculate_improvement_percentage(
      before_results.avg_upcoming_query_ms,
      after_results.avg_upcoming_query_ms
    )
    
    past_improvement = calculate_improvement_percentage(
      before_results.avg_past_query_ms,
      after_results.avg_past_query_ms
    )
    
    filter_improvement = calculate_improvement_percentage(
      before_results.avg_filter_counts_ms,
      after_results.avg_filter_counts_ms
    )
    
    Logger.info("""
    
    === #{phase_name} Performance Improvement ===
    
    Total Load Time: #{Float.round(before_results.avg_total_time_ms, 1)}ms → #{Float.round(after_results.avg_total_time_ms, 1)}ms (#{total_improvement})
    Upcoming Query: #{Float.round(before_results.avg_upcoming_query_ms, 1)}ms → #{Float.round(after_results.avg_upcoming_query_ms, 1)}ms (#{upcoming_improvement})
    Past Query: #{Float.round(before_results.avg_past_query_ms, 1)}ms → #{Float.round(after_results.avg_past_query_ms, 1)}ms (#{past_improvement})
    Filter Counts: #{Float.round(before_results.avg_filter_counts_ms, 1)}ms → #{Float.round(after_results.avg_filter_counts_ms, 1)}ms (#{filter_improvement})
    
    ================================================
    """)
    
    %{
      total_improvement: total_improvement,
      query_improvements: %{
        upcoming: upcoming_improvement,
        past: past_improvement,
        filter_counts: filter_improvement
      }
    }
  end
  
  defp calculate_improvement_percentage(before, after_value) do
    if before > 0 do
      improvement_pct = ((before - after_value) / before) * 100
      if improvement_pct > 0 do
        "#{Float.round(improvement_pct, 1)}% faster"
      else
        "#{Float.round(abs(improvement_pct), 1)}% slower"
      end
    else
      "N/A"
    end
  end
end