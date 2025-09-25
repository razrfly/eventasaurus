defmodule EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.CityIndexJob do
  @moduledoc """
  DEPRECATED: This job is replaced by Sources.Bandsintown.Jobs.SyncJob
  which uses the unified Processor for venue enforcement.

  Old Oban job for fetching events from a Bandsintown city page.
  Kept for reference but should not be used.

  This job:
  1. Fetches the city page HTML
  2. Extracts event URLs
  3. Schedules EventDetailJob for each event
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{id: _job_id, args: _args}) do
    # This job is deprecated - return error to prevent execution
    Logger.error("""
    ⛔ DEPRECATED: Bandsintown CityIndexJob should not be used.
    Please use EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob instead.
    This ensures all events go through the unified Processor with venue requirements.
    """)
    {:error, :deprecated_job}
  end
end