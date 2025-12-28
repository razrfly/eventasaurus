defmodule EventasaurusApp.Images.PerformerImages do
  @moduledoc """
  Virtual performer images derived from event source appearances.

  Performer images are NOT cached separately. Instead, they're derived from
  the event_source images where the performer appeared. This avoids duplication
  since performer.image_url often equals event_source.image_url.

  ## How It Works

  Query path: performer → public_event_performers → events → public_event_sources → cached_images

  Each cached image includes:
  - `cdn_url` - The cached R2 URL (use this!)
  - `original_url` - The original source URL
  - `original_source` - Which source provided this image (e.g., "bandsintown")

  ## Usage

      # Get all cached images for a performer
      images = PerformerImages.get_images(performer_id)

      # Get the primary (most recent) image
      image = PerformerImages.get_primary_image(performer_id)

      # Get just the URL (CDN if cached, original as fallback)
      url = PerformerImages.get_url(performer_id)

      # Batch lookup for multiple performers (avoids N+1)
      urls = PerformerImages.get_urls([performer_id1, performer_id2, ...])

  ## Future: Canonical Artist Images

  If we later add dedicated performer images from Spotify, MusicBrainz, etc.,
  those would use `entity_type: "performer"` in cached_images. This module
  would be updated to prefer those over event-derived images.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Images.{CachedImage, ImageEnv}
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.PublicEvents.PublicEventPerformer

  @doc """
  Get all cached images for a performer from their event appearances.

  Returns distinct images (by original_url) ordered by most recent first.
  Only returns successfully cached images with CDN URLs.

  In non-production, returns empty list (no cache lookup).
  """
  @spec get_images(integer()) :: [CachedImage.t()]
  def get_images(performer_id) when is_integer(performer_id) do
    if ImageEnv.production?() do
      from(ci in CachedImage,
        join: pes in PublicEventSource,
        on: ci.entity_type == "public_event_source" and ci.entity_id == pes.id,
        join: pep in PublicEventPerformer,
        on: pep.event_id == pes.event_id,
        where: pep.performer_id == ^performer_id,
        where: ci.status == "cached",
        where: not is_nil(ci.cdn_url),
        distinct: ci.original_url,
        order_by: [desc: ci.inserted_at],
        select: ci
      )
      |> Repo.all()
    else
      # In dev/test, skip cache lookup - return empty list
      []
    end
  end

  @doc """
  Get the primary (most recent) cached image for a performer.

  Returns nil if no cached images exist.

  In non-production, returns nil (no cache lookup).
  """
  @spec get_primary_image(integer()) :: CachedImage.t() | nil
  def get_primary_image(performer_id) when is_integer(performer_id) do
    if ImageEnv.production?() do
      from(ci in CachedImage,
        join: pes in PublicEventSource,
        on: ci.entity_type == "public_event_source" and ci.entity_id == pes.id,
        join: pep in PublicEventPerformer,
        on: pep.event_id == pes.event_id,
        where: pep.performer_id == ^performer_id,
        where: ci.status == "cached",
        where: not is_nil(ci.cdn_url),
        order_by: [desc: ci.inserted_at],
        limit: 1,
        select: ci
      )
      |> Repo.one()
    else
      # In dev/test, skip cache lookup - return nil
      nil
    end
  end

  @doc """
  Get the effective URL for a performer's image.

  Returns the CDN URL if a cached image exists, nil otherwise.
  For fallback to original URL, use `get_url_with_fallback/2`.
  """
  @spec get_url(integer()) :: String.t() | nil
  def get_url(performer_id) when is_integer(performer_id) do
    case get_primary_image(performer_id) do
      nil -> nil
      cached -> cached.cdn_url
    end
  end

  @doc """
  Get the effective URL with fallback to the performer's stored image_url.

  Prefers cached CDN URL, falls back to the provided original URL.
  """
  @spec get_url_with_fallback(integer(), String.t() | nil) :: String.t() | nil
  def get_url_with_fallback(performer_id, fallback_url) when is_integer(performer_id) do
    get_url(performer_id) || fallback_url
  end

  @doc """
  Batch get URLs for multiple performers.

  Returns a map of `%{performer_id => url}`. Performers without cached
  images will not have entries in the map.

  This is efficient for avoiding N+1 queries when displaying lists.

  In non-production, returns empty map (uses fallbacks).
  """
  @spec get_urls([integer()]) :: %{integer() => String.t()}
  def get_urls([]), do: %{}

  def get_urls(performer_ids) when is_list(performer_ids) do
    if ImageEnv.production?() do
      # Subquery to get the most recent cached image per performer
      from(ci in CachedImage,
        join: pes in PublicEventSource,
        on: ci.entity_type == "public_event_source" and ci.entity_id == pes.id,
        join: pep in PublicEventPerformer,
        on: pep.event_id == pes.event_id,
        where: pep.performer_id in ^performer_ids,
        where: ci.status == "cached",
        where: not is_nil(ci.cdn_url),
        distinct: pep.performer_id,
        order_by: [asc: pep.performer_id, desc: ci.inserted_at],
        select: {pep.performer_id, ci.cdn_url}
      )
      |> Repo.all()
      |> Map.new()
    else
      # In dev/test, return empty map - fallbacks will be used
      %{}
    end
  end

  @doc """
  Batch get URLs with fallbacks for multiple performers.

  Takes a map of `%{performer_id => fallback_url}` and returns
  `%{performer_id => effective_url}` preferring cached URLs.

  In non-production, returns fallbacks directly (no cache lookup).
  """
  @spec get_urls_with_fallbacks(%{integer() => String.t() | nil}) :: %{
          integer() => String.t() | nil
        }
  def get_urls_with_fallbacks(performer_fallbacks) when is_map(performer_fallbacks) do
    if ImageEnv.production?() do
      performer_ids = Map.keys(performer_fallbacks)
      cached_urls = get_urls(performer_ids)

      Map.new(performer_fallbacks, fn {performer_id, fallback} ->
        {performer_id, Map.get(cached_urls, performer_id, fallback)}
      end)
    else
      # In dev/test, just return the fallbacks as-is
      performer_fallbacks
    end
  end

  @doc """
  Get image count for a performer (how many distinct cached images).

  In non-production, returns 0 (no cache lookup).
  """
  @spec count_images(integer()) :: non_neg_integer()
  def count_images(performer_id) when is_integer(performer_id) do
    if ImageEnv.production?() do
      from(ci in CachedImage,
        join: pes in PublicEventSource,
        on: ci.entity_type == "public_event_source" and ci.entity_id == pes.id,
        join: pep in PublicEventPerformer,
        on: pep.event_id == pes.event_id,
        where: pep.performer_id == ^performer_id,
        where: ci.status == "cached",
        where: not is_nil(ci.cdn_url),
        select: count(ci.id, :distinct)
      )
      |> Repo.one() || 0
    else
      # In dev/test, no cached images
      0
    end
  end
end
