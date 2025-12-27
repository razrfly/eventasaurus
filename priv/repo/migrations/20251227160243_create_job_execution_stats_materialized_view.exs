defmodule EventasaurusApp.Repo.Migrations.CreateJobExecutionStatsMaterializedView do
  @moduledoc """
  Creates a materialized view for job execution dashboard statistics.

  ## Problem

  The `job_execution_summaries` table has 400K+ rows and is queried 6x per dashboard load
  with expensive aggregations:
  - COUNT(*) for total processed
  - COUNT(*) WHERE collision_data IS NOT NULL
  - AVG(collision_data->>'confidence')
  - COUNT(DISTINCT source) with string parsing
  - GROUP BY worker, collision_type

  PlanetScale Insights shows P99 latencies of 1-6 seconds for these queries,
  consuming 28% of total database runtime.

  ## Solution

  Pre-aggregate statistics into hourly buckets per source. The materialized view
  contains ~24 rows per source per day instead of querying 400K+ raw rows.

  Dashboard queries become simple sums over the materialized view:
  - SUM(total_processed) WHERE hour_bucket >= now() - interval '24 hours'

  ## Expected Impact

  - P99 latency: 1-6 seconds → <50ms
  - Rows read: 400K+ → <500 rows
  - Database runtime reduction: ~20 minutes/day

  ## Refresh Strategy

  Refreshed every 15 minutes by JobExecutionStatsRefreshWorker.
  Uses CONCURRENTLY for zero-downtime refresh.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Create the materialized view with hourly aggregations per source
    execute("""
    CREATE MATERIALIZED VIEW job_execution_stats AS
    SELECT
      -- Time bucket (hourly granularity)
      date_trunc('hour', j.inserted_at) AS hour_bucket,

      -- Source extraction from worker name
      -- e.g., "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob" -> "cinema_city"
      LOWER(
        REGEXP_REPLACE(
          split_part(j.worker, '.', array_length(string_to_array(j.worker, '.'), 1) - 2),
          '([a-z])([A-Z])', '\\1_\\2', 'g'
        )
      ) AS source,

      -- Basic counts
      COUNT(*) AS total_processed,
      COUNT(*) FILTER (WHERE j.state = 'success') AS success_count,
      COUNT(*) FILTER (WHERE j.state = 'failure') AS failure_count,

      -- Collision statistics
      COUNT(*) FILTER (WHERE j.results -> 'collision_data' IS NOT NULL) AS collision_count,
      COUNT(*) FILTER (WHERE j.results -> 'collision_data' ->> 'type' = 'same_source') AS same_source_collisions,
      COUNT(*) FILTER (WHERE j.results -> 'collision_data' ->> 'type' = 'cross_source') AS cross_source_collisions,

      -- Confidence score aggregations (for cross-source collisions)
      AVG((j.results -> 'collision_data' ->> 'confidence')::float)
        FILTER (WHERE j.results -> 'collision_data' ->> 'confidence' IS NOT NULL) AS avg_confidence,
      MIN((j.results -> 'collision_data' ->> 'confidence')::float)
        FILTER (WHERE j.results -> 'collision_data' ->> 'confidence' IS NOT NULL) AS min_confidence,
      MAX((j.results -> 'collision_data' ->> 'confidence')::float)
        FILTER (WHERE j.results -> 'collision_data' ->> 'confidence' IS NOT NULL) AS max_confidence,

      -- Duration statistics
      AVG(j.duration_ms) AS avg_duration_ms,
      PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY j.duration_ms) AS p95_duration_ms,

      -- Distinct worker types per source per hour
      COUNT(DISTINCT j.worker) AS distinct_workers

    FROM job_execution_summaries j
    WHERE j.inserted_at >= NOW() - INTERVAL '7 days'
    GROUP BY
      date_trunc('hour', j.inserted_at),
      LOWER(
        REGEXP_REPLACE(
          split_part(j.worker, '.', array_length(string_to_array(j.worker, '.'), 1) - 2),
          '([a-z])([A-Z])', '\\1_\\2', 'g'
        )
      )
    """)

    # Create UNIQUE index required for REFRESH CONCURRENTLY
    execute("""
    CREATE UNIQUE INDEX CONCURRENTLY job_execution_stats_pk_idx
    ON job_execution_stats (hour_bucket, source)
    """)

    # Create index on hour_bucket for time-range queries
    execute("""
    CREATE INDEX CONCURRENTLY job_execution_stats_hour_idx
    ON job_execution_stats (hour_bucket DESC)
    """)

    # Create index on source for source-specific queries
    execute("""
    CREATE INDEX CONCURRENTLY job_execution_stats_source_idx
    ON job_execution_stats (source)
    """)

    # Create covering index for common dashboard query pattern
    execute("""
    CREATE INDEX CONCURRENTLY job_execution_stats_dashboard_idx
    ON job_execution_stats (hour_bucket DESC)
    INCLUDE (total_processed, collision_count, same_source_collisions, cross_source_collisions, avg_confidence)
    """)
  end

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS job_execution_stats")
  end
end
