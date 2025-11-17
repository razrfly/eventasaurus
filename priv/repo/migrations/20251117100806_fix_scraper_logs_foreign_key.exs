defmodule EventasaurusApp.Repo.Migrations.FixScraperLogsForeignKey do
  use Ecto.Migration

  @moduledoc """
  Fixes the foreign key constraint on scraper_processing_logs.job_id to use
  on_delete: :nilify instead of on_delete: :nothing. This prevents foreign key
  violations when Oban's Pruner plugin tries to delete old completed/cancelled jobs.

  The scraper_processing_logs table is used for debugging, so we want to keep the
  logs even after the Oban job is pruned - we just set job_id to NULL.
  """

  def up do
    # Drop the existing foreign key constraint
    execute """
    ALTER TABLE scraper_processing_logs
    DROP CONSTRAINT scraper_processing_logs_job_id_fkey
    """

    # Add it back with ON DELETE SET NULL
    execute """
    ALTER TABLE scraper_processing_logs
    ADD CONSTRAINT scraper_processing_logs_job_id_fkey
    FOREIGN KEY (job_id) REFERENCES oban_jobs(id)
    ON DELETE SET NULL
    """
  end

  def down do
    # Drop the SET NULL constraint
    execute """
    ALTER TABLE scraper_processing_logs
    DROP CONSTRAINT scraper_processing_logs_job_id_fkey
    """

    # Add back the original constraint with ON DELETE NO ACTION
    execute """
    ALTER TABLE scraper_processing_logs
    ADD CONSTRAINT scraper_processing_logs_job_id_fkey
    FOREIGN KEY (job_id) REFERENCES oban_jobs(id)
    ON DELETE NO ACTION
    """
  end
end
