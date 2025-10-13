defmodule Eventasaurus.Sitemap.SupabaseS3Store do
  @moduledoc """
  Store which persists sitemap files to Supabase Storage using S3-compatible API.

  This implementation uses the S3-compatible API which works correctly with
  Supabase's NEW secret keys (sb_secret_...), unlike the REST API which only
  accepts JWT tokens.

  Implements the Sitemapper.Store behavior to upload sitemap files
  to Supabase Storage using the S3-compatible API via ExAws.

  ## Configuration

  * `:path` (required) - folder path within the bucket (e.g., "sitemaps")

  ## Requirements

  - Supabase configuration must be set in config/supabase.exs
  - SUPABASE_URL environment variable
  - SUPABASE_SECRET_KEY (NEW secret key: sb_secret_...) environment variable
  - Bucket must exist in Supabase Storage (default: "event-images")

  ## Example

      config = [
        store: Eventasaurus.Sitemap.SupabaseS3Store,
        store_config: [path: "sitemaps"]
      ]
  """

  @behaviour Sitemapper.Store

  require Logger

  @doc """
  Writes a sitemap file to Supabase Storage using S3-compatible API.

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

    Logger.info("Uploading sitemap file to Supabase Storage (S3 API): #{storage_path}")

    case upload_to_supabase_s3(storage_path, file_data) do
      {:ok, _response} ->
        public_url = build_public_url(storage_path)
        Logger.info("Successfully uploaded sitemap to #{public_url}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to upload sitemap to Supabase Storage: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Upload file to Supabase Storage using S3-compatible API
  defp upload_to_supabase_s3(storage_path, file_data) do
    bucket = get_bucket_name()

    # Use ExAws S3 client with Supabase configuration
    ExAws.S3.put_object(bucket, storage_path, file_data, [
      {:content_type, get_content_type(storage_path)}
    ])
    |> ExAws.request(get_ex_aws_config())
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

  # Build public URL for uploaded file
  defp build_public_url(storage_path) do
    "#{get_storage_url()}/object/public/#{get_bucket_name()}/#{storage_path}"
  end

  # Get Supabase Storage URL from config
  defp get_storage_url do
    config = Application.get_env(:eventasaurus, :supabase)
    "#{config[:url]}/storage/v1"
  end

  # Get bucket name from environment or config
  defp get_bucket_name do
    # Allow override via environment variable, otherwise use config
    System.get_env("SUPABASE_BUCKET") ||
      (Application.get_env(:eventasaurus, :supabase) |> Keyword.get(:bucket)) ||
      "eventasaur.us"
  end

  # Get S3 configuration for ExAws
  defp get_ex_aws_config do
    # Read directly from environment variables to avoid dev.exs overrides
    supabase_url = System.get_env("SUPABASE_URL") || raise "SUPABASE_URL environment variable not set"

    # Use dedicated S3 credentials generated in Supabase dashboard
    access_key_id = System.get_env("SUPABASE_S3_ACCESS_KEY_ID") || raise "SUPABASE_S3_ACCESS_KEY_ID environment variable not set"
    secret_access_key = System.get_env("SUPABASE_S3_SECRET_ACCESS_KEY") || raise "SUPABASE_S3_SECRET_ACCESS_KEY environment variable not set"

    # Extract project ref from URL (e.g., "vnhxedeynrtvakglinnr" from "https://vnhxedeynrtvakglinnr.supabase.co")
    project_ref =
      supabase_url
      |> String.replace(~r/^https?:\/\//, "")
      |> String.split(".")
      |> List.first()

    # Supabase S3 credentials from dashboard (Project Settings → Storage → S3 Access Keys)
    [
      # S3 credentials generated in Supabase dashboard
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      # AWS region (eu-central-1 for this project)
      region: "eu-central-1",
      # Supabase S3 endpoint: https://project_ref.supabase.co/storage/v1/s3
      scheme: "https://",
      host: "#{project_ref}.supabase.co/storage/v1/s3",
      port: 443
    ]
  end
end
