defmodule Eventasaurus.CDN do
  @moduledoc """
  Helper module for wrapping external image URLs with Cloudflare Image Resizing in production.

  In development, returns original URLs unchanged by default.
  In production, wraps URLs with Cloudflare's CDN for optimization and caching.

  ## Configuration

  Configure in your config files:

      # config/config.exs
      config :eventasaurus, :cdn,
        enabled: false,
        domain: "cdn.wombie.com"

      # config/prod.exs
      config :eventasaurus, :cdn,
        enabled: true

  ## Testing in Development

  Enable CDN temporarily for testing:

      CDN_ENABLED=true mix phx.server

  ## Usage

      # Simple usage - uses default settings
      CDN.url("https://example.com/image.jpg")

      # With transformation options
      CDN.url("https://example.com/image.jpg", width: 800, quality: 90)

      # Multiple transformations
      CDN.url("https://example.com/image.jpg",
        width: 1200,
        height: 800,
        fit: "cover",
        quality: 85,
        format: "webp"
      )

  ## Supported Options

  - `width` / `w` - Maximum width in pixels
  - `height` / `h` - Maximum height in pixels
  - `quality` / `q` - Quality 1-100 (default varies by format)
  - `fit` - Resizing mode: "scale-down", "contain", "cover", "crop", "pad"
  - `format` / `f` - Output format: "auto", "webp", "avif", "json"
  - `dpr` - Device pixel ratio (1-3)

  See Cloudflare docs: https://developers.cloudflare.com/images/transform-images/transform-via-url/
  """

  @doc """
  Wraps an image URL with Cloudflare CDN transformations.

  Returns the original URL if:
  - CDN is disabled (development mode)
  - URL is nil or empty
  - URL is already a CDN URL
  - URL is invalid

  ## Examples

      iex> CDN.url("https://example.com/image.jpg")
      "https://example.com/image.jpg"  # CDN disabled in dev

      iex> CDN.url("https://example.com/image.jpg", width: 800, quality: 90)
      "https://cdn.wombie.com/cdn-cgi/image/width=800,quality=90/https://example.com/image.jpg"  # CDN enabled

      iex> CDN.url(nil)
      nil

      iex> CDN.url("")
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
      # CDN disabled - return original URL
      not enabled?() ->
        source_url

      # Already a CDN URL - don't double-wrap
      cdn_url?(source_url) ->
        source_url

      # Invalid URL - return original as fallback
      not valid_url?(source_url) ->
        source_url

      # Transform URL with CDN
      true ->
        build_cdn_url(source_url, opts)
    end
  end

  ## Private Functions

  # Check if CDN is enabled via configuration
  defp enabled? do
    Application.get_env(:eventasaurus, :cdn, [])
    |> Keyword.get(:enabled, false)
  end

  # Get configured CDN domain
  defp domain do
    Application.get_env(:eventasaurus, :cdn, [])
    |> Keyword.get(:domain, "cdn.wombie.com")
  end

  # Check if URL is already a CDN URL (avoid double-wrapping)
  defp cdn_url?(url) do
    String.contains?(url, domain()) and String.contains?(url, "/cdn-cgi/image/")
  end

  # Basic URL validation
  defp valid_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and uri.host != nil
  rescue
    _ -> false
  end

  # Build the CDN URL with transformations
  defp build_cdn_url(source_url, opts) do
    case build_options_string(opts) do
      "" ->
        # No transformations, just proxy through CDN
        "https://#{domain()}/cdn-cgi/image/#{source_url}"

      options_string ->
        # With transformations
        "https://#{domain()}/cdn-cgi/image/#{options_string}/#{source_url}"
    end
  end

  # Build comma-separated options string for Cloudflare
  defp build_options_string(opts) do
    opts
    |> Enum.map(&normalize_option/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  # Normalize option to Cloudflare format
  defp normalize_option({key, value}) do
    case normalize_key(key) do
      nil -> nil
      normalized_key -> "#{normalized_key}=#{value}"
    end
  end

  # Map Elixir-style keys to Cloudflare option names
  defp normalize_key(:width), do: "width"
  defp normalize_key(:w), do: "width"
  defp normalize_key(:height), do: "height"
  defp normalize_key(:h), do: "height"
  defp normalize_key(:quality), do: "quality"
  defp normalize_key(:q), do: "quality"
  defp normalize_key(:fit), do: "fit"
  defp normalize_key(:format), do: "format"
  defp normalize_key(:f), do: "format"
  defp normalize_key(:dpr), do: "dpr"
  # Unknown keys are ignored
  defp normalize_key(_), do: nil
end
