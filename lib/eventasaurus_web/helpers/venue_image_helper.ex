defmodule EventasaurusWeb.Helpers.VenueImageHelper do
  @moduledoc """
  Helper for getting venue images with intelligent fallback strategy.

  Fallback order:
  1. Venue's own images (if available)
  2. Random image from city's Unsplash gallery (consistent per venue)
  3. Placeholder image
  """

  alias Eventasaurus.CDN

  @doc """
  Get the best available image for a venue with CDN optimization.

  ## Options

  - `:width` - Target width in pixels (default: 400)
  - `:height` - Target height in pixels (default: 300)
  - `:quality` - JPEG/WebP quality 1-100 (default: 85)
  - `:fit` - Resize behavior: "scale-down", "contain", "cover", "crop", "pad" (default: "cover")

  ## Examples

      # Grid view (400x300)
      get_venue_image(venue, city, width: 400, height: 300, quality: 85)

      # List view thumbnail (192x192)
      get_venue_image(venue, city, width: 192, height: 192, quality: 85)

      # Hero image (1200x600)
      get_venue_image(venue, city, width: 1200, height: 600, quality: 90)
  """
  @spec get_venue_image(map(), map(), keyword()) :: String.t()
  def get_venue_image(venue, city, opts \\ []) do
    width = Keyword.get(opts, :width, 400)
    height = Keyword.get(opts, :height, 300)
    quality = Keyword.get(opts, :quality, 85)
    fit = Keyword.get(opts, :fit, "cover")

    cdn_opts = [width: width, height: height, fit: fit, quality: quality]

    cond do
      # 1. Use venue's own images if available
      has_venue_images?(venue) ->
        venue.venue_images
        |> List.first()
        |> get_venue_image_url()
        |> CDN.url(cdn_opts)

      # 2. Use random image from city's Unsplash gallery
      has_city_gallery?(city) ->
        get_random_city_image(venue.id, city.unsplash_gallery)
        |> CDN.url(cdn_opts)

      # 3. Fallback to placeholder
      true ->
        "/images/venue-placeholder.jpg"
    end
  end

  @doc """
  Get a random image from city's Unsplash gallery, consistent per venue ID.

  Uses venue ID as seed to ensure the same venue always gets the same image
  from the gallery, providing visual consistency across the site.
  """
  @spec get_random_city_image(integer(), map()) :: String.t() | nil
  def get_random_city_image(venue_id, gallery) when is_map(gallery) do
    images = gallery["images"] || []

    if Enum.empty?(images) do
      nil
    else
      # Use venue_id as seed for consistent image per venue
      index = rem(venue_id, length(images))
      image = Enum.at(images, index)

      # Return the main URL (not thumb_url)
      image["url"]
    end
  end

  def get_random_city_image(_venue_id, _gallery), do: nil

  # Private helpers

  defp has_venue_images?(%{venue_images: images}) when is_list(images) do
    length(images) > 0
  end

  defp has_venue_images?(_), do: false

  defp get_venue_image_url(image) when is_map(image) do
    image["url"] || image[:url]
  end

  defp get_venue_image_url(_), do: nil

  defp has_city_gallery?(%{unsplash_gallery: gallery}) when is_map(gallery) do
    images = gallery["images"] || []
    is_list(images) and length(images) > 0
  end

  defp has_city_gallery?(_), do: false
end
