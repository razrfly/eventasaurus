defmodule Mix.Tasks.Baseline.CityPage do
  @moduledoc """
  Captures city page performance baseline metrics for before/after deployment comparison.

  This task measures query performance, cache effectiveness, and overall page load
  characteristics. Results can be saved to JSON files for comparison.

  ## Usage

      # Capture baseline for Kraków (default)
      mix baseline.city_page

      # Capture baseline for specific city
      mix baseline.city_page --city warsaw

      # Run multiple iterations for statistical reliability
      mix baseline.city_page --iterations 5

      # Save baseline to file with optional label
      mix baseline.city_page --save --label "before_optimization"

      # Compare against a previous baseline
      mix baseline.city_page --compare .baselines/city_page_20250120.json

  ## Output

  Reports timing for:
  - list_events query time
  - aggregation time
  - count queries time
  - total consolidated time
  - event counts
  - cache hit/miss rates
  """

  use Mix.Task

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Locations

  @shortdoc "Capture city page performance baseline"

  @default_city "krakow"
  @default_iterations 3
  @default_radius 50
  @baselines_dir ".baselines"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          city: :string,
          iterations: :integer,
          radius: :integer,
          save: :boolean,
          label: :string,
          compare: :string,
          verbose: :boolean
        ],
        aliases: [c: :city, i: :iterations, r: :radius, s: :save, l: :label, v: :verbose]
      )

    city_slug = Keyword.get(opts, :city, @default_city)
    iterations = Keyword.get(opts, :iterations, @default_iterations)
    radius = Keyword.get(opts, :radius, @default_radius)
    save = Keyword.get(opts, :save, false)
    label = Keyword.get(opts, :label)
    compare_file = Keyword.get(opts, :compare)
    verbose = Keyword.get(opts, :verbose, false)

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("City Page Performance Baseline")
    IO.puts(String.duplicate("=", 70))

    case Locations.get_city_by_slug(city_slug) do
      nil ->
        IO.puts("❌ City '#{city_slug}' not found")
        list_available_cities()

      city ->
        baseline = capture_baseline(city, iterations, radius, verbose)

        print_baseline(baseline)

        if save do
          save_baseline(baseline, label)
        end

        if compare_file do
          compare_baselines(baseline, compare_file)
        end
    end
  end

  defp capture_baseline(city, iterations, radius, verbose) do
    IO.puts("\n📍 City: #{city.name} (#{city.slug})")
    IO.puts("🔄 Iterations: #{iterations}")
    IO.puts("📏 Radius: #{radius}km")
    IO.puts("")

    # Warm up query cache
    IO.puts("Warming up...")
    _ = run_single_measurement(city, radius)
    :timer.sleep(500)

    IO.puts("Running #{iterations} iterations...\n")

    # Collect measurements
    measurements =
      Enum.map(1..iterations, fn i ->
        if verbose, do: IO.puts("--- Iteration #{i} ---")
        measurement = run_single_measurement(city, radius)

        if verbose do
          IO.puts("  Consolidated: #{Float.round(measurement.consolidated_ms, 1)}ms")
          IO.puts("  Events: #{measurement.event_count}")
        end

        measurement
      end)

    # Calculate statistics
    %{
      city_slug: city.slug,
      city_name: city.name,
      radius_km: radius,
      iterations: iterations,
      captured_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: get_app_version(),
      metrics: calculate_statistics(measurements),
      raw_measurements: measurements
    }
  end

  defp run_single_measurement(city, radius) do
    today = Date.utc_today()
    end_date = Date.add(today, 30)

    # Convert Decimal coordinates to float
    lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    # Build query options matching production CityLive.Index
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

    # Build all_events_filters (without date restrictions)
    all_events_filters =
      base_opts
      |> Map.drop([:from_date, :to_date, :page, :page_size])
      |> Map.put(:aggregate, true)
      |> Map.put(:ignore_city_in_aggregation, true)
      |> Map.put(:viewing_city, city)

    opts = Map.put(base_opts, :all_events_filters, all_events_filters)

    # Measure consolidated query
    {consolidated_time, {events, total_count, all_events_count}} =
      :timer.tc(fn ->
        PublicEventsEnhanced.list_events_with_aggregation_and_counts(opts)
      end)

    # Measure individual components for breakdown
    {list_time, _events} =
      :timer.tc(fn ->
        PublicEventsEnhanced.list_events(Map.drop(opts, [:all_events_filters]))
      end)

    {count_time, _count} =
      :timer.tc(fn ->
        PublicEventsEnhanced.count_events(Map.drop(opts, [:page, :page_size, :all_events_filters]))
      end)

    %{
      consolidated_ms: consolidated_time / 1000,
      list_events_ms: list_time / 1000,
      count_events_ms: count_time / 1000,
      event_count: length(events),
      total_count: total_count,
      all_events_count: all_events_count,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp calculate_statistics(measurements) do
    consolidated_times = Enum.map(measurements, & &1.consolidated_ms)
    list_times = Enum.map(measurements, & &1.list_events_ms)
    count_times = Enum.map(measurements, & &1.count_events_ms)

    sample = List.first(measurements)

    %{
      consolidated: calc_stats(consolidated_times),
      list_events: calc_stats(list_times),
      count_events: calc_stats(count_times),
      events_on_page: sample.event_count,
      total_matching: sample.total_count,
      all_events_count: sample.all_events_count
    }
  end

  defp calc_stats(values) do
    sorted = Enum.sort(values)
    count = length(values)

    %{
      avg: Float.round(Enum.sum(values) / count, 2),
      min: Float.round(Enum.min(values), 2),
      max: Float.round(Enum.max(values), 2),
      p50: Float.round(percentile(sorted, 50), 2),
      p95: Float.round(percentile(sorted, 95), 2)
    }
  end

  defp percentile(sorted_values, p) when p >= 0 and p <= 100 do
    count = length(sorted_values)
    index = (p / 100) * (count - 1)
    lower_index = floor(index)
    upper_index = ceil(index)

    if lower_index == upper_index do
      Enum.at(sorted_values, lower_index)
    else
      lower_value = Enum.at(sorted_values, lower_index)
      upper_value = Enum.at(sorted_values, upper_index)
      lower_value + (upper_value - lower_value) * (index - lower_index)
    end
  end

  defp print_baseline(baseline) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("BASELINE RESULTS")
    IO.puts(String.duplicate("-", 70))

    metrics = baseline.metrics

    IO.puts("\n📊 Query Timing (#{baseline.iterations} iterations):\n")

    print_timing_row("Consolidated (main)", metrics.consolidated)
    print_timing_row("├─ list_events", metrics.list_events)
    print_timing_row("└─ count_events", metrics.count_events)

    IO.puts("\n📈 Data Statistics:")
    IO.puts("  Events on page: #{metrics.events_on_page}")
    IO.puts("  Total matching: #{metrics.total_matching}")
    IO.puts("  All events count: #{metrics.all_events_count}")

    IO.puts("\n💡 Key Metrics:")
    IO.puts("  Consolidated avg: #{metrics.consolidated.avg}ms")
    IO.puts("  Consolidated P95: #{metrics.consolidated.p95}ms")

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  defp print_timing_row(label, stats) do
    IO.puts(
      "  #{String.pad_trailing(label, 25)} " <>
        "avg: #{String.pad_leading("#{stats.avg}", 8)}ms  " <>
        "p50: #{String.pad_leading("#{stats.p50}", 8)}ms  " <>
        "p95: #{String.pad_leading("#{stats.p95}", 8)}ms"
    )
  end

  defp save_baseline(baseline, label) do
    File.mkdir_p!(@baselines_dir)

    date_str = Date.utc_today() |> Date.to_iso8601() |> String.replace("-", "")
    label_suffix = if label, do: "_#{label}", else: ""
    filename = "#{@baselines_dir}/city_page_#{baseline.city_slug}_#{date_str}#{label_suffix}.json"

    # Remove raw measurements for smaller file
    baseline_for_save = Map.drop(baseline, [:raw_measurements])

    File.write!(filename, Jason.encode!(baseline_for_save, pretty: true))

    IO.puts("\n💾 Baseline saved to: #{filename}")
  end

  defp compare_baselines(current, compare_file) do
    case File.read(compare_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, previous} ->
            IO.puts("\n" <> String.duplicate("-", 70))
            IO.puts("COMPARISON: #{Path.basename(compare_file)} → Current")
            IO.puts(String.duplicate("-", 70))

            prev_consolidated = get_in(previous, ["metrics", "consolidated", "avg"])
            curr_consolidated = current.metrics.consolidated.avg

            diff = curr_consolidated - prev_consolidated
            diff_pct = (diff / prev_consolidated) * 100

            direction = if diff < 0, do: "🟢 FASTER", else: "🔴 SLOWER"

            IO.puts("\n  Consolidated avg:")
            IO.puts("    Previous: #{prev_consolidated}ms")
            IO.puts("    Current:  #{curr_consolidated}ms")
            IO.puts("    Change:   #{Float.round(diff, 2)}ms (#{Float.round(diff_pct, 1)}%) #{direction}")

            prev_p95 = get_in(previous, ["metrics", "consolidated", "p95"])
            curr_p95 = current.metrics.consolidated.p95

            diff_p95 = curr_p95 - prev_p95
            diff_p95_pct = (diff_p95 / prev_p95) * 100

            direction_p95 = if diff_p95 < 0, do: "🟢 FASTER", else: "🔴 SLOWER"

            IO.puts("\n  Consolidated P95:")
            IO.puts("    Previous: #{prev_p95}ms")
            IO.puts("    Current:  #{curr_p95}ms")
            IO.puts("    Change:   #{Float.round(diff_p95, 2)}ms (#{Float.round(diff_p95_pct, 1)}%) #{direction_p95}")

          {:error, _} ->
            IO.puts("❌ Failed to parse baseline file: #{compare_file}")
        end

      {:error, _} ->
        IO.puts("❌ Could not read baseline file: #{compare_file}")
    end
  end

  defp get_app_version do
    case :application.get_key(:eventasaurus, :vsn) do
      {:ok, version} -> to_string(version)
      _ -> "unknown"
    end
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
