defmodule EventasaurusApp.Repo.Migrations.AddPerformanceIndexesPhase1 do
  @moduledoc """
  Phase 1 performance indexes based on PlanetScale Insights analysis (2025-12-25).

  Issues addressed:
  1. performers.source_id - Index only 68.9% utilized due to NULL values
     Adding partial index for non-NULL source_id lookups

  2. job_execution_summaries.results - JSONB aggregations doing full table scans
     Adding GIN index for JSONB containment queries

  See: https://github.com/razrfly/eventasaurus/issues/2908
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # 1. Partial index on performers.source_id for non-NULL values
    # Current index has 68.9% utilization - many NULL source_id values
    # This partial index will be more selective for actual lookups
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS performers_source_id_not_null_idx
    ON performers (source_id)
    WHERE source_id IS NOT NULL
    """

    # 2. GIN index on job_execution_summaries.results for JSONB containment queries
    # NOTE: GIN with default jsonb_ops only accelerates containment (@>), key-exists (?, ?|, ?&),
    # and jsonpath operations - NOT arrow operators (-> or ->>).
    # This index helps queries like: WHERE results @> '{"collision_detected": true}'
    # For arrow operator queries, use expression indexes (see below and Phase 2)
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS job_execution_summaries_results_gin_idx
    ON job_execution_summaries USING gin (results jsonb_path_ops)
    """

    # 3. Expression index for common JSONB key lookup pattern
    # Optimizes: WHERE results ->> 'error_category' = 'network_error'
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS job_execution_summaries_error_category_idx
    ON job_execution_summaries ((results ->> 'error_category'))
    WHERE results ->> 'error_category' IS NOT NULL
    """
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS performers_source_id_not_null_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS job_execution_summaries_results_gin_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS job_execution_summaries_error_category_idx"
  end
end
