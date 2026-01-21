defmodule EventasaurusApp.Workers.UnsplashCountryRefreshWorker do
  @moduledoc """
  Oban worker that refreshes Unsplash images for a single country.

  This worker is queued by the UnsplashRefreshWorker coordinator to enable
  parallel processing of country image refreshes.

  ## Process

  1. Receives country_id as job argument
  2. Checks if images are stale (based on last_refreshed_at and configured interval)
  3. Fetches all 5 categorized image galleries for the country if stale
  4. Handles rate limiting and failures gracefully

  ## Categories

  Fetches images for all 5 categories per country:
  - general: Country landscapes and iconic views
  - architecture: Modern buildings and architecture
  - historic: Historic buildings and monuments
  - landmarks: Famous landmarks and attractions
  - nature: Natural landscapes and scenery

  ## Refresh Interval

  Images are only refreshed if stale (older than configured interval).
  Default: 7 days (configurable via UNSPLASH_COUNTRY_REFRESH_DAYS env var).

  ## Rate Limiting

  Unsplash has a rate limit of 5000 requests/hour in production.
  Each country refresh makes approximately 5 API calls (one per category).
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
  alias EventasaurusDiscovery.Locations.Country
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"country_id" => country_id}}) do
    Logger.info("🖼️  Unsplash Country Refresh: Starting refresh for country_id=#{country_id}")

    case JobRepo.get(Country, country_id) do
      nil ->
        Logger.error("Country not found: #{country_id}")
        {:error, :country_not_found}

      country ->
        refresh_days = Application.get_env(:eventasaurus, :unsplash)[:country_refresh_days] || 7

        case should_refresh?(country, refresh_days) do
          {true, reason} ->
            Logger.info("🔄 Refreshing #{country.name} - #{reason}")
            refresh_country_images(country, country_id)

          {false, age_days} ->
            Logger.info(
              "⏭️  Skipping #{country.name} - images are fresh (#{age_days} days old, threshold: #{refresh_days} days)"
            )

            {:ok,
             %{
               country_id: country_id,
               country_name: country.name,
               skipped: true,
               reason: "images_fresh",
               age_days: age_days,
               job_role: "worker"
             }}
        end
    end
  end

  # Private functions

  defp refresh_country_images(country, country_id) do
    Logger.info("Refreshing all categories for #{country.name} (id=#{country.id})")

    case UnsplashImageFetcher.fetch_and_store_all_categories_for_country(country) do
      {:ok, updated_country} ->
        categories = get_in(updated_country.unsplash_gallery, ["categories"]) || %{}

        total_images =
          Enum.reduce(categories, 0, fn {_name, data}, acc ->
            acc + length(Map.get(data, "images", []))
          end)

        Logger.info(
          "  ✅ Successfully refreshed #{map_size(categories)} categories with #{total_images} images for #{country.name}"
        )

        # Return results map for tracking
        {:ok,
         %{
           country_id: country_id,
           country_name: country.name,
           categories_refreshed: map_size(categories),
           images_fetched: total_images,
           skipped: false,
           job_role: "worker"
         }}

      {:error, :all_categories_failed} ->
        Logger.error("  ❌ Failed to fetch any categories for #{country.name}")
        {:error, :all_categories_failed}

      {:error, reason} ->
        Logger.error("  ❌ Failed to refresh #{country.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Check if a country's images need refreshing based on staleness.
  #
  # Returns {true, reason} if refresh needed, {false, age_days} if still fresh
  defp should_refresh?(%Country{unsplash_gallery: nil}, _refresh_days) do
    {true, "no gallery exists"}
  end

  defp should_refresh?(%Country{unsplash_gallery: gallery}, refresh_days) when is_map(gallery) do
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
