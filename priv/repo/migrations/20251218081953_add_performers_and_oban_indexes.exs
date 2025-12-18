defmodule EventasaurusApp.Repo.Migrations.AddPerformersAndObanIndexes do
  @moduledoc """
  Add missing indexes to fix connection exhaustion and query performance.

  ## Problems Identified (PlanetScale Insights #44, #45)

  ### 1. performers.source_id (no index)
  Query: SELECT ... FROM performers WHERE source_id = $1
  Impact: 46M rows read for 10K queries (full table scan)
  Result: Jobs holding connections for 9+ minutes

  ### 2. performers.name (case-insensitive lookups)
  Query: WHERE lower(name) = lower($1)
  Impact: Full table scan for every performer lookup in event_processor.ex
  Result: Slow performer matching during event ingestion

  ### 3. oban_jobs.queue (distinct queue queries)
  Query: SELECT DISTINCT queue FROM oban_jobs
  Impact: 32M rows read for 1,183 queries
  Result: Oban monitoring overhead

  ## Solution
  Add indexes using CONCURRENTLY to avoid locking tables during creation.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # 1. Index on performers.source_id for source-based lookups
    # Fixes: 46M row scans → index lookup
    # Note: CONCURRENTLY cannot use IF NOT EXISTS, so we check first and handle errors
    unless index_exists?("performers_source_id_index") do
      execute "CREATE INDEX CONCURRENTLY performers_source_id_index ON performers(source_id)"
    end

    # 2. Functional index on lower(performers.name) for case-insensitive lookups
    # Fixes: Full table scans in event_processor.ex find_or_create_performer
    # PlanetScale Insight #45
    unless index_exists?("performers_lower_name_index") do
      execute "CREATE INDEX CONCURRENTLY performers_lower_name_index ON performers(lower(name))"
    end

    # 3. Index on oban_jobs.queue for distinct queue queries
    # Fixes: 32M row scans for Oban monitoring
    # PlanetScale Insight #44
    # Note: oban_jobs already has oban_jobs_state_queue_priority_scheduled_at_id_index
    # but a dedicated queue index helps SELECT DISTINCT queue queries
    unless index_exists?("oban_jobs_queue_index") do
      execute "CREATE INDEX CONCURRENTLY oban_jobs_queue_index ON oban_jobs(queue)"
    end
  end

  defp index_exists?(index_name) do
    query = "SELECT 1 FROM pg_indexes WHERE indexname = '#{index_name}'"

    case repo().query(query) do
      {:ok, %{num_rows: n}} when n > 0 -> true
      _ -> false
    end
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS performers_source_id_index"
    execute "DROP INDEX CONCURRENTLY IF EXISTS performers_lower_name_index"
    execute "DROP INDEX CONCURRENTLY IF EXISTS oban_jobs_queue_index"
  end
end
