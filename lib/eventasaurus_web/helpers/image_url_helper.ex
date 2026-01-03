defmodule EventasaurusWeb.Helpers.ImageUrlHelper do
  @moduledoc """
  Unified image URL helper for all entity types.

  Provides:
  - URL resolution (Supabase → R2, relative paths, etc.)
  - og:image URL generation (1200x630, Cloudflare-optimized)
  - Social card image URL generation (400x400, Cloudflare-optimized)

  ## Priority Order for Images
  1. Cached CDN images (`cdn2.wombie.com/images/`) - already optimized, use directly
  2. External URLs - apply Cloudflare transformation for on-the-fly resizing

  ## Supported Entity Types
  - Events/Activities (via EventSourceImages)
  - Movies (via MovieImages)
  - Any entity with `cover_image_url` or `image_url` field

  ## URL Resolution

  Handles various image URL formats and normalizes them to the correct CDN URL:
  - R2 CDN URLs (current storage) - returned as-is
  - Legacy Supabase storage URLs - converted to R2 CDN URLs
  - Static asset paths (/images/...) - returned as-is
  - Relative paths (events/...) - prepended with R2 CDN URL

  ## PHASE 2 TODO
  This module contains legacy Supabase URL translation logic that should be removed
  after the database migration normalizes all URLs to relative paths.
  See: https://github.com/razrfly/eventasaurus/issues/XXXX

  After Phase 2 database migration:
  1. Remove `is_supabase_url?/1` and `supabase_to_r2/1` functions
  2. Remove the Supabase URL pattern matching in `resolve/1`
  3. Simplify to only handle: R2 URLs, static assets, and relative paths

  ## Usage

      # URL Resolution
      iex> ImageUrlHelper.resolve("https://cdn2.wombie.com/events/image.jpg")
      "https://cdn2.wombie.com/events/image.jpg"

      iex> ImageUrlHelper.resolve("https://xxx.supabase.co/storage/v1/object/public/bucket/events/image.jpg")
      "https://cdn2.wombie.com/events/image.jpg"

      # og:image generation (1200x630)
      iex> ImageUrlHelper.og_image_url(%{cover_image_url: "https://example.com/image.jpg"})
      "https://cdn.wombie.com/cdn-cgi/image/width=1200,height=630,fit=cover,quality=85/https://example.com/image.jpg"

      # Cached images bypass Cloudflare transformation
      iex> ImageUrlHelper.og_image_url(%{cover_image_url: "https://cdn2.wombie.com/images/..."})
      "https://cdn2.wombie.com/images/..."

      # Social card images (400x400)
      iex> ImageUrlHelper.social_card_image_url(%{cover_image_url: "https://example.com/image.jpg"})
      "https://cdn.wombie.com/cdn-cgi/image/width=400,height=400,fit=cover,quality=85/https://example.com/image.jpg"
  """

  # Standard image dimensions
  @og_image_width 1200
  @og_image_height 630
  @social_card_width 400
  @social_card_height 400

  # CDN configuration
  @cloudflare_cdn_domain "cdn.wombie.com"

  @doc """
  Resolve an image URL to its correct display URL.

  Handles legacy Supabase URLs, R2 CDN URLs, static assets, and relative paths.
  """
  def resolve(nil), do: nil
  def resolve(""), do: nil

  def resolve(url) when is_binary(url) do
    cond do
      # Already an R2 CDN URL - return as-is
      is_r2_cdn_url?(url) ->
        url

      # PHASE 2 REMOVAL: Legacy Supabase URL - extract path and redirect to R2
      # This block can be removed after database migration normalizes URLs
      is_supabase_url?(url) ->
        supabase_to_r2(url)

      # Static asset path - leave as-is (served from priv/static)
      String.starts_with?(url, "/images/") ->
        url

      # Other absolute paths - leave as-is
      String.starts_with?(url, "/") ->
        url

      # External URL (other domains) - leave as-is
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        url

      # Relative path - prepend R2 CDN URL
      true ->
        "#{r2_cdn_url()}/#{url}"
    end
  end

  @doc """
  Check if a URL is an R2 CDN URL.
  """
  def is_r2_cdn_url?(url) when is_binary(url) do
    String.starts_with?(url, r2_cdn_url())
  end

  def is_r2_cdn_url?(_), do: false

  # PHASE 2 REMOVAL: These functions handle legacy Supabase URLs
  # Remove after database migration normalizes all URLs

  @doc false
  # Detect legacy Supabase storage URLs
  def is_supabase_url?(url) when is_binary(url) do
    String.contains?(url, "supabase.co/storage")
  end

  def is_supabase_url?(_), do: false

  @doc false
  # Convert a Supabase storage URL to R2 CDN URL
  defp supabase_to_r2(url) do
    case extract_supabase_path(url) do
      {:ok, path} -> "#{r2_cdn_url()}/#{path}"
      # Fallback: return original if can't parse (shouldn't happen)
      :error -> url
    end
  end

  @doc false
  # Extract the file path from a Supabase storage URL
  # Handles URLs like:
  # - https://xxx.supabase.co/storage/v1/object/public/bucket-name/path/to/file.jpg
  # - https://xxx.supabase.co/storage/v1/object/sign/bucket-name/path/to/file.jpg?token=...
  defp extract_supabase_path(url) do
    # Pattern: /storage/v1/object/public/{bucket}/{path}
    # or: /storage/v1/object/sign/{bucket}/{path}?...
    patterns = [
      # Public URL pattern - captures everything after bucket name
      ~r{/storage/v1/object/public/[^/]+/(.+)$},
      # Signed URL pattern - captures path before query string
      ~r{/storage/v1/object/sign/[^/]+/([^?]+)}
    ]

    Enum.find_value(patterns, :error, fn pattern ->
      case Regex.run(pattern, url) do
        [_, path] -> {:ok, path}
        _ -> nil
      end
    end)
  end

  # END PHASE 2 REMOVAL

  @doc """
  Get the configured R2 CDN URL.

  Mirrors the fallback logic in R2Client to ensure consistent URL generation.
  """
  def r2_cdn_url do
    r2_config = Application.get_env(:eventasaurus, :r2) || %{}
    r2_config[:cdn_url] || System.get_env("R2_CDN_URL") || "https://cdn2.wombie.com"
  end

  # ===========================================================================
  # og:image URL Generation (1200x630)
  # ===========================================================================

  @doc """
  Generate an optimized og:image URL for any entity.

  Returns a URL suitable for Open Graph image tags (1200x630 recommended).

  ## Priority
  1. Cached CDN images (`cdn2.wombie.com/images/`) - returned as-is (already optimized)
  2. External URLs - wrapped with Cloudflare transformation for on-the-fly resizing

  ## Options
  - `:width` - Override default width (default: 1200)
  - `:height` - Override default height (default: 630)

  ## Examples

      # Entity with cover_image_url
      iex> og_image_url(%{cover_image_url: "https://example.com/image.jpg"})
      "https://cdn.wombie.com/cdn-cgi/image/width=1200,height=630,fit=cover,quality=85/https://example.com/image.jpg"

      # Cached CDN image - no transformation needed
      iex> og_image_url(%{cover_image_url: "https://cdn2.wombie.com/images/public_event_source/123/0.jpg"})
      "https://cdn2.wombie.com/images/public_event_source/123/0.jpg"

      # Entity with image_url field
      iex> og_image_url(%{image_url: "https://example.com/poster.jpg"})
      "https://cdn.wombie.com/cdn-cgi/image/width=1200,height=630,fit=cover,quality=85/https://example.com/poster.jpg"
  """
  @spec og_image_url(map(), keyword()) :: String.t() | nil
  def og_image_url(entity, opts \\ [])
  def og_image_url(nil, _opts), do: nil

  def og_image_url(entity, opts) when is_map(entity) do
    width = Keyword.get(opts, :width, @og_image_width)
    height = Keyword.get(opts, :height, @og_image_height)

    case extract_image_url(entity) do
      nil -> nil
      url -> optimized_url(url, width, height)
    end
  end

  @doc """
  Generate an optimized social card image URL for any entity.

  Returns a URL suitable for social card generation (400x400 for embedding in SVG).

  ## Priority
  1. Cached CDN images (`cdn2.wombie.com/images/`) - returned as-is (already optimized)
  2. External URLs - wrapped with Cloudflare transformation for on-the-fly resizing

  ## Options
  - `:width` - Override default width (default: 400)
  - `:height` - Override default height (default: 400)

  ## Examples

      iex> social_card_image_url(%{cover_image_url: "https://example.com/image.jpg"})
      "https://cdn.wombie.com/cdn-cgi/image/width=400,height=400,fit=cover,quality=85/https://example.com/image.jpg"
  """
  @spec social_card_image_url(map(), keyword()) :: String.t() | nil
  def social_card_image_url(entity, opts \\ [])
  def social_card_image_url(nil, _opts), do: nil

  def social_card_image_url(entity, opts) when is_map(entity) do
    width = Keyword.get(opts, :width, @social_card_width)
    height = Keyword.get(opts, :height, @social_card_height)

    case extract_image_url(entity) do
      nil -> nil
      url -> optimized_url(url, width, height)
    end
  end

  # ===========================================================================
  # Private Helpers for Image URL Generation
  # ===========================================================================

  # Extract image URL from various entity types
  # Supports: cover_image_url, image_url, poster_url, backdrop_url
  defp extract_image_url(entity) do
    cond do
      Map.has_key?(entity, :cover_image_url) and entity.cover_image_url ->
        entity.cover_image_url

      Map.has_key?(entity, :image_url) and entity.image_url ->
        entity.image_url

      Map.has_key?(entity, :poster_url) and entity.poster_url ->
        entity.poster_url

      Map.has_key?(entity, :backdrop_url) and entity.backdrop_url ->
        entity.backdrop_url

      # String key versions (for maps with string keys)
      is_map(entity) and Map.get(entity, "cover_image_url") ->
        Map.get(entity, "cover_image_url")

      is_map(entity) and Map.get(entity, "image_url") ->
        Map.get(entity, "image_url")

      true ->
        nil
    end
  end

  # Generate optimized URL with Cloudflare transformation or return cached URL directly
  defp optimized_url(url, width, height) when is_binary(url) do
    # First resolve any legacy URLs
    resolved_url = resolve(url)

    cond do
      # Cached CDN images are already optimized - return directly
      is_cached_cdn_image?(resolved_url) ->
        resolved_url

      # Static assets - return directly (can't transform)
      String.starts_with?(resolved_url, "/") ->
        resolved_url

      # External URLs - apply Cloudflare transformation
      true ->
        cloudflare_transform_url(resolved_url, width, height)
    end
  end

  defp optimized_url(_, _, _), do: nil

  @doc """
  Check if a URL is from our cached CDN (R2 images/).
  These images are already optimized and don't need Cloudflare transformation.
  """
  @spec is_cached_cdn_image?(any()) :: boolean()
  def is_cached_cdn_image?(url) when is_binary(url) do
    prefix = String.trim_trailing(r2_cdn_url(), "/") <> "/images/"
    String.starts_with?(url, prefix)
  end

  def is_cached_cdn_image?(_), do: false

  # Apply Cloudflare image transformation to a URL
  defp cloudflare_transform_url(url, width, height) do
    "https://#{@cloudflare_cdn_domain}/cdn-cgi/image/width=#{width},height=#{height},fit=cover,quality=85/#{url}"
  end
end
