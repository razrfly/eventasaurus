defmodule EventasaurusApp.Repo.Migrations.DropScraperProcessingLogsTable do
  @moduledoc """
  Drops the deprecated scraper_processing_logs table.

  Issue #3048 Phase 3: Deprecation & Cleanup

  This table was replaced by job_execution_summaries which provides
  better monitoring capabilities through Oban's telemetry system.
  """
  use Ecto.Migration

  def up do
    drop_if_exists table(:scraper_processing_logs)
  end

  def down do
    # Note: We don't restore the table structure on rollback
    # because this table is deprecated and the data would be empty anyway.
    # If needed, the original migration can be referenced for the schema.
    :ok
  end
end
