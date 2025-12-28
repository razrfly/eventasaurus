defmodule EventasaurusApp.Images.EventSourceImages do
  @moduledoc """
  Get cached event source images from R2 storage.

  Event source images are cached via `EventImageCaching` processor during scraping.
  This module provides retrieval functions following the same patterns as MovieImages.

  ## Usage

      # Get cached URL with fallback to original
      url = EventSourceImages.get_url(source_id, source.image_url)

      # Get hero image (preferred for display)
      url = EventSourceImages.get_hero_url(source_id, source.image_url)

      # Get gallery images (for carousels, galleries)
      urls = EventSourceImages.get_gallery_urls(source_id, limit: 5)

      # Get all images with types
      images = EventSourceImages.get_all_images(source_id)

      # Batch lookup for multiple sources (avoids N+1)
      urls = EventSourceImages.get_urls([source_id1, source_id2])

      # Batch with fallbacks
      fallbacks = %{source1.id => source1.image_url, source2.id => source2.image_url}
      urls = EventSourceImages.get_urls_with_fallbacks(fallbacks)
  """

  import Ecto.Query, warn: false

  alias EventasaurusApp.Images.{ImageCacheService, ImageEnv, CachedImage}
  alias EventasaurusApp.Repo

  @position 0

  # Valid image types for event sources
  @image_types ["hero", "poster", "gallery", "primary"]

  # ============================================================================
  # Single Source Lookups
  # ============================================================================

  @doc """
  Get the cached image URL for an event source.

  Returns the CDN URL if the image is cached, the fallback URL otherwise,
  or nil if neither exists.

  In non-production environments, returns the fallback directly without
  cache lookup (dev uses original URLs, no R2 caching).

  ## Examples

      iex> EventSourceImages.get_url(123, "https://example.com/image.jpg")
      "https://cdn.wombie.com/images/public_event_source/123/0.jpg"

      iex> EventSourceImages.get_url(999, "https://example.com/image.jpg")
      "https://example.com/image.jpg"  # Falls back to original
  """
  @spec get_url(integer(), String.t() | nil) :: String.t() | nil
  def get_url(source_id, fallback \\ nil) when is_integer(source_id) do
    if ImageEnv.production?() do
      ImageCacheService.get_url!("public_event_source", source_id, @position) || fallback
    else
      # In dev/test, skip cache lookup - just use original URL
      fallback
    end
  end

  # ============================================================================
  # Batch Lookups (N+1 Prevention)
  # ============================================================================

  @doc """
  Batch get image URLs for multiple event sources.

  Returns a map of `%{source_id => cdn_url}`. Sources without cached
  images will not have entries in the map.

  In non-production, returns empty map (uses fallbacks).

  ## Example

      iex> EventSourceImages.get_urls([1, 2, 3])
      %{1 => "https://cdn...", 2 => "https://cdn..."}  # source 3 has no cached image
  """
  @spec get_urls([integer()]) :: %{integer() => String.t()}
  def get_urls([]), do: %{}

  def get_urls(source_ids) when is_list(source_ids) do
    if ImageEnv.production?() do
      import Ecto.Query
      alias EventasaurusApp.Repo
      alias EventasaurusApp.Images.CachedImage

      from(c in CachedImage,
        where: c.entity_type == "public_event_source",
        where: c.entity_id in ^source_ids,
        where: c.position == ^@position,
        where: c.status == "cached",
        where: not is_nil(c.cdn_url),
        select: {c.entity_id, c.cdn_url}
      )
      |> Repo.all()
      |> Map.new()
    else
      # In dev/test, return empty map - fallbacks will be used
      %{}
    end
  end

  @doc """
  Batch get image URLs with fallbacks for multiple event sources.

  Takes a map of `%{source_id => fallback_url}` and returns
  `%{source_id => effective_url}` preferring cached URLs.

  In non-production, returns fallbacks directly (no cache lookup).

  ## Example

      iex> fallbacks = %{1 => "https://example/1.jpg", 2 => "https://example/2.jpg"}
      iex> EventSourceImages.get_urls_with_fallbacks(fallbacks)
      %{1 => "https://cdn.wombie.com/...", 2 => "https://example/2.jpg"}
  """
  @spec get_urls_with_fallbacks(%{integer() => String.t() | nil}) ::
          %{integer() => String.t() | nil}
  def get_urls_with_fallbacks(source_fallbacks) when is_map(source_fallbacks) do
    if ImageEnv.production?() do
      source_ids = Map.keys(source_fallbacks)
      cached_urls = get_urls(source_ids)

      Map.new(source_fallbacks, fn {source_id, fallback} ->
        {source_id, Map.get(cached_urls, source_id, fallback)}
      end)
    else
      # In dev/test, just return the fallbacks as-is
      source_fallbacks
    end
  end

  # ============================================================================
  # Typed Image Lookups (Multi-Image Support)
  # ============================================================================

  @doc """
  Get the hero image URL for an event source.

  Hero images are the primary/featured images, typically 16:9 aspect ratio.
  Falls back to position 0 "primary" if no hero type exists.

  ## Examples

      iex> EventSourceImages.get_hero_url(123, "https://example.com/fallback.jpg")
      "https://cdn.wombie.com/images/public_event_source/123/hero/0.jpg"
  """
  @spec get_hero_url(integer(), String.t() | nil) :: String.t() | nil
  def get_hero_url(source_id, fallback \\ nil) when is_integer(source_id) do
    if ImageEnv.production?() do
      # Try hero first, then primary (legacy)
      ImageCacheService.get_url!("public_event_source", source_id, "hero", 0) ||
        ImageCacheService.get_url!("public_event_source", source_id, "primary", 0) ||
        fallback
    else
      fallback
    end
  end

  @doc """
  Get the poster image URL for an event source.

  Poster images are 4:3 or portrait aspect ratio, ideal for card layouts.

  ## Examples

      iex> EventSourceImages.get_poster_url(123, "https://example.com/fallback.jpg")
      "https://cdn.wombie.com/images/public_event_source/123/poster/1.jpg"
  """
  @spec get_poster_url(integer(), String.t() | nil) :: String.t() | nil
  def get_poster_url(source_id, fallback \\ nil) when is_integer(source_id) do
    if ImageEnv.production?() do
      ImageCacheService.get_url!("public_event_source", source_id, "poster", 1) || fallback
    else
      fallback
    end
  end

  @doc """
  Get gallery image URLs for an event source.

  Returns a list of cached gallery images sorted by position.
  Gallery images are additional images beyond the hero/poster.

  ## Options

  - `:limit` - Maximum number of gallery images to return (default: 5)

  ## Returns

  List of `%{url: String.t(), position: integer(), metadata: map()}` maps.

  ## Examples

      iex> EventSourceImages.get_gallery_urls(123, limit: 3)
      [
        %{url: "https://cdn.wombie.com/...", position: 2, metadata: %{...}},
        %{url: "https://cdn.wombie.com/...", position: 3, metadata: %{...}}
      ]
  """
  @spec get_gallery_urls(integer(), keyword()) :: list()
  def get_gallery_urls(source_id, opts \\ []) when is_integer(source_id) do
    limit = Keyword.get(opts, :limit, 5)

    if ImageEnv.production?() do
      from(c in CachedImage,
        where: c.entity_type == "public_event_source",
        where: c.entity_id == ^source_id,
        where: c.image_type == "gallery",
        where: c.status == "cached",
        where: not is_nil(c.cdn_url),
        order_by: [asc: c.position],
        limit: ^limit,
        select: %{
          url: c.cdn_url,
          position: c.position,
          metadata: c.metadata
        }
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Get all cached images for an event source with their types.

  Returns all cached images (hero, poster, gallery) sorted by position.
  Useful for building image galleries or carousels.

  ## Returns

  List of `%{url: String.t(), image_type: String.t(), position: integer(), metadata: map()}` maps.

  ## Examples

      iex> EventSourceImages.get_all_images(123)
      [
        %{url: "https://cdn...", image_type: "hero", position: 0, metadata: %{...}},
        %{url: "https://cdn...", image_type: "poster", position: 1, metadata: %{...}},
        %{url: "https://cdn...", image_type: "gallery", position: 2, metadata: %{...}}
      ]
  """
  @spec get_all_images(integer()) :: list()
  def get_all_images(source_id) when is_integer(source_id) do
    if ImageEnv.production?() do
      from(c in CachedImage,
        where: c.entity_type == "public_event_source",
        where: c.entity_id == ^source_id,
        where: c.image_type in ^@image_types,
        where: c.status == "cached",
        where: not is_nil(c.cdn_url),
        order_by: [asc: c.position],
        select: %{
          url: c.cdn_url,
          image_type: c.image_type,
          position: c.position,
          metadata: c.metadata
        }
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Batch get hero images for multiple event sources.

  Returns a map of `%{source_id => hero_url}`.

  ## Examples

      iex> EventSourceImages.get_hero_urls([1, 2, 3])
      %{1 => "https://cdn...", 2 => "https://cdn..."}
  """
  @spec get_hero_urls([integer()]) :: %{integer() => String.t()}
  def get_hero_urls([]), do: %{}

  def get_hero_urls(source_ids) when is_list(source_ids) do
    if ImageEnv.production?() do
      # Get hero images first
      hero_urls =
        from(c in CachedImage,
          where: c.entity_type == "public_event_source",
          where: c.entity_id in ^source_ids,
          where: c.image_type == "hero",
          where: c.position == 0,
          where: c.status == "cached",
          where: not is_nil(c.cdn_url),
          select: {c.entity_id, c.cdn_url}
        )
        |> Repo.all()
        |> Map.new()

      # For sources without hero, try primary (legacy)
      missing_ids = source_ids -- Map.keys(hero_urls)

      if missing_ids == [] do
        hero_urls
      else
        primary_urls =
          from(c in CachedImage,
            where: c.entity_type == "public_event_source",
            where: c.entity_id in ^missing_ids,
            where: c.image_type == "primary",
            where: c.position == 0,
            where: c.status == "cached",
            where: not is_nil(c.cdn_url),
            select: {c.entity_id, c.cdn_url}
          )
          |> Repo.all()
          |> Map.new()

        Map.merge(hero_urls, primary_urls)
      end
    else
      %{}
    end
  end

  @doc """
  Get image counts by type for an event source.

  Returns a map of `%{image_type => count}`.

  ## Examples

      iex> EventSourceImages.get_image_counts(123)
      %{"hero" => 1, "poster" => 1, "gallery" => 3}
  """
  @spec get_image_counts(integer()) :: %{String.t() => integer()}
  def get_image_counts(source_id) when is_integer(source_id) do
    if ImageEnv.production?() do
      from(c in CachedImage,
        where: c.entity_type == "public_event_source",
        where: c.entity_id == ^source_id,
        where: c.image_type in ^@image_types,
        where: c.status == "cached",
        group_by: c.image_type,
        select: {c.image_type, count(c.id)}
      )
      |> Repo.all()
      |> Map.new()
    else
      %{}
    end
  end
end
