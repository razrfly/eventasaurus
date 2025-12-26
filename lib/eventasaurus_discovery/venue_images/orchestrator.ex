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
  alias EventasaurusApp.Images.ImageCacheService
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
  - `:retry_failed_only` - Only retry existing failed uploads, don't call providers (default: false)

  ## Staleness Policy

  Images are considered stale after 30 days.
  """
  def enrich_venue(venue, opts \\ []) do
    retry_failed_only = Keyword.get(opts, :retry_failed_only, false)

    # If retry_failed_only mode, delegate to retry worker
    if retry_failed_only do
      alias EventasaurusDiscovery.VenueImages.FailedUploadRetryWorker

      Logger.info("🔄 Retry-only mode: skipping provider API calls for venue #{venue.id}")

      case FailedUploadRetryWorker.perform_now(venue) do
        {:ok, %EventasaurusApp.Venues.Venue{} = updated_venue} ->
          {:ok, updated_venue}

        {:ok, _msg} ->
          # If no retries were performed, return the original venue
          {:ok, Repo.get!(EventasaurusApp.Venues.Venue, venue.id)}

        {:error, _} = err ->
          err
      end
    else
      # Normal enrichment flow
      providers = Keyword.get(opts, :providers)
      force = Keyword.get(opts, :force, false)
      max_retries = Keyword.get(opts, :max_retries, 3)

      # Log provider override if specified
      if providers do
        Logger.info(
          "🎯 Provider override active for venue #{venue.id}: using only #{inspect(providers)}"
        )
      end

      if needs_enrichment?(venue, force) do
        do_enrich_venue(venue, providers, max_retries)
      else
        Logger.debug("⏭️  Venue #{venue.id} images are fresh, skipping enrichment")
        {:ok, venue}
      end
    end
  end

  @doc """
  Checks if a venue needs image enrichment using simplified 3-criteria logic.

  ## The Three Criteria

  1. **Never Checked Before** (Priority 1)
     - No `last_checked_at` timestamp in metadata
     - Always enqueue - we don't know if images exist

  2. **When Last Checked** (Priority 2 & 3)
     - Check `last_checked_at` timestamp against cooldown period
     - Cooldown period depends on whether venue has images

  3. **Has Images**
     - Determines cooldown period:
       - With images: 90 days (refresh quarterly)
       - Without images: 7 days (retry weekly)

  ## Examples

  - Never checked → ✅ ENQUEUE
  - Checked 3 days ago, no images → ❌ SKIP (within 7-day cooldown)
  - Checked 10 days ago, no images → ✅ ENQUEUE (past 7-day cooldown)
  - Checked 50 days ago, has images → ❌ SKIP (within 90-day cooldown)
  - Checked 100 days ago, has images → ✅ ENQUEUE (past 90-day cooldown)
  """
  def needs_enrichment?(venue, force \\ false)

  def needs_enrichment?(_venue, true), do: true

  def needs_enrichment?(venue, false) do
    # Simple 3-criteria check:
    # 1. Never checked? → enqueue
    # 2. When last checked? → compare to cooldown
    # 3. Has images? → determines cooldown period (7 days vs 90 days)

    metadata = venue.image_enrichment_metadata || %{}
    last_checked = metadata["last_checked_at"] || metadata[:last_checked_at]

    # Priority 1: Never checked before
    if is_nil(last_checked) do
      true
    else
      # Priority 2 & 3: Check based on staleness + image status
      case parse_datetime(last_checked) do
        {:ok, last_checked_dt} ->
          days_since_check = DateTime.diff(DateTime.utc_now(), last_checked_dt, :day)
          has_images = venue.venue_images && length(venue.venue_images) > 0

          # Different cooldowns based on whether venue has images
          cooldown_days =
            if has_images do
              # Venues with images: refresh every 90 days
              90
            else
              # Venues without images: retry every 7 days (configurable)
              Application.get_env(:eventasaurus, :venue_images, [])
              |> Keyword.get(:no_images_cooldown_days, 7)
            end

          days_since_check >= cooldown_days

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
    case get_in(venue, [:provider_ids, provider_name]) ||
           get_in(venue, ["provider_ids", provider_name]) do
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
              succeeded: [provider_name | acc_meta[:succeeded] || succeeded],
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
              failed: [provider_name | acc_meta[:failed] || failed],
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
        # Ideal landscape
        aspect_ratio >= 1.3 and aspect_ratio <= 1.8 -> 0.3
        # Square-ish
        aspect_ratio >= 1.0 and aspect_ratio < 1.3 -> 0.25
        # Wide landscape
        aspect_ratio > 1.8 and aspect_ratio <= 2.4 -> 0.25
        # Portrait or very wide
        true -> 0.2
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
        Logger.warning("⚠️ Image fetch attempt #{attempt} found no images, retrying...")

        # Exponential backoff: 1s, 2s, 4s...
        :timer.sleep((:math.pow(2, attempt - 1) * 1000) |> round())
        fetch_venue_images_with_retry(venue_input, providers, max_retries, attempt + 1)

      {:ok, images, metadata} ->
        # Either images found or max retries reached
        {:ok, images, metadata}
    end
  end

  defp update_venue_with_images(venue, images, metadata) do
    # Calculate next enrichment due date (30 days from now)
    # 30 days = 30 * 86400 seconds
    now = DateTime.utc_now()
    next_enrichment = DateTime.add(now, 30 * 86_400, :second) |> DateTime.to_iso8601()

    # Get max images to process per provider (for dev environment optimization)
    # nil means no limit (production default)
    max_images_per_provider =
      Application.get_env(:eventasaurus, :venue_images, [])
      |> Keyword.get(:max_images_per_provider)

    # Get max images per venue (controls R2 storage usage)
    max_images_per_venue =
      Application.get_env(:eventasaurus, :venue_images, [])
      |> Keyword.get(:max_images_per_venue, 25)

    # Group images by provider to apply per-provider limits
    images_by_provider =
      Enum.group_by(images, fn img ->
        img.provider || img["provider"]
      end)

    # Apply per-provider limits and flatten back to list
    provider_limited_images =
      images_by_provider
      |> Enum.flat_map(fn {_provider, provider_images} ->
        case max_images_per_provider do
          n when is_integer(n) and n > 0 -> Enum.take(provider_images, n)
          _ -> provider_images
        end
      end)

    # Apply per-venue limit (after per-provider limits)
    # Guard against negative values to prevent tail enumeration
    limited_images = Enum.take(provider_limited_images, max(0, max_images_per_venue))

    # Log if we're limiting images
    if is_integer(max_images_per_provider) and length(images) > length(provider_limited_images) do
      Logger.info(
        "📊 Found #{length(images)} images, processing only #{length(provider_limited_images)} (limit: #{max_images_per_provider}/provider)"
      )
    end

    if length(provider_limited_images) > length(limited_images) do
      Logger.info(
        "📊 Limiting to #{length(limited_images)} images per venue (max: #{max_images_per_venue})"
      )
    end

    # Cache images to R2 via ImageCacheService
    # This queues async jobs to download from provider and upload to R2
    # The cached_images table tracks status and provides fallback to original URL
    cache_results =
      limited_images
      |> Enum.with_index()
      |> Enum.map(fn {img, position} ->
        provider_url = img.url || img["url"]
        provider = img.provider || img["provider"]

        # Build complete metadata to preserve ALL source data
        # This is stored in cached_images.metadata without transformation
        image_metadata =
          %{
            # Original image data from provider
            "provider" => provider,
            "provider_url" => provider_url,
            "width" => img[:width] || img["width"],
            "height" => img[:height] || img["height"],
            "quality_score" => img[:quality_score] || img["quality_score"],
            "attribution" => img[:attribution] || img["attribution"],
            "html_attributions" => img[:html_attributions] || img["html_attributions"],
            "photo_reference" => img[:photo_reference] || img["photo_reference"],
            # Enrichment context
            "fetched_at" => img[:fetched_at] || img["fetched_at"] || DateTime.to_iso8601(now),
            "venue_id" => venue.id,
            "venue_slug" => venue.slug
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        # Queue the image for R2 caching
        # ImageCacheService handles deduplication and creates Oban job
        case ImageCacheService.cache_image("venue", venue.id, position, provider_url,
               source: provider,
               priority: 1,
               metadata: image_metadata
             ) do
          {:ok, cached_image} ->
            Logger.debug(
              "📸 Queued image #{position} for venue #{venue.id} (cached_image_id: #{cached_image.id})"
            )

            {:ok, position, cached_image}

          {:exists, cached_image} ->
            Logger.debug(
              "⏭️  Image #{position} for venue #{venue.id} already exists (cached_image_id: #{cached_image.id})"
            )

            {:exists, position, cached_image}

          {:error, changeset} ->
            Logger.warning(
              "⚠️  Failed to queue image #{position} for venue #{venue.id}: #{inspect(changeset.errors)}"
            )

            {:error, position, changeset}
        end
      end)

    # Count results for logging and metadata
    {queued, existing, errors} =
      Enum.reduce(cache_results, {0, 0, 0}, fn result, {q, e, err} ->
        case result do
          {:ok, _, _} -> {q + 1, e, err}
          {:exists, _, _} -> {q, e + 1, err}
          {:error, _, _} -> {q, e, err + 1}
        end
      end)

    images_cached = queued + existing

    Logger.info(
      "📸 R2 caching: #{queued} queued, #{existing} existing, #{errors} errors for venue #{venue.id}"
    )

    # Build enrichment metadata with history
    # NOTE: We no longer update venue_images JSONB - images are now in cached_images table
    existing_metadata = venue.image_enrichment_metadata || %{}
    existing_history = existing_metadata["enrichment_history"] || []

    # Track which providers we've seen across all enrichments
    all_providers_used =
      (existing_metadata["providers_used"] || [])
      |> Kernel.++(metadata.providers_succeeded || metadata[:providers_succeeded] || [])
      |> Enum.uniq()

    # Create history entry for this enrichment
    history_entry = %{
      "enriched_at" => DateTime.to_iso8601(now),
      "providers" => metadata.providers_succeeded || metadata[:providers_succeeded] || [],
      "images_fetched" => length(images),
      "images_cached" => images_cached,
      "images_queued" => queued,
      "images_existing" => existing,
      "cache_errors" => errors,
      "cost_usd" => metadata.total_cost || metadata[:total_cost] || 0.0,
      # New field: indicates images are in cached_images table, not venue_images JSONB
      "storage_system" => "r2"
    }

    # Determine last attempt result based on cache results
    # Success if we cached any images (queued or existing)
    last_attempt_result =
      cond do
        images_cached > 0 ->
          "success"

        errors > 0 ->
          "error"

        true ->
          determine_attempt_result(
            limited_images,
            metadata.providers_failed || metadata[:providers_failed] || [],
            metadata.error_details || metadata[:error_details] || %{}
          )
      end

    # Store detailed information about this attempt for cooldown logic
    last_attempt_details =
      build_attempt_details(
        metadata.providers_succeeded || metadata[:providers_succeeded] || [],
        metadata.providers_failed || metadata[:providers_failed] || [],
        metadata.error_details || metadata[:error_details] || %{}
      )

    # Calculate completeness score (0.0-1.0)
    # Measures how successful the enrichment was across all attempted providers
    providers_succeeded = metadata.providers_succeeded || metadata[:providers_succeeded] || []
    providers_failed = metadata.providers_failed || metadata[:providers_failed] || []
    total_providers_attempted = length(providers_succeeded) + length(providers_failed)

    completeness_score =
      if total_providers_attempted > 0 do
        length(providers_succeeded) / total_providers_attempted
      else
        0.0
      end

    enrichment_metadata = %{
      # Schema versioning for future-proof migrations
      "schema_version" => "2.0",
      "scoring_version" => "1.0",
      # Indicates images are now stored in cached_images table via R2
      "storage_system" => "r2",
      # Single timestamp: when was this venue last checked for images?
      "last_checked_at" => DateTime.to_iso8601(now),
      "completeness_score" => completeness_score,
      "next_enrichment_due" => next_enrichment,
      "providers_used" => all_providers_used,
      "total_images_cached" => images_cached,
      "cost_breakdown" => metadata.cost_breakdown || metadata[:cost_breakdown] || %{},
      # Keep last 10
      "enrichment_history" => [history_entry | existing_history] |> Enum.take(10),
      "providers_failed" => metadata.providers_failed || metadata[:providers_failed] || [],
      "error_details" => metadata.error_details || metadata[:error_details] || %{},
      # Track result of last check (for debugging/reporting)
      "last_check_result" => last_attempt_result,
      "last_check_providers" =>
        (metadata.providers_succeeded || metadata[:providers_succeeded] || []) ++
          (metadata.providers_failed || metadata[:providers_failed] || []),
      "last_check_details" => last_attempt_details
    }

    # Update ONLY the enrichment metadata, NOT venue_images JSONB
    # Images are now stored in the cached_images table
    changeset =
      venue
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:image_enrichment_metadata, enrichment_metadata)

    case Repo.update(changeset) do
      {:ok, updated_venue} ->
        providers_count =
          length(metadata.providers_succeeded || metadata[:providers_succeeded] || [])

        Logger.info(
          "✅ Cached #{images_cached} images for venue #{venue.id} (#{queued} new, #{existing} existing) from #{providers_count} provider(s)"
        )

        {:ok, updated_venue}

      {:error, changeset} ->
        Logger.error("❌ Failed to update venue #{venue.id}: #{inspect(changeset.errors)}")
        {:error, :update_failed}
    end
  end

  # Determines the result of the last enrichment attempt
  # Returns: "success", "error", or "no_images"
  # CRITICAL: Only returns "no_images" when providers explicitly said ZERO_RESULTS
  defp determine_attempt_result(images, providers_failed, error_details) do
    # Any images fetched in this attempt counts as success (regardless of upload status)
    # This includes "skipped_dev" uploads - we still got the images from providers
    if length(images) > 0 do
      "success"
    else
      cond do
        # If no providers failed, but we have no images, treat as no_images
        # (edge case where providers returned empty results without error)
        Enum.empty?(providers_failed) ->
          "no_images"

        # If providers failed, check WHY they failed
        true ->
          # Check if ANY provider had an API error (not ZERO_RESULTS)
          has_api_errors? =
            Enum.any?(providers_failed, fn provider ->
              error = get_provider_error(error_details, provider)
              is_api_error?(error)
            end)

          if has_api_errors?, do: "error", else: "no_images"
      end
    end
  end

  # Builds detailed information about provider responses for last attempt
  defp build_attempt_details(providers_succeeded, providers_failed, error_details) do
    # Build details for successful providers
    success_details =
      providers_succeeded
      |> Enum.map(fn provider ->
        {provider, %{"status" => "success"}}
      end)
      |> Map.new()

    # Build details for failed providers
    failure_details =
      providers_failed
      |> Enum.map(fn provider ->
        error = get_provider_error(error_details, provider)
        status = if is_zero_results?(error), do: "ZERO_RESULTS", else: "ERROR"

        {provider,
         %{
           "status" => status,
           "message" => inspect(error)
         }}
      end)
      |> Map.new()

    Map.merge(success_details, failure_details)
  end

  # Gets the error for a specific provider from error_details map
  defp get_provider_error(error_details, provider) do
    Map.get(error_details, provider) || Map.get(error_details, to_string(provider))
  end

  # Checks if an error is an API error (not ZERO_RESULTS)
  # API errors include: INVALID_REQUEST, authentication failures, rate limits, etc.
  # ZERO_RESULTS is NOT an API error - it means "no images available"
  defp is_api_error?(error) when is_binary(error) do
    # Check for API error patterns (not ZERO_RESULTS)
    String.contains?(error, "INVALID_REQUEST") or
      String.contains?(error, "REQUEST_DENIED") or
      String.contains?(error, "INVALID_API_KEY") or
      String.contains?(error, "HTTP 400") or
      String.contains?(error, "HTTP 401") or
      String.contains?(error, "HTTP 403") or
      String.contains?(error, "HTTP 429") or
      String.contains?(error, "HTTP 500") or
      String.contains?(error, "HTTP 502") or
      String.contains?(error, "HTTP 503") or
      String.contains?(error, "rate_limited") or
      String.contains?(error, "timeout") or
      String.contains?(error, "network_error")
  end

  defp is_api_error?(:rate_limited), do: true
  defp is_api_error?(:timeout), do: true
  defp is_api_error?(:network_error), do: true
  defp is_api_error?(:auth_error), do: true
  defp is_api_error?(:api_key_missing), do: true
  defp is_api_error?(:invalid_api_key), do: true
  defp is_api_error?(_), do: false

  # Checks if an error represents "no images available" (ZERO_RESULTS)
  # This is the ONLY case that should trigger "no_images" status
  defp is_zero_results?(error) when is_binary(error) do
    String.contains?(error, "ZERO_RESULTS") or
      String.contains?(error, "No images") or
      String.contains?(error, "no images")
  end

  defp is_zero_results?(_), do: false

  defp parse_datetime(nil), do: {:error, nil}

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: {:ok, dt}
  defp parse_datetime(_), do: {:error, :invalid_type}
end
