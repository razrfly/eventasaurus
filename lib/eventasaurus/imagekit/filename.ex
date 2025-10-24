defmodule Eventasaurus.ImageKit.Filename do
  @moduledoc """
  Generates deterministic, hash-based filenames for ImageKit uploads.

  Uses provider codes and URL hashing to create short, unique filenames
  that prevent duplicate uploads and enable efficient deduplication.

  ## Examples

      iex> generate("https://maps.googleapis.com/...", "google_places")
      "gp-a8f3d2.jpg"

      iex> generate("https://images.unsplash.com/...", "unsplash")
      "us-7bc419.jpg"
  """

  @provider_codes %{
    "google_places" => "gp",
    "unsplash" => "us",
    "foursquare" => "fs",
    "pexels" => "px",
    "instagram" => "ig"
  }

  @doc """
  Generates a deterministic filename from provider URL and provider name.

  ## Parameters

  - `provider_url` - The original image URL from the provider
  - `provider` - Provider name (e.g., "google_places", "unsplash")

  ## Returns

  A short, deterministic filename in format: `{provider_code}-{hash}.jpg`

  ## Examples

      iex> generate("https://maps.googleapis.com/maps/api/place/photo?photoreference=ABC123", "google_places")
      "gp-a8f3d2.jpg"

      iex> generate("https://images.unsplash.com/photo-123", "unsplash")
      "us-7bc419.jpg"
  """
  @spec generate(String.t(), String.t()) :: String.t()
  def generate(provider_url, provider) when is_binary(provider_url) and is_binary(provider) do
    provider_code = get_provider_code(provider)
    hash = generate_hash(provider_url)

    "#{provider_code}-#{hash}.jpg"
  end

  @doc """
  Gets the provider code for a given provider name.

  ## Examples

      iex> get_provider_code("google_places")
      "gp"

      iex> get_provider_code("unsplash")
      "us"

      iex> get_provider_code("unknown_provider")
      "xx"
  """
  @spec get_provider_code(String.t()) :: String.t()
  def get_provider_code(provider) do
    Map.get(@provider_codes, provider, "xx")
  end

  @doc """
  Generates a 6-character hash from a URL using MD5.

  The hash is deterministic - the same URL will always produce the same hash.
  This enables deduplication by checking if a file already exists before uploading.

  ## Examples

      iex> generate_hash("https://example.com/image.jpg")
      "a8f3d2"
  """
  @spec generate_hash(String.t()) :: String.t()
  def generate_hash(url) when is_binary(url) do
    :crypto.hash(:md5, url)
    |> Base.encode16(case: :lower)
    |> String.slice(0..5)
  end

  @doc """
  Builds the full ImageKit folder path for a venue.

  ## Examples

      iex> build_folder_path(123)
      "/venues/123"
  """
  @spec build_folder_path(integer() | String.t()) :: String.t()
  def build_folder_path(venue_id) do
    "/venues/#{venue_id}"
  end

  @doc """
  Builds the complete ImageKit path (folder + filename).

  ## Examples

      iex> build_full_path(123, "gp-a8f3d2.jpg")
      "/venues/123/gp-a8f3d2.jpg"
  """
  @spec build_full_path(integer() | String.t(), String.t()) :: String.t()
  def build_full_path(venue_id, filename) do
    "#{build_folder_path(venue_id)}/#{filename}"
  end
end
