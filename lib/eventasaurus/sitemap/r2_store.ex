defmodule Eventasaurus.Sitemap.R2Store do
  @moduledoc """
  Store which persists sitemap files to Cloudflare R2 Storage.

  Implements the Sitemapper.Store behavior to upload sitemap files
  to R2 using the S3-compatible API via ExAws.

  ## Configuration

  * `:path` (required) - folder path within the bucket (e.g., "sitemaps")

  ## Requirements

  - R2 configuration must be set in config/runtime.exs
  - CLOUDFLARE_ACCOUNT_ID environment variable
  - CLOUDFLARE_ACCESS_KEY_ID environment variable
  - CLOUDFLARE_SECRET_ACCESS_KEY environment variable
  - R2_BUCKET environment variable (default: "wombie")
  - R2_CDN_URL environment variable (default: "https://cdn2.wombie.com")

  ## Example

      config = [
        store: Eventasaurus.Sitemap.R2Store,
        store_config: [path: "sitemaps"]
      ]
  """

  @behaviour Sitemapper.Store

  require Logger

  alias EventasaurusApp.Services.R2Client

  @doc """
  Writes a sitemap file to R2 Storage.

  ## Parameters

  - `filename` - The name of the sitemap file (e.g., "sitemap.xml.gz")
  - `data` - The file content as IO.chardata (binary or iolist)
  - `config` - Keyword list with `:path` key

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @impl true
  def write(filename, data, config) do
    path = Keyword.fetch!(config, :path)
    storage_path = Path.join(path, filename)

    # Convert IO.chardata to binary if needed
    file_data = IO.chardata_to_string(data)

    # Determine content type based on file extension
    content_type = get_content_type(filename)

    Logger.info("Uploading sitemap file to R2 Storage: #{storage_path}")

    case R2Client.upload(storage_path, file_data, content_type: content_type) do
      {:ok, public_url} ->
        Logger.info("Successfully uploaded sitemap to #{public_url}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to upload sitemap to R2 Storage: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Determine content type based on file extension
  defp get_content_type(filename) do
    cond do
      String.ends_with?(filename, ".xml.gz") -> "application/gzip"
      String.ends_with?(filename, ".xml") -> "application/xml"
      String.ends_with?(filename, ".txt") -> "text/plain"
      true -> "application/octet-stream"
    end
  end
end
