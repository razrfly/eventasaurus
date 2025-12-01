defmodule EventasaurusWeb.UploadController do
  @moduledoc """
  Controller for handling file upload operations via Cloudflare R2.

  Provides endpoints for generating presigned URLs for direct browser uploads.
  """

  use EventasaurusWeb, :controller

  alias EventasaurusApp.Services.R2Client

  @allowed_folders ~w(events groups avatars sources)
  @allowed_mime_types ~w(image/jpeg image/png image/gif image/webp image/avif)
  @max_file_size 5 * 1024 * 1024

  @doc """
  Generate a presigned URL for uploading a file directly to R2.

  ## Request Body

  ```json
  {
    "folder": "events",
    "filename": "image.jpg",
    "content_type": "image/jpeg",
    "file_size": 102400
  }
  ```

  ## Response

  ```json
  {
    "upload_url": "https://...",
    "public_url": "https://cdn2.wombie.com/events/...",
    "content_type": "image/jpeg",
    "expires_in": 3600
  }
  ```
  """
  def presign(conn, params) do
    with {:ok, folder} <- validate_folder(params["folder"]),
         {:ok, filename} <- validate_filename(params["filename"]),
         {:ok, content_type} <- validate_content_type(params["content_type"]),
         :ok <- validate_file_size(params["file_size"]) do
      # Generate unique filename to prevent overwrites
      unique_filename = generate_unique_filename(filename)
      path = "#{folder}/#{unique_filename}"

      case R2Client.presigned_upload_url(path, content_type: content_type) do
        {:ok, result} ->
          json(conn, %{
            upload_url: result.upload_url,
            public_url: result.public_url,
            content_type: result.content_type,
            expires_in: result.expires_in,
            path: path
          })

        {:error, {:not_configured, message}} ->
          conn
          |> put_status(:service_unavailable)
          |> json(%{
            error: "R2 storage is not configured",
            details: message,
            hint: "Set CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_ACCESS_KEY_ID, and CLOUDFLARE_SECRET_ACCESS_KEY environment variables"
          })

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to generate upload URL", details: inspect(reason)})
      end
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  @doc """
  Delete a file from R2 storage.

  ## Request Body

  ```json
  {
    "url": "https://cdn2.wombie.com/events/image.jpg"
  }
  ```
  """
  def delete(conn, %{"url" => url}) do
    with {:ok, path} <- R2Client.extract_path(url),
         :ok <- R2Client.delete(path) do
      json(conn, %{status: "deleted", path: path})
    else
      {:error, :invalid_url} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid URL format"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete file", details: inspect(reason)})
    end
  end

  # Private functions

  defp validate_folder(folder) when folder in @allowed_folders, do: {:ok, folder}
  defp validate_folder(nil), do: {:error, "folder is required"}
  defp validate_folder(_), do: {:error, "Invalid folder. Allowed: #{Enum.join(@allowed_folders, ", ")}"}

  defp validate_filename(nil), do: {:error, "filename is required"}
  defp validate_filename(""), do: {:error, "filename cannot be empty"}

  defp validate_filename(filename) when is_binary(filename) do
    # Sanitize filename - only allow alphanumeric, dash, underscore, and dots
    if Regex.match?(~r/^[a-zA-Z0-9_\-\.]+$/, filename) do
      {:ok, filename}
    else
      {:error, "Invalid filename. Only alphanumeric, dash, underscore, and dot characters allowed"}
    end
  end

  defp validate_content_type(content_type) when content_type in @allowed_mime_types do
    {:ok, content_type}
  end

  defp validate_content_type(nil), do: {:error, "content_type is required"}

  defp validate_content_type(_) do
    {:error, "Invalid content type. Allowed: #{Enum.join(@allowed_mime_types, ", ")}"}
  end

  defp validate_file_size(nil), do: :ok
  defp validate_file_size(size) when is_integer(size) and size <= @max_file_size, do: :ok
  defp validate_file_size(size) when is_binary(size), do: validate_file_size(String.to_integer(size))

  defp validate_file_size(_) do
    max_mb = @max_file_size / 1024 / 1024
    {:error, "File size exceeds maximum allowed (#{max_mb}MB)"}
  end

  defp generate_unique_filename(original_filename) do
    extension = Path.extname(original_filename)
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{random}_#{timestamp}#{extension}"
  end
end
