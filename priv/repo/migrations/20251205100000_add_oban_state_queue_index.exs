defmodule EventasaurusApp.Repo.Migrations.AddObanStateQueueIndex do
  @moduledoc """
  Add composite index on oban_jobs(state, queue) to optimize Oban.Web dashboard queries.

  This addresses P0 query performance issue:
  - Query: SELECT state, queue, count(id) FROM oban_jobs WHERE state = any($1) GROUP BY state, queue
  - Issue: 18.24% of database runtime, 121M rows read, 6,055 calls
  - Called by Oban.Web dashboard polling (approximately once per second)

  The composite index allows the GROUP BY to use an index scan instead of a sequential scan.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Composite index for state + queue grouping queries
    # This is the primary query pattern from Oban.Web dashboard
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS oban_jobs_state_queue_idx
      ON oban_jobs (state, queue)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS oban_jobs_state_queue_idx
      """
    )
  end
end
