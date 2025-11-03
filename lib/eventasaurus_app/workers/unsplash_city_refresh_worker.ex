defmodule EventasaurusApp.Workers.UnsplashCityRefreshWorker do
  @moduledoc """
  Oban worker that refreshes Unsplash images for a single city.

  This worker is queued by the UnsplashRefreshWorker coordinator to enable
  parallel processing of city image refreshes.

  ## Process

  1. Receives city_id as job argument
  2. Fetches all 5 categorized image galleries for the city
  3. Handles rate limiting and failures gracefully

  ## Categories

  Fetches images for all 5 categories per city:
  - general: City skyline and cityscape
  - architecture: Modern buildings and architecture
  - historic: Historic buildings and monuments
  - old_town: Old town and medieval areas
  - city_landmarks: Famous landmarks and attractions

  ## Rate Limiting

  Unsplash has a rate limit of 5000 requests/hour in production.
  Each city refresh makes approximately 5 API calls (one per category).

  ## Retry Strategy

  - max_attempts: 3
  - Exponential backoff for rate limit errors
  - Partial success is acceptable (some categories may fail)
  """

  use Oban.Worker, queue: :unsplash, max_attempts: 3

  alias EventasaurusApp.Services.UnsplashImageFetcher
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"city_id" => city_id}}) do
    Logger.info("🖼️  Unsplash City Refresh: Starting refresh for city_id=#{city_id}")

    case Repo.get(City, city_id) do
      nil ->
        Logger.error("City not found: #{city_id}")
        {:error, :city_not_found}

      city ->
        refresh_city_images(city)
    end
  end

  # Private functions

  defp refresh_city_images(city) do
    Logger.info("Refreshing all categories for #{city.name} (id=#{city.id})")

    case UnsplashImageFetcher.fetch_and_store_all_categories(city) do
      {:ok, updated_city} ->
        categories = get_in(updated_city.unsplash_gallery, ["categories"]) || %{}
        total_images = Enum.reduce(categories, 0, fn {_name, data}, acc ->
          acc + length(Map.get(data, "images", []))
        end)
        Logger.info("  ✅ Successfully refreshed #{map_size(categories)} categories with #{total_images} images for #{city.name}")
        :ok

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
