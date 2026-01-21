defmodule EventasaurusApp.Workers.UnsplashRefreshWorker do
  @moduledoc """
  Coordinator worker that queues individual city and country image refresh jobs.

  This worker acts as a coordinator, queuing UnsplashCityRefreshWorker and
  UnsplashCountryRefreshWorker jobs. This enables parallel processing and better scalability.

  ## Process

  1. Find all cities with venue_count >= 3
  2. Find all countries with cities
  3. Queue individual refresh worker jobs for each city and country
  4. Jobs are processed in parallel by Oban's :unsplash queue

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
  alias EventasaurusApp.Workers.UnsplashCountryRefreshWorker
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Locations.Country
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    Logger.info("🖼️  Unsplash Refresh Coordinator: Starting scheduled refresh [job #{job_id}]")

    # Get all cities with venues
    cities = get_active_cities()
    total_venues = Enum.reduce(cities, 0, fn city, acc -> acc + city.venue_count end)
    Logger.info("Found #{length(cities)} cities with venues (#{total_venues} total venues)")

    # Get all countries
    countries = get_countries()
    Logger.info("Found #{length(countries)} countries")

    # Queue individual city refresh jobs with parent tracking
    city_jobs =
      Enum.map(cities, fn city ->
        UnsplashCityRefreshWorker.new(
          %{city_id: city.id},
          meta: %{"parent_job_id" => job_id, "job_role" => "worker", "entity_type" => "city"}
        )
      end)

    # Queue individual country refresh jobs with parent tracking
    country_jobs =
      Enum.map(countries, fn country ->
        UnsplashCountryRefreshWorker.new(
          %{country_id: country.id},
          meta: %{"parent_job_id" => job_id, "job_role" => "worker", "entity_type" => "country"}
        )
      end)

    # Combine all jobs
    all_jobs = city_jobs ++ country_jobs

    if Enum.empty?(all_jobs) do
      Logger.info("No cities or countries found, skipping refresh")
      {:ok, %{cities_queued: 0, countries_queued: 0, total_queued: 0}}
    else
      # Insert all jobs in a single transaction
      case Oban.insert_all(all_jobs) do
        [] ->
          Logger.error("❌ Unsplash Refresh Coordinator: Failed to queue jobs")
          {:error, :queue_failed}

        inserted_jobs ->
          count = length(inserted_jobs)
          city_count = length(city_jobs)
          country_count = length(country_jobs)

          Logger.info(
            "✅ Unsplash Refresh Coordinator: Queued #{count} refresh jobs (#{city_count} cities, #{country_count} countries)"
          )

          # Return results map for tracking
          {:ok,
           %{
             cities_queued: city_count,
             countries_queued: country_count,
             total_queued: count,
             job_role: "coordinator"
           }}
      end
    end
  end

  # Private functions

  defp get_active_cities do
    query =
      from(c in City,
        left_join: v in assoc(c, :venues),
        group_by: c.id,
        having: count(v.id) >= 3,
        order_by: c.name,
        select: %{id: c.id, name: c.name, venue_count: count(v.id)}
      )

    JobRepo.all(query)
  end

  defp get_countries do
    query =
      from(c in Country,
        left_join: cities in assoc(c, :cities),
        group_by: c.id,
        having: count(cities.id) > 0,
        order_by: c.name,
        select: %{id: c.id, name: c.name, city_count: count(cities.id)}
      )

    JobRepo.all(query)
  end
end
