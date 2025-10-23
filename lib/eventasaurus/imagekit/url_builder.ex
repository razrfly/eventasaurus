defmodule Eventasaurus.ImageKit.URLBuilder do
  @moduledoc """
  Builds ImageKit URLs with transformations for images in Media Library.

  This module is for images that have been uploaded to ImageKit's Media Library.
  For serving external URLs through web proxy, see `Eventasaurus.ImageKit` module.

  ## Examples

      # Original size from Media Library
      build_url("/venues/123/image.jpg")
      #=> "https://ik.imagekit.io/wombie/venues/123/image.jpg"

      # Thumbnail (200px width)
      build_url("/venues/123/image.jpg", width: 200)
      #=> "https://ik.imagekit.io/wombie/tr:w-200/venues/123/image.jpg"

      # WebP format, compressed
      build_url("/venues/123/image.jpg", width: 800, quality: 85, format: "webp")
      #=> "https://ik.imagekit.io/wombie/tr:w-800,q-85,f-webp/venues/123/image.jpg"

      # Multiple transformations
      build_url("/venues/123/image.jpg",
        width: 1200,
        height: 800,
        crop: "maintain_ratio",
        quality: 90
      )
      #=> "https://ik.imagekit.io/wombie/tr:w-1200,h-800,c-maintain_ratio,q-90/venues/123/image.jpg"
  """

  alias Eventasaurus.ImageKit.Config

  @doc """
  Builds an ImageKit URL with optional transformations.

  ## Parameters

  - `path` - Image path in ImageKit Media Library (e.g., "/venues/123/image.jpg")
  - `opts` - Transformation options:
    - `:width` / `:w` - Width in pixels
    - `:height` / `:h` - Height in pixels
    - `:quality` / `:q` - Quality 1-100
    - `:format` / `:f` - Output format: "webp", "jpg", "png", "auto"
    - `:crop` / `:c` - Crop mode: "maintain_ratio", "force", "at_least", "at_max"
    - `:focus` / `:fo` - Focus area: "auto", "face", "center"

  ## Returns

  Full ImageKit CDN URL with transformations.

  ## Examples

      iex> URLBuilder.build_url("/venues/123/photo.jpg")
      "https://ik.imagekit.io/wombie/venues/123/photo.jpg"

      iex> URLBuilder.build_url("/venues/123/photo.jpg", width: 400, quality: 85)
      "https://ik.imagekit.io/wombie/tr:w-400,q-85/venues/123/photo.jpg"
  """
  @spec build_url(String.t(), keyword()) :: String.t()
  def build_url(path, opts \\ []) do
    base = Config.url_endpoint()

    case build_transformations(opts) do
      "" ->
        # No transformations, return direct URL
        "#{base}#{path}"

      transformations ->
        # With transformations using path-based syntax
        "#{base}/tr:#{transformations}#{path}"
    end
  end

  @doc """
  Builds transformation string from options.

  Converts keyword list into ImageKit transformation format.

  ## Examples

      iex> build_transformations([width: 800, quality: 90])
      "w-800,q-90"

      iex> build_transformations([])
      ""
  """
  @spec build_transformations(keyword()) :: String.t()
  def build_transformations(opts) do
    opts
    |> Enum.map(&normalize_transformation/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  # Normalize transformation options to ImageKit format
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
