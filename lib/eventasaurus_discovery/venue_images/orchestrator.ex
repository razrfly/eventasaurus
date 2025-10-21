defmodule EventasaurusDiscovery.VenueImages.Orchestrator do
  @moduledoc """
  Orchestrates venue image fetching across multiple providers.

  Unlike geocoding (which returns on first success), this orchestrator:
  1. Queries ALL active image providers in parallel
  2. Aggregates results from all providers
  3. Deduplicates images by URL
  4. Tracks costs, attempts, and success rates
  5. Returns merged results sorted by provider priority

  ## Usage

      venue = %{
        name: "Blue Note Jazz Club",
        latitude: 40.7308,
        longitude: -74.0007,
        provider_ids: %{"google_places" => "ChIJ...", "foursquare" => "4b..."}
      }

      {:ok, images, metadata} = Orchestrator.fetch_venue_images(venue)

  ## Metadata Structure

      %{
        providers_attempted: ["google_places", "foursquare", "here"],
        providers_succeeded: ["google_places", "foursquare"],
        total_images_found: 15,
        total_cost: 0.007,
        fetched_at: ~U[2025-01-21 12:00:00Z]
      }
  """

  require Logger
  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider
  alias EventasaurusDiscovery.VenueImages.RateLimiter

  @doc """
  Fetches images for a venue from all active image providers.

  Returns {:ok, images, metadata} where:
  - images: List of deduplicated image maps with position
  - metadata: Hash with attempt tracking and costs
  """
  def fetch_venue_images(venue) when is_map(venue) do
    providers = get_enabled_image_providers()

    if Enum.empty?(providers) do
      Logger.warning("⚠️ No active image providers configured")
      {:ok, [], %{providers_attempted: [], providers_succeeded: [], total_images_found: 0}}
    else
      aggregate_from_all_providers(venue, providers)
    end
  end

  @doc """
  Enriches a venue with images from all providers and updates the database.

  Returns {:ok, venue} with updated venue_images and image_enrichment_metadata.

  ## Options

  - `:force` - Force re-enrichment even if not stale (default: false)
  - `:max_retries` - Maximum retry attempts on failure (default: 3)

  ## Staleness Policy

  Images are considered stale after 30 days.
  """
  def enrich_venue(venue, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    max_retries = Keyword.get(opts, :max_retries, 3)

    if needs_enrichment?(venue, force) do
      do_enrich_venue(venue, max_retries)
    else
      Logger.debug("⏭️  Venue #{venue.id} images are fresh, skipping enrichment")
      {:ok, venue}
    end
  end

  @doc """
  Checks if a venue needs image enrichment.

  A venue needs enrichment if:
  - It has never been enriched (no image_enrichment_metadata)
  - It has no images (empty venue_images)
  - Images are stale (>30 days old)
  - Force flag is true
  """
  def needs_enrichment?(venue, force \\ false)

  def needs_enrichment?(_venue, true), do: true

  def needs_enrichment?(venue, false) do
    metadata = venue.image_enrichment_metadata || %{}

    cond do
      # Never enriched
      is_nil(metadata["last_enriched_at"]) and is_nil(metadata[:last_enriched_at]) ->
        true

      # No images
      is_nil(venue.venue_images) or venue.venue_images == [] ->
        true

      # Check staleness
      true ->
        last_enriched =
          metadata["last_enriched_at"] || metadata[:last_enriched_at]

        case parse_datetime(last_enriched) do
          {:ok, last_enriched_dt} ->
            staleness_days = DateTime.diff(DateTime.utc_now(), last_enriched_dt, :day)
            staleness_days > 30

          {:error, _} ->
            # Can't parse timestamp, assume stale
            true
        end
    end
  end

  @doc """
  Gets all active providers that support image fetching.

  Filters by:
  - is_active = true
  - capabilities.images = true
  - Ordered by priorities.images (lower = higher priority)
  """
  def get_enabled_image_providers do
    from(p in GeocodingProvider,
      where: p.is_active == true,
      where: fragment("? @> ?", p.capabilities, ^%{"images" => true}),
      order_by: [
        asc:
          fragment(
            "COALESCE(CAST(? ->> 'images' AS INTEGER), 999)",
            p.priorities
          )
      ]
    )
    |> Repo.all()
  end

  # Private Functions

  defp aggregate_from_all_providers(venue, providers) do
    Logger.info("🖼️  Fetching images from #{length(providers)} providers for: #{venue.name}")

    # Fetch from all providers in parallel using Task.async_stream
    results =
      providers
      |> Task.async_stream(
        fn provider ->
          fetch_from_provider(venue, provider)
        end,
        max_concurrency: 5,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, :timeout, reason}
      end)

    # Aggregate results
    {images, metadata} = process_results(results, providers)

    # Deduplicate and sort
    final_images = deduplicate_and_sort(images, providers)

    Logger.info(
      "✅ Aggregated #{length(final_images)} unique images from #{length(metadata.providers_succeeded)} providers"
    )

    {:ok, final_images, metadata}
  end

  defp fetch_from_provider(venue, provider) do
    # Check rate limits before making request
    case RateLimiter.check_rate_limit(provider) do
      :ok ->
        provider_module = get_provider_module(provider.name)

        if provider_module do
          # Extract provider-specific place_id from venue.provider_ids map
          place_id =
            get_in(venue, [:provider_ids, provider.name]) ||
              get_in(venue, ["provider_ids", provider.name])

          if place_id do
            # Record request for rate limiting
            RateLimiter.record_request(provider.name)

            # Provider has a stored place_id, use it directly
            case provider_module.get_images(place_id) do
              {:ok, images} when is_list(images) ->
                {:ok, provider.name, images, calculate_cost(provider, length(images))}

              {:error, reason} ->
                Logger.warning("⚠️ #{provider.name} failed: #{inspect(reason)}")
                {:error, provider.name, reason}
            end
          else
            # No stored place_id for this provider, skip
            Logger.debug("⏭️  Skipping #{provider.name}: no provider_id available")
            {:error, provider.name, :no_place_id}
          end
        else
          Logger.warning("⚠️ Provider module not found for: #{provider.name}")
          {:error, provider.name, :module_not_found}
        end

      {:error, :rate_limited} ->
        Logger.warning("⚠️ Skipping #{provider.name}: rate limit exceeded")
        {:error, provider.name, :rate_limited}
    end
  end

  defp process_results(results, providers) do
    attempted = Enum.map(providers, & &1.name)
    succeeded = []
    failed = []
    cost_breakdown = %{}
    requests_made = %{}
    all_images = []

    {images, metadata} =
      Enum.reduce(results, {all_images, %{}}, fn result, {acc_images, acc_meta} ->
        case result do
          {:ok, provider_name, images, cost} ->
            # Tag each image with provider
            tagged_images =
              Enum.map(images, fn img ->
                Map.merge(img, %{
                  provider: provider_name,
                  fetched_at: DateTime.utc_now() |> DateTime.to_iso8601()
                })
              end)

            new_meta = %{
              succeeded: [provider_name | (acc_meta[:succeeded] || succeeded)],
              cost_breakdown:
                Map.put(
                  acc_meta[:cost_breakdown] || cost_breakdown,
                  provider_name,
                  cost
                ),
              requests_made:
                Map.put(
                  acc_meta[:requests_made] || requests_made,
                  provider_name,
                  1
                ),
              total_cost: (acc_meta[:total_cost] || 0.0) + cost
            }

            {acc_images ++ tagged_images, new_meta}

          {:error, provider_name, _reason} ->
            new_meta = %{
              failed: [provider_name | (acc_meta[:failed] || failed)],
              succeeded: acc_meta[:succeeded] || succeeded,
              cost_breakdown: acc_meta[:cost_breakdown] || cost_breakdown,
              requests_made: acc_meta[:requests_made] || requests_made,
              total_cost: acc_meta[:total_cost] || 0.0
            }

            {acc_images, new_meta}

          _ ->
            {acc_images, acc_meta}
        end
      end)

    final_metadata =
      Map.merge(metadata, %{
        providers_attempted: attempted,
        providers_succeeded: Enum.reverse(metadata[:succeeded] || []),
        providers_failed: Enum.reverse(metadata[:failed] || []),
        cost_breakdown: metadata[:cost_breakdown] || %{},
        requests_made: metadata[:requests_made] || %{},
        total_images_found: length(images),
        total_cost: metadata[:total_cost] || 0.0,
        fetched_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {images, final_metadata}
  end

  defp deduplicate_and_sort(images, providers) do
    # Create priority map from providers
    priority_map =
      providers
      |> Enum.with_index()
      |> Map.new(fn {provider, idx} -> {provider.name, idx} end)

    images
    # Deduplicate by URL (keep first occurrence)
    |> Enum.uniq_by(& &1.url)
    # Sort by provider priority, then original position
    |> Enum.sort_by(fn img ->
      provider_priority = Map.get(priority_map, img.provider, 999)
      {provider_priority, img[:position] || 0}
    end)
    # Add final position
    |> Enum.with_index(1)
    |> Enum.map(fn {img, position} ->
      Map.put(img, :position, position)
    end)
  end

  defp calculate_cost(provider, image_count) do
    # Extract cost per image from provider metadata
    cost_per_image =
      get_in(provider.metadata, ["cost_per_image"]) ||
        get_in(provider.metadata, [:cost_per_image]) ||
        0.0

    cost_per_image * image_count
  end

  defp get_provider_module(provider_name) do
    # Map provider names to their modules
    # This uses the multi-capability provider pattern from issue #1918
    case provider_name do
      "google_places" -> EventasaurusDiscovery.Geocoding.Providers.GooglePlaces
      "foursquare" -> EventasaurusDiscovery.Geocoding.Providers.Foursquare
      "here" -> EventasaurusDiscovery.Geocoding.Providers.Here
      "geoapify" -> EventasaurusDiscovery.Geocoding.Providers.Geoapify
      "unsplash" -> EventasaurusDiscovery.VenueImages.Providers.Unsplash
      _ -> nil
    end
  end

  # Enrichment Functions

  defp do_enrich_venue(venue, max_retries) do
    Logger.info("🖼️  Enriching venue #{venue.id} (#{venue.name}) with images")

    venue_input = %{
      name: venue.name,
      latitude: venue.latitude,
      longitude: venue.longitude,
      provider_ids: venue.provider_ids || %{}
    }

    case fetch_venue_images_with_retry(venue_input, max_retries) do
      {:ok, images, metadata} ->
        update_venue_with_images(venue, images, metadata)

      {:error, reason} ->
        Logger.error("❌ Failed to enrich venue #{venue.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_venue_images_with_retry(venue_input, max_retries, attempt \\ 1) do
    case fetch_venue_images(venue_input) do
      {:ok, images, metadata} when is_list(images) ->
        {:ok, images, metadata}

      {:error, reason} when attempt < max_retries ->
        Logger.warning(
          "⚠️ Image fetch attempt #{attempt} failed: #{inspect(reason)}, retrying..."
        )

        # Exponential backoff: 1s, 2s, 4s...
        :timer.sleep(:math.pow(2, attempt - 1) * 1000 |> round())
        fetch_venue_images_with_retry(venue_input, max_retries, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_venue_with_images(venue, images, metadata) do
    import Ecto.Changeset

    # Calculate next enrichment due date (30 days from now)
    next_enrichment = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_iso8601()

    enrichment_metadata =
      Map.merge(metadata, %{
        "last_enriched_at" => metadata.fetched_at,
        "next_enrichment_due" => next_enrichment
      })

    changeset =
      venue
      |> change()
      |> put_change(:venue_images, images)
      |> put_change(:image_enrichment_metadata, enrichment_metadata)

    case Repo.update(changeset) do
      {:ok, updated_venue} ->
        Logger.info(
          "✅ Enriched venue #{venue.id} with #{length(images)} images from #{length(metadata.providers_succeeded)} providers"
        )

        {:ok, updated_venue}

      {:error, changeset} ->
        Logger.error("❌ Failed to update venue #{venue.id}: #{inspect(changeset.errors)}")
        {:error, :update_failed}
    end
  end

  defp parse_datetime(nil), do: {:error, :nil}

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: {:ok, dt}
  defp parse_datetime(_), do: {:error, :invalid_type}
end
