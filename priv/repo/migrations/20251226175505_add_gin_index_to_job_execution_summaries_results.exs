defmodule EventasaurusApp.Repo.Migrations.AddGinIndexToJobExecutionSummariesResults do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @doc """
  Adds GIN index on job_execution_summaries.results JSONB column.

  ## Problem

  The admin discovery dashboard runs multiple aggregation queries on the
  job_execution_summaries table, filtering by JSONB fields like:
  - `results -> 'collision_detected' IS NOT NULL`
  - `results -> 'metrics' ->> 'duration_ms'`

  These queries scan 400K+ rows with P99 latency of 1.8-2.4 seconds.

  ## Solution

  A GIN index on the results column enables PostgreSQL to efficiently
  filter by JSONB containment and key existence.

  ## Expected Improvement

  - Before: Full table scan (~400K rows), P99 ~2 seconds
  - After: Index scan, P99 <200ms
  """

  def up do
    # GIN index for JSONB containment and key existence queries
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS job_execution_summaries_results_gin_idx
    ON job_execution_summaries USING gin (results)
    WHERE results IS NOT NULL
    """

    # Additional expression index for the specific collision_detected lookups
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS job_execution_summaries_collision_detected_idx
    ON job_execution_summaries ((results -> 'collision_detected'))
    WHERE results -> 'collision_detected' IS NOT NULL
    """
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS job_execution_summaries_collision_detected_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS job_execution_summaries_results_gin_idx"
  end
end
