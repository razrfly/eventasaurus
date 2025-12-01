defmodule EventasaurusWeb.Helpers.ImageUrlHelper do
  @moduledoc """
  Storage-agnostic image URL helper.

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

      iex> ImageUrlHelper.resolve("https://cdn2.wombie.com/events/image.jpg")
      "https://cdn2.wombie.com/events/image.jpg"

      iex> ImageUrlHelper.resolve("https://xxx.supabase.co/storage/v1/object/public/bucket/events/image.jpg")
      "https://cdn2.wombie.com/events/image.jpg"

      iex> ImageUrlHelper.resolve("/images/events/abstract/abstract1.png")
      "/images/events/abstract/abstract1.png"

      iex> ImageUrlHelper.resolve("events/image.jpg")
      "https://cdn2.wombie.com/events/image.jpg"
  """

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
end
