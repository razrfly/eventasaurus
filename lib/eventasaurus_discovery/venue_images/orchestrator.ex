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
  def fetch_venue_images(venue, provider_names \\ nil) when is_map(venue) do
    # Get enabled providers and optionally filter by provider names
    providers =
      case provider_names do
        nil ->
          # No filter, use all enabled providers
          get_enabled_image_providers()

        names when is_list(names) ->
          # Filter to only requested providers
          Logger.info("🔍 Filtering image providers to: #{inspect(names)}")
          all_providers = get_enabled_image_providers()
          filtered = Enum.filter(all_providers, fn p -> p.name in names end)
          Logger.info("✅ Found #{length(filtered)} matching provider(s)")
          filtered
      end

    if Enum.empty?(providers) do
      filter_msg = if provider_names, do: " matching #{inspect(provider_names)}", else: ""
      Logger.warning("⚠️ No active image providers configured#{filter_msg}")
      {:ok, [], %{providers_attempted: [], providers_succeeded: [], total_images_found: 0}}
    else
      aggregate_from_all_providers(venue, providers)
    end
  end

  @doc """
  Enriches a venue with images from providers and updates the database.

  Returns {:ok, venue} with updated venue_images and image_enrichment_metadata.

  ## Options

  - `:providers` - List of specific provider names to use (default: all enabled providers)
  - `:force` - Force re-enrichment even if not stale (default: false)
  - `:max_retries` - Maximum retry attempts on failure (default: 3)

  ## Staleness Policy

  Images are considered stale after 30 days.
  """
  def enrich_venue(venue, opts \\ []) do
    providers = Keyword.get(opts, :providers)
    force = Keyword.get(opts, :force, false)
    max_retries = Keyword.get(opts, :max_retries, 3)

    # Log provider override if specified
    if providers do
      Logger.info("🎯 Provider override active for venue #{venue.id}: using only #{inspect(providers)}")
    end

    if needs_enrichment?(venue, force) do
      do_enrich_venue(venue, providers, max_retries)
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
    with :ok <- RateLimiter.check_rate_limit(provider),
         {:ok, provider_module} <- get_provider_module_result(provider.name),
         {:ok, place_id} <- get_place_id(venue, provider.name) do
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
      {:error, :rate_limited} ->
        Logger.warning("⚠️ Skipping #{provider.name}: rate limit exceeded")
        {:error, provider.name, :rate_limited}

      {:error, :module_not_found} ->
        Logger.warning("⚠️ Provider module not found for: #{provider.name}")
        {:error, provider.name, :module_not_found}

      {:error, :no_place_id} ->
        Logger.debug("⏭️  Skipping #{provider.name}: no provider_id available")
        {:error, provider.name, :no_place_id}
    end
  end

  defp get_provider_module_result(provider_name) do
    case get_provider_module(provider_name) do
      nil -> {:error, :module_not_found}
      module -> {:ok, module}
    end
  end

  defp get_place_id(venue, provider_name) do
    case get_in(venue, [:provider_ids, provider_name]) || get_in(venue, ["provider_ids", provider_name]) do
      nil -> {:error, :no_place_id}
      place_id -> {:ok, place_id}
    end
  end

  defp process_results(results, providers) do
    attempted = Enum.map(providers, & &1.name)
    succeeded = []
    failed = []
    cost_breakdown = %{}
    requests_made = %{}
    error_details = %{}
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
              total_cost: (acc_meta[:total_cost] || 0.0) + cost,
              error_details: acc_meta[:error_details] || error_details
            }

            {acc_images ++ tagged_images, new_meta}

          {:error, provider_name, reason} ->
            new_meta = %{
              failed: [provider_name | (acc_meta[:failed] || failed)],
              succeeded: acc_meta[:succeeded] || succeeded,
              cost_breakdown: acc_meta[:cost_breakdown] || cost_breakdown,
              requests_made: acc_meta[:requests_made] || requests_made,
              total_cost: acc_meta[:total_cost] || 0.0,
              error_details:
                Map.put(
                  acc_meta[:error_details] || error_details,
                  provider_name,
                  reason
                )
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
        error_details: metadata[:error_details] || %{},
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
    # Add quality scores to all images
    |> Enum.map(&add_quality_score/1)
    # Deduplicate by URL, keeping highest quality version
    |> deduplicate_by_quality()
    # Sort by quality score (descending), then provider priority
    |> Enum.sort_by(fn img ->
      provider_priority = Map.get(priority_map, img.provider, 999)
      {-img.quality_score, provider_priority, img[:position] || 0}
    end)
    # Add final position
    |> Enum.with_index(1)
    |> Enum.map(fn {img, position} ->
      Map.put(img, :position, position)
    end)
  end

  # Calculate quality score for an image based on resolution and aspect ratio
  defp add_quality_score(image) do
    width = image[:width] || image["width"] || 0
    height = image[:height] || image["height"] || 0

    quality_score = calculate_quality_score(width, height)
    Map.put(image, :quality_score, quality_score)
  end

  # Quality scoring algorithm
  # Scores range from 0.0 to 1.0, with higher being better
  defp calculate_quality_score(width, height) when width > 0 and height > 0 do
    # Resolution score: normalize to 4MP (2048x2048)
    # Higher resolution = better score, with diminishing returns above 4MP
    resolution = width * height
    resolution_score = min(resolution / 4_000_000, 1.0) * 0.7

    # Aspect ratio score: prefer landscape images between 1.3:1 and 1.8:1
    # Common aspect ratios: 16:9 (1.78), 4:3 (1.33), 3:2 (1.5)
    aspect_ratio = width / height

    aspect_score =
      cond do
        aspect_ratio >= 1.3 and aspect_ratio <= 1.8 -> 0.3  # Ideal landscape
        aspect_ratio >= 1.0 and aspect_ratio < 1.3 -> 0.25  # Square-ish
        aspect_ratio > 1.8 and aspect_ratio <= 2.4 -> 0.25  # Wide landscape
        true -> 0.2  # Portrait or very wide
      end

    resolution_score + aspect_score
  end

  # No dimensions available - assign minimum score
  defp calculate_quality_score(_, _), do: 0.1

  # Deduplicate images by URL, keeping the highest quality version
  defp deduplicate_by_quality(images) do
    images
    |> Enum.group_by(fn img -> img.url || img["url"] end)
    |> Enum.map(fn {_url, duplicate_images} ->
      # If multiple images with same URL, pick highest quality
      duplicate_images
      |> Enum.max_by(fn img -> img.quality_score end)
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

  defp do_enrich_venue(venue, providers, max_retries) do
    Logger.info("🖼️  Enriching venue #{venue.id} (#{venue.name}) with images")

    venue_input = %{
      name: venue.name,
      latitude: venue.latitude,
      longitude: venue.longitude,
      provider_ids: venue.provider_ids || %{}
    }

    # fetch_venue_images_with_retry always returns {:ok, images, metadata}
    # even if no images found (images will be empty list)
    {:ok, images, metadata} = fetch_venue_images_with_retry(venue_input, providers, max_retries)
    update_venue_with_images(venue, images, metadata)
  end

  defp fetch_venue_images_with_retry(venue_input, providers, max_retries, attempt \\ 1) do
    case fetch_venue_images(venue_input, providers) do
      {:ok, images, metadata} when is_list(images) and length(images) > 0 ->
        {:ok, images, metadata}

      {:ok, [], _metadata} when attempt < max_retries ->
        # No images found, retry with backoff
        Logger.warning(
          "⚠️ Image fetch attempt #{attempt} found no images, retrying..."
        )

        # Exponential backoff: 1s, 2s, 4s...
        :timer.sleep(:math.pow(2, attempt - 1) * 1000 |> round())
        fetch_venue_images_with_retry(venue_input, providers, max_retries, attempt + 1)

      {:ok, images, metadata} ->
        # Either images found or max retries reached
        {:ok, images, metadata}
    end
  end

  defp update_venue_with_images(venue, images, metadata) do
    alias EventasaurusApp.Venues.Venue

    # Calculate next enrichment due date (30 days from now)
    # 30 days = 30 * 86400 seconds
    now = DateTime.utc_now()
    next_enrichment = DateTime.add(now, 30 * 86_400, :second) |> DateTime.to_iso8601()

    # Convert new images to proper structure with string keys (JSONB requirement)
    new_structured_images =
      Enum.map(images, fn img ->
        %{
          "url" => img.url || img["url"],
          "provider" => img.provider || img["provider"],
          "width" => img[:width] || img["width"],
          "height" => img[:height] || img["height"],
          "quality_score" => img[:quality_score] || img["quality_score"],
          "attribution" => img[:attribution] || img["attribution"],
          "fetched_at" => img[:fetched_at] || img["fetched_at"] || DateTime.to_iso8601(now)
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      end)

    # Merge with existing images (deduplicate by URL, keep highest quality)
    existing_images = venue.venue_images || []
    merged_images = merge_and_deduplicate_images(existing_images, new_structured_images)

    # Build enrichment metadata with history
    existing_metadata = venue.image_enrichment_metadata || %{}
    existing_history = existing_metadata["enrichment_history"] || []

    # Track which providers we've seen across all enrichments
    all_providers_used =
      (existing_metadata["providers_used"] || [])
      |> Kernel.++(metadata.providers_succeeded || metadata[:providers_succeeded] || [])
      |> Enum.uniq()

    # Calculate new images added (not just fetched)
    images_before = length(existing_images)
    images_after = length(merged_images)
    net_new_images = max(images_after - images_before, 0)

    # Create history entry for this enrichment
    history_entry = %{
      "enriched_at" => DateTime.to_iso8601(now),
      "providers" => metadata.providers_succeeded || metadata[:providers_succeeded] || [],
      "images_fetched" => length(images),
      "images_added" => net_new_images,
      "cost_usd" => metadata.total_cost || metadata[:total_cost] || 0.0
    }

    enrichment_metadata = %{
      "last_enriched_at" => DateTime.to_iso8601(now),
      "next_enrichment_due" => next_enrichment,
      "providers_used" => all_providers_used,
      "total_images_fetched" => length(merged_images),
      "cost_breakdown" => metadata.cost_breakdown || metadata[:cost_breakdown] || %{},
      "enrichment_history" => [history_entry | existing_history] |> Enum.take(10),  # Keep last 10
      "providers_failed" => metadata.providers_failed || metadata[:providers_failed] || [],
      "error_details" => metadata.error_details || metadata[:error_details] || %{}
    }

    # Use the specialized changeset function from Venue schema
    changeset = Venue.update_venue_images(venue, merged_images, enrichment_metadata)

    case Repo.update(changeset) do
      {:ok, updated_venue} ->
        providers_count = length(metadata.providers_succeeded || metadata[:providers_succeeded] || [])
        Logger.info(
          "✅ Stored #{length(merged_images)} images for venue #{venue.id} (+#{net_new_images} new) from #{providers_count} provider(s)"
        )

        {:ok, updated_venue}

      {:error, changeset} ->
        Logger.error("❌ Failed to update venue #{venue.id}: #{inspect(changeset.errors)}")
        {:error, :update_failed}
    end
  end

  # Merge existing and new images, deduplicating by URL and keeping highest quality
  defp merge_and_deduplicate_images(existing_images, new_images) do
    all_images = existing_images ++ new_images

    # Group by URL
    all_images
    |> Enum.group_by(fn img -> img["url"] end)
    |> Enum.map(fn {_url, duplicate_images} ->
      # Pick the image with highest quality score
      # Prefer images with quality_score, fall back to newest (last in list)
      duplicate_images
      |> Enum.max_by(
        fn img ->
          {
            img["quality_score"] || 0.0,
            img["fetched_at"] || "1970-01-01T00:00:00Z"
          }
        end
      )
    end)
    # Sort by quality score descending
    |> Enum.sort_by(fn img -> -(img["quality_score"] || 0.0) end)
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
