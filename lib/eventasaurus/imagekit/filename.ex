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
  - `content_type` - Optional content type (e.g., "image/png", "image/webp"). Defaults to .jpg

  ## Returns

  A short, deterministic filename in format: `{provider_code}-{hash}.{ext}`

  ## Examples

      iex> generate("https://maps.googleapis.com/maps/api/place/photo?photoreference=ABC123", "google_places")
      "gp-a8f3d2ab.jpg"

      iex> generate("https://images.unsplash.com/photo-123", "unsplash", "image/png")
      "us-7bc419ab.png"
  """
  @spec generate(String.t(), String.t(), String.t() | nil) :: String.t()
  def generate(provider_url, provider, content_type \\ nil)
      when is_binary(provider_url) and is_binary(provider) do
    provider_code = get_provider_code(provider)
    hash = generate_hash(provider_url)

    extension =
      extension_from_content_type(content_type) || extension_from_url(provider_url) || "jpg"

    "#{provider_code}-#{hash}.#{extension}"
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
  Generates an 8-character hash from a URL using MD5.

  The hash is deterministic - the same URL will always produce the same hash.
  This enables deduplication by checking if a file already exists before uploading.

  For URLs with query parameters (like Google Places), only specific stable parameters
  are included in the hash (e.g., photoreference, photo_id) to ensure the same photo
  always generates the same hash regardless of API key changes.

  ## Examples

      iex> generate_hash("https://example.com/image.jpg")
      "a8f3d2ab"

      iex> generate_hash("https://maps.googleapis.com/maps/api/place/photo?photoreference=ABC&key=123")
      # Same hash as with key=456 (only photoreference matters)
  """
  @spec generate_hash(String.t()) :: String.t()
  def generate_hash(url) when is_binary(url) do
    normalized_url = normalize_url_for_hash(url)

    :crypto.hash(:md5, normalized_url)
    |> Base.encode16(case: :lower)
    |> String.slice(0..7)
  end

  # Normalize URLs to ensure consistent hashing
  defp normalize_url_for_hash(url) do
    uri = URI.parse(url)

    case uri.query do
      nil ->
        # No query params, use full URL
        url

      query_string ->
        # Parse query params
        params = URI.decode_query(query_string)

        # For Google Places URLs, only use stable identifiers
        stable_params =
          if String.contains?(url, "maps.googleapis.com") do
            Map.take(params, ["photoreference", "photo_id", "maxwidth", "maxheight"])
          else
            # For other providers, use all params
            params
          end

        # Rebuild URL with only stable params in deterministic order
        normalized_query =
          stable_params
          |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
          |> Enum.sort_by(fn {k, _} -> k end)
          |> URI.encode_query()

        %{uri | query: normalized_query}
        |> URI.to_string()
    end
  end

  @doc """
  Builds the full ImageKit folder path for a venue using slug.

  Validates slug to prevent path traversal or unsafe characters.
  Uses folder from config (e.g., "/venues" in production, "/venues_test" in development).

  ## Examples

      iex> build_folder_path("blue-note-jazz-club")
      "/venues/blue-note-jazz-club"

      iex> build_folder_path("invalid/slug")
      ** (ArgumentError) invalid venue slug: contains unsafe characters
  """
  @spec build_folder_path(String.t()) :: String.t()
  def build_folder_path(venue_slug) when is_binary(venue_slug) do
    if valid_slug?(venue_slug) do
      # Get base folder from config (e.g., "/venues" or "/venues_test")
      base_folder = Application.get_env(:eventasaurus, :imagekit, [])[:folder] || "/venues"
      "#{base_folder}/#{venue_slug}"
    else
      raise ArgumentError, "invalid venue slug: contains unsafe characters"
    end
  end

  @doc """
  Validates that a slug contains only safe characters.

  Safe characters: lowercase letters, numbers, hyphens

  ## Examples

      iex> valid_slug?("blue-note-jazz-club")
      true

      iex> valid_slug?("../etc/passwd")
      false

      iex> valid_slug?("slug with spaces")
      false
  """
  @spec valid_slug?(String.t()) :: boolean()
  def valid_slug?(slug) when is_binary(slug) do
    String.match?(slug, ~r/\A[a-z0-9-]+\z/)
  end

  def valid_slug?(_), do: false

  @doc """
  Extracts file extension from content-type header.

  ## Examples

      iex> extension_from_content_type("image/png")
      "png"

      iex> extension_from_content_type("image/jpeg")
      "jpg"

      iex> extension_from_content_type("image/webp")
      "webp"

      iex> extension_from_content_type(nil)
      nil
  """
  @spec extension_from_content_type(String.t() | nil) :: String.t() | nil
  def extension_from_content_type(nil), do: nil
  def extension_from_content_type("image/jpeg"), do: "jpg"
  def extension_from_content_type("image/jpg"), do: "jpg"
  def extension_from_content_type("image/png"), do: "png"
  def extension_from_content_type("image/webp"), do: "webp"
  def extension_from_content_type("image/gif"), do: "gif"
  def extension_from_content_type("image/svg+xml"), do: "svg"
  def extension_from_content_type(_), do: nil

  @doc """
  Extracts file extension from URL path.

  ## Examples

      iex> extension_from_url("https://example.com/image.png")
      "png"

      iex> extension_from_url("https://example.com/image.jpg")
      "jpg"

      iex> extension_from_url("https://example.com/no-extension")
      nil
  """
  @spec extension_from_url(String.t()) :: String.t() | nil
  def extension_from_url(url) when is_binary(url) do
    uri = URI.parse(url)
    path = uri.path || ""

    case Path.extname(path) do
      "." <> ext when ext in ~w(jpg jpeg png webp gif svg) ->
        if ext == "jpeg", do: "jpg", else: ext

      _ ->
        nil
    end
  end

  def extension_from_url(_), do: nil

  @doc """
  Builds the complete ImageKit path (folder + filename).

  ## Examples

      iex> build_full_path("blue-note-jazz-club", "gp-a8f3d2.jpg")
      "/venues/blue-note-jazz-club/gp-a8f3d2.jpg"
  """
  @spec build_full_path(String.t(), String.t()) :: String.t()
  def build_full_path(venue_slug, filename) when is_binary(venue_slug) and is_binary(filename) do
    "#{build_folder_path(venue_slug)}/#{filename}"
  end
end
