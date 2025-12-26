defmodule EventasaurusApp.Workers.VenueMigrationJob do
  @moduledoc """
  Oban worker that migrates a single venue's images from ImageKit to R2.

  This worker is responsible for:
  1. Loading a venue by ID
  2. Calling VenueImageMigrator.migrate_venue/2
  3. Tracking success/failure metrics

  ## Queue Configuration

  Uses the `image_cache` queue (shared with ImageCacheJob):
  - Moderate concurrency (3) to avoid overwhelming external servers
  - Rate limiting is handled by ImageCacheJob for actual downloads

  ## Job Arguments

  - `venue_id` - ID of the venue to migrate
  - `priority` - Optional priority for child ImageCacheJob jobs (default: 2)

  ## Error Handling

  - Always returns `:ok` (even if some images fail - they'll be retried)
  - Individual image failures are tracked in `stats.errors` count
  - Failed images are tracked in `cached_images` table for retry
  """

  use Oban.Worker, queue: :image_cache, max_attempts: 3

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Images.VenueImageMigrator

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_id" => venue_id} = args}) do
    priority = Map.get(args, "priority", 2)

    Logger.info("📸 VenueMigrationJob: Starting migration for venue_id=#{venue_id}")

    case Repo.get(Venue, venue_id) do
      nil ->
        Logger.error("VenueMigrationJob: Venue not found: #{venue_id}")
        # Don't retry - venue doesn't exist
        :ok

      venue ->
        {:ok, stats} = VenueImageMigrator.migrate_venue(venue, priority: priority)

        Logger.info(
          "✅ VenueMigrationJob: Completed venue #{venue_id} - " <>
            "queued=#{stats.queued}, skipped=#{stats.skipped}, errors=#{stats.errors}"
        )

        :ok
    end
  end
end
