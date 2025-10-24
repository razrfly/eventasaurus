defmodule Eventasaurus.ImageKit.Fetcher do
  @moduledoc """
  Fetches venue images from ImageKit Media Library.

  Used in local development to display production images without requiring
  production database access. Queries ImageKit API to list files in a venue's folder.

  ## Usage

      # Fetch images for a venue by slug
      {:ok, images} = Fetcher.list_venue_images("blue-note-jazz-club")

      # Returns:
      # [
      #   %{
      #     "url" => "https://ik.imagekit.io/wombie/venues/blue-note-jazz-club/gp-a8f3d2.jpg",
      #     "provider" => "google_places",
      #     "width" => 1920,
      #     "height" => 1080
      #   },
      #   ...
      # ]

  ## Configuration

  Requires IMAGEKIT_PRIVATE_KEY in environment for API authentication.
  """

  require Logger
  alias Eventasaurus.ImageKit.Config

  @doc """
  Lists all images for a venue from ImageKit Media Library.

  Queries ImageKit API for files in `/venues/{slug}/` folder.

  ## Parameters

  - `venue_slug` - The venue slug (e.g., "blue-note-jazz-club")

  ## Returns

  - `{:ok, images}` - List of image maps with url, provider, width, height
  - `{:error, reason}` - Error fetching images

  ## Examples

      iex> Fetcher.list_venue_images("blue-note-jazz-club")
      {:ok, [%{"url" => "https://ik.imagekit.io/...", "provider" => "google_places"}]}

      iex> Fetcher.list_venue_images("nonexistent-venue")
      {:ok, []}
  """
  @spec list_venue_images(String.t()) :: {:ok, list(map())} | {:error, atom() | String.t()}
  def list_venue_images(venue_slug) when is_binary(venue_slug) do
    # Build folder path - may raise ArgumentError if slug is invalid
    # Wrap in try/catch to match function spec
    with {:ok, folder_path} <- build_safe_folder_path(venue_slug) do
      # Build search query for ImageKit API
      # Note: slug is already validated by build_folder_path to only contain [a-z0-9-]
      # so no special Lucene characters can appear in the path
      search_query = ~s(path: "#{folder_path}")

      Logger.debug("🔍 Fetching images from ImageKit: #{search_query}")

      case query_imagekit_api(search_query) do
        {:ok, files} ->
          images = Enum.map(files, &format_image/1)
          Logger.debug("✅ Found #{length(images)} images for venue: #{venue_slug}")
          {:ok, images}

        {:error, reason} ->
          Logger.warning("⚠️  Failed to fetch images for venue #{venue_slug}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Safely build folder path, catching ArgumentError from invalid slug
  defp build_safe_folder_path(venue_slug) do
    try do
      folder_path = Eventasaurus.ImageKit.Filename.build_folder_path(venue_slug) <> "/"
      {:ok, folder_path}
    rescue
      ArgumentError ->
        Logger.warning("⚠️  Invalid venue slug: #{venue_slug}")
        {:error, :invalid_slug}
    end
  end

  # Query ImageKit API for files matching search query
  defp query_imagekit_api(search_query) do
    # ImageKit API endpoint for listing files
    api_url = "https://api.imagekit.io/v1/files"

    # Build authentication header
    # ImageKit uses HTTP Basic Auth with private_key as username and empty password
    auth = {:basic, Config.private_key(), ""}

    case Req.get(
           api_url,
           params: [searchQuery: search_query],
           auth: auth,
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: files}} when is_list(files) ->
        {:ok, files}

      {:ok, %Req.Response{status: 200, body: body}} ->
        Logger.error("❌ ImageKit API returned non-list body: #{inspect(body)}")
        {:error, :invalid_response}

      {:ok, %Req.Response{status: 401}} ->
        Logger.error("❌ ImageKit authentication failed - check IMAGEKIT_PRIVATE_KEY")
        {:error, :authentication_failed}

      {:ok, %Req.Response{status: 403}} ->
        Logger.error("❌ ImageKit forbidden - check API permissions")
        {:error, :forbidden}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("❌ ImageKit API error (#{status}): #{inspect(body)}")
        {:error, {:http_error, status}}

      {:error, exception} ->
        Logger.error("❌ HTTP request failed: #{inspect(exception)}")
        {:error, :request_failed}
    end
  end

  # Format ImageKit file response into venue_images structure
  defp format_image(file) when is_map(file) do
    provider = extract_provider_from_filename(file["name"])

    %{
      "url" => file["url"],
      "provider" => provider,
      "width" => file["width"],
      "height" => file["height"]
    }
  end

  # Extract provider name from filename pattern: {provider_code}-{hash}.jpg
  defp extract_provider_from_filename(filename) when is_binary(filename) do
    case String.split(filename, "-", parts: 2) do
      ["gp" | _] -> "google_places"
      ["fs" | _] -> "foursquare"
      ["us" | _] -> "unsplash"
      ["px" | _] -> "pexels"
      ["ig" | _] -> "instagram"
      _ -> "unknown"
    end
  end

  defp extract_provider_from_filename(_), do: "unknown"
end
