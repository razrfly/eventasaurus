defmodule Mix.Tasks.Benchmark.CityPage do
  @moduledoc """
  Benchmarks city page performance by measuring query execution time.

  This measures the actual database query time, not network latency,
  giving us precise insight into optimization impact.

  ## Usage

      # Benchmark Kraków (default)
      mix benchmark.city_page

      # Benchmark specific city
      mix benchmark.city_page --city warsaw

      # Run multiple iterations
      mix benchmark.city_page --iterations 5

      # Verbose output showing query breakdown
      mix benchmark.city_page --verbose

  ## Output

  Reports timing for:
  - Total query time
  - Event fetch time
  - Aggregation time
  - Count queries time
  - Preload time
  """

  use Mix.Task

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Locations

  @shortdoc "Benchmark city page query performance"

  @default_city "krakow"
  @default_iterations 3
  @default_radius 50

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          city: :string,
          iterations: :integer,
          verbose: :boolean,
          radius: :integer
        ],
        aliases: [c: :city, i: :iterations, v: :verbose, r: :radius]
      )

    city_slug = Keyword.get(opts, :city, @default_city)
    iterations = Keyword.get(opts, :iterations, @default_iterations)
    verbose = Keyword.get(opts, :verbose, false)
    radius = Keyword.get(opts, :radius, @default_radius)

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("City Page Performance Benchmark")
    IO.puts(String.duplicate("=", 70))

    case Locations.get_city_by_slug(city_slug) do
      nil ->
        IO.puts("❌ City '#{city_slug}' not found")
        list_available_cities()

      city ->
        run_benchmark(city, iterations, radius, verbose)
    end
  end

  defp run_benchmark(city, iterations, radius, verbose) do
    IO.puts("\n📍 City: #{city.name} (#{city.slug})")
    IO.puts("🔄 Iterations: #{iterations}")
    IO.puts("📏 Radius: #{radius}km")
    IO.puts("")

    # Warm up query cache
    IO.puts("Warming up...")
    run_single_benchmark(city, radius, false)
    :timer.sleep(500)

    IO.puts("\nRunning #{iterations} iterations...\n")

    results =
      Enum.map(1..iterations, fn i ->
        if verbose, do: IO.puts("--- Iteration #{i} ---")
        result = run_single_benchmark(city, radius, verbose)
        if verbose, do: IO.puts("")
        result
      end)

    print_summary(results, city)
  end

  defp run_single_benchmark(city, radius, verbose) do
    today = Date.utc_today()
    end_date = Date.add(today, 30)

    # Convert Decimal coordinates to float (matching production code)
    lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    # Base query filters (matching production CityLive.Index)
    base_opts = %{
      center_lat: lat,
      center_lng: lng,
      radius_km: radius,
      from_date: today,
      to_date: end_date,
      page: 1,
      page_size: 30,
      sort_by: :starts_at,
      sort_order: :asc,
      aggregate: true,
      ignore_city_in_aggregation: true,
      viewing_city: city
    }

    # Build all_events_filters (without date restrictions - for "all events" count)
    all_events_filters =
      base_opts
      |> Map.drop([:from_date, :to_date, :page, :page_size])
      |> Map.put(:aggregate, true)
      |> Map.put(:ignore_city_in_aggregation, true)
      |> Map.put(:viewing_city, city)

    # Complete opts with all_events_filters (matching production)
    opts = Map.put(base_opts, :all_events_filters, all_events_filters)

    # Measure the consolidated query (what the city page actually calls)
    # Returns {events, total_count, all_events_count}
    {consolidated_time, {events, total_count, all_events_count}} =
      :timer.tc(fn ->
        PublicEventsEnhanced.list_events_with_aggregation_and_counts(opts)
      end)

    # Also measure individual components for breakdown
    {list_time, _events} =
      :timer.tc(fn ->
        PublicEventsEnhanced.list_events(opts)
      end)

    {count_time, _count} =
      :timer.tc(fn ->
        PublicEventsEnhanced.count_events(opts)
      end)

    result = %{
      consolidated_ms: consolidated_time / 1000,
      list_ms: list_time / 1000,
      count_ms: count_time / 1000,
      event_count: length(events),
      total_count: total_count,
      all_events_count: all_events_count
    }

    if verbose do
      IO.puts("  Consolidated query: #{Float.round(result.consolidated_ms, 1)}ms")
      IO.puts("  ├─ list_events: #{Float.round(result.list_ms, 1)}ms")
      IO.puts("  └─ count_events: #{Float.round(result.count_ms, 1)}ms")
      IO.puts("  Events returned: #{result.event_count} / #{result.total_count} total")
    end

    result
  end

  defp print_summary(results, city) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("RESULTS SUMMARY")
    IO.puts(String.duplicate("-", 70))

    consolidated_times = Enum.map(results, & &1.consolidated_ms)
    list_times = Enum.map(results, & &1.list_ms)
    count_times = Enum.map(results, & &1.count_ms)

    sample = List.first(results)

    IO.puts("\n📊 Query Timing (#{length(results)} iterations):\n")

    print_timing_row("Consolidated (main)", consolidated_times)
    print_timing_row("├─ list_events", list_times)
    print_timing_row("└─ count_events", count_times)

    IO.puts("\n📈 Data Statistics:")
    IO.puts("  Events on page: #{sample.event_count}")
    IO.puts("  Total matching: #{sample.total_count}")
    IO.puts("  All events count: #{sample.all_events_count}")

    # Calculate theoretical minimum (if we eliminated duplicates)
    avg_consolidated = Enum.sum(consolidated_times) / length(consolidated_times)
    avg_list = Enum.sum(list_times) / length(list_times)

    IO.puts("\n💡 Analysis:")
    IO.puts("  Current consolidated query: #{Float.round(avg_consolidated, 1)}ms")
    IO.puts("  Single list_events call: #{Float.round(avg_list, 1)}ms")

    if avg_consolidated > avg_list * 1.5 do
      savings = avg_consolidated - avg_list
      IO.puts("  ⚠️  Potential savings from P0: ~#{Float.round(savings, 0)}ms (#{Float.round(savings / avg_consolidated * 100, 0)}%)")
    end

    IO.puts("\n" <> String.duplicate("=", 70))

    # Output machine-readable summary for comparison
    IO.puts("\n📋 Benchmark ID: #{city.slug}_#{DateTime.utc_now() |> DateTime.to_iso8601()}")
    IO.puts("   CONSOLIDATED_AVG=#{Float.round(avg_consolidated, 1)}")
    IO.puts("   LIST_AVG=#{Float.round(avg_list, 1)}")
    IO.puts("   EVENTS=#{sample.total_count}")
  end

  defp print_timing_row(label, times) do
    avg = Enum.sum(times) / length(times)
    min = Enum.min(times)
    max = Enum.max(times)

    IO.puts(
      "  #{String.pad_trailing(label, 25)} avg: #{String.pad_leading(Float.round(avg, 1) |> to_string(), 8)}ms  " <>
        "min: #{String.pad_leading(Float.round(min, 1) |> to_string(), 8)}ms  " <>
        "max: #{String.pad_leading(Float.round(max, 1) |> to_string(), 8)}ms"
    )
  end

  defp list_available_cities do
    IO.puts("\nAvailable cities:")

    Locations.list_cities_with_coordinates()
    |> Enum.take(20)
    |> Enum.each(fn city ->
      IO.puts("  - #{city.slug} (#{city.name})")
    end)
  end
end
