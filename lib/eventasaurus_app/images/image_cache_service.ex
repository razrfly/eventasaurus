defmodule EventasaurusApp.Images.ImageCacheService do
  @moduledoc """
  Service for caching external images to R2 storage.

  Provides a unified interface for caching images from any entity type,
  handling the download, upload, and status tracking.

  ## Usage

      # Queue an image for caching
      ImageCacheService.cache_image("venue", 123, 0, "https://example.com/image.jpg")

      # Get the effective URL (cached if available, original as fallback)
      ImageCacheService.get_url("venue", 123, 0)

      # Bulk cache images for an entity
      ImageCacheService.cache_entity_images("venue", 123, [
        %{position: 0, url: "https://example.com/main.jpg"},
        %{position: 1, url: "https://example.com/gallery1.jpg"}
      ])

  ## Entity Types

  - `venue` - Venue images
  - `public_event_source` - Event source images
  - `performer` - Performer/artist images
  - `event` - Event cover images
  - `movie` - Movie posters and backdrops
  - `group` - Group avatars and covers
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Images.{CachedImage, ImageEnv}
  alias EventasaurusApp.Workers.ImageCacheJob

  import Ecto.Query

  @doc """
  Queue an image for caching.

  Creates a pending CachedImage record and enqueues an Oban job to download
  and upload the image to R2.

  ## Parameters

  - `entity_type` - Type of entity (e.g., "venue", "performer")
  - `entity_id` - ID of the entity
  - `position` - Position/order of the image (0-based index)
  - `original_url` - URL of the original image to cache
  - `opts` - Options:
    - `:source` - Original source identifier (e.g., "google_places", "tmdb")
    - `:metadata` - Raw source data map (preserved as-is, not for parsing)
    - `:priority` - Oban job priority (default: 2)

  ## Returns

  - `{:ok, cached_image}` - Record created and job queued
  - `{:exists, cached_image}` - Image already exists for this entity/position
  - `{:skipped, :non_production}` - Skipped in non-production environment
  - `{:error, changeset}` - Failed to create record
  """
  def cache_image(entity_type, entity_id, position, original_url, opts \\ []) do
    # In non-production environments, skip caching entirely.
    # Images will display using original URLs via the bridge modules.
    # This prevents dev/test from polluting the production R2 bucket.
    if ImageEnv.production?() do
      do_cache_image(entity_type, entity_id, position, original_url, opts)
    else
      Logger.debug(
        "ImageCacheService: Skipping cache in #{Application.get_env(:eventasaurus, :environment)} - using original URLs"
      )

      {:skipped, :non_production}
    end
  end

  defp do_cache_image(entity_type, entity_id, position, original_url, opts) do
    source = Keyword.get(opts, :source)
    metadata = Keyword.get(opts, :metadata, %{})
    priority = Keyword.get(opts, :priority, 2)

    # Check if we already have a record for this entity/position
    case get_cached_image(entity_type, entity_id, position) do
      nil ->
        # Create new record
        attrs = %{
          entity_type: to_string(entity_type),
          entity_id: entity_id,
          position: position,
          original_url: original_url,
          original_source: source,
          metadata: metadata,
          status: "pending"
        }

        case %CachedImage{} |> CachedImage.changeset(attrs) |> Repo.insert() do
          {:ok, cached_image} ->
            # Enqueue the download job with observable context
            # Args include entity info for Oban dashboard visibility
            build_job_args(cached_image, original_url, source)
            |> ImageCacheJob.new(priority: priority)
            |> Oban.insert()

            {:ok, cached_image}

          {:error, changeset} ->
            {:error, changeset}
        end

      existing ->
        # Already exists - check if URL changed
        if existing.original_url == original_url do
          {:exists, existing}
        else
          # URL changed - update and re-queue
          attrs = %{
            original_url: original_url,
            original_source: source,
            status: "pending",
            retry_count: 0,
            last_error: nil,
            r2_key: nil,
            cdn_url: nil
          }

          case existing |> CachedImage.changeset(attrs) |> Repo.update() do
            {:ok, updated} ->
              # Enqueue with observable context
              build_job_args(updated, original_url, source)
              |> ImageCacheJob.new(priority: priority)
              |> Oban.insert()

              {:ok, updated}

            {:error, changeset} ->
              {:error, changeset}
          end
        end
    end
  end

  @doc """
  Get the effective URL for a cached image.

  Returns the CDN URL if the image is successfully cached,
  otherwise returns the original URL as a fallback.

  ## Parameters

  - `entity_type` - Type of entity
  - `entity_id` - ID of the entity
  - `position` - Position of the image (0-based)

  ## Returns

  - `{:cached, cdn_url}` - Image is cached, returns CDN URL
  - `{:fallback, original_url}` - Not cached, returns original URL
  - `{:not_found, nil}` - No record exists
  """
  def get_url(entity_type, entity_id, position) do
    case get_cached_image(entity_type, entity_id, position) do
      %CachedImage{status: "cached", cdn_url: cdn_url} when is_binary(cdn_url) ->
        {:cached, cdn_url}

      %CachedImage{original_url: url} ->
        {:fallback, url}

      nil ->
        {:not_found, nil}
    end
  end

  @doc """
  Get effective URL as simple string (for use in templates).

  Returns CDN URL if cached, original URL if not, nil if not found.
  """
  def get_url!(entity_type, entity_id, position) do
    case get_url(entity_type, entity_id, position) do
      {:cached, url} -> url
      {:fallback, url} -> url
      {:not_found, _} -> nil
    end
  end

  @doc """
  Bulk cache images for an entity.

  ## Parameters

  - `entity_type` - Type of entity
  - `entity_id` - ID of the entity
  - `images` - List of maps with `:position` and `:url` keys
  - `opts` - Options passed to cache_image/5

  ## Returns

  - `{:ok, results}` - List of results for each image
  """
  def cache_entity_images(entity_type, entity_id, images, opts \\ []) when is_list(images) do
    results =
      Enum.map(images, fn image ->
        position = image[:position] || image["position"]
        url = image[:url] || image["url"]

        if is_integer(position) && url do
          cache_image(entity_type, entity_id, position, url, opts)
        else
          {:error, :invalid_image_spec}
        end
      end)

    {:ok, results}
  end

  @doc """
  Get all cached images for an entity.
  """
  @spec get_entity_images(String.t() | atom(), integer()) :: [CachedImage.t()]
  def get_entity_images(entity_type, entity_id) do
    CachedImage.for_entity(to_string(entity_type), entity_id)
    |> Repo.all()
  end

  @doc """
  Batch get image counts for multiple entities of the same type.

  Returns a map of entity_id => image_count for efficient N+1 prevention.

  ## Parameters

  - `entity_type` - Type of entity (e.g., "venue", "performer")
  - `entity_ids` - List of entity IDs to fetch counts for

  ## Returns

  Map of `%{entity_id => count}` for all entities with images.
  Missing keys indicate 0 images.

  ## Example

      counts = ImageCacheService.get_entity_image_counts("venue", [1, 2, 3])
      # => %{1 => 3, 2 => 1}  # venue 3 has no images
  """
  @spec get_entity_image_counts(String.t() | atom(), [integer()]) :: %{
          integer() => non_neg_integer()
        }
  def get_entity_image_counts(_entity_type, []), do: %{}

  def get_entity_image_counts(entity_type, entity_ids) when is_list(entity_ids) do
    entity_type_str = to_string(entity_type)

    from(c in CachedImage,
      where: c.entity_type == ^entity_type_str and c.entity_id in ^entity_ids,
      group_by: c.entity_id,
      select: {c.entity_id, count(c.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Get a specific cached image record by position.
  """
  def get_cached_image(entity_type, entity_id, position) when is_integer(position) do
    CachedImage.for_entity(to_string(entity_type), entity_id, position)
    |> Repo.one()
  end

  @doc """
  Get a cached image by ID.
  """
  def get_cached_image(id) when is_integer(id) do
    Repo.get(CachedImage, id)
  end

  @doc """
  Retry all failed images that haven't exceeded max retries.

  ## Parameters

  - `opts` - Options:
    - `:limit` - Maximum number to retry (default: 100)
    - `:max_retries` - Maximum retry count (default: 3)

  ## Returns

  - `{:ok, count}` - Number of images queued for retry
  """
  def retry_failed(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    max_retries = Keyword.get(opts, :max_retries, 3)

    images =
      CachedImage.retriable(max_retries)
      |> limit(^limit)
      |> Repo.all()

    Enum.each(images, fn image ->
      # Enqueue with observable context for retry visibility
      build_job_args(image, image.original_url, image.original_source)
      |> ImageCacheJob.new(priority: 3)
      |> Oban.insert()
    end)

    {:ok, length(images)}
  end

  @doc """
  Get statistics about cached images.

  ## Returns

  Map with counts by status and entity type.
  """
  def stats do
    by_status =
      from(c in CachedImage,
        group_by: c.status,
        select: {c.status, count(c.id)}
      )
      |> Repo.all()
      |> Map.new()

    by_entity =
      from(c in CachedImage,
        group_by: c.entity_type,
        select: {c.entity_type, count(c.id)}
      )
      |> Repo.all()
      |> Map.new()

    total = Repo.aggregate(CachedImage, :count, :id)

    cached_count = Map.get(by_status, "cached", 0)

    %{
      total: total,
      by_status: by_status,
      by_entity_type: by_entity,
      cache_rate: if(total > 0, do: cached_count / total * 100, else: 0.0)
    }
  end

  @doc """
  Find an existing cached version of a URL across all entities.

  Useful for deduplication - if the same URL is used by multiple entities,
  we can reference the same R2 object.

  ## Returns

  - `{:ok, cached_image}` - Found existing cached version
  - `{:not_found, nil}` - No cached version exists
  """
  def find_cached_url(url) do
    case CachedImage.by_original_url(url)
         |> where([c], c.status == "cached")
         |> limit(1)
         |> Repo.one() do
      nil -> {:not_found, nil}
      cached -> {:ok, cached}
    end
  end

  # Private helpers

  # Build job args with observable context for Oban dashboard visibility.
  # Follows source-implementation-guide.md Section 13: Job Args Standards
  # All important identifiers at top level, flat structure.
  defp build_job_args(%CachedImage{} = cached_image, original_url, source) do
    %{
      # Primary identifier
      cached_image_id: cached_image.id,
      # Entity context (visible in Oban dashboard)
      entity_type: cached_image.entity_type,
      entity_id: cached_image.entity_id,
      position: cached_image.position,
      # Source info for debugging
      original_url: truncate_url(original_url),
      provider: source
    }
  end

  # Truncate long URLs to avoid bloating job args
  # Keep domain + first part of path for identifiability
  defp truncate_url(nil), do: nil

  defp truncate_url(url) when is_binary(url) do
    if String.length(url) > 100 do
      String.slice(url, 0, 97) <> "..."
    else
      url
    end
  end

end
