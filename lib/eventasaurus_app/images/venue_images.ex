defmodule EventasaurusApp.Images.VenueImages do
  @moduledoc """
  Get cached venue image URLs from R2 storage with city gallery fallback.

  Fallback order:
  1. Venue's cached images from R2 (via cached_images table) - uses our CDN
  2. City's categorized Unsplash gallery (via CityFallbackImageCache) - raw Unsplash URLs
  3. nil (no image available)

  ## Image Variety

  When using Unsplash fallback, different venues get different images via
  `CityFallbackImageCache.get_fallback_image(city_id, category, venue_id)`.
  The venue_id provides variety so not all venues show the same image.

  ## Batch Lookups (N+1 Prevention)

      # Batch get cached URLs for multiple venues
      urls = VenueImages.get_urls([venue_id1, venue_id2])

      # Batch with fallbacks
      fallbacks = %{venue1.id => venue1.image_url, venue2.id => venue2.image_url}
      urls = VenueImages.get_urls_with_fallbacks(fallbacks)
  """

  alias EventasaurusApp.Images.{ImageCacheService, ImageEnv}
  alias EventasaurusApp.Cache.CityFallbackImageCache
  alias EventasaurusApp.Venues.CategoryMapper

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Images.CachedImage

  @position 0

  @doc """
  Get the best available image for a venue.

  Fallback chain:
  1. R2 cached venue image → CDN transformation (our CDN)
  2. City Unsplash gallery → raw Unsplash URL with native params (no CDN wrapper)
  3. nil → UI shows placeholder icon

  ## Options

  - `:width` - Target width in pixels (default: 400)
  - `:height` - Target height in pixels (default: 300)
  - `:quality` - JPEG/WebP quality 1-100 (default: 85)
  - `:fit` - Resize behavior: "scale-down", "contain", "cover", "crop", "pad" (default: "cover")

  ## Examples

      # Grid view (400x300)
      get_image(venue, city, width: 400, height: 300, quality: 85)

      # List view thumbnail (192x192)
      get_image(venue, city, width: 192, height: 192, quality: 85)

      # Hero image (1200x600)
      get_image(venue, city, width: 1200, height: 600, quality: 90)
  """
  @spec get_image(map(), map(), keyword()) :: String.t() | nil
  def get_image(venue, city, opts \\ []) do
    venue_id = get_venue_id(venue)

    # Layer 1: Check R2 cached venue image (uses our CDN)
    case get_url(venue_id) do
      url when is_binary(url) ->
        # R2 cached images get CDN transformation
        cdn_opts = [
          width: Keyword.get(opts, :width, 400),
          height: Keyword.get(opts, :height, 300),
          quality: Keyword.get(opts, :quality, 85),
          fit: Keyword.get(opts, :fit, "cover")
        ]

        Eventasaurus.CDN.url(url, cdn_opts)

      nil ->
        # Layer 2: City Unsplash gallery fallback (raw Unsplash URLs, no CDN wrapper)
        get_city_fallback_image(venue, city)
    end
  end

  # Get venue ID from various venue representations
  defp get_venue_id(%{id: id}) when is_integer(id), do: id
  defp get_venue_id(_), do: nil

  # Get city fallback image using CityFallbackImageCache
  # This provides variety via venue_id and returns raw Unsplash URLs
  defp get_city_fallback_image(venue, city) do
    city_id = get_city_id(city)
    venue_id = get_venue_id(venue) || 0
    category = CategoryMapper.determine_category(venue)

    # Try category-specific first, then fall back to general
    CityFallbackImageCache.get_fallback_image(city_id, category, venue_id) ||
      CityFallbackImageCache.get_fallback_image(city_id, "general", venue_id)
  end

  defp get_city_id(%{id: id}) when is_integer(id), do: id
  defp get_city_id(_), do: nil

  # ============================================================================
  # Single Venue Lookups (Cache Only)
  # ============================================================================

  @doc """
  Get the cached image URL for a venue.

  Returns the CDN URL if the image is cached, the fallback URL otherwise,
  or nil if neither exists.

  In non-production environments, returns the fallback directly without
  cache lookup (dev uses original URLs, no R2 caching).

  ## Examples

      iex> get_url(123, "https://example.com/image.jpg")
      "https://cdn.wombie.com/images/venue/123/0.jpg"

      iex> get_url(999, "https://example.com/image.jpg")
      "https://example.com/image.jpg"  # Falls back to original
  """
  @spec get_url(integer(), String.t() | nil) :: String.t() | nil
  def get_url(venue_id, fallback \\ nil) when is_integer(venue_id) do
    if ImageEnv.production?() do
      ImageCacheService.get_url!("venue", venue_id, @position) || fallback
    else
      # In dev/test, skip cache lookup - just use original URL
      fallback
    end
  end

  # ============================================================================
  # Batch Lookups (N+1 Prevention)
  # ============================================================================

  @doc """
  Batch get image URLs for multiple venues.

  Returns a map of `%{venue_id => cdn_url}`. Venues without cached
  images will not have entries in the map.

  In non-production, returns empty map (uses fallbacks).

  ## Example

      iex> get_urls([1, 2, 3])
      %{1 => "https://cdn...", 2 => "https://cdn..."}  # venue 3 has no cached image
  """
  @spec get_urls([integer()]) :: %{integer() => String.t()}
  def get_urls([]), do: %{}

  def get_urls(venue_ids) when is_list(venue_ids) do
    if ImageEnv.production?() do
      from(c in CachedImage,
        where: c.entity_type == "venue",
        where: c.entity_id in ^venue_ids,
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
  Batch get image URLs with fallbacks for multiple venues.

  Takes a map of `%{venue_id => fallback_url}` and returns
  `%{venue_id => effective_url}` preferring cached URLs.

  In non-production, returns fallbacks directly (no cache lookup).

  ## Example

      iex> fallbacks = %{1 => "https://example/1.jpg", 2 => "https://example/2.jpg"}
      iex> get_urls_with_fallbacks(fallbacks)
      %{1 => "https://cdn.wombie.com/...", 2 => "https://example/2.jpg"}
  """
  @spec get_urls_with_fallbacks(%{integer() => String.t() | nil}) ::
          %{integer() => String.t() | nil}
  def get_urls_with_fallbacks(venue_fallbacks) when is_map(venue_fallbacks) do
    if ImageEnv.production?() do
      venue_ids = Map.keys(venue_fallbacks)
      cached_urls = get_urls(venue_ids)

      Map.new(venue_fallbacks, fn {venue_id, fallback} ->
        {venue_id, Map.get(cached_urls, venue_id, fallback)}
      end)
    else
      # In dev/test, just return the fallbacks as-is
      venue_fallbacks
    end
  end
end
