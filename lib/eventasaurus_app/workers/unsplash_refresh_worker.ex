defmodule EventasaurusApp.Workers.UnsplashRefreshWorker do
  @moduledoc """
  Oban worker that refreshes Unsplash city images on a daily schedule.

  Runs daily to:
  1. Find all cities with discovery enabled
  2. Refresh all 5 categorized image galleries for each city
  3. Handle rate limiting and failures gracefully

  ## Categories

  Fetches images for all 5 categories per city:
  - general: City skyline and cityscape
  - architecture: Modern buildings and architecture
  - historic: Historic buildings and monuments
  - old_town: Old town and medieval areas
  - city_landmarks: Famous landmarks and attractions

  ## Configuration

  The worker runs on a daily schedule and only processes cities where
  `discovery_enabled = true`. This ensures we only maintain image galleries
  for active cities.

  ## Rate Limiting

  Unsplash has a rate limit of 5000 requests/hour in production. With the
  default configuration:
  - 10 images per category (50 total per city)
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
        order_by: c.name
      )

    Repo.all(query)
  end

  defp refresh_city_images(city) do
    Logger.info("Refreshing all categories for #{city.name}")

    case UnsplashImageFetcher.fetch_and_store_all_categories(city) do
      {:ok, updated_city} ->
        categories = get_in(updated_city.unsplash_gallery, ["categories"]) || %{}
        total_images = Enum.reduce(categories, 0, fn {_name, data}, acc ->
          acc + length(Map.get(data, "images", []))
        end)
        Logger.info("  ✅ Successfully refreshed #{map_size(categories)} categories with #{total_images} images for #{city.name}")
        {:ok, city.name}

      {:error, :inactive_city} ->
        Logger.warning("  ⚠️  City #{city.name} is not active (discovery_enabled = false)")
        {:error, :inactive_city}

      {:error, :all_categories_failed} ->
        Logger.error("  ❌ Failed to fetch any categories for #{city.name}")
        {:error, :all_categories_failed}

      {:error, reason} ->
        Logger.error("  ❌ Failed to refresh #{city.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
