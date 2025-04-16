defmodule EventasaurusApp.Storage.SupabaseProvider do
  @moduledoc """
  Storage provider implementation for Supabase Storage.

  This provider integrates with Supabase's Storage service for file operations.
  """

  @behaviour EventasaurusApp.Storage.Provider

  alias EventasaurusApp.Storage.StorageError
  alias EventasaurusApp.Auth.Client, as: SupabaseClient

  # Default bucket name
  @default_bucket "event-images"

  @doc """
  Initialize the storage provider.

  Ensures the required buckets exist in Supabase Storage.
  """
  @impl true
  def init() do
    case create_bucket_if_not_exists(@default_bucket) do
      :ok -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Upload a file to storage.
  """
  @impl true
  def upload(source_path, opts) do
    bucket = Map.get(opts, :bucket, @default_bucket)
    path = Map.get(opts, :destination)
    content_type = Map.get(opts, :content_type)

    # Generate a destination path if not provided
    destination = if path, do: path, else: Path.basename(source_path)

    with {:ok, file_binary} <- File.read(source_path),
         {:ok, _response} <- upload_to_supabase(file_binary, destination, bucket, content_type) do
      {:ok, %{path: destination, url: get_public_url_sync(destination, bucket)}}
    else
      {:error, :enoent} ->
        {:error, StorageError.not_found("Source file not found: #{source_path}")}
      {:error, reason} when is_binary(reason) ->
        {:error, StorageError.server_error(reason)}
      {:error, %{message: message}} ->
        {:error, StorageError.server_error(message)}
      {:error, reason} ->
        {:error, StorageError.server_error("Upload failed: #{inspect(reason)}")}
    end
  end

  @doc """
  Delete a file from storage.
  """
  @impl true
  def delete(path, opts) do
    bucket = Map.get(opts, :bucket, @default_bucket)

    case SupabaseClient.storage_from(bucket) |> SupabaseClient.remove([path]) do
      {:ok, _} -> :ok
      {:error, %{message: "Object not found"}} -> :ok  # Already deleted
      {:error, %{message: message}} ->
        {:error, StorageError.server_error(message)}
      {:error, reason} ->
        {:error, StorageError.server_error("Delete failed: #{inspect(reason)}")}
    end
  end

  @doc """
  Check if a file exists in storage.
  """
  @impl true
  def exists?(path, opts) do
    bucket = Map.get(opts, :bucket, @default_bucket)

    case SupabaseClient.storage_from(bucket) |> SupabaseClient.list(path) do
      {:ok, []} -> {:ok, false}
      {:ok, _} -> {:ok, true}
      {:error, %{message: "Not found"}} -> {:ok, false}
      {:error, %{message: message}} ->
        {:error, StorageError.server_error(message)}
      {:error, reason} ->
        {:error, StorageError.server_error("Error checking existence: #{inspect(reason)}")}
    end
  end

  @doc """
  Get a public URL for a stored file.
  """
  @impl true
  def get_public_url(path, opts) do
    bucket = Map.get(opts, :bucket, @default_bucket)

    case SupabaseClient.storage_from(bucket) |> SupabaseClient.create_signed_url(path, 3600) do
      {:ok, %{"signedURL" => signed_url}} ->
        {:ok, signed_url}
      {:error, %{message: message}} ->
        {:error, StorageError.server_error(message)}
      {:error, reason} ->
        {:error, StorageError.server_error("Failed to get URL: #{inspect(reason)}")}
    end
  end

  @doc """
  Copy a file within storage.
  """
  @impl true
  def copy(source_path, destination_path, opts) do
    source_bucket = Map.get(opts, :source_bucket, @default_bucket)
    destination_bucket = Map.get(opts, :destination_bucket, source_bucket)

    # For Supabase, we need to download and reupload
    with {:ok, data} <- download_from_supabase(source_path, source_bucket),
         {:ok, _} <- upload_to_supabase(data, destination_path, destination_bucket) do
      {:ok, destination_path}
    else
      {:error, %{message: message}} ->
        {:error, StorageError.server_error(message)}
      {:error, reason} ->
        {:error, StorageError.server_error("Copy failed: #{inspect(reason)}")}
    end
  end

  # Private functions

  defp create_bucket_if_not_exists(bucket) do
    case SupabaseClient.create_bucket(bucket, %{public: true}) do
      {:ok, _} -> :ok
      {:error, %{message: "Bucket already exists"}} -> :ok
      {:error, %{message: message}} ->
        {:error, StorageError.server_error("Failed to create bucket: #{message}")}
      {:error, reason} ->
        {:error, StorageError.server_error("Failed to create bucket: #{inspect(reason)}")}
    end
  end

  defp upload_to_supabase(data, path, bucket, content_type \\ nil) do
    options = if content_type, do: %{content_type: content_type}, else: %{}

    SupabaseClient.storage_from(bucket)
    |> SupabaseClient.upload(path, data, options)
  end

  defp download_from_supabase(path, bucket) do
    with {:ok, %{"signedURL" => url}} <- SupabaseClient.storage_from(bucket)
                                         |> SupabaseClient.create_signed_url(path, 60),
         {:ok, %{body: body, status_code: 200}} <- http_get(url) do
      {:ok, body}
    end
  end

  defp http_get(url) do
    client = Application.get_env(:eventasaurus, :http_client, HTTPoison)
    client.get(url)
  end

  # Synchronous version of get_public_url that returns just the URL string
  # Used internally when we need the URL directly
  defp get_public_url_sync(path, bucket) do
    case get_public_url(path, %{bucket: bucket}) do
      {:ok, url} -> url
      _ -> nil
    end
  end
end
