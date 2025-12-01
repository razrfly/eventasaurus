defmodule EventasaurusApp.Repo.Migrations.FixMissingJobExecutionSummariesTable do
  @moduledoc """
  Idempotent migration to fix missing job_execution_summaries table in production.

  Background: Migration 20251118144848 was recorded as "already up" in schema_migrations,
  but the actual table doesn't exist in production (phantom migration). This migration
  uses IF NOT EXISTS semantics to safely create the table and indexes without affecting
  environments where they already exist.

  See: https://github.com/razrfly/eventasaurus/issues/2455
  """
  use Ecto.Migration

  def up do
    # Create table only if it doesn't exist
    execute """
    CREATE TABLE IF NOT EXISTS job_execution_summaries (
      id BIGSERIAL PRIMARY KEY,
      job_id BIGINT NOT NULL,
      worker VARCHAR(255) NOT NULL,
      queue VARCHAR(255) NOT NULL,
      state VARCHAR(255) NOT NULL,
      args JSONB DEFAULT '{}',
      results JSONB DEFAULT '{}',
      error TEXT,
      attempted_at TIMESTAMP WITHOUT TIME ZONE,
      completed_at TIMESTAMP WITHOUT TIME ZONE,
      duration_ms INTEGER,
      inserted_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
      updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL
    )
    """

    # Create indexes only if they don't exist
    # From original migration 20251118144848
    execute "CREATE INDEX IF NOT EXISTS job_execution_summaries_job_id_index ON job_execution_summaries (job_id)"
    execute "CREATE INDEX IF NOT EXISTS job_execution_summaries_worker_index ON job_execution_summaries (worker)"
    execute "CREATE INDEX IF NOT EXISTS job_execution_summaries_state_index ON job_execution_summaries (state)"
    execute "CREATE INDEX IF NOT EXISTS job_execution_summaries_worker_attempted_at_index ON job_execution_summaries (worker, attempted_at)"
    execute "CREATE INDEX IF NOT EXISTS job_execution_summaries_attempted_at_index ON job_execution_summaries (attempted_at)"

    # From migration 20251118172645 (job lineage indexes)
    execute "CREATE INDEX IF NOT EXISTS job_execution_summaries_parent_job_id_index ON job_execution_summaries ((results->>'parent_job_id'))"
    execute "CREATE INDEX IF NOT EXISTS job_execution_summaries_pipeline_id_index ON job_execution_summaries ((results->>'pipeline_id'))"
  end

  def down do
    # Only drop if this migration actually created it
    # Since we used IF NOT EXISTS, we should be careful about dropping
    # In environments where the table existed before, we don't want to drop it
    :ok
  end
end
