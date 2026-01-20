defmodule EventasaurusWeb.Telemetry.CityPageTelemetry do
  @moduledoc """
  Telemetry instrumentation for city page performance monitoring.

  ## Events Emitted

  ### Page Load Events
  - `[:eventasaurus, :city_page, :load, :start]` - Page load started
  - `[:eventasaurus, :city_page, :load, :stop]` - Page load completed
  - `[:eventasaurus, :city_page, :load, :exception]` - Page load failed

  ### Query Events
  - `[:eventasaurus, :city_page, :query, :start]` - Query started
  - `[:eventasaurus, :city_page, :query, :stop]` - Query completed
  - `[:eventasaurus, :city_page, :query, :exception]` - Query failed

  ### Cache Events
  - `[:eventasaurus, :city_page, :cache, :hit]` - Cache hit
  - `[:eventasaurus, :city_page, :cache, :miss]` - Cache miss (computation required)

  ### Aggregation Events
  - `[:eventasaurus, :city_page, :aggregation, :start]` - Aggregation started
  - `[:eventasaurus, :city_page, :aggregation, :stop]` - Aggregation completed

  ## Metadata Fields

  All events include relevant context:
  - `city_slug` - The city being viewed
  - `radius_km` - Geographic search radius
  - `query_type` - Type of query (events, counts, aggregation, etc.)
  - `event_count` - Number of events returned
  - `cache_key` - Cache key for cache events
  """

  require Logger

  # Event name prefixes
  @city_page_prefix [:eventasaurus, :city_page]

  @doc """
  Wraps a function with telemetry span tracking.

  ## Examples

      CityPageTelemetry.span(:query, %{city_slug: "krakow", query_type: :events}, fn ->
        PublicEventsEnhanced.list_events(opts)
      end)
  """
  def span(event_type, metadata, fun) when is_atom(event_type) and is_function(fun, 0) do
    event_name = @city_page_prefix ++ [event_type]

    :telemetry.span(event_name, metadata, fn ->
      result = fun.()
      {result, metadata}
    end)
  end

  @doc """
  Emits a telemetry event for cache operations.

  ## Examples

      CityPageTelemetry.cache_event(:hit, %{cache_key: "categories_list", city_slug: "krakow"})
      CityPageTelemetry.cache_event(:miss, %{cache_key: "date_counts:krakow:50", city_slug: "krakow"})
  """
  def cache_event(type, metadata) when type in [:hit, :miss] do
    :telemetry.execute(
      @city_page_prefix ++ [:cache, type],
      %{system_time: System.system_time(:millisecond)},
      Map.put(metadata, :cache_type, type)
    )
  end

  @doc """
  Measures and logs query execution time.

  Returns `{duration_ms, result}` where duration_ms is the execution time.

  ## Examples

      {duration_ms, events} = CityPageTelemetry.measure_query(:events, %{city_slug: "krakow"}, fn ->
        Repo.all(query)
      end)
  """
  def measure_query(query_type, metadata, fun) when is_atom(query_type) and is_function(fun, 0) do
    start_time = System.monotonic_time(:millisecond)

    result =
      span(:query, Map.put(metadata, :query_type, query_type), fun)

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    {duration_ms, result}
  end

  @doc """
  Logs slow operations (> threshold_ms) with context.
  Default threshold is 100ms.
  """
  def log_if_slow(operation, duration_ms, metadata, threshold_ms \\ 100) do
    if duration_ms > threshold_ms do
      Logger.warning(
        "[CityPage:SLOW] #{operation} took #{duration_ms}ms (threshold: #{threshold_ms}ms)",
        Map.to_list(metadata) ++ [duration_ms: duration_ms, operation: operation]
      )
    end

    :ok
  end

  @doc """
  Creates a timing context for tracking multi-stage operations.

  ## Examples

      ctx = CityPageTelemetry.start_timing("krakow")
      # ... do work ...
      ctx = CityPageTelemetry.mark(ctx, :categories_loaded)
      # ... do more work ...
      CityPageTelemetry.finish_timing(ctx)
  """
  def start_timing(city_slug) do
    %{
      city_slug: city_slug,
      start_time: System.monotonic_time(:millisecond),
      marks: []
    }
  end

  def mark(ctx, label) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - ctx.start_time
    %{ctx | marks: [{label, elapsed} | ctx.marks]}
  end

  def finish_timing(ctx) do
    now = System.monotonic_time(:millisecond)
    total_duration = now - ctx.start_time

    # Emit completion event with all timing data
    :telemetry.execute(
      @city_page_prefix ++ [:load, :complete],
      %{
        total_duration_ms: total_duration,
        marks: Enum.reverse(ctx.marks)
      },
      %{city_slug: ctx.city_slug}
    )

    %{
      city_slug: ctx.city_slug,
      total_duration_ms: total_duration,
      marks: Enum.reverse(ctx.marks)
    }
  end

  @doc """
  Attaches telemetry handlers for logging and monitoring.
  Called from Application.start/2.
  """
  def attach_handlers do
    handlers = [
      # Log slow queries
      {
        "city-page-slow-query-logger",
        @city_page_prefix ++ [:query, :stop],
        &__MODULE__.handle_query_stop/4
      },
      # Log cache performance
      {
        "city-page-cache-logger",
        @city_page_prefix ++ [:cache, :miss],
        &__MODULE__.handle_cache_miss/4
      },
      # Log page load completion
      {
        "city-page-load-logger",
        @city_page_prefix ++ [:load, :complete],
        &__MODULE__.handle_load_complete/4
      }
    ]

    for {id, event, handler} <- handlers do
      :telemetry.attach(id, event, handler, %{slow_threshold_ms: 100})
    end

    :ok
  end

  @doc false
  def handle_query_stop(_event, measurements, metadata, config) do
    duration_ms = measurements[:duration] && div(measurements[:duration], 1_000_000)

    if duration_ms && duration_ms > config.slow_threshold_ms do
      Logger.warning(
        "[CityPage:SLOW_QUERY] #{metadata[:query_type]} query took #{duration_ms}ms",
        city_slug: metadata[:city_slug],
        query_type: metadata[:query_type],
        duration_ms: duration_ms
      )
    end
  end

  @doc false
  def handle_cache_miss(_event, _measurements, metadata, _config) do
    Logger.info(
      "[CityPage:CACHE_MISS] #{metadata[:cache_key]}",
      city_slug: metadata[:city_slug],
      cache_key: metadata[:cache_key]
    )
  end

  @doc false
  def handle_load_complete(_event, measurements, metadata, _config) do
    duration_ms = measurements[:total_duration_ms]
    marks = measurements[:marks] || []

    # Build timing breakdown string
    breakdown =
      marks
      |> Enum.map(fn {label, elapsed} -> "#{label}=#{elapsed}ms" end)
      |> Enum.join(", ")

    log_level = if duration_ms > 1000, do: :warning, else: :info

    Logger.log(
      log_level,
      "[CityPage:LOAD] #{metadata[:city_slug]} completed in #{duration_ms}ms [#{breakdown}]",
      city_slug: metadata[:city_slug],
      total_duration_ms: duration_ms,
      timing_breakdown: marks
    )
  end
end
