defmodule EventasaurusDiscovery.Geocoding.ProviderIdBackfillJob do
  @moduledoc """
  Oban job to backfill missing provider IDs for existing venues.

  This job solves the architectural limitation where venues only have ONE provider ID
  (from whichever provider was used for geocoding). The image enrichment system requires
  provider IDs from ALL providers to maximize image coverage.

  ## Problem

  - Geocoding stores only ONE provider ID per venue (first success)
  - Image enrichment requires provider IDs to query each provider's API
  - Without Foursquare IDs, we can't get Foursquare images (best coverage for venues)
  - Result: ~90% of potential image coverage unused

  ## Solution

  For each venue, attempt to get provider IDs from all providers using:
  - Foursquare: Coordinate + name search (best accuracy for venues)
  - Geoapify: Reverse geocoding (place ID from coordinates)
  - HERE: Reverse geocoding (place ID from coordinates)

  ## Usage

      # Backfill single venue
      %{venue_id: 360} |> EventasaurusDiscovery.Geocoding.ProviderIdBackfillJob.new() |> Oban.insert()

      # Backfill all venues (via mix task)
      mix backfill_provider_ids --all

  ## Rate Limiting

  - Foursquare: 500 requests/day limit (TIGHT - spread over time)
  - Geoapify: 3,000 requests/day (SAFE)
  - HERE: 250,000 requests/month (VERY SAFE)

  Job priority and queue configuration handle rate limiting automatically.
  """

  use Oban.Worker,
    queue: :geocoding,
    max_attempts: 3,
    priority: 2

  require Logger
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusApp.Venues.Venue

  @provider_modules %{
    "foursquare" => EventasaurusDiscovery.Geocoding.Providers.Foursquare,
    "geoapify" => EventasaurusDiscovery.Geocoding.Providers.Geoapify,
    "here" => EventasaurusDiscovery.Geocoding.Providers.Here
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_id" => venue_id}}) do
    Logger.info("🔄 Backfill job starting for venue ##{venue_id}")

    case JobRepo.get(Venue, venue_id) do
      nil ->
        Logger.warning("⚠️ Venue ##{venue_id} not found")
        {:error, :venue_not_found}

      venue ->
        backfill_venue(venue)
    end
  end

  defp backfill_venue(venue) do
    # Check if venue has coordinates
    if is_nil(venue.latitude) or is_nil(venue.longitude) do
      Logger.warning("⚠️ Venue ##{venue.id} has no coordinates, skipping")
      {:ok, :no_coordinates}
    else
      # Get existing provider_ids (may be nil or empty map)
      # Normalize keys to strings to prevent atom/string mix
      existing_ids =
        (venue.provider_ids || %{})
        |> Enum.map(fn {k, v} -> {to_string(k), v} end)
        |> Enum.into(%{})

      Logger.info(
        "📍 Venue ##{venue.id} \"#{venue.name}\" at #{venue.latitude},#{venue.longitude}"
      )

      Logger.info("   Existing IDs: #{inspect(Map.keys(existing_ids))}")

      # Try to get IDs from providers that don't have them yet
      new_ids = collect_missing_provider_ids(venue, existing_ids)

      if map_size(new_ids) > 0 do
        # Merge with existing and update venue
        updated_ids = Map.merge(existing_ids, new_ids)

        case JobRepo.update(Ecto.Changeset.change(venue, provider_ids: updated_ids)) do
          {:ok, _updated_venue} ->
            Logger.info(
              "✅ Venue ##{venue.id} updated with #{map_size(new_ids)} new provider IDs: #{inspect(Map.keys(new_ids))}"
            )

            {:ok, :updated, new_ids}

          {:error, changeset} ->
            Logger.error("❌ Failed to update venue ##{venue.id}: #{inspect(changeset.errors)}")
            {:error, :update_failed}
        end
      else
        Logger.info(
          "ℹ️  Venue ##{venue.id} already has all available provider IDs or no new IDs found"
        )

        {:ok, :no_changes}
      end
    end
  end

  defp collect_missing_provider_ids(venue, existing_ids) do
    # Try each provider that doesn't already have an ID
    @provider_modules
    |> Enum.filter(fn {provider_name, _module} ->
      # Skip if we already have this provider's ID
      !Map.has_key?(existing_ids, provider_name)
    end)
    |> Enum.reduce(%{}, fn {provider_name, provider_module}, acc ->
      case get_provider_id(venue, provider_module, provider_name) do
        {:ok, provider_id} ->
          Logger.info("   ✅ #{provider_name}: #{provider_id}")
          Map.put(acc, provider_name, provider_id)

        {:error, :api_key_missing} ->
          Logger.debug("   ⏭️  #{provider_name}: API key not configured")
          acc

        {:error, :rate_limited} ->
          Logger.warning("   ⚠️  #{provider_name}: rate limited (will retry)")
          acc

        {:error, reason} ->
          Logger.debug("   ❌ #{provider_name}: #{reason}")
          acc
      end
    end)
  end

  defp get_provider_id(venue, provider_module, provider_name) do
    # Use the new search_by_coordinates method
    # Pass venue name for Foursquare (helps with matching)
    # Other providers ignore it but accept it for API consistency
    venue_name = venue.name

    try do
      provider_module.search_by_coordinates(
        venue.latitude,
        venue.longitude,
        venue_name
      )
    rescue
      e ->
        Logger.error("   ❌ #{provider_name} search_by_coordinates crashed: #{inspect(e)}")
        {:error, :provider_error}
    catch
      :exit, reason ->
        Logger.error("   ❌ #{provider_name} search_by_coordinates exited: #{inspect(reason)}")
        {:error, :provider_error}
    end
  end
end
