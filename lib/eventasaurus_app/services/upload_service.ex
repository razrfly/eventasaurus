defmodule EventasaurusApp.Services.UploadService do
  @moduledoc """
  Service for handling file uploads to Cloudflare R2 Storage.

  Provides functionality for uploading, validating, and managing image files
  for groups, events, and user profiles.

  Note: This service now uses R2 instead of Supabase Storage. The access_token
  parameter is kept for backwards compatibility but is no longer used for R2 uploads.
  """

  require Logger

  alias EventasaurusApp.Services.R2Client

  # 5MB
  @max_file_size 5 * 1024 * 1024
  @allowed_mime_types ~w[image/jpeg image/png image/gif image/webp image/avif]

  @doc """
  Upload a file to R2 Storage.

  ## Parameters

  * `file_path` - Local path to the temporary uploaded file
  * `filename` - Desired filename in storage (should include extension)
  * `content_type` - MIME type of the file
  * `folder` - Storage folder (e.g., "groups", "events", "avatars", "sources")
  * `access_token` - (deprecated) Kept for backwards compatibility, not used for R2

  ## Returns

  * `{:ok, public_url}` - Successfully uploaded, returns CDN URL
  * `{:error, reason}` - Upload failed

  ## Examples

      iex> upload_file("/tmp/image.jpg", "group_123_cover.jpg", "image/jpeg", "groups", token)
      {:ok, "https://cdn2.wombie.com/groups/group_123_cover.jpg"}

      iex> upload_file("/tmp/large.jpg", "large.jpg", "image/jpeg", "groups", token)
      {:error, :file_too_large}
  """
  def upload_file(file_path, filename, content_type, folder, _access_token) do
    with :ok <- validate_file(file_path, content_type),
         {:ok, file_data} <- File.read(file_path),
         storage_path <- Path.join(folder, filename),
         {:ok, public_url} <- R2Client.upload(storage_path, file_data, content_type: content_type) do
      Logger.info("Successfully uploaded file to #{public_url}")
      {:ok, public_url}
    else
      error ->
        Logger.error("File upload failed: #{inspect(error)}")
        error
    end
  end

  @doc """
  Upload multiple files from Phoenix LiveView uploads.

  ## Parameters

  * `socket` - LiveView socket with uploaded entries
  * `upload_config` - Upload configuration atom (e.g., :cover_image, :avatar)
  * `folder` - Storage folder prefix
  * `id_prefix` - Prefix for generated filenames (e.g., "group_123")
  * `access_token` - User's Supabase access token

  ## Returns

  * `{:ok, [public_urls]}` - List of uploaded file URLs
  * `{:error, reason}` - Upload failed
  """
  def upload_liveview_files(socket, upload_config, folder, id_prefix, access_token) do
    consume_uploaded_entries(socket, upload_config, fn %{path: path}, entry ->
      filename = generate_filename(id_prefix, upload_config, entry.client_name)
      upload_file(path, filename, entry.client_type, folder, access_token)
    end)
  end

  @doc """
  Delete a file from R2 Storage.

  ## Parameters

  * `file_url` - Full public URL of the file to delete
  * `access_token` - (deprecated) Kept for backwards compatibility, not used for R2

  ## Returns

  * `:ok` - Successfully deleted
  * `{:error, reason}` - Deletion failed
  """
  def delete_file(file_url, _access_token) when is_binary(file_url) do
    with {:ok, storage_path} <- R2Client.extract_path(file_url),
         :ok <- R2Client.delete(storage_path) do
      Logger.info("Successfully deleted file: #{storage_path}")
      :ok
    else
      {:error, :invalid_url} ->
        # Try legacy Supabase URL extraction for backwards compatibility
        case extract_legacy_storage_path(file_url) do
          {:ok, path} ->
            case R2Client.delete(path) do
              :ok ->
                Logger.info("Successfully deleted file (legacy URL): #{path}")
                :ok

              error ->
                Logger.error("File deletion failed: #{inspect(error)}")
                error
            end

          {:error, _} ->
            Logger.warning("Could not extract path from URL: #{file_url}")
            :ok
        end

      error ->
        Logger.error("File deletion failed: #{inspect(error)}")
        error
    end
  end

  def delete_file(nil, _access_token), do: :ok

  @doc """
  Validate file size and MIME type.
  """
  def validate_file(file_path, content_type) do
    with :ok <- validate_mime_type(content_type),
         :ok <- validate_file_size(file_path) do
      :ok
    end
  end

  @doc """
  Generate a unique filename for uploads.
  """
  def generate_filename(prefix, upload_type, original_filename) do
    extension = Path.extname(original_filename)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    "#{prefix}_#{upload_type}_#{timestamp}_#{random}#{extension}"
  end

  # Private Functions

  defp validate_mime_type(content_type) do
    if content_type in @allowed_mime_types do
      :ok
    else
      {:error, :invalid_mime_type}
    end
  end

  defp validate_file_size(file_path) do
    case File.stat(file_path) do
      {:ok, %{size: size}} when size <= @max_file_size -> :ok
      {:ok, %{size: _size}} -> {:error, :file_too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  # Extract storage path from legacy Supabase URLs for backwards compatibility
  # Handles URLs like: https://xxx.supabase.co/storage/v1/object/public/bucket/path/file.jpg
  defp extract_legacy_storage_path(public_url) do
    # Try to match Supabase Storage URL pattern
    case Regex.run(~r{/object/public/[^/]+/(.+)$}, public_url) do
      [_, storage_path] -> {:ok, storage_path}
      _ -> {:error, :invalid_url}
    end
  end

  defp consume_uploaded_entries(socket, upload_config, fun) do
    Phoenix.LiveView.consume_uploaded_entries(socket, upload_config, fun)
  end
end
