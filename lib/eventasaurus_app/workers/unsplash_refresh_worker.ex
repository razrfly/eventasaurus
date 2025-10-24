defmodule EventasaurusApp.Workers.UnsplashRefreshWorker do
  @moduledoc """
  Oban worker that refreshes Unsplash city images on a daily schedule.

  Runs daily to:
  1. Find all cities with discovery enabled
  2. Refresh cached Unsplash images for each city
  3. Handle rate limiting and failures gracefully

  ## Configuration

  The worker runs on a daily schedule and only processes cities where
  `discovery_enabled = true`. This ensures we only maintain image galleries
  for active cities.

  ## Rate Limiting

  Unsplash has a rate limit of 5000 requests/hour in production. With the
  default configuration:
  - 10 images per city
  - Random page (1-5) for variety
  - Retry logic with exponential backoff

  ## Scheduling

  Add to your Oban configuration in `config/config.exs`:

      config :eventasaurus_app, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             # Refresh Unsplash images daily at 3 AM UTC
             {"0 3 * * *", EventasaurusApp.Workers.UnsplashRefreshWorker}
           ]}
        ]
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias EventasaurusApp.Services.UnsplashImageFetcher
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("🖼️  Unsplash Refresh Worker: Starting scheduled refresh")

    # Get all active cities
    cities = get_active_cities()

    Logger.info("Found #{length(cities)} active cities to refresh")

    if Enum.empty?(cities) do
      Logger.info("No active cities found, skipping refresh")
      :ok
    else
      # Process each city with rate limiting delays
      results = Enum.map(cities, &refresh_city_images/1)

      # Summary statistics
      success_count = Enum.count(results, fn {status, _} -> status == :ok end)
      failure_count = length(results) - success_count

      Logger.info(
        "✅ Unsplash Refresh Worker: Complete (#{success_count} succeeded, #{failure_count} failed)"
      )

      :ok
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

  defp refresh_city_images(city) do
    Logger.info("Refreshing images for #{city.name}")

    case UnsplashImageFetcher.fetch_and_store_city_images(city.name) do
      {:ok, gallery} ->
        image_count = length(gallery["images"])
        Logger.info("  ✅ Successfully refreshed #{image_count} images for #{city.name}")
        {:ok, city.name}

      {:error, :rate_limited} ->
        Logger.warning("  ⚠️  Rate limited while refreshing #{city.name}, will retry later")
        {:error, :rate_limited}

      {:error, :max_retries_exceeded} ->
        Logger.warning("  ⚠️  Max retries exceeded for #{city.name}, skipping this cycle")

        {:error, :max_retries_exceeded}

      {:error, :no_images} ->
        Logger.warning("  ⚠️  No images found for #{city.name}")
        {:error, :no_images}

      {:error, reason} ->
        Logger.error("  ❌ Failed to refresh #{city.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
