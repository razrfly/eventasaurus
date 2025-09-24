defmodule EventasaurusApp.Services.UploadService do
  @moduledoc """
  Service for handling file uploads to Supabase Storage.

  Provides functionality for uploading, validating, and managing image files
  for groups, events, and user profiles.
  """

  require Logger

  # 5MB
  @max_file_size 5 * 1024 * 1024
  @allowed_mime_types ~w[image/jpeg image/png image/gif image/webp]

  # Get bucket name from config with fallback
  defp get_bucket_name do
    Application.get_env(:eventasaurus, :supabase)[:bucket] || "images"
  end

  @doc """
  Upload a file to Supabase Storage.

  ## Parameters

  * `file_path` - Local path to the temporary uploaded file
  * `filename` - Desired filename in storage (should include extension)
  * `content_type` - MIME type of the file
  * `folder` - Storage folder (e.g., "groups", "events", "avatars")
  * `access_token` - User's Supabase access token

  ## Returns

  * `{:ok, public_url}` - Successfully uploaded, returns public URL
  * `{:error, reason}` - Upload failed

  ## Examples

      iex> upload_file("/tmp/image.jpg", "group_123_cover.jpg", "image/jpeg", "groups", token)
      {:ok, "https://supabase.com/storage/v1/object/public/images/groups/group_123_cover.jpg"}
      
      iex> upload_file("/tmp/large.jpg", "large.jpg", "image/jpeg", "groups", token)
      {:error, :file_too_large}
  """
  def upload_file(file_path, filename, content_type, folder, access_token) do
    with :ok <- validate_file(file_path, content_type),
         {:ok, file_data} <- File.read(file_path),
         storage_path <- Path.join(folder, filename),
         {:ok, _response} <-
           upload_to_supabase(storage_path, file_data, content_type, access_token) do
      public_url = build_public_url(storage_path)
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
  Delete a file from Supabase Storage.

  ## Parameters

  * `file_url` - Full public URL of the file to delete
  * `access_token` - User's Supabase access token

  ## Returns

  * `:ok` - Successfully deleted
  * `{:error, reason}` - Deletion failed
  """
  def delete_file(file_url, access_token) when is_binary(file_url) do
    with {:ok, storage_path} <- extract_storage_path(file_url),
         {:ok, _response} <- delete_from_supabase(storage_path, access_token) do
      Logger.info("Successfully deleted file: #{storage_path}")
      :ok
    else
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

  defp upload_to_supabase(storage_path, file_data, content_type, access_token) do
    url = "#{get_storage_url()}/object/#{get_bucket_name()}/#{storage_path}"

    headers = [
      {"Authorization", "Bearer #{access_token}"},
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

  defp delete_from_supabase(storage_path, access_token) do
    url = "#{get_storage_url()}/object/#{get_bucket_name()}/#{storage_path}"

    headers = [
      {"Authorization", "Bearer #{access_token}"}
    ]

    case HTTPoison.delete(url, headers) do
      {:ok, %{status_code: status}} when status in [200, 204] ->
        {:ok, %{}}

      {:ok, %{status_code: code, body: response_body}} ->
        error = Jason.decode!(response_body)
        {:error, %{status: code, message: error["message"] || "Delete failed"}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_public_url(storage_path) do
    "#{get_storage_url()}/object/public/#{get_bucket_name()}/#{storage_path}"
  end

  defp extract_storage_path(public_url) do
    case String.split(public_url, "/object/public/#{get_bucket_name()}/") do
      [_base, storage_path] -> {:ok, storage_path}
      _ -> {:error, :invalid_url}
    end
  end

  defp get_storage_url do
    config = Application.get_env(:eventasaurus, :supabase)
    "#{config[:url]}/storage/v1"
  end

  defp consume_uploaded_entries(socket, upload_config, fun) do
    Phoenix.LiveView.consume_uploaded_entries(socket, upload_config, fun)
  end
end
