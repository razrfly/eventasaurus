defmodule EventasaurusWeb.Cache.CityPageCacheInvalidation do
  @moduledoc """
  Telemetry handler for invalidating city page cache after scraper completions.

  Listens to Oban job completion events and triggers cache refresh when
  SyncJob workers complete successfully. This ensures city pages show
  fresh data after scrapers update events.

  ## How It Works

  1. Attaches to `[:oban, :job, :stop]` telemetry event
  2. Filters for SyncJob completions with :success state
  3. Extracts city information from job args (city_name, city_slug, etc.)
  4. Invalidates stale cache and enqueues cache refresh job

  ## City Detection

  Different scrapers store city info differently in job args:
  - Cinema City: `options.city_name` (e.g., "Kraków")
  - Repertuary: `city_slug` (e.g., "krakow")
  - Week.pl: `city_slug` (e.g., "warszawa")
  - Others: May need specific handling

  We normalize these to city slugs for cache invalidation.

  ## Usage

  Automatically attached during application startup:

      EventasaurusWeb.Cache.CityPageCacheInvalidation.attach()
  """

  require Logger

  alias EventasaurusWeb.Cache.CityPageCache
  alias EventasaurusWeb.Jobs.CityPageCacheRefreshJob
  alias EventasaurusDiscovery.Locations

  # Workers that trigger cache invalidation when completed
  @sync_job_patterns [
    "SyncJob",
    "RegionSyncJob"
  ]

  # Default radius for cache refresh (matches city page default)
  @default_radius_km 50

  @doc """
  Attaches telemetry handler for cache invalidation.

  Should be called once during application startup.
  """
  def attach do
    :telemetry.attach(
      "city-page-cache-invalidation",
      [:oban, :job, :stop],
      &__MODULE__.handle_event/4,
      nil
    )

    Logger.info("[CacheInvalidation] Attached telemetry handler for scraper completions")
  end

  @doc """
  Handles Oban job stop events.

  Only processes successful SyncJob completions to trigger cache refresh.
  """
  def handle_event([:oban, :job, :stop], _measurements, %{job: job, state: :success}, _config) do
    if sync_job?(job.worker) do
      process_sync_completion(job)
    end
  end

  # Ignore non-success states and other events
  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  # Check if worker is a SyncJob that should trigger cache invalidation
  defp sync_job?(worker) when is_binary(worker) do
    Enum.any?(@sync_job_patterns, fn pattern ->
      String.ends_with?(worker, pattern)
    end)
  end

  defp sync_job?(_), do: false

  # Process a successful SyncJob completion
  defp process_sync_completion(%{worker: worker, args: args}) do
    case extract_city_slug(args) do
      {:ok, city_slug} ->
        Logger.info("[CacheInvalidation] SyncJob completed for #{city_slug}, refreshing cache")

        # Invalidate existing cache entries for this city
        CityPageCache.invalidate_aggregated_events(city_slug)
        CityPageCache.invalidate_date_counts(city_slug)
        CityPageCache.invalidate_city_stats(city_slug)

        # Enqueue cache refresh with short delay (let DB settle)
        case CityPageCacheRefreshJob.enqueue(city_slug, @default_radius_km, schedule_in: 5) do
          {:ok, :duplicate} ->
            Logger.debug("[CacheInvalidation] Cache refresh already queued for #{city_slug}")

          {:ok, _} ->
            Logger.debug("[CacheInvalidation] Scheduled cache refresh for #{city_slug}")

          {:error, reason} ->
            Logger.warning(
              "[CacheInvalidation] Failed to schedule refresh for #{city_slug}: #{inspect(reason)}"
            )
        end

      {:error, :no_city} ->
        Logger.debug("[CacheInvalidation] No city found in #{worker} args, skipping")

      {:error, reason} ->
        Logger.warning(
          "[CacheInvalidation] Failed to extract city from #{worker}: #{inspect(reason)}"
        )
    end
  end

  # Extract city slug from job args
  # Different scrapers store city info differently
  defp extract_city_slug(args) when is_map(args) do
    cond do
      # Direct city_slug (Repertuary, Week.pl, etc.)
      is_binary(args["city_slug"]) and args["city_slug"] != "" ->
        {:ok, args["city_slug"]}

      # City name in options (Cinema City)
      is_map(args["options"]) and is_binary(args["options"]["city_name"]) ->
        city_name_to_slug(args["options"]["city_name"])

      # City name at top level
      is_binary(args["city_name"]) and args["city_name"] != "" ->
        city_name_to_slug(args["city_name"])

      # City ID - look up slug
      is_integer(args["city_id"]) ->
        city_id_to_slug(args["city_id"])

      # No city info found
      true ->
        {:error, :no_city}
    end
  end

  defp extract_city_slug(_), do: {:error, :invalid_args}

  # Convert city name to slug (e.g., "Kraków" -> "krakow")
  defp city_name_to_slug(city_name) when is_binary(city_name) do
    # Simple slug conversion for common Polish city names
    slug =
      city_name
      |> String.downcase()
      |> String.replace(~r/[ąà]/, "a")
      |> String.replace(~r/[ćç]/, "c")
      |> String.replace(~r/[ęè]/, "e")
      |> String.replace(~r/[łł]/, "l")
      |> String.replace(~r/[ńñ]/, "n")
      |> String.replace(~r/[óò]/, "o")
      |> String.replace(~r/[śş]/, "s")
      |> String.replace(~r/[źżž]/, "z")
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    # Verify city exists
    case Locations.get_city_by_slug(slug) do
      nil ->
        # Try without diacritics conversion (maybe already slugified)
        alt_slug =
          city_name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.trim("-")

        case Locations.get_city_by_slug(alt_slug) do
          nil -> {:error, :city_not_found}
          _city -> {:ok, alt_slug}
        end

      _city ->
        {:ok, slug}
    end
  end

  # Look up city by ID and return slug
  defp city_id_to_slug(city_id) when is_integer(city_id) do
    case EventasaurusApp.Repo.get(EventasaurusDiscovery.Locations.City, city_id) do
      nil -> {:error, :city_not_found}
      city -> {:ok, city.slug}
    end
  end
end
