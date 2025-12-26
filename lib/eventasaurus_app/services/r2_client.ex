defmodule EventasaurusApp.Services.R2Client do
  @moduledoc """
  Client for Cloudflare R2 storage operations.

  Provides functionality for uploading files, generating presigned URLs,
  and managing objects in R2 buckets using the S3-compatible API.

  ## Configuration

  Requires the following environment variables:
  - CLOUDFLARE_ACCOUNT_ID
  - CLOUDFLARE_ACCESS_KEY_ID
  - CLOUDFLARE_SECRET_ACCESS_KEY
  - R2_BUCKET (optional, defaults to "wombie")
  - R2_CDN_URL (optional, defaults to "https://cdn2.wombie.com")
  """

  require Logger

  @doc """
  Upload a file to R2 storage.

  ## Parameters

  - `path` - The object key/path in the bucket (e.g., "events/image.jpg")
  - `data` - The file content as binary
  - `opts` - Options:
    - `:content_type` - MIME type (auto-detected if not provided)

  ## Returns

  - `{:ok, public_url}` - Successfully uploaded, returns CDN URL
  - `{:error, reason}` - Upload failed
  """
  def upload(path, data, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, guess_content_type(path))

    case config() do
      {:ok, aws_config} ->
        case ExAws.S3.put_object(bucket(), path, data, content_type: content_type)
             |> ExAws.request(aws_config) do
          {:ok, _response} ->
            public_url = build_cdn_url(path)
            Logger.info("Successfully uploaded to R2: #{path}")
            {:ok, public_url}

          {:error, reason} ->
            Logger.error("Failed to upload to R2: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :not_configured, message} ->
        Logger.error("R2 not configured: #{message}")
        {:error, {:not_configured, message}}
    end
  end

  @doc """
  Delete a file from R2 storage.

  ## Parameters

  - `path` - The object key/path to delete

  ## Returns

  - `:ok` - Successfully deleted
  - `{:error, reason}` - Deletion failed
  """
  def delete(path) do
    case config() do
      {:ok, aws_config} ->
        case ExAws.S3.delete_object(bucket(), path) |> ExAws.request(aws_config) do
          {:ok, _response} ->
            Logger.info("Successfully deleted from R2: #{path}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to delete from R2: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :not_configured, message} ->
        Logger.error("R2 not configured: #{message}")
        {:error, {:not_configured, message}}
    end
  end

  @doc """
  Generate a presigned URL for uploading a file directly from the browser.

  ## Parameters

  - `path` - The object key/path where the file will be uploaded
  - `opts` - Options:
    - `:content_type` - Required MIME type for the upload
    - `:expires_in` - URL expiration in seconds (default: 3600)

  ## Returns

  - `{:ok, %{upload_url: url, public_url: url}}` - Presigned upload URL and resulting public URL
  - `{:error, reason}` - Failed to generate URL
  """
  def presigned_upload_url(path, opts \\ []) do
    content_type = Keyword.fetch!(opts, :content_type)
    expires_in = Keyword.get(opts, :expires_in, 3600)

    case config() do
      {:ok, aws_config} ->
        presign_opts = [
          expires_in: expires_in,
          virtual_host: false,
          query_params: [{"Content-Type", content_type}]
        ]

        case ExAws.S3.presigned_url(aws_config, :put, bucket(), path, presign_opts) do
          {:ok, upload_url} ->
            {:ok,
             %{
               upload_url: upload_url,
               public_url: build_cdn_url(path),
               content_type: content_type,
               expires_in: expires_in
             }}

          {:error, reason} ->
            Logger.error("Failed to generate presigned URL: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :not_configured, message} ->
        Logger.error("R2 not configured: #{message}")
        {:error, {:not_configured, message}}
    end
  end

  @doc """
  Check if a file exists in R2 storage.

  ## Parameters

  - `path` - The object key/path to check

  ## Returns

  - `true` - File exists
  - `false` - File does not exist
  """
  def exists?(path) do
    case config() do
      {:ok, aws_config} ->
        case ExAws.S3.head_object(bucket(), path) |> ExAws.request(aws_config) do
          {:ok, _} -> true
          {:error, _} -> false
        end

      {:error, :not_configured, _message} ->
        false
    end
  end

  @doc """
  List objects in a folder.

  ## Parameters

  - `prefix` - The folder prefix (e.g., "events/")
  - `opts` - Options:
    - `:max_keys` - Maximum number of keys to return (default: 1000)

  ## Returns

  - `{:ok, [%{key: key, size: size, last_modified: datetime}]}` - List of objects
  - `{:error, reason}` - Failed to list objects
  """
  def list(prefix, opts \\ []) do
    max_keys = Keyword.get(opts, :max_keys, 1000)

    case config() do
      {:ok, aws_config} ->
        case ExAws.S3.list_objects(bucket(), prefix: prefix, max_keys: max_keys)
             |> ExAws.request(aws_config) do
          {:ok, %{body: %{contents: contents}}} ->
            files =
              contents
              |> Enum.filter(fn obj -> !String.ends_with?(obj.key, "/") end)
              |> Enum.map(fn obj ->
                %{
                  key: obj.key,
                  size: String.to_integer(obj.size),
                  last_modified: obj.last_modified
                }
              end)

            {:ok, files}

          {:ok, %{body: body}} ->
            {:ok, Map.get(body, :contents, [])}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_configured, message} ->
        Logger.error("R2 not configured: #{message}")
        {:error, {:not_configured, message}}
    end
  end

  @doc """
  Build the public CDN URL for a given path.
  """
  def build_cdn_url(path) do
    "#{cdn_url()}/#{path}"
  end

  @doc """
  Extract the path from a CDN URL.

  ## Returns

  - `{:ok, path}` - Successfully extracted path
  - `{:error, :invalid_url}` - URL doesn't match CDN pattern
  """
  def extract_path(url) do
    cdn = cdn_url()

    if String.starts_with?(url, cdn) do
      path = String.replace_prefix(url, "#{cdn}/", "")
      {:ok, path}
    else
      {:error, :invalid_url}
    end
  end

  @doc """
  Download an image from a URL and upload it to R2.

  Handles the full process of fetching an external image and storing it
  in R2, including content-type detection and error handling.

  ## Parameters

  - `source_url` - URL to download from
  - `r2_path` - Destination path in R2 bucket
  - `opts` - Options:
    - `:timeout` - HTTP timeout in ms (default: 30_000)
    - `:max_size` - Maximum file size in bytes (default: 10MB)
    - `:user_agent` - Custom User-Agent header

  ## Returns

  - `{:ok, %{cdn_url: url, content_type: type, file_size: size, r2_key: path}}` - Success
  - `{:error, reason}` - Download or upload failed

  ## Error Reasons

  - `{:http_error, status_code}` - HTTP request returned non-2xx status
  - `{:download_failed, reason}` - HTTP request failed (timeout, network error)
  - `:file_too_large` - File exceeds max_size limit
  - `{:not_configured, message}` - R2 credentials not configured
  """
  @spec download_and_upload(String.t(), String.t(), keyword()) ::
          {:ok, %{cdn_url: String.t(), content_type: String.t(), file_size: non_neg_integer(), r2_key: String.t()}}
          | {:error, term()}
  def download_and_upload(source_url, r2_path, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    max_size = Keyword.get(opts, :max_size, 10 * 1024 * 1024)

    user_agent =
      Keyword.get(
        opts,
        :user_agent,
        "Mozilla/5.0 (compatible; Eventasaurus/1.0; +https://wombie.com)"
      )

    headers = [
      {"User-Agent", user_agent},
      {"Accept", "image/*"}
    ]

    http_opts = [
      timeout: timeout,
      recv_timeout: timeout,
      follow_redirect: true,
      max_redirect: 5
    ]

    with {:ok, %{status_code: status, body: body, headers: resp_headers}}
         when status in 200..299 <- HTTPoison.get(source_url, headers, http_opts),
         :ok <- validate_size(body, max_size),
         content_type <- extract_content_type(resp_headers, r2_path),
         {:ok, cdn_url} <- upload(r2_path, body, content_type: content_type) do
      {:ok,
       %{
         cdn_url: cdn_url,
         content_type: content_type,
         file_size: byte_size(body),
         r2_key: r2_path
       }}
    else
      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:download_failed, reason}}

      {:error, :file_too_large} ->
        {:error, :file_too_large}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_size(body, max_size) do
    if byte_size(body) <= max_size do
      :ok
    else
      {:error, :file_too_large}
    end
  end

  defp extract_content_type(headers, fallback_path) do
    # Try to get content-type from headers first
    case List.keyfind(headers, "content-type", 0) || List.keyfind(headers, "Content-Type", 0) do
      {_, content_type} ->
        # Extract just the mime type (remove charset etc)
        content_type |> String.split(";") |> List.first() |> String.trim()

      nil ->
        # Fallback to guessing from path
        guess_content_type(fallback_path)
    end
  end

  # Private functions

  @doc """
  Check if R2 is properly configured.
  Returns true if all required credentials are present.
  """
  def configured? do
    r2_config = Application.get_env(:eventasaurus, :r2) || %{}

    account_id = r2_config[:account_id] || System.get_env("CLOUDFLARE_ACCOUNT_ID")
    access_key_id = r2_config[:access_key_id] || System.get_env("CLOUDFLARE_ACCESS_KEY_ID")

    secret_access_key =
      r2_config[:secret_access_key] || System.get_env("CLOUDFLARE_SECRET_ACCESS_KEY")

    !is_nil(account_id) and account_id != "" and
      !is_nil(access_key_id) and access_key_id != "" and
      !is_nil(secret_access_key) and secret_access_key != ""
  end

  defp config do
    r2_config = Application.get_env(:eventasaurus, :r2) || %{}

    account_id = r2_config[:account_id] || System.get_env("CLOUDFLARE_ACCOUNT_ID")
    access_key_id = r2_config[:access_key_id] || System.get_env("CLOUDFLARE_ACCESS_KEY_ID")

    secret_access_key =
      r2_config[:secret_access_key] || System.get_env("CLOUDFLARE_SECRET_ACCESS_KEY")

    # Return error tuple if not configured instead of raising
    cond do
      is_nil(account_id) or account_id == "" ->
        {:error, :not_configured, "CLOUDFLARE_ACCOUNT_ID not configured"}

      is_nil(access_key_id) or access_key_id == "" ->
        {:error, :not_configured, "CLOUDFLARE_ACCESS_KEY_ID not configured"}

      is_nil(secret_access_key) or secret_access_key == "" ->
        {:error, :not_configured, "CLOUDFLARE_SECRET_ACCESS_KEY not configured"}

      true ->
        {:ok,
         %{
           access_key_id: access_key_id,
           secret_access_key: secret_access_key,
           region: "auto",
           scheme: "https://",
           host: "#{account_id}.r2.cloudflarestorage.com",
           port: 443
         }}
    end
  end

  defp bucket do
    r2_config = Application.get_env(:eventasaurus, :r2) || %{}
    r2_config[:bucket] || System.get_env("R2_BUCKET") || "wombie"
  end

  defp cdn_url do
    r2_config = Application.get_env(:eventasaurus, :r2) || %{}
    r2_config[:cdn_url] || System.get_env("R2_CDN_URL") || "https://cdn2.wombie.com"
  end

  defp guess_content_type(filename) do
    cond do
      String.ends_with?(filename, ".jpg") or String.ends_with?(filename, ".jpeg") -> "image/jpeg"
      String.ends_with?(filename, ".png") -> "image/png"
      String.ends_with?(filename, ".gif") -> "image/gif"
      String.ends_with?(filename, ".webp") -> "image/webp"
      String.ends_with?(filename, ".avif") -> "image/avif"
      String.ends_with?(filename, ".svg") -> "image/svg+xml"
      String.ends_with?(filename, ".xml.gz") -> "application/gzip"
      String.ends_with?(filename, ".xml") -> "application/xml"
      String.ends_with?(filename, ".txt") -> "text/plain"
      String.ends_with?(filename, ".json") -> "application/json"
      true -> "application/octet-stream"
    end
  end
end
