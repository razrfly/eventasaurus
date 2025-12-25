defmodule EventasaurusApp.Repo.Migrations.AddPerformanceIndexesPhase2 do
  @moduledoc """
  Phase 2 performance indexes based on PlanetScale Insights analysis (2025-12-25).

  Issues addressed:
  1. job_execution_summaries LIKE search on args::text - 32 second P99!
     Adding pg_trgm GIN index for efficient text pattern matching

  2. venues city_id queries - 277ms P99, high volume
     Adding covering index with commonly selected columns

  3. job_execution_summaries collision detection queries
     Adding expression index for has_collision lookups

  See: https://github.com/razrfly/eventasaurus/issues/2908
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # 1. Enable pg_trgm extension for text pattern matching
    # This is required for gin_trgm_ops indexes
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # 2. GIN trigram index on job_execution_summaries.args for LIKE search
    # The critical 32-second P99 query casts args to text and uses LIKE
    # pg_trgm allows efficient pattern matching on text
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS job_execution_summaries_args_trgm_idx
    ON job_execution_summaries USING gin ((args::text) gin_trgm_ops)
    """

    # 3. Expression index for collision detection queries
    # Dashboard queries filter on: results -> 'collision_detected' IS NOT NULL
    # This index allows efficient filtering for collision-related aggregations
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS job_execution_summaries_collision_idx
    ON job_execution_summaries ((results -> 'collision_detected'))
    WHERE results -> 'collision_detected' IS NOT NULL
    """

    # 4. Covering index for venues.city_id queries
    # Most venue queries select id, name, slug, latitude, longitude
    # INCLUDE clause creates a covering index avoiding heap lookups
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS venues_city_id_covering_idx
    ON venues (city_id) INCLUDE (id, name, slug, latitude, longitude, is_public)
    """

    # 5. Composite index for job_execution_summaries time-range queries
    # Dashboard queries filter on inserted_at with JSONB conditions
    # Putting inserted_at first allows range scans then JSONB filtering
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS job_execution_summaries_inserted_at_results_idx
    ON job_execution_summaries (inserted_at DESC, (results -> 'collision_detected'))
    WHERE results IS NOT NULL
    """
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS job_execution_summaries_args_trgm_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS job_execution_summaries_collision_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS venues_city_id_covering_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS job_execution_summaries_inserted_at_results_idx"
    # Note: We don't drop pg_trgm extension as other things may depend on it
  end
end
