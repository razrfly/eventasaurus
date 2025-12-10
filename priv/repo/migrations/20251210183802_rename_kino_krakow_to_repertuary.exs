defmodule EventasaurusApp.Repo.Migrations.RenameKinoKrakowToRepertuary do
  @moduledoc """
  Phase 2: Rename Kino Krakow source to Repertuary for multi-city support.

  This migration:
  1. Updates the source record (name, slug, website_url)
  2. Updates Oban job worker names
  3. Updates job execution summary records
  """
  use Ecto.Migration

  @worker_mappings [
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob"},
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MoviePageJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.MoviePageJob"},
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.MovieDetailJob"},
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.ShowtimeProcessJob"},
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.DayPageJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.DayPageJob"}
  ]

  def up do
    # 1. Update the source record
    execute """
    UPDATE sources
    SET name = 'Repertuary',
        slug = 'repertuary',
        website_url = 'https://repertuary.pl',
        updated_at = NOW()
    WHERE slug = 'kino-krakow'
    """

    # 2. Update Oban job worker names
    for {old_worker, new_worker} <- @worker_mappings do
      execute """
      UPDATE oban_jobs
      SET worker = '#{new_worker}'
      WHERE worker = '#{old_worker}'
      """
    end

    # 3. Update job execution summaries - worker names
    execute """
    UPDATE job_execution_summaries
    SET worker = REPLACE(worker, 'KinoKrakow', 'Repertuary')
    WHERE worker LIKE '%KinoKrakow%'
    """

    # 4. Update job execution summaries - source slug in results JSONB
    execute """
    UPDATE job_execution_summaries
    SET results = jsonb_set(results, '{source}', '"repertuary"')
    WHERE results->>'source' = 'kino-krakow'
    """
  end

  def down do
    # 1. Revert the source record
    execute """
    UPDATE sources
    SET name = 'Kino Krakow',
        slug = 'kino-krakow',
        website_url = 'https://www.kino.krakow.pl',
        updated_at = NOW()
    WHERE slug = 'repertuary'
    """

    # 2. Revert Oban job worker names
    for {old_worker, new_worker} <- @worker_mappings do
      execute """
      UPDATE oban_jobs
      SET worker = '#{old_worker}'
      WHERE worker = '#{new_worker}'
      """
    end

    # 3. Revert job execution summaries - worker names
    execute """
    UPDATE job_execution_summaries
    SET worker = REPLACE(worker, 'Repertuary', 'KinoKrakow')
    WHERE worker LIKE '%Repertuary%'
    """

    # 4. Revert job execution summaries - source slug in results JSONB
    execute """
    UPDATE job_execution_summaries
    SET results = jsonb_set(results, '{source}', '"kino-krakow"')
    WHERE results->>'source' = 'repertuary'
    """
  end
end
