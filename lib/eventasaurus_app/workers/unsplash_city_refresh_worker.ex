defmodule EventasaurusApp.Workers.UnsplashCityRefreshWorker do
  @moduledoc """
  Oban worker that refreshes Unsplash images for a single city.

  This worker is queued by the UnsplashRefreshWorker coordinator to enable
  parallel processing of city image refreshes.

  ## Process

  1. Receives city_id as job argument
  2. Checks if images are stale (based on last_refreshed_at and configured interval)
  3. Fetches all 5 categorized image galleries for the city if stale
  4. Handles rate limiting and failures gracefully

  ## Categories

  Fetches images for all 5 categories per city:
  - general: City skyline and cityscape
  - architecture: Modern buildings and architecture
  - historic: Historic buildings and monuments
  - old_town: Old town and medieval areas
  - city_landmarks: Famous landmarks and attractions

  ## Refresh Interval

  Images are only refreshed if stale (older than configured interval).
  Default: 7 days (configurable via UNSPLASH_CITY_REFRESH_DAYS env var).

  ## Rate Limiting

  Unsplash has a rate limit of 5000 requests/hour in production.
  Each city refresh makes approximately 5 API calls (one per category).
  With staleness checking, actual API usage is reduced by ~85%.

  ## Retry Strategy

  - max_attempts: 3
  - Exponential backoff for rate limit errors
  - Partial success is acceptable (some categories may fail)
  """

  use Oban.Worker, queue: :enrichment, max_attempts: 3

  alias EventasaurusApp.Services.UnsplashImageFetcher
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Locations.City
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"city_id" => city_id}}) do
    Logger.info("🖼️  Unsplash City Refresh: Starting refresh for city_id=#{city_id}")

    case JobRepo.get(City, city_id) do
      nil ->
        Logger.error("City not found: #{city_id}")
        {:error, :city_not_found}

      city ->
        refresh_days = Application.get_env(:eventasaurus, :unsplash)[:city_refresh_days] || 7

        case should_refresh?(city, refresh_days) do
          {true, reason} ->
            Logger.info("🔄 Refreshing #{city.name} - #{reason}")
            refresh_city_images(city, city_id)

          {false, age_days} ->
            Logger.info(
              "⏭️  Skipping #{city.name} - images are fresh (#{age_days} days old, threshold: #{refresh_days} days)"
            )

            {:ok,
             %{
               city_id: city_id,
               city_name: city.name,
               skipped: true,
               reason: "images_fresh",
               age_days: age_days,
               job_role: "worker"
             }}
        end
    end
  end

  # Private functions

  defp refresh_city_images(city, city_id) do
    Logger.info("Refreshing all categories for #{city.name} (id=#{city.id})")

    case UnsplashImageFetcher.fetch_and_store_all_categories(city) do
      {:ok, updated_city} ->
        categories = get_in(updated_city.unsplash_gallery, ["categories"]) || %{}

        total_images =
          Enum.reduce(categories, 0, fn {_name, data}, acc ->
            acc + length(Map.get(data, "images", []))
          end)

        Logger.info(
          "  ✅ Successfully refreshed #{map_size(categories)} categories with #{total_images} images for #{city.name}"
        )

        # Return results map for tracking
        {:ok,
         %{
           city_id: city_id,
           city_name: city.name,
           categories_refreshed: map_size(categories),
           images_fetched: total_images,
           skipped: false,
           job_role: "worker"
         }}

      {:error, :all_categories_failed} ->
        Logger.error("  ❌ Failed to fetch any categories for #{city.name}")
        {:error, :all_categories_failed}

      {:error, reason} ->
        Logger.error("  ❌ Failed to refresh #{city.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Check if a city's images need refreshing based on staleness.
  #
  # Returns {true, reason} if refresh needed, {false, age_days} if still fresh
  defp should_refresh?(%City{unsplash_gallery: nil}, _refresh_days) do
    {true, "no gallery exists"}
  end

  defp should_refresh?(%City{unsplash_gallery: gallery}, refresh_days) when is_map(gallery) do
    categories = Map.get(gallery, "categories", %{})

    cond do
      map_size(categories) == 0 ->
        {true, "gallery has no categories"}

      true ->
        check_category_staleness(categories, refresh_days)
    end
  end

  # Check if any category is stale based on last_refreshed_at
  # Returns {true, reason} if stale, {false, age_days} if fresh
  defp check_category_staleness(categories, refresh_days) do
    refresh_timestamps =
      categories
      |> Map.values()
      |> Enum.map(&Map.get(&1, "last_refreshed_at"))
      |> Enum.reject(&is_nil/1)

    cond do
      Enum.empty?(refresh_timestamps) ->
        {true, "no refresh timestamps found"}

      true ->
        oldest_refresh_str = Enum.min(refresh_timestamps)

        case DateTime.from_iso8601(oldest_refresh_str) do
          {:ok, oldest_refresh, _offset} ->
            cutoff = DateTime.add(DateTime.utc_now(), -refresh_days, :day)
            age_days = div(DateTime.diff(DateTime.utc_now(), oldest_refresh, :second), 86400)

            if DateTime.compare(oldest_refresh, cutoff) == :lt do
              {true, "images are #{age_days} days old (threshold: #{refresh_days} days)"}
            else
              {false, age_days}
            end

          {:error, _reason} ->
            {true, "invalid refresh timestamp"}
        end
    end
  end
end
