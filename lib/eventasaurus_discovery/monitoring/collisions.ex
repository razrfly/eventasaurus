defmodule EventasaurusDiscovery.Monitoring.Collisions do
  @moduledoc """
  Collision/deduplication monitoring for event scrapers.

  Provides analysis of:
  - Same-source collisions (external_id matches)
  - Cross-source collisions (fuzzy matches)
  - Source overlap patterns
  - Confidence score distributions

  ## Data Source

  Collision data is stored in `job_execution_summaries.results` JSONB field
  under the `collision_data` key. This data is populated by MetricsTracker
  when deduplication handlers detect duplicates.

  ## Collision Data Structure

      %{
        "collision_data" => %{
          "type" => "same_source" | "cross_source",
          "matched_event_id" => 12345,
          "matched_source" => "bandsintown",  # only for cross_source
          "confidence" => 0.85,
          "match_factors" => ["performer", "venue", "date", "gps"],
          "resolution" => "deferred" | "created"
        }
      }

  ## Usage

      # Get recent collisions
      {:ok, collisions} = Collisions.list(source: "kupbilecik", limit: 50)

      # Get collision statistics
      {:ok, stats} = Collisions.stats(hours: 24)

      # Get source overlap matrix
      {:ok, matrix} = Collisions.overlap_matrix(hours: 24)

      # Get confidence distribution
      {:ok, distribution} = Collisions.confidence_distribution(source: "kupbilecik")
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  @doc """
  List recent collision detections with optional filtering.

  ## Options

    * `:limit` - Number of results (default: 50)
    * `:source` - Filter by source name (e.g., "kupbilecik")
    * `:type` - Filter by collision type: "same_source" or "cross_source"
    * `:hours` - Time range in hours (default: nil = all time)

  ## Returns

    * `{:ok, collisions}` - List of collision records
    * `{:error, reason}` - Error occurred

  ## Example

      {:ok, collisions} = Collisions.list(source: "kupbilecik", type: "cross_source")
  """
  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    source = Keyword.get(opts, :source)
    type = Keyword.get(opts, :type)
    hours = Keyword.get(opts, :hours)

    query =
      from(j in JobExecutionSummary,
        where: fragment("?->'collision_data' IS NOT NULL", j.results),
        order_by: [desc: j.inserted_at],
        limit: ^limit
      )

    query = apply_time_filter(query, hours)
    query = apply_source_filter(query, source)
    query = apply_type_filter(query, type)

    collisions =
      query
      |> Repo.replica().all()
      |> Enum.map(&format_collision/1)

    {:ok, collisions}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get collision statistics aggregated by source.

  ## Options

    * `:hours` - Time range in hours (default: 24)
    * `:source` - Filter to specific source

  ## Returns

    * `{:ok, stats}` - Statistics map with per-source breakdown
    * `{:error, reason}` - Error occurred

  ## Example

      {:ok, stats} = Collisions.stats(hours: 24)
      # Returns:
      # %{
      #   total_processed: 850,
      #   total_collisions: 98,
      #   same_source_count: 65,
      #   cross_source_count: 33,
      #   collision_rate: 11.5,
      #   avg_confidence: 0.82,
      #   by_source: [
      #     %{source: "kupbilecik", processed: 150, same_source: 12, cross_source: 5, rate: 11.3},
      #     ...
      #   ]
      # }
  """
  def stats(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    source = Keyword.get(opts, :source)

    cutoff = hours_ago(hours)

    # Get all job executions in the time range
    all_query =
      from(j in JobExecutionSummary,
        where: j.inserted_at >= ^cutoff
      )

    all_query = apply_source_filter(all_query, source)

    all_jobs = Repo.replica().all(all_query)

    # Get collision jobs
    collision_jobs =
      Enum.filter(all_jobs, fn job ->
        Map.has_key?(job.results || %{}, "collision_data")
      end)

    # Calculate stats
    total_processed = length(all_jobs)
    total_collisions = length(collision_jobs)

    same_source_count =
      Enum.count(collision_jobs, fn job ->
        get_in(job.results, ["collision_data", "type"]) == "same_source"
      end)

    cross_source_count = total_collisions - same_source_count

    collision_rate =
      if total_processed > 0,
        do: Float.round(total_collisions / total_processed * 100, 1),
        else: 0.0

    avg_confidence = calculate_avg_confidence(collision_jobs)

    # Group by source
    by_source = calculate_by_source_stats(all_jobs, collision_jobs)

    {:ok,
     %{
       period_hours: hours,
       total_processed: total_processed,
       total_collisions: total_collisions,
       same_source_count: same_source_count,
       cross_source_count: cross_source_count,
       collision_rate: collision_rate,
       avg_confidence: avg_confidence,
       by_source: by_source
     }}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Generate a cross-source overlap matrix showing which sources find the same events.

  ## Options

    * `:hours` - Time range in hours (default: 24)

  ## Returns

    * `{:ok, matrix}` - Overlap matrix with source pairs and counts
    * `{:error, reason}` - Error occurred

  ## Example

      {:ok, matrix} = Collisions.overlap_matrix(hours: 24)
      # Returns:
      # %{
      #   sources: ["bandsintown", "kupbilecik", "week_pl"],
      #   overlaps: [
      #     %{source: "kupbilecik", matched_source: "bandsintown", count: 15, avg_confidence: 0.85},
      #     %{source: "kupbilecik", matched_source: "week_pl", count: 3, avg_confidence: 0.72},
      #     ...
      #   ]
      # }
  """
  def overlap_matrix(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    cutoff = hours_ago(hours)

    # Get cross-source collisions only
    query =
      from(j in JobExecutionSummary,
        where:
          j.inserted_at >= ^cutoff and
            fragment("?->'collision_data'->>'type' = 'cross_source'", j.results)
      )

    collision_jobs = Repo.replica().all(query)

    # Extract unique sources
    sources =
      collision_jobs
      |> Enum.flat_map(fn job ->
        source = extract_source_from_worker(job.worker)
        matched_source = get_in(job.results, ["collision_data", "matched_source"])
        [source, matched_source]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    # Calculate overlaps
    overlaps =
      collision_jobs
      |> Enum.group_by(fn job ->
        source = extract_source_from_worker(job.worker)
        matched_source = get_in(job.results, ["collision_data", "matched_source"])
        {source, matched_source}
      end)
      |> Enum.map(fn {{source, matched_source}, jobs} ->
        confidences =
          jobs
          |> Enum.map(fn job -> get_in(job.results, ["collision_data", "confidence"]) end)
          |> Enum.reject(&is_nil/1)

        avg_confidence =
          if length(confidences) > 0,
            do: Float.round(Enum.sum(confidences) / length(confidences), 2),
            else: nil

        %{
          source: source,
          matched_source: matched_source,
          count: length(jobs),
          avg_confidence: avg_confidence
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)

    {:ok,
     %{
       period_hours: hours,
       sources: sources,
       overlaps: overlaps
     }}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get confidence score distribution for fuzzy matches.

  ## Options

    * `:source` - Filter to specific source
    * `:hours` - Time range in hours (default: 24)
    * `:buckets` - Number of histogram buckets (default: 10)

  ## Returns

    * `{:ok, distribution}` - Confidence distribution data
    * `{:error, reason}` - Error occurred

  ## Example

      {:ok, dist} = Collisions.confidence_distribution(source: "kupbilecik")
      # Returns:
      # %{
      #   min: 0.65,
      #   max: 0.98,
      #   avg: 0.82,
      #   median: 0.85,
      #   histogram: [
      #     %{range: "0.60-0.70", count: 5},
      #     %{range: "0.70-0.80", count: 12},
      #     %{range: "0.80-0.90", count: 25},
      #     %{range: "0.90-1.00", count: 8}
      #   ]
      # }
  """
  def confidence_distribution(opts \\ []) do
    source = Keyword.get(opts, :source)
    hours = Keyword.get(opts, :hours, 24)
    buckets = Keyword.get(opts, :buckets, 10)

    cutoff = hours_ago(hours)

    # Get cross-source collisions (they have meaningful confidence scores)
    query =
      from(j in JobExecutionSummary,
        where:
          j.inserted_at >= ^cutoff and
            fragment("?->'collision_data'->>'type' = 'cross_source'", j.results)
      )

    query = apply_source_filter(query, source)

    collision_jobs = Repo.replica().all(query)

    # Extract confidence scores
    confidences =
      collision_jobs
      |> Enum.map(fn job -> get_in(job.results, ["collision_data", "confidence"]) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    if length(confidences) == 0 do
      {:ok,
       %{
         period_hours: hours,
         source: source,
         count: 0,
         min: nil,
         max: nil,
         avg: nil,
         median: nil,
         histogram: []
       }}
    else
      min_conf = List.first(confidences)
      max_conf = List.last(confidences)
      avg_conf = Float.round(Enum.sum(confidences) / length(confidences), 2)
      median_conf = Enum.at(confidences, div(length(confidences), 2))

      histogram = build_histogram(confidences, buckets)

      {:ok,
       %{
         period_hours: hours,
         source: source,
         count: length(confidences),
         min: min_conf,
         max: max_conf,
         avg: avg_conf,
         median: median_conf,
         histogram: histogram
       }}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get a summary of collision metrics suitable for dashboard display.

  Uses database-level aggregations for memory efficiency (avoids OOM on large datasets).

  ## Options

    * `:hours` - Time range in hours (default: 24)

  ## Returns

    * `{:ok, summary}` - Summary map with key metrics
  """
  def summary(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)

    with {:ok, stats} <- stats_lightweight(hours: hours),
         {:ok, matrix} <- overlap_matrix_lightweight(hours: hours) do
      top_overlaps = Enum.take(matrix.overlaps, 5)

      {:ok,
       %{
         period_hours: hours,
         total_processed: stats.total_processed,
         total_collisions: stats.total_collisions,
         collision_rate: stats.collision_rate,
         same_source_count: stats.same_source_count,
         cross_source_count: stats.cross_source_count,
         avg_confidence: stats.avg_confidence,
         sources_with_collisions: stats.sources_with_collisions,
         top_overlaps: top_overlaps
       }}
    end
  end

  @doc """
  Lightweight version of stats using database aggregations (avoids loading all records into memory).

  Uses the `job_execution_stats` materialized view when available for optimal performance.
  Falls back to direct queries against `job_execution_summaries` if the view doesn't exist.
  """
  def stats_lightweight(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)

    case stats_from_materialized_view(hours) do
      {:ok, stats} -> {:ok, stats}
      {:error, _} -> stats_from_raw_table(hours)
    end
  end

  # Query the pre-aggregated materialized view (fast path: <50ms vs 1-6 seconds)
  defp stats_from_materialized_view(hours) do
    cutoff = hours_ago(hours)

    result =
      Repo.replica().one(
        from(fragment("job_execution_stats"),
          where: fragment("hour_bucket >= ?", ^cutoff),
          select: %{
            total_processed: fragment("COALESCE(SUM(total_processed), 0)::bigint"),
            total_collisions: fragment("COALESCE(SUM(collision_count), 0)::bigint"),
            same_source_count: fragment("COALESCE(SUM(same_source_collisions), 0)::bigint"),
            cross_source_count: fragment("COALESCE(SUM(cross_source_collisions), 0)::bigint"),
            avg_confidence: fragment("AVG(avg_confidence)"),
            sources_with_collisions:
              fragment("COUNT(DISTINCT CASE WHEN collision_count > 0 THEN source END)::bigint")
          }
        )
      )

    if result do
      total_processed = result.total_processed || 0
      total_collisions = result.total_collisions || 0

      collision_rate =
        if total_processed > 0,
          do: Float.round(total_collisions / total_processed * 100, 1),
          else: 0.0

      avg_confidence =
        if result.avg_confidence, do: Float.round(result.avg_confidence, 2), else: nil

      {:ok,
       %{
         period_hours: hours,
         total_processed: total_processed,
         total_collisions: total_collisions,
         same_source_count: result.same_source_count || 0,
         cross_source_count: result.cross_source_count || 0,
         collision_rate: collision_rate,
         avg_confidence: avg_confidence,
         sources_with_collisions: result.sources_with_collisions || 0,
         by_source: []
       }}
    else
      {:error, :no_data}
    end
  rescue
    # Materialized view doesn't exist yet - fall back to raw table
    e in Postgrex.Error -> {:error, e}
    e -> {:error, e}
  end

  # Fallback: Query the raw job_execution_summaries table (slow path)
  defp stats_from_raw_table(hours) do
    cutoff = hours_ago(hours)

    # Use database aggregations instead of loading all records
    total_processed =
      Repo.replica().one(
        from(j in JobExecutionSummary,
          where: j.inserted_at >= ^cutoff,
          select: count(j.id)
        )
      ) || 0

    total_collisions =
      Repo.replica().one(
        from(j in JobExecutionSummary,
          where:
            j.inserted_at >= ^cutoff and
              fragment("?->'collision_data' IS NOT NULL", j.results),
          select: count(j.id)
        )
      ) || 0

    same_source_count =
      Repo.replica().one(
        from(j in JobExecutionSummary,
          where:
            j.inserted_at >= ^cutoff and
              fragment("?->'collision_data'->>'type' = 'same_source'", j.results),
          select: count(j.id)
        )
      ) || 0

    cross_source_count = total_collisions - same_source_count

    collision_rate =
      if total_processed > 0,
        do: Float.round(total_collisions / total_processed * 100, 1),
        else: 0.0

    # Get average confidence using database aggregation
    avg_confidence =
      Repo.replica().one(
        from(j in JobExecutionSummary,
          where:
            j.inserted_at >= ^cutoff and
              fragment("?->'collision_data' IS NOT NULL", j.results),
          select:
            avg(
              type(
                fragment("(?->'collision_data'->>'confidence')::float", j.results),
                :float
              )
            )
        )
      )

    avg_confidence =
      if avg_confidence, do: Float.round(avg_confidence, 2), else: nil

    # Count distinct sources with collisions (using a limited subquery)
    sources_with_collisions =
      Repo.replica().one(
        from(j in JobExecutionSummary,
          where:
            j.inserted_at >= ^cutoff and
              fragment("?->'collision_data' IS NOT NULL", j.results),
          select:
            count(
              fragment(
                "DISTINCT split_part(?, '.', array_length(string_to_array(?, '.'), 1) - 2)",
                j.worker,
                j.worker
              )
            )
        )
      ) || 0

    {:ok,
     %{
       period_hours: hours,
       total_processed: total_processed,
       total_collisions: total_collisions,
       same_source_count: same_source_count,
       cross_source_count: cross_source_count,
       collision_rate: collision_rate,
       avg_confidence: avg_confidence,
       sources_with_collisions: sources_with_collisions,
       # Skip per-source breakdown for lightweight version
       by_source: []
     }}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Lightweight version of overlap_matrix using database aggregations with limits.
  """
  def overlap_matrix_lightweight(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    limit = Keyword.get(opts, :limit, 10)
    cutoff = hours_ago(hours)

    # Get top cross-source overlaps directly from database with aggregation
    overlaps =
      Repo.replica().all(
        from(j in JobExecutionSummary,
          where:
            j.inserted_at >= ^cutoff and
              fragment("?->'collision_data'->>'type' = 'cross_source'", j.results),
          group_by: [
            fragment(
              "split_part(?, '.', array_length(string_to_array(?, '.'), 1) - 2)",
              j.worker,
              j.worker
            ),
            fragment("?->'collision_data'->>'matched_source'", j.results)
          ],
          select: %{
            source:
              fragment(
                "split_part(?, '.', array_length(string_to_array(?, '.'), 1) - 2)",
                j.worker,
                j.worker
              ),
            matched_source: fragment("?->'collision_data'->>'matched_source'", j.results),
            count: count(j.id),
            avg_confidence:
              avg(
                type(
                  fragment("(?->'collision_data'->>'confidence')::float", j.results),
                  :float
                )
              )
          },
          order_by: [desc: count(j.id)],
          limit: ^limit
        )
      )
      |> Enum.map(fn overlap ->
        %{
          source: overlap.source,
          matched_source: overlap.matched_source,
          count: overlap.count,
          avg_confidence:
            if(overlap.avg_confidence, do: Float.round(overlap.avg_confidence, 2), else: nil)
        }
      end)

    # Extract unique sources from overlaps
    sources =
      overlaps
      |> Enum.flat_map(fn o -> [o.source, o.matched_source] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    {:ok,
     %{
       period_hours: hours,
       sources: sources,
       overlaps: overlaps
     }}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Private Functions

  defp apply_time_filter(query, nil), do: query

  defp apply_time_filter(query, hours) when is_integer(hours) do
    cutoff = hours_ago(hours)
    from(j in query, where: j.inserted_at >= ^cutoff)
  end

  defp apply_source_filter(query, nil), do: query

  defp apply_source_filter(query, source) do
    # Convert snake_case source to PascalCase for worker matching
    pascal_source = Macro.camelize(source)
    from(j in query, where: like(j.worker, ^"%#{pascal_source}%"))
  end

  defp apply_type_filter(query, nil), do: query

  defp apply_type_filter(query, type) when type in ["same_source", "cross_source"] do
    from(j in query, where: fragment("?->'collision_data'->>'type' = ?", j.results, ^type))
  end

  defp apply_type_filter(query, _), do: query

  defp hours_ago(hours) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-hours * 3600, :second)
  end

  defp format_collision(job) do
    collision_data = Map.get(job.results || %{}, "collision_data", %{})
    external_id = Map.get(job.results || %{}, "external_id")

    %{
      id: job.id,
      job_id: job.job_id,
      source: extract_source_from_worker(job.worker),
      worker: extract_job_name(job.worker),
      external_id: external_id,
      type: Map.get(collision_data, "type"),
      matched_event_id: Map.get(collision_data, "matched_event_id"),
      matched_source: Map.get(collision_data, "matched_source"),
      confidence: Map.get(collision_data, "confidence"),
      match_factors: Map.get(collision_data, "match_factors", []),
      resolution: Map.get(collision_data, "resolution"),
      detected_at: job.inserted_at
    }
  end

  defp extract_source_from_worker(worker) do
    worker
    |> String.split(".")
    |> Enum.at(-3)
    |> case do
      nil -> "unknown"
      source -> Macro.underscore(source)
    end
  end

  defp extract_job_name(worker) do
    worker
    |> String.split(".")
    |> List.last() || "Unknown"
  end

  defp calculate_avg_confidence(collision_jobs) do
    confidences =
      collision_jobs
      |> Enum.map(fn job -> get_in(job.results, ["collision_data", "confidence"]) end)
      |> Enum.reject(&is_nil/1)

    if length(confidences) > 0,
      do: Float.round(Enum.sum(confidences) / length(confidences), 2),
      else: nil
  end

  defp calculate_by_source_stats(all_jobs, collision_jobs) do
    # Group all jobs by source
    all_by_source = Enum.group_by(all_jobs, &extract_source_from_worker(&1.worker))

    # Group collision jobs by source
    collisions_by_source = Enum.group_by(collision_jobs, &extract_source_from_worker(&1.worker))

    all_by_source
    |> Enum.map(fn {source, jobs} ->
      collision_jobs_for_source = Map.get(collisions_by_source, source, [])

      same_source =
        Enum.count(collision_jobs_for_source, fn job ->
          get_in(job.results, ["collision_data", "type"]) == "same_source"
        end)

      cross_source = length(collision_jobs_for_source) - same_source

      total_collisions = same_source + cross_source
      processed = length(jobs)

      rate =
        if processed > 0,
          do: Float.round(total_collisions / processed * 100, 1),
          else: 0.0

      %{
        source: source,
        processed: processed,
        same_source: same_source,
        cross_source: cross_source,
        total_collisions: total_collisions,
        rate: rate
      }
    end)
    |> Enum.filter(fn s -> s.total_collisions > 0 end)
    |> Enum.sort_by(& &1.rate, :desc)
  end

  defp build_histogram(_confidences, buckets) when buckets <= 0, do: []

  defp build_histogram(confidences, buckets) do
    bucket_size = 1.0 / buckets

    0..(buckets - 1)
    |> Enum.map(fn i ->
      range_start = i * bucket_size
      range_end = (i + 1) * bucket_size

      # For the last bucket, include values equal to 1.0 (use <= instead of <)
      is_last_bucket = i == buckets - 1

      count =
        Enum.count(confidences, fn c ->
          if is_last_bucket do
            c >= range_start and c <= range_end
          else
            c >= range_start and c < range_end
          end
        end)

      range_label =
        "#{Float.round(range_start, 2) |> format_percent()}-#{Float.round(range_end, 2) |> format_percent()}"

      %{range: range_label, count: count}
    end)
    |> Enum.filter(fn bucket -> bucket.count > 0 end)
  end

  defp format_percent(value) do
    value
    |> Kernel.*(100)
    |> round()
    |> Integer.to_string()
    |> then(&"#{&1}%")
  end
end
