defmodule Eventasaurus.Sitemap.SupabaseStore do
  @moduledoc """
  Store which persists sitemap files to Supabase Storage.

  Implements the Sitemapper.Store behavior to upload sitemap files
  to Supabase Storage using the REST API.

  ## Configuration

  * `:path` (required) - folder path within the sitemaps bucket (e.g., "sitemaps")

  ## Requirements

  - Supabase configuration must be set in config/supabase.exs
  - SUPABASE_URL environment variable
  - SUPABASE_SECRET_KEY (service_role_key) environment variable
  - "sitemaps" bucket must exist in Supabase Storage (can be public or private)

  ## Example

      config = [
        store: Eventasaurus.Sitemap.SupabaseStore,
        store_config: [path: "sitemaps"]
      ]
  """

  @behaviour Sitemapper.Store

  require Logger

  @doc """
  Writes a sitemap file to Supabase Storage.

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

    Logger.info("Uploading sitemap file to Supabase Storage: #{storage_path}")

    case upload_to_supabase(storage_path, file_data, content_type) do
      {:ok, _response} ->
        public_url = build_public_url(storage_path)
        Logger.info("Successfully uploaded sitemap to #{public_url}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to upload sitemap to Supabase Storage: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Upload file to Supabase Storage using REST API
  defp upload_to_supabase(storage_path, file_data, content_type) do
    url = "#{get_storage_url()}/object/#{get_bucket_name()}/#{storage_path}"

    headers = [
      {"Authorization", "Bearer #{get_service_role_key()}"},
      {"Content-Type", content_type},
      # Allow overwriting existing files
      {"x-upsert", "true"}
    ]

    case HTTPoison.post(url, file_data, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Upload failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  # Build public URL for uploaded file
  defp build_public_url(storage_path) do
    "#{get_storage_url()}/object/public/#{get_bucket_name()}/#{storage_path}"
  end

  # Get Supabase Storage URL from config
  defp get_storage_url do
    config = Application.get_env(:eventasaurus, :supabase)
    "#{config[:url]}/storage/v1"
  end

  # Get bucket name (hardcoded to "sitemaps" for sitemap files)
  defp get_bucket_name do
    "sitemaps"
  end

  # Get service role key (server-side authentication)
  defp get_service_role_key do
    config = Application.get_env(:eventasaurus, :supabase)
    config[:service_role_key] || raise "SUPABASE_SECRET_KEY not configured"
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
