defmodule EventasaurusApp.Images.EventSourceImages do
  @moduledoc """
  Get cached event source images from R2 storage.

  Event source images are cached via `EventImageCaching` processor during scraping.
  This module provides retrieval functions following the same patterns as MovieImages.

  ## Usage

      # Get cached URL with fallback to original
      url = EventSourceImages.get_url(source_id, source.image_url)

      # Batch lookup for multiple sources (avoids N+1)
      urls = EventSourceImages.get_urls([source_id1, source_id2])

      # Batch with fallbacks
      fallbacks = %{source1.id => source1.image_url, source2.id => source2.image_url}
      urls = EventSourceImages.get_urls_with_fallbacks(fallbacks)
  """

  alias EventasaurusApp.Images.ImageCacheService

  @position 0

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
    if production_env?() do
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
    if production_env?() do
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
    if production_env?() do
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

  # Check if we're running in production environment.
  # Image cache lookups only run in production - dev uses original URLs.
  defp production_env? do
    Application.get_env(:eventasaurus, :env) == :prod
  end
end
