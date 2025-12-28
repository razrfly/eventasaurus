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

  ## Disabling CDN (e.g., when quota exceeded)

  To disable CDN transformations temporarily (e.g., when Cloudflare quota is exceeded):

      fly secrets set CDN_FORCE_DISABLED=true

  To re-enable:

      fly secrets unset CDN_FORCE_DISABLED

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

      # Get both CDN and fallback URLs for client-side fallback
      CDN.url_with_fallback("https://example.com/image.jpg", width: 800)
      # => %{src: "https://cdn.wombie.com/...", fallback: "https://example.com/image.jpg"}

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
  - CDN is disabled (development mode or CDN_FORCE_DISABLED=true)
  - URL is nil or empty
  - URL is already a CDN URL
  - URL is from R2 storage (already Cloudflare-cached)
  - URL is from Unsplash (they have their own CDN)
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
    # PHASE 2 TODO: Remove this resolve step after database migration normalizes URLs
    # First resolve any legacy Supabase URLs to R2 CDN URLs
    resolved_url = EventasaurusWeb.Helpers.ImageUrlHelper.resolve(source_url)

    cond do
      # CDN force disabled via env var (for quota exceeded situations)
      force_disabled?() ->
        resolved_url

      # CDN disabled in config
      not enabled?() ->
        resolved_url

      # Already a CDN URL - don't double-wrap
      cdn_url?(resolved_url) ->
        resolved_url

      # R2 CDN URLs - already cached via Cloudflare, don't double-wrap
      r2_cdn_url?(resolved_url) ->
        resolved_url

      # Unsplash URLs already have their own global CDN - don't wrap
      unsplash_url?(resolved_url) ->
        resolved_url

      # Invalid URL - return resolved as fallback
      not valid_url?(resolved_url) ->
        resolved_url

      # Transform URL with CDN
      true ->
        build_cdn_url(resolved_url, opts)
    end
  end

  @doc """
  Returns both the CDN URL and the fallback (original) URL.

  This is useful for client-side fallback handling where the browser can
  switch to the fallback URL if the CDN URL fails to load.

  ## Examples

      iex> CDN.url_with_fallback("https://example.com/image.jpg", width: 800)
      %{src: "https://cdn.wombie.com/cdn-cgi/image/width=800/https://example.com/image.jpg",
        fallback: "https://example.com/image.jpg"}

      iex> CDN.url_with_fallback(nil)
      %{src: nil, fallback: nil}
  """
  @spec url_with_fallback(String.t() | nil, keyword()) :: %{
          src: String.t() | nil,
          fallback: String.t() | nil
        }
  def url_with_fallback(source_url, opts \\ [])
  def url_with_fallback(nil, _opts), do: %{src: nil, fallback: nil}
  def url_with_fallback("", _opts), do: %{src: "", fallback: ""}

  def url_with_fallback(source_url, opts) when is_binary(source_url) do
    # Resolve any legacy URLs first
    resolved_url = EventasaurusWeb.Helpers.ImageUrlHelper.resolve(source_url)

    %{
      src: url(source_url, opts),
      fallback: resolved_url
    }
  end

  @doc """
  Checks if CDN is currently disabled (either by config or force override).
  """
  @spec disabled?() :: boolean()
  def disabled? do
    force_disabled?() or not enabled?()
  end

  ## Private Functions

  # Check if CDN is force disabled via environment variable
  defp force_disabled? do
    System.get_env("CDN_FORCE_DISABLED") == "true"
  end

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

  # Check if URL is from R2 CDN (already Cloudflare-cached via R2)
  # These images are already optimized and served from Cloudflare's edge network
  defp r2_cdn_url?(url) do
    r2_cdn = r2_cdn_domain()
    String.starts_with?(url, r2_cdn)
  end

  # Get configured R2 CDN domain
  defp r2_cdn_domain do
    r2_config = Application.get_env(:eventasaurus, :r2, [])
    r2_config[:cdn_url] || "https://cdn2.wombie.com"
  end

  # Check if URL is from Unsplash (they have their own global CDN)
  defp unsplash_url?(url) do
    String.contains?(url, "unsplash.com")
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
