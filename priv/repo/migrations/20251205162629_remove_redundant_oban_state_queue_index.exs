defmodule EventasaurusApp.Repo.Migrations.RemoveRedundantObanStateQueueIndex do
  @moduledoc """
  Remove redundant oban_jobs_state_queue_idx index.

  ## Why This Index Is Redundant

  PlanetScale Recommendation #43 correctly identifies this index as redundant because
  Oban already maintains a compound index:

    oban_jobs_pkey (id)
    oban_jobs_state_queue_priority_scheduled_at_id_index (state, queue, priority, scheduled_at, id)

  The existing Oban compound index already covers (state, queue) as its first two columns,
  making a separate (state, queue) index wasteful:
  - Extra write overhead on every INSERT/UPDATE
  - Additional storage space
  - No performance benefit since the compound index serves the same queries

  ## Correct Solution for Dashboard Query Performance

  The real issue with the oban_jobs aggregation query (7.48% runtime, 19.8M rows read)
  is NOT missing indexes. The solutions are:

  1. Route dashboard queries to read replica (implemented in DashboardStats)
  2. Reduce dashboard polling frequency
  3. Let Pruner catch up with cleaning old jobs (2-day retention configured)

  See GitHub Issue #2537 for full analysis.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Remove the redundant index that was incorrectly added
    execute(
      """
      DROP INDEX CONCURRENTLY IF EXISTS oban_jobs_state_queue_idx
      """,
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS oban_jobs_state_queue_idx
      ON oban_jobs (state, queue)
      """
    )
  end
end
