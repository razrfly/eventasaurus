defmodule EventasaurusApp.Images.VenueImageMigrator do
  @moduledoc """
  Migrates venue images from ImageKit to Cloudflare R2 storage.

  This module provides the business logic for migrating venues from the
  existing ImageKit-based `venue_images` JSONB column to the new
  `cached_images` table backed by R2.

  ## Migration Flow

  1. Query venues with images in `venue_images` JSONB
  2. For each venue, extract ImageKit URLs and queue them for caching
  3. The `ImageCacheJob` downloads from ImageKit and uploads to R2
  4. Progress is tracked in the `cached_images` table

  ## Safety Guarantees

  - The `venue_images` JSONB column is **READ ONLY** during migration
  - No data is removed until verification is complete
  - Images exist in both ImageKit and R2 during the transition period
  - Rollback is always possible by reverting to JSONB URLs

  ## Usage

      # Migrate a single venue (for testing)
      VenueImageMigrator.migrate_venue(venue)

      # Queue migration for venues with images
      VenueImageMigrator.queue_migration(limit: 100)

      # Get migration status
      VenueImageMigrator.status()

  ## R2 Path Structure

  Images are stored in R2 with the following path format:

      images/venue/{venue-slug}/{position}.{ext}

  For example:
  - `images/venue/cinema-city-krakow/0.jpg`
  - `images/venue/cinema-city-krakow/1.jpg`
  - `images/venue/cinema-city-krakow/2.jpg`
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Images.CachedImage
  alias EventasaurusApp.Images.ImageCacheService

  import Ecto.Query

  @doc """
  Migrate all images for a single venue to R2.

  Creates `CachedImage` records for each image in the venue's `venue_images`
  array and queues them for download via `ImageCacheJob`.

  ## Parameters

  - `venue` - A `%Venue{}` struct with `venue_images` populated
  - `opts` - Options:
    - `:priority` - Oban job priority (default: 2)
    - `:dry_run` - If true, don't actually create records (default: false)

  ## Returns

  - `{:ok, %{queued: count, skipped: count, errors: count, venue_id: id, dry_run: boolean}}`

  Note: Always returns `{:ok, stats}`. Individual image failures are tracked
  in the `errors` count, not as a top-level error.

  ## Examples

      iex> venue = Repo.get!(Venue, 123)
      iex> VenueImageMigrator.migrate_venue(venue)
      {:ok, %{queued: 5, skipped: 0, errors: 0, venue_id: 123, dry_run: false}}

  """
  @spec migrate_venue(Venue.t(), keyword()) :: {:ok, map()}
  def migrate_venue(%Venue{} = venue, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    priority = Keyword.get(opts, :priority, 2)

    images = venue.venue_images || []

    if Enum.empty?(images) do
      {:ok, %{queued: 0, skipped: 0, errors: 0, venue_id: venue.id, dry_run: dry_run}}
    else
      results =
        images
        |> Enum.with_index()
        |> Enum.map(fn {image, index} ->
          migrate_single_image(venue, image, index, dry_run: dry_run, priority: priority)
        end)

      stats = aggregate_results(results, venue.id, dry_run)

      if stats.queued > 0 do
        Logger.info(
          "📸 VenueImageMigrator: Queued #{stats.queued} images for venue #{venue.id} (#{venue.slug})"
        )
      end

      {:ok, stats}
    end
  end

  @doc """
  Queue migration jobs for venues with images.

  Finds venues that have images in `venue_images` but haven't been migrated
  yet, and creates `VenueMigrationJob` Oban jobs for each.

  ## Parameters

  - `opts` - Options:
    - `:limit` - Maximum venues to process (default: 100)
    - `:batch_size` - Venues per batch (default: 10)
    - `:priority` - Oban job priority (default: 2)
    - `:dry_run` - If true, just return count without queueing (default: false)
    - `:venue_ids` - Specific venue IDs to migrate (optional)

  ## Returns

  - `{:ok, %{venues_found: count, jobs_queued: count}}` - Queue stats
  """
  @spec queue_migration(keyword()) :: {:ok, map()}
  def queue_migration(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    batch_size = Keyword.get(opts, :batch_size, 10)
    priority = Keyword.get(opts, :priority, 2)
    dry_run = Keyword.get(opts, :dry_run, false)
    venue_ids = Keyword.get(opts, :venue_ids)

    venues = find_venues_to_migrate(limit, venue_ids)

    if dry_run do
      {:ok, %{venues_found: length(venues), jobs_queued: 0, dry_run: true}}
    else
      # Queue in batches to avoid overwhelming Oban
      jobs_queued =
        venues
        |> Enum.chunk_every(batch_size)
        |> Enum.reduce(0, fn batch, acc ->
          batch_count = queue_batch(batch, priority)
          acc + batch_count
        end)

      {:ok, %{venues_found: length(venues), jobs_queued: jobs_queued, dry_run: false}}
    end
  end

  @doc """
  Get migration status and statistics.

  Returns counts of:
  - Total venues with images
  - Venues fully migrated
  - Venues partially migrated
  - Venues not started
  - Images by status (pending, downloading, cached, failed)

  ## Returns

  Map with migration statistics.
  """
  @spec status() :: map()
  def status do
    # Count venues with images
    total_venues_with_images =
      from(v in Venue,
        where: fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) > 0", v.venue_images)
      )
      |> Repo.aggregate(:count)

    # Count total images in venue_images JSONB
    total_images_in_jsonb =
      from(v in Venue,
        select:
          fragment(
            "COALESCE(SUM(jsonb_array_length(COALESCE(?, '[]'::jsonb))), 0)",
            v.venue_images
          )
      )
      |> Repo.one()
      |> then(fn
        nil -> 0
        val when is_binary(val) -> String.to_integer(val)
        val -> val
      end)

    # Count cached_images by status for venues
    cached_image_stats =
      from(c in CachedImage,
        where: c.entity_type == "venue",
        group_by: c.status,
        select: {c.status, count(c.id)}
      )
      |> Repo.all()
      |> Map.new()

    # Count unique venues with cached images
    venues_with_cached_images =
      from(c in CachedImage,
        where: c.entity_type == "venue",
        distinct: c.entity_id,
        select: c.entity_id
      )
      |> Repo.aggregate(:count)

    # Count venues fully migrated (all images cached)
    venues_fully_migrated =
      from(c in CachedImage,
        where: c.entity_type == "venue" and c.status == "cached",
        group_by: c.entity_id,
        select: c.entity_id
      )
      |> Repo.all()
      |> length()

    %{
      total_venues_with_images: total_venues_with_images,
      total_images_in_jsonb: total_images_in_jsonb,
      cached_images: %{
        pending: Map.get(cached_image_stats, "pending", 0),
        downloading: Map.get(cached_image_stats, "downloading", 0),
        cached: Map.get(cached_image_stats, "cached", 0),
        failed: Map.get(cached_image_stats, "failed", 0),
        total: Enum.reduce(cached_image_stats, 0, fn {_status, count}, acc -> acc + count end)
      },
      venues_with_cached_images: venues_with_cached_images,
      venues_fully_migrated: venues_fully_migrated,
      migration_percentage:
        if total_images_in_jsonb > 0 do
          cached = Map.get(cached_image_stats, "cached", 0)
          Float.round(cached / total_images_in_jsonb * 100, 1)
        else
          0.0
        end
    }
  end

  @doc """
  Get list of venues that still need migration.

  ## Parameters

  - `opts` - Options:
    - `:limit` - Maximum venues to return (default: 50)
    - `:with_errors` - Include venues with failed images (default: false)

  ## Returns

  List of venue maps with id, slug, and image counts.
  """
  @spec pending_venues(keyword()) :: [map()]
  def pending_venues(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    _with_errors = Keyword.get(opts, :with_errors, false)

    # Find venues with images that don't have corresponding cached_images
    # This is a bit complex because we need to compare JSONB array length
    # with cached_images count

    # First, get venues with images
    venues_query =
      from(v in Venue,
        where: fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) > 0", v.venue_images),
        select: %{
          id: v.id,
          slug: v.slug,
          image_count: fragment("jsonb_array_length(?)", v.venue_images)
        },
        limit: ^limit
      )

    venues = Repo.all(venues_query)

    # For each venue, check how many are already cached
    Enum.map(venues, fn venue ->
      cached_count =
        from(c in CachedImage,
          where: c.entity_type == "venue" and c.entity_id == ^venue.id,
          select: count(c.id)
        )
        |> Repo.one()

      Map.merge(venue, %{
        cached_count: cached_count,
        pending_count: venue.image_count - cached_count
      })
    end)
    |> Enum.filter(fn v -> v.pending_count > 0 end)
  end

  # Private functions

  defp migrate_single_image(venue, image, position, opts) do
    dry_run = Keyword.get(opts, :dry_run, false)
    priority = Keyword.get(opts, :priority, 2)

    # Extract the URL - check both "url" (ImageKit) and "provider_url" (original)
    # We want to download from ImageKit if available (already optimized)
    url = Map.get(image, "url") || Map.get(image, "provider_url")

    if is_nil(url) or url == "" do
      {:error, :no_url}
    else
      # Extract source/provider info
      source = Map.get(image, "provider", "imagekit")

      if dry_run do
        {:dry_run, %{position: position, url: url, source: source}}
      else
        # Use ImageCacheService to queue the image
        # Store the ENTIRE original image map as metadata - preserves all source data
        case ImageCacheService.cache_image("venue", venue.id, position, url,
               source: source,
               priority: priority,
               metadata: image
             ) do
          {:ok, _cached_image} -> {:queued, position}
          {:exists, _cached_image} -> {:skipped, position}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  defp aggregate_results(results, venue_id, dry_run) do
    Enum.reduce(results, %{queued: 0, skipped: 0, errors: 0}, fn result, acc ->
      case result do
        {:queued, _} -> %{acc | queued: acc.queued + 1}
        {:skipped, _} -> %{acc | skipped: acc.skipped + 1}
        {:dry_run, _} -> %{acc | queued: acc.queued + 1}
        {:error, _} -> %{acc | errors: acc.errors + 1}
      end
    end)
    |> Map.put(:venue_id, venue_id)
    |> Map.put(:dry_run, dry_run)
  end

  defp find_venues_to_migrate(limit, nil) do
    # Find venues with images that haven't been fully migrated yet
    # A venue needs migration if it has venue_images but fewer cached_images

    subquery =
      from(c in CachedImage,
        where: c.entity_type == "venue",
        group_by: c.entity_id,
        select: %{entity_id: c.entity_id, cached_count: count(c.id)}
      )

    from(v in Venue,
      left_join: c in subquery(subquery),
      on: c.entity_id == v.id,
      where: fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) > 0", v.venue_images),
      where:
        is_nil(c.cached_count) or
          c.cached_count < fragment("jsonb_array_length(?)", v.venue_images),
      select: v,
      limit: ^limit,
      order_by: [asc: v.id]
    )
    |> Repo.all()
  end

  defp find_venues_to_migrate(_limit, venue_ids) when is_list(venue_ids) do
    from(v in Venue,
      where: v.id in ^venue_ids,
      where: fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) > 0", v.venue_images)
    )
    |> Repo.all()
  end

  defp queue_batch(venues, priority) do
    alias EventasaurusApp.Workers.VenueMigrationJob

    Enum.reduce(venues, 0, fn venue, count ->
      %{venue_id: venue.id, priority: priority}
      |> VenueMigrationJob.new(priority: priority)
      |> Oban.insert()

      count + 1
    end)
  end
end
