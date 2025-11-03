defmodule EventasaurusApp.Workers.UnsplashRefreshWorker do
  @moduledoc """
  Coordinator worker that queues individual city image refresh jobs.

  This worker acts as a coordinator, queuing UnsplashCityRefreshWorker jobs
  for each active city. This enables parallel processing and better scalability.

  ## Process

  1. Find all cities with discovery_enabled = true
  2. Queue individual UnsplashCityRefreshWorker jobs for each city
  3. Jobs are processed in parallel by Oban's :unsplash queue

  ## Benefits of Coordinator Pattern

  - **Parallel Processing**: Cities are refreshed concurrently instead of sequentially
  - **Better Retry Logic**: Each city has independent retry attempts
  - **Improved Observability**: Track individual city job status in Oban dashboard
  - **Resource Management**: Oban handles queue concurrency and rate limiting

  ## Categories

  Each queued city job fetches images for all 5 categories:
  - general: City skyline and cityscape
  - architecture: Modern buildings and architecture
  - historic: Historic buildings and monuments
  - old_town: Old town and medieval areas
  - city_landmarks: Famous landmarks and attractions

  ## Configuration

  The coordinator runs on a daily schedule. Configure in `config/config.exs`:

      config :eventasaurus_app, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             # Queue city refresh jobs daily at 3 AM UTC
             {"0 3 * * *", EventasaurusApp.Workers.UnsplashRefreshWorker}
           ]}
        ],
        queues: [
          maintenance: 10,
          unsplash: 3  # Process 3 city refreshes concurrently
        ]

  ## Rate Limiting

  Unsplash has a rate limit of 5000 requests/hour in production.
  With 3 concurrent city jobs and 5 API calls per city, we stay well under limits.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias EventasaurusApp.Workers.UnsplashCityRefreshWorker
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("🖼️  Unsplash Refresh Coordinator: Starting scheduled refresh")

    # Get all active cities
    cities = get_active_cities()

    Logger.info("Found #{length(cities)} active cities to queue for refresh")

    if Enum.empty?(cities) do
      Logger.info("No active cities found, skipping refresh")
      :ok
    else
      # Queue individual city refresh jobs
      jobs = Enum.map(cities, fn city ->
        UnsplashCityRefreshWorker.new(%{city_id: city.id})
      end)

      # Insert all jobs in a single transaction
      case Oban.insert_all(jobs) do
        [] ->
          Logger.error("❌ Unsplash Refresh Coordinator: Failed to queue city jobs")
          {:error, :queue_failed}

        inserted_jobs ->
          count = length(inserted_jobs)
          Logger.info("✅ Unsplash Refresh Coordinator: Queued #{count} city refresh jobs")
          :ok
      end
    end
  end

  # Private functions

  defp get_active_cities do
    query =
      from(c in City,
        where: c.discovery_enabled == true,
        order_by: c.name,
        select: %{id: c.id, name: c.name}
      )

    Repo.all(query)
  end
end
