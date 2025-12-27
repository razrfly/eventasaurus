defmodule Eventasaurus.ImageKit do
  @moduledoc """
  Helper module for wrapping external image URLs with ImageKit CDN in production.

  In development, returns original URLs unchanged by default.
  In production, returns ImageKit CDN URLs for optimized delivery.

  ## Note on Venue Images

  Venue images have been migrated to R2/Cloudflare CDN storage via the `cached_images`
  table and `ImageCacheService`. This module is now primarily used for other image types
  that still need ImageKit CDN transformation (e.g., external event images).

  See Issue #2977 for the migration details.

  ## Configuration

  Configure in your config files:

      # config/config.exs
      config :eventasaurus, :imagekit,
        enabled: false,
        id: "wombie",
        endpoint: "https://ik.imagekit.io/wombie"

      # config/prod.exs
      config :eventasaurus, :imagekit,
        enabled: true

  ## Testing in Development

  Enable ImageKit CDN temporarily for testing:

      IMAGEKIT_CDN_ENABLED=true mix phx.server

  ## Usage

      # Simple usage - uses default settings
      ImageKit.url("https://example.com/image.jpg")

      # With transformation options
      ImageKit.url("https://example.com/image.jpg", width: 800, quality: 90)

      # Multiple transformations
      ImageKit.url("https://example.com/image.jpg",
        width: 1200,
        height: 800,
        crop: "maintain_ratio",
        quality: 85,
        format: "webp"
      )

  ## Supported Options

  - `width` / `w` - Width in pixels
  - `height` / `h` - Height in pixels
  - `quality` / `q` - Quality 1-100
  - `format` / `f` - Output format: "webp", "jpg", "png", "auto"
  - `crop` / `c` - Crop mode: "maintain_ratio", "force", "at_least", "at_max"
  - `focus` / `fo` - Focus area: "auto", "face", "center"

  See ImageKit docs: https://docs.imagekit.io/features/image-transformations
  """

  @doc """
  Wraps an image URL with ImageKit CDN transformations.

  Returns the original URL if:
  - ImageKit CDN is disabled (development mode)
  - URL is nil or empty
  - URL is already an ImageKit URL
  - URL is invalid

  ## Examples

      iex> ImageKit.url("https://example.com/image.jpg")
      "https://example.com/image.jpg"  # ImageKit disabled in dev

      iex> ImageKit.url("https://example.com/image.jpg", width: 800, quality: 90)
      "https://ik.imagekit.io/wombie/https://example.com/image.jpg?tr=w-800,q-90"  # ImageKit enabled

      iex> ImageKit.url(nil)
      nil

      iex> ImageKit.url("")
      ""
  """
  @spec url(String.t() | nil, keyword()) :: String.t() | nil
  def url(source_url, opts \\ [])

  # Handle nil URL
  def url(nil, _opts), do: nil

  # Handle empty URL
  def url("", _opts), do: ""

  # Main URL transformation
  def url(source_url, opts) when is_binary(source_url) do
    cond do
      # ImageKit CDN disabled - return original URL
      not enabled?() ->
        source_url

      # Already an ImageKit URL - don't double-wrap
      imagekit_url?(source_url) ->
        source_url

      # Invalid URL - return original as fallback
      not valid_url?(source_url) ->
        source_url

      # Transform URL with ImageKit CDN
      true ->
        build_imagekit_url(source_url, opts)
    end
  end

  ## Private Functions

  # Check if ImageKit CDN is enabled via configuration
  defp enabled? do
    Application.get_env(:eventasaurus, :imagekit, [])
    |> Keyword.get(:enabled, false)
  end

  # Get configured ImageKit endpoint
  defp endpoint do
    Application.get_env(:eventasaurus, :imagekit, [])
    |> Keyword.get(:endpoint, "https://ik.imagekit.io/wombie")
  end

  # Check if URL is already an ImageKit URL (avoid double-wrapping)
  defp imagekit_url?(url) do
    String.starts_with?(url, "https://ik.imagekit.io/")
  end

  # Basic URL validation
  defp valid_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and uri.host != nil
  rescue
    _ -> false
  end

  # Build the ImageKit CDN URL with transformations
  defp build_imagekit_url(source_url, opts) do
    case build_transformations_string(opts) do
      "" ->
        # No transformations, just serve through ImageKit
        "#{endpoint()}/#{source_url}"

      transformations ->
        # With transformations using ImageKit URL syntax
        "#{endpoint()}/#{source_url}?tr=#{transformations}"
    end
  end

  # Build transformation string for ImageKit
  # Format: tr=w-800,h-600,q-90,f-webp
  defp build_transformations_string(opts) do
    opts
    |> Enum.map(&normalize_transformation/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  # Normalize transformation to ImageKit format
  defp normalize_transformation({key, value}) do
    case normalize_key(key) do
      nil -> nil
      normalized_key -> "#{normalized_key}-#{value}"
    end
  end

  # Map Elixir-style keys to ImageKit transformation names
  defp normalize_key(:width), do: "w"
  defp normalize_key(:w), do: "w"
  defp normalize_key(:height), do: "h"
  defp normalize_key(:h), do: "h"
  defp normalize_key(:quality), do: "q"
  defp normalize_key(:q), do: "q"
  defp normalize_key(:format), do: "f"
  defp normalize_key(:f), do: "f"
  defp normalize_key(:crop), do: "c"
  defp normalize_key(:c), do: "c"
  defp normalize_key(:focus), do: "fo"
  defp normalize_key(:fo), do: "fo"
  # Unknown keys are ignored
  defp normalize_key(_), do: nil
end
